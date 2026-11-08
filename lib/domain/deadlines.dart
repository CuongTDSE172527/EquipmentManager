import 'models.dart';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime monthEnd(DateTime d) => DateTime(d.year, d.month + 1, 0);

/// Calendar arithmetic clamps the day instead of overflowing into another month.
DateTime addMonths(DateTime d, int months) {
  final first = DateTime(d.year, d.month + months, 1);
  final last = monthEnd(first).day;
  return DateTime(first.year, first.month, d.day > last ? last : d.day);
}

DateTime? effectiveDue(DeadlineItem item) => item.dueDate == null
    ? null
    : item.precision == DatePrecision.month
    ? monthEnd(item.dueDate!)
    : dateOnly(item.dueDate!);

/// UTC is used ONLY for counting calendar days, avoiding DST-length day errors.
int calendarDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

DeadlineStatus statusOf(
  DeadlineItem item,
  Equipment equipment,
  AppSettings settings,
  DateTime today,
) {
  if (equipment.managementStatus != ManagementStatus.active) {
    return DeadlineStatus.excluded;
  }
  if (item.isDone) return DeadlineStatus.done;
  if (item.kind == ItemKind.insurance &&
      (item.insuranceMode == InsuranceMode.centralized ||
          item.insuranceMode == InsuranceMode.notApplicable)) {
    return DeadlineStatus.excluded;
  }
  if (item.requiresConfirmation) return DeadlineStatus.needsUpdate;
  if (item.expiredWithoutDate ||
      (item.kind == ItemKind.insurance &&
          item.insuranceMode == InsuranceMode.expired)) {
    return DeadlineStatus.overdue;
  }
  if (item.kind == ItemKind.insurance &&
      item.insuranceMode == InsuranceMode.unknown) {
    return DeadlineStatus.needsUpdate;
  }
  final due = effectiveDue(item);
  if (due == null) return DeadlineStatus.needsUpdate;
  final remaining = calendarDaysBetween(today, due);
  if (remaining < 0) return DeadlineStatus.overdue;
  final threshold = item.kind == ItemKind.lifespan
      ? settings.lifespanWarnDays
      : settings.warnDays;
  return remaining <= threshold
      ? DeadlineStatus.upcoming
      : DeadlineStatus.valid;
}

({DeadlineItem item, HistoryLog history}) completeItem(
  DeadlineItem item, {
  required DateTime doneDate,
  int? cost,
  required String provider,
  String note = '',
  DateTime? explicitNextDate,
}) {
  if (item.isDone) throw StateError('Hạng mục đã hoàn thành.');
  if (item.cycleMonths < 0) throw ArgumentError('Chu kỳ không được âm.');
  if (cost != null && cost < 0) throw ArgumentError('Chi phí không được âm.');
  DateTime? next;
  if (item.cycleMonths > 0) {
    if (item.kind == ItemKind.lifespan) {
      throw ArgumentError('Niên hạn sử dụng không tự động gia hạn.');
    }
    final anchored =
        item.kind == ItemKind.insurance || item.kind == ItemKind.inspection;
    if (anchored && item.dueDate == null && explicitNextDate == null) {
      throw ArgumentError(
        'Chưa có hạn cũ. Hãy nhập hạn tiếp theo đã xác nhận.',
      );
    }
    next =
        explicitNextDate ??
        addMonths(anchored ? item.dueDate! : doneDate, item.cycleMonths);
    next = item.precision == DatePrecision.month
        ? monthEnd(next)
        : dateOnly(next);
  }
  final updated = item.copy({
    'dueDate': next?.toIso8601String() ?? item.dueDate?.toIso8601String(),
    'isDone': item.cycleMonths == 0,
    'cost': cost,
    'provider': provider,
    'requiresConfirmation': false,
    'expiredWithoutDate': false,
    if (item.kind == ItemKind.insurance)
      'insuranceMode': InsuranceMode.dated.name,
  });
  return (
    item: updated,
    history: HistoryLog(
      itemId: item.id,
      doneDate: dateOnly(doneDate),
      cost: cost,
      provider: provider,
      note: note,
      previousDueDate: item.dueDate,
      nextDueDate: next,
    ),
  );
}

({DateTime date, DatePrecision precision}) parseVietnameseDate(String raw) {
  final text = raw.trim();
  final month = RegExp(r'^(\d{1,2})/(\d{4})$').firstMatch(text);
  if (month != null) {
    final m = int.parse(month[1]!);
    final y = int.parse(month[2]!);
    if (m < 1 || m > 12 || y < 1900 || y > 9999) {
      throw const FormatException('Tháng/năm không hợp lệ.');
    }
    return (date: DateTime(y, m + 1, 0), precision: DatePrecision.month);
  }
  final day = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text);
  if (day == null) throw const FormatException('Nhập dd/MM/yyyy hoặc MM/yyyy.');
  final d = int.parse(day[1]!);
  final m = int.parse(day[2]!);
  final y = int.parse(day[3]!);
  final date = DateTime(y, m, d);
  if (y < 1900 ||
      y > 9999 ||
      date.year != y ||
      date.month != m ||
      date.day != d) {
    throw const FormatException('Ngày không tồn tại.');
  }
  return (date: date, precision: DatePrecision.day);
}

String displayDate(DateTime? d, [DatePrecision precision = DatePrecision.day]) {
  if (d == null) return 'Chưa có thông tin';
  final m = d.month.toString().padLeft(2, '0');
  return precision == DatePrecision.month
      ? '$m/${d.year}'
      : '${d.day.toString().padLeft(2, '0')}/$m/${d.year}';
}

class TrackedDeadline {
  const TrackedDeadline(this.equipment, this.item, this.status);
  final Equipment equipment;
  final DeadlineItem item;
  final DeadlineStatus status;
}

List<TrackedDeadline> trackedDeadlines(
  List<Equipment> equipment,
  List<DeadlineItem> items,
  AppSettings settings,
  DateTime today,
) {
  final byId = {for (final e in equipment) e.id: e};
  final rows = <TrackedDeadline>[];
  for (final item in items) {
    final e = byId[item.equipmentId];
    if (e != null) {
      rows.add(TrackedDeadline(e, item, statusOf(item, e, settings, today)));
    }
  }
  rows.sort((a, b) {
    final status = a.status.index.compareTo(b.status.index);
    if (status != 0) return status;
    final ad = effectiveDue(a.item);
    final bd = effectiveDue(b.item);
    if (ad == null && bd == null) {
      return a.equipment.name.compareTo(b.equipment.name);
    }
    if (ad == null) return 1;
    if (bd == null) return -1;
    return ad.compareTo(bd);
  });
  return rows;
}

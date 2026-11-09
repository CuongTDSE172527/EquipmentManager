import 'models.dart';
import 'deadlines.dart';

enum PlanPeriod {
  thisMonth('Tháng này'),
  nextMonth('Tháng sau'),
  thisQuarter('Quý này'),
  nextQuarter('Quý sau');

  const PlanPeriod(this.label);
  final String label;
}

class PlanRange {
  const PlanRange(this.start, this.end, this.title);
  final DateTime start, end;
  final String title;
}

PlanRange planRange(PlanPeriod period, DateTime today) {
  final day = dateOnly(today);
  final quarterStart = ((day.month - 1) ~/ 3) * 3 + 1;
  final (start, months) = switch (period) {
    PlanPeriod.thisMonth => (DateTime(day.year, day.month), 1),
    PlanPeriod.nextMonth => (DateTime(day.year, day.month + 1), 1),
    PlanPeriod.thisQuarter => (DateTime(day.year, quarterStart), 3),
    PlanPeriod.nextQuarter => (DateTime(day.year, quarterStart + 3), 3),
  };
  final end = DateTime(start.year, start.month + months, 0);
  final title = months == 1
      ? 'THÁNG ${start.month.toString().padLeft(2, '0')}/${start.year}'
      : 'QUÝ ${(start.month - 1) ~/ 3 + 1}/${start.year}';
  return PlanRange(start, end, title);
}

class PlannedDeadline {
  const PlannedDeadline(this.row, this.due, {required this.overdue});
  final TrackedDeadline row;
  final DateTime? due;
  final bool overdue;
}

/// Deadlines to prepare for in [period]. Items needing confirmation keep their
/// original date and are listed by it, so the plan never guesses a new date.
/// Unknown dates cannot be scheduled and stay in the "Cần cập nhật" queue.
List<PlannedDeadline> plannedDeadlines(
  List<TrackedDeadline> rows,
  PlanPeriod period,
  DateTime today, {
  bool includeOverdue = true,
}) {
  final day = dateOnly(today);
  final range = planRange(period, day);
  final from = range.start.isAfter(day) ? range.start : day;
  final result = <PlannedDeadline>[];
  for (final r in rows) {
    if (r.status == DeadlineStatus.excluded ||
        r.status == DeadlineStatus.done) {
      continue;
    }
    final due = effectiveDue(r.item);
    if (hasPastDeadline(r.item, day)) {
      if (includeOverdue) result.add(PlannedDeadline(r, due, overdue: true));
      continue;
    }
    if (due != null && !due.isBefore(from) && !due.isAfter(range.end)) {
      result.add(PlannedDeadline(r, due, overdue: false));
    }
  }
  result.sort((a, b) {
    final provider = a.row.item.provider.compareTo(b.row.item.provider);
    if (provider != 0) return provider;
    if (a.overdue != b.overdue) return a.overdue ? -1 : 1;
    final ad = a.due ?? DateTime(0), bd = b.due ?? DateTime(0);
    final date = ad.compareTo(bd);
    return date != 0
        ? date
        : a.row.equipment.name.compareTo(b.row.equipment.name);
  });
  return result;
}

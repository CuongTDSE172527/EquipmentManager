import 'package:flutter_test/flutter_test.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/domain/deadlines.dart';

void main() {
  final e = Equipment(id: 'e', name: 'Thiết bị kiểm thử');
  const s = AppSettings();
  DeadlineItem item({
    DateTime? due,
    DatePrecision precision = DatePrecision.day,
    ItemKind kind = ItemKind.maintenance,
    InsuranceMode mode = InsuranceMode.dated,
    bool done = false,
    bool confirm = false,
    int cycle = 0,
  }) => DeadlineItem(
    equipmentId: e.id,
    kind: kind,
    title: 'Kiểm thử',
    dueDate: due,
    precision: precision,
    insuranceMode: mode,
    isDone: done,
    requiresConfirmation: confirm,
    cycleMonths: cycle,
  );
  test('Cộng tháng chặn cuối tháng, năm nhuận và qua năm', () {
    expect(addMonths(DateTime(2025, 1, 31), 1), DateTime(2025, 2, 28));
    expect(addMonths(DateTime(2024, 1, 31), 1), DateTime(2024, 2, 29));
    expect(addMonths(DateTime(2024, 2, 29), 12), DateTime(2025, 2, 28));
    expect(addMonths(DateTime(2025, 12, 31), 2), DateTime(2026, 2, 28));
  });
  test('Hôm nay vẫn sắp hạn; ngưỡng gồm ngày cuối', () {
    final today = DateTime(2026, 11, 8);
    expect(
      statusOf(item(due: DateTime(2026, 11, 7)), e, s, today),
      DeadlineStatus.overdue,
    );
    expect(statusOf(item(due: today), e, s, today), DeadlineStatus.upcoming);
    expect(
      statusOf(item(due: DateTime(2026, 12, 8)), e, s, today),
      DeadlineStatus.upcoming,
    );
    expect(
      statusOf(item(due: DateTime(2026, 12, 9)), e, s, today),
      DeadlineStatus.valid,
    );
  });
  test('Hạn tháng chỉ quá hạn sau ngày cuối tháng', () {
    final i = item(due: DateTime(2024, 2, 1), precision: DatePrecision.month);
    expect(statusOf(i, e, s, DateTime(2024, 2, 29)), DeadlineStatus.upcoming);
    expect(statusOf(i, e, s, DateTime(2024, 3, 1)), DeadlineStatus.overdue);
  });
  test('Thiếu ngày và chưa có thông tin không coi là còn hạn', () {
    expect(statusOf(item(), e, s, DateTime(2026)), DeadlineStatus.needsUpdate);
    expect(
      statusOf(
        item(
          kind: ItemKind.insurance,
          mode: InsuranceMode.unknown,
          due: DateTime(2030),
        ),
        e,
        s,
        DateTime(2026),
      ),
      DeadlineStatus.needsUpdate,
    );
  });
  test('Các chế độ bảo hiểm và hạng mục hoàn thành', () {
    for (final mode in [
      InsuranceMode.centralized,
      InsuranceMode.notApplicable,
    ]) {
      expect(
        statusOf(
          item(kind: ItemKind.insurance, mode: mode),
          e,
          s,
          DateTime(2026),
        ),
        DeadlineStatus.excluded,
      );
    }
    expect(
      statusOf(
        item(kind: ItemKind.insurance, mode: InsuranceMode.expired),
        e,
        s,
        DateTime(2026),
      ),
      DeadlineStatus.overdue,
    );
    expect(
      statusOf(item(done: true), e, s, DateTime(2026)),
      DeadlineStatus.done,
    );
  });
  test(
    'Thiết bị ngừng quản lý không cảnh báo; chờ xác nhận là cần cập nhật',
    () {
      expect(
        statusOf(
          item(due: DateTime(2000)),
          e.copy({'managementStatus': 'handedOver'}),
          s,
          DateTime(2026),
        ),
        DeadlineStatus.excluded,
      );
      expect(
        statusOf(
          item(due: DateTime(2000), confirm: true),
          e,
          s,
          DateTime(2026),
        ),
        DeadlineStatus.needsUpdate,
      );
    },
  );
  test('Niên hạn dùng ngưỡng riêng', () {
    expect(
      statusOf(
        item(kind: ItemKind.lifespan, due: DateTime(2026, 5)),
        e,
        s,
        DateTime(2026),
      ),
      DeadlineStatus.upcoming,
    );
    expect(
      statusOf(item(due: DateTime(2026, 5)), e, s, DateTime(2026)),
      DeadlineStatus.valid,
    );
  });
  test('Gia hạn bảo hiểm/kiểm định theo hạn cũ, ghi lịch sử', () {
    for (final kind in [ItemKind.insurance, ItemKind.inspection]) {
      final result = completeItem(
        item(kind: kind, due: DateTime(2024, 1, 31), cycle: 1),
        doneDate: DateTime(2024, 2, 10),
        provider: 'Đơn vị thử',
        cost: 500000,
      );
      expect(result.item.dueDate, DateTime(2024, 2, 29));
      expect(result.history.doneDate, DateTime(2024, 2, 10));
      expect(result.history.cost, 500000);
      expect(result.item.isDone, false);
    }
  });
  test('Bảo dưỡng/sửa chữa/khác theo ngày thực hiện', () {
    for (final kind in [
      ItemKind.maintenance,
      ItemKind.repair,
      ItemKind.other,
    ]) {
      final result = completeItem(
        item(kind: kind, due: DateTime(2024, 1, 1), cycle: 1),
        doneDate: DateTime(2024, 1, 31),
        provider: '',
      );
      expect(result.item.dueDate, DateTime(2024, 2, 29));
    }
  });
  test('Gia hạn theo tháng giữ độ chính xác tháng', () {
    final result = completeItem(
      item(
        kind: ItemKind.inspection,
        due: DateTime(2024, 2, 29),
        cycle: 1,
        precision: DatePrecision.month,
      ),
      doneDate: DateTime(2024, 2, 10),
      provider: '',
    );
    expect(result.item.dueDate, DateTime(2024, 3, 31));
    expect(result.item.precision, DatePrecision.month);
  });
  test('Một lần sang đã xong; chặn hoàn thành hai lần', () {
    final result = completeItem(item(), doneDate: DateTime(2026), provider: '');
    expect(result.item.isDone, true);
    expect(
      () => completeItem(result.item, doneDate: DateTime(2026), provider: ''),
      throwsStateError,
    );
  });
  test('Không đoán hạn cũ khi gia hạn; cho nhập hạn đã xác nhận', () {
    final i = item(kind: ItemKind.insurance, cycle: 12);
    expect(
      () => completeItem(i, doneDate: DateTime(2026), provider: ''),
      throwsArgumentError,
    );
    expect(
      completeItem(
        i,
        doneDate: DateTime(2026),
        provider: '',
        explicitNextDate: DateTime(2027),
      ).item.dueDate,
      DateTime(2027),
    );
  });
  test('Đọc ngày chặt chẽ, không để Dart chuẩn hóa ngày sai', () {
    expect(parseVietnameseDate('05/2026').date, DateTime(2026, 5, 31));
    expect(parseVietnameseDate('29/02/2024').precision, DatePrecision.day);
    for (final text in [
      '31/02/2026',
      '29/02/2025',
      '13/2026',
      '00/2026',
      '2026-02-01',
      'abc',
    ]) {
      expect(() => parseVietnameseDate(text), throwsFormatException);
    }
  });
  test('Sắp xếp trạng thái rồi hạn tăng dần', () {
    final rows = trackedDeadlines(
      [e],
      [
        item(due: DateTime(2030)),
        item(),
        item(due: DateTime(2020)),
        item(due: DateTime(2026, 1, 2)),
        item(done: true),
      ],
      s,
      DateTime(2026),
    );
    expect(rows.map((r) => r.status), [
      DeadlineStatus.overdue,
      DeadlineStatus.upcoming,
      DeadlineStatus.needsUpdate,
      DeadlineStatus.valid,
      DeadlineStatus.done,
    ]);
  });
}

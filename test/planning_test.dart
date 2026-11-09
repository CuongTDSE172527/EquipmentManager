import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:equipment_manager/domain/deadlines.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/domain/planning.dart';
import 'package:equipment_manager/services/spreadsheets.dart';

void main() {
  test('Kỳ kế hoạch qua cuối năm và ranh giới quý', () {
    final dec = DateTime(2026, 12, 15);
    expect(planRange(PlanPeriod.thisMonth, dec).end, DateTime(2026, 12, 31));
    final next = planRange(PlanPeriod.nextMonth, dec);
    expect(next.start, DateTime(2027, 1, 1));
    expect(next.end, DateTime(2027, 1, 31));
    expect(next.title, 'THÁNG 01/2027');
    final quarter = planRange(PlanPeriod.thisQuarter, dec);
    expect(quarter.start, DateTime(2026, 10, 1));
    expect(quarter.end, DateTime(2026, 12, 31));
    expect(quarter.title, 'QUÝ 4/2026');
    final nextQuarter = planRange(PlanPeriod.nextQuarter, dec);
    expect(nextQuarter.start, DateTime(2027, 1, 1));
    expect(nextQuarter.end, DateTime(2027, 3, 31));
    expect(
      planRange(PlanPeriod.nextMonth, DateTime(2027, 1, 31)).end,
      DateTime(2027, 2, 28),
    );
  });

  test('Chọn hạng mục trong kỳ, quá hạn, bỏ loại trừ/đã xong/chưa có ngày', () {
    final today = DateTime(2026, 11, 9);
    const settings = AppSettings();
    final active = Equipment(name: 'Xe kéo');
    final retired = Equipment(
      name: 'Xe cũ',
      managementStatus: ManagementStatus.retired,
    );
    DeadlineItem item(
      String title, {
      DateTime? due,
      Equipment? e,
      ItemKind kind = ItemKind.maintenance,
      DatePrecision precision = DatePrecision.day,
      bool done = false,
      bool confirm = false,
      String provider = 'SAGS',
      InsuranceMode mode = InsuranceMode.dated,
    }) => DeadlineItem(
      equipmentId: (e ?? active).id,
      kind: kind,
      title: title,
      dueDate: due,
      precision: precision,
      isDone: done,
      requiresConfirmation: confirm,
      provider: provider,
      insuranceMode: mode,
    );
    final items = [
      item('Trong tháng sau', due: DateTime(2026, 12, 5)),
      // MM/yyyy counts to the last day of the month: 12/2026 -> 31/12/2026.
      item(
        'Theo tháng',
        due: DateTime(2026, 12, 1),
        precision: DatePrecision.month,
      ),
      item('Tháng 01', due: DateTime(2027, 1, 2)),
      item('Quá hạn', due: DateTime(2026, 10, 1), provider: 'Toyota'),
      item('Cần xác nhận', due: DateTime(2026, 9, 1), confirm: true),
      item('Đã xong', due: DateTime(2026, 12, 6), done: true),
      item('Chưa có ngày'),
      item('Thiết bị ngừng', due: DateTime(2026, 12, 7), e: retired),
      item(
        'ACV',
        kind: ItemKind.insurance,
        mode: InsuranceMode.centralized,
        due: DateTime(2026, 12, 8),
      ),
    ];
    final rows = trackedDeadlines([active, retired], items, settings, today);
    final plan = plannedDeadlines(rows, PlanPeriod.nextMonth, today);
    expect(plan.map((p) => p.row.item.title), [
      'Cần xác nhận',
      'Trong tháng sau',
      'Theo tháng',
      'Quá hạn',
    ]);
    expect(plan.first.overdue, isTrue);
    expect(plan[2].due, DateTime(2026, 12, 31));
    final only = plannedDeadlines(
      rows,
      PlanPeriod.nextMonth,
      today,
      includeOverdue: false,
    );
    expect(only.map((p) => p.row.item.title), [
      'Trong tháng sau',
      'Theo tháng',
    ]);
    final thisMonth = plannedDeadlines(
      rows,
      PlanPeriod.thisMonth,
      today,
      includeOverdue: false,
    );
    expect(thisMonth, isEmpty);

    final bytes = SpreadsheetService().planReport(
      plan,
      planRange(PlanPeriod.nextMonth, today),
      settings,
    );
    final book = Excel.decodeBytes(bytes);
    expect(book.tables.keys, containsAll(['Kế hoạch', 'Tổng hợp']));
    final text = book.tables['Kế hoạch']!.rows
        .expand((r) => r)
        .map((c) => c?.value?.toString() ?? '')
        .join('|');
    expect(text, contains('THÁNG 12/2026'));
    expect(text, contains('SAGS (3 hạng mục)'));
    expect(text, contains('Quá hạn, chưa xử lý • Cần xác nhận'));
    expect(text, contains('12/2026'));
  });
}

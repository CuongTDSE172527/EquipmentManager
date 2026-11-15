import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/importing.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/services/spreadsheets.dart';
import 'package:equipment_manager/ui/controller.dart';
import 'session_helper.dart';

Uint8List workbook(Map<String, List<List<String>>> sheets) {
  final book = Excel.createExcel();
  for (final entry in sheets.entries) {
    final sheet = book[entry.key];
    for (final row in entry.value) {
      sheet.appendRow([for (final v in row) TextCellValue(v)]);
    }
  }
  book.delete('Sheet1');
  return Uint8List.fromList(book.encode()!);
}

void main() {
  final today = DateTime(2026, 11, 15);

  test('Mẫu nhập có sheet Hạng mục theo dõi với đủ cột', () {
    final book = Excel.decodeBytes(SpreadsheetService().template());
    final rows = book.tables[itemSheetName]!.rows;
    expect(rows.first.map((c) => c?.value.toString()).toList(), itemColumns);
  });

  test('Sheet Hạng mục theo dõi: nhiều hạng mục tên riêng cho một thiết bị, '
      'ghép theo biển số rồi theo tên', () {
    final bytes = workbook({
      'Theo dõi': [
        trackingColumns,
        ['1', 'Xe nâng', '29C-12345', '01/2027', 'ACV mua', '', ''],
      ],
      itemSheetName: [
        itemColumns,
        [
          'Xe nâng',
          '29C-12345',
          'Đăng kiểm/Kiểm định',
          'Kiểm định cẩu',
          '15/03/2027',
          '12',
          'Trung tâm kiểm định',
          'Theo hợp đồng',
        ],
        ['xe nâng', '', 'Khác', 'Kiểm định bình áp lực', '06/2027', '', '', ''],
        [
          'Xe cứu hỏa',
          'CAH-01-001',
          'Bảo dưỡng',
          'Bảo dưỡng 500 giờ',
          '12/2026',
          '6',
          '',
          '',
        ],
        ['Xe cứu hỏa', 'CAH-01-001', 'Niên hạn', '', '12/2035', '5', '', ''],
        ['', '', 'Bảo hiểm', 'Bảo hiểm thân vỏ', '01/2027', '', '', ''],
      ],
    });
    final p = readWorkbook(bytes, 'mau.xlsx', today: today);
    expect(p.records, hasLength(2));
    final forklift = p.records.first;
    expect(forklift.equipment.name, 'Xe nâng');
    expect(forklift.items.map((i) => i.title), [
      'Đăng kiểm/Kiểm định',
      'Bảo hiểm',
      'Bảo dưỡng',
      'Kiểm định cẩu',
      'Kiểm định bình áp lực',
    ]);
    expect(
      forklift.items.every((i) => i.equipmentId == forklift.equipment.id),
      isTrue,
    );
    final crane = forklift.items[3];
    expect(crane.kind, ItemKind.inspection);
    expect(crane.dueDate, DateTime(2027, 3, 15));
    expect(crane.cycleMonths, 12);
    expect(crane.provider, 'Trung tâm kiểm định');
    expect(crane.note, 'Theo hợp đồng');
    final vessel = forklift.items[4];
    expect(vessel.kind, ItemKind.other);
    expect(vessel.precision, DatePrecision.month);

    final truck = p.records.last;
    expect(truck.equipment.name, 'Xe cứu hỏa');
    expect(truck.equipment.controlPlate, 'CAH-01-001');
    expect(truck.suppliedFields, isEmpty);
    expect(truck.items.map((i) => i.title), [
      'Bảo dưỡng 500 giờ',
      'Niên hạn sử dụng',
    ]);
    expect(truck.items.last.kind, ItemKind.lifespan);
    expect(truck.items.last.cycleMonths, 0);
    expect(
      p.issues.any((i) => i.message.contains('niên hạn không có chu kỳ')),
      isTrue,
    );
    expect(
      p.issues.where((i) => i.error).single.message,
      'Thiếu tên phương tiện hoặc biển số.',
    );
  });

  test('Hai thiết bị cùng tên trong file thì báo lỗi, không đoán', () {
    final p = readWorkbook(
      Uint8List.fromList(
        utf8.encode(
          [
            'STT,Tên phương tiện,Biển số,Hạn đăng kiểm,Hạn bảo hiểm,Bảo dưỡng tiếp theo,Ghi chú',
            '1,Xe đầu kéo,29C-11111,,,,',
            '2,Xe đầu kéo,29C-22222,,,,',
          ].join('\n'),
        ),
      ),
      'thiet-bi.csv',
      today: today,
      link: false,
    );
    p.add(
      readWorkbook(
        Uint8List.fromList(
          utf8.encode(
            [
              itemColumns.join(','),
              'Xe đầu kéo,,Khác,Kiểm định mâm kéo,01/2027,,,',
              'Xe đầu kéo,29C-22222,Khác,Kiểm định mâm kéo,02/2027,,,',
            ].join('\n'),
          ),
        ),
        'hang-muc.csv',
        today: today,
        link: false,
      ),
    );
    p.linkItems();
    expect(p.records, hasLength(2));
    expect(p.issues.where((i) => i.error), hasLength(1));
    expect(
      p.records.first.items.where((i) => i.title.contains('mâm')),
      isEmpty,
    );
    expect(
      p.records.last.items.singleWhere((i) => i.title.contains('mâm')).dueDate,
      DateTime(2027, 2, 28),
    );
  });

  test('Ghép hạng mục vào thiết bị có sẵn: không đổi thông tin thiết bị, '
      'cập nhật hạng mục cùng tên, thêm hạng mục mới', () async {
    final db = AppDatabase.memory();
    final repo = EquipmentRepository(db);
    final c = AppController(repo, clock: () => today);
    try {
      final e = Equipment(
        name: 'Xe cứu hỏa chuyên dụng',
        group: 'II. Khẩn nguy',
        controlPlate: 'CAH-01-001',
      );
      await repo.saveEquipment(e);
      final old = DeadlineItem(
        equipmentId: e.id,
        kind: ItemKind.maintenance,
        title: 'Bảo dưỡng 500 giờ',
        dueDate: DateTime(2026, 12, 1),
      );
      await repo.saveItem(old);
      await signInForTest(c);
      await c.load();
      final p = readWorkbook(
        Uint8List.fromList(
          utf8.encode(
            [
              itemColumns.join(','),
              'Xe cứu hỏa,CAH-01-001,Bảo dưỡng,Bảo dưỡng 500 giờ,15/06/2027,6,,',
              'Xe cứu hỏa,CAH-01-001,Khác,Kiểm định bình áp lực,06/2027,12,,',
            ].join('\n'),
          ),
        ),
        'hang-muc.csv',
        today: today,
      );
      p.suggestMatches(c.equipment);
      final r = p.records.single;
      expect(r.suggestedIds, [e.id]);
      r.targetId = e.id;
      r.approved = true;
      await c.importPlan(p, confirmPast: true);
      final saved = (await repo.equipment()).single;
      expect(saved.toJson(), e.toJson());
      final items = await repo.items();
      expect(items, hasLength(2));
      final updated = items.singleWhere((i) => i.id == old.id);
      expect(updated.dueDate, DateTime(2027, 6, 15));
      expect(updated.cycleMonths, 6);
      expect(
        items.singleWhere((i) => i.id != old.id).title,
        'Kiểm định bình áp lực',
      );
    } finally {
      c.dispose();
      await db.close();
    }
  });
}

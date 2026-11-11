import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/domain/importing.dart';
import 'package:equipment_manager/services/spreadsheets.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/ui/controller.dart';
import 'session_helper.dart';

void main() {
  test('Nhận tiêu đề nhóm I/II ở cột STT, cho đánh số lại trong mỗi nhóm', () {
    final p = ImportPlan();
    parseEquipmentRows(
      p,
      'Nguồn giả lập',
      [
        trackingColumns,
        ['I', 'Phục vụ bay'],
        ['1', 'Xe thử A', 'CAH-99-001', '', 'ACV mua', '', ''],
        ['II', 'Khẩn nguy'],
        ['1', 'Xe thử B', 'CAH-99-002', '', 'ACV mua', '', ''],
      ],
      metadataOnly: false,
      today: DateTime(2026, 11, 9),
    );
    expect(p.readRows, 2);
    expect(p.records.map((r) => r.equipment.group), [
      'I. Phục vụ bay',
      'II. Khẩn nguy',
    ]);
    expect(p.issues.any((i) => i.message.contains('Trùng STT')), false);
  });
  test('Ghép phụ lục giữ tên chi tiết, mã thiết bị và lịch sử đã có', () async {
    final db = AppDatabase.memory();
    final repo = EquipmentRepository(db);
    final c = AppController(repo);
    try {
      final e = Equipment(name: 'Xe thử Model ABC123', note: 'Ghi chú ban đầu');
      await repo.saveEquipment(e);
      final i = DeadlineItem(
        equipmentId: e.id,
        kind: ItemKind.maintenance,
        title: 'Bảo dưỡng',
      );
      await repo.saveItem(i);
      final log = HistoryLog(
        itemId: i.id,
        doneDate: DateTime(2026, 1, 1),
        provider: 'Đơn vị thử',
      );
      await repo.recordCompletion(i, log);
      await signInForTest(c);
      final metadata = Equipment(
        name: 'Xe thử',
        controlPlate: 'CAH-99-999',
        country: 'Việt Nam',
        yearMade: 2026,
      );
      final p = ImportPlan();
      p.records.add(
        ImportRecord(
          source: 'Phụ lục giả lập',
          row: 2,
          equipment: metadata,
          items: [],
          metadataOnly: true,
          suppliedFields: {'name', 'controlPlate', 'country', 'yearMade'},
          targetId: e.id,
          approved: true,
        ),
      );
      await c.importPlan(p, confirmPast: true);
      final merged = (await repo.equipment()).single;
      expect(merged.id, e.id);
      expect(merged.name, e.name);
      expect(merged.controlPlate, 'CAH-99-999');
      expect(merged.note, contains('Tên trong phụ lục: Xe thử'));
      expect((await repo.history()).single.toJson(), log.toJson());
    } finally {
      c.dispose();
      await db.close();
    }
  });
  final today = DateTime(2026, 11, 8);
  test('Giá trị đặc biệt bảo hiểm, kiểm định và hạn theo tháng', () {
    expect(
      parseImportedDeadline('ACV mua', 'e', ItemKind.insurance)!.insuranceMode,
      InsuranceMode.centralized,
    );
    expect(
      parseImportedDeadline('Hết', 'e', ItemKind.insurance)!.insuranceMode,
      InsuranceMode.expired,
    );
    expect(
      parseImportedDeadline(
        'Hết ĐK',
        'e',
        ItemKind.inspection,
      )!.expiredWithoutDate,
      true,
    );
    expect(
      parseImportedDeadline('05/2026', 'e', ItemKind.maintenance)!.precision,
      DatePrecision.month,
    );
    expect(
      parseImportedDeadline('Không áp dụng', 'e', ItemKind.inspection),
      null,
    );
    expect(
      parseImportedDeadline('', 'e', ItemKind.insurance)!.insuranceMode,
      InsuranceMode.unknown,
    );
  });
  test('Không tự ghép biển cũ khác định dạng, kể cả tên trùng', () {
    final existing = Equipment(name: 'Xe giả lập', controlPlate: 'CAH-01-001');
    final p = ImportPlan();
    parseEquipmentRows(
      p,
      'giả lập',
      [
        trackingColumns,
        ['1', 'Xe giả lập', 'CAH-10101', '', 'ACV mua', '05/2026', ''],
      ],
      metadataOnly: false,
      today: today,
    );
    p.suggestMatches([existing]);
    expect(p.records.single.targetId, null);
    expect(p.records.single.approved, false);
    expect(p.ready, false);
    expect(plateKey('CAH-10101'), isNot(plateKey('CAH-01-001')));
    expect(p.records.single.suggestedIds, [existing.id]);
  });
  test('Báo sai ngày, thiếu cột và trùng STT, giữ đúng số dòng', () {
    final p = ImportPlan();
    parseEquipmentRows(
      p,
      'giả lập',
      [
        trackingColumns,
        ['18', 'A', 'A', '31/02/2026', '', '', ''],
        ['18', 'B', 'B', '', '', '', ''],
      ],
      metadataOnly: false,
      today: today,
    );
    expect(p.readRows, 2);
    expect(p.hasErrors, true);
    expect(p.issues.any((i) => i.message.contains('Trùng STT 18')), true);
    final missing = ImportPlan();
    parseEquipmentRows(
      missing,
      'sai cột',
      [
        ['Tên phương tiện'],
        ['X'],
      ],
      metadataOnly: false,
      today: today,
    );
    expect(missing.hasErrors, true);
  });
  test('Tách ghi chú nhưng giữ nguyên văn bản gốc', () {
    final p = ImportPlan();
    parseEquipmentRows(
      p,
      'giả lập',
      [
        trackingColumns,
        [
          '1',
          'Xe thử',
          '69A-00001',
          '',
          '',
          '05/2026',
          'Bảo dưỡng SAGS thực hiện; 12/2026 hết niên hạn SD; Bàn giao cho BQLDA',
        ],
      ],
      metadataOnly: false,
      today: today,
    );
    final record = p.records.single;
    expect(record.equipment.managementStatus, ManagementStatus.handedOver);
    expect(
      record.items.firstWhere((i) => i.kind == ItemKind.maintenance).provider,
      'SAGS',
    );
    expect(
      record.items.firstWhere((i) => i.kind == ItemKind.lifespan).dueDate,
      DateTime(2026, 12, 31),
    );
    expect(record.equipment.note, contains('Bàn giao'));
  });
  test('CSV có BOM, dấu chấm phẩy; file hỏng trả lỗi', () {
    final text =
        '\uFEFF${trackingColumns.join(';')}\r\n1;Xe thử;ABC;;ACV mua;05/2026;';
    final p = readWorkbook(
      Uint8List.fromList(utf8.encode(text)),
      'a.csv',
      today: today,
    );
    expect(p.records.length, 1);
    expect(
      () =>
          readWorkbook(Uint8List.fromList([1, 2, 3]), 'bad.xlsx', today: today),
      throwsA(anything),
    );
  });
  test(
    'Nhập đã duyệt trong giao dịch, bảo toàn mã và lịch sử khi ghép',
    () async {
      final db = AppDatabase.memory();
      final repo = EquipmentRepository(db);
      final c = AppController(repo, clock: () => today);
      try {
        final existing = Equipment(
          name: 'Xe thử',
          oldControlPlate: 'CAH-10101',
        );
        await repo.saveEquipment(existing);
        await signInForTest(c);
        final p = ImportPlan();
        parseEquipmentRows(
          p,
          'giả lập',
          [
            trackingColumns,
            ['1', 'Xe thử', 'CAH-10101', '', 'ACV mua', '05/2026', ''],
          ],
          metadataOnly: false,
          today: today,
        );
        p.records.single.targetId = existing.id;
        p.records.single.approved = true;
        await c.importPlan(p, confirmPast: true);
        expect((await repo.equipment()).single.id, existing.id);
        expect(
          (await repo.items())
              .firstWhere((i) => i.kind == ItemKind.maintenance)
              .requiresConfirmation,
          true,
        );
      } finally {
        c.dispose();
        await db.close();
      }
    },
  );
}

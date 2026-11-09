import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/domain/deadlines.dart';
import 'package:equipment_manager/domain/service_history.dart';
import 'package:equipment_manager/services/spreadsheets.dart';

void main() {
  test(
    'Ghi/sửa/xóa sổ độc lập, giữ hạn, gom lịch sử cũ và sao lưu đầy đủ',
    () async {
      final db = AppDatabase.memory();
      final other = AppDatabase.memory();
      final repo = EquipmentRepository(db);
      try {
        final e = Equipment(name: 'Xe thử', controlPlate: 'CAH-99-888');
        await repo.saveEquipment(e);
        final item = DeadlineItem(
          equipmentId: e.id,
          kind: ItemKind.maintenance,
          title: 'Bảo dưỡng định kỳ',
          dueDate: DateTime(2026, 12, 1),
          cycleMonths: 6,
        );
        await repo.saveItem(item);
        final completion = completeItem(
          item,
          doneDate: DateTime(2026, 10, 1),
          cost: 100000,
          provider: 'Đơn vị A',
        );
        await repo.recordCompletion(completion.item, completion.history);
        final originalItem = (await repo.items()).single.toJson();
        final record = ServiceRecord(
          equipmentId: e.id,
          kind: ItemKind.repair,
          title: 'Thay ắc quy',
          doneDate: DateTime(2026, 11, 2),
          cost: 2500000,
          provider: 'Đơn vị B',
          note: 'Đã kiểm tra sau sửa chữa',
        );
        await repo.saveServiceRecord(record);
        await repo.saveServiceRecord(
          ServiceRecord.fromJson({...record.toJson(), 'cost': 2400000}),
        );
        expect(await repo.catalog('provider'), contains('Đơn vị B'));
        expect((await repo.items()).single.toJson(), originalItem);
        final visits = serviceVisits(
          await repo.equipment(),
          await repo.items(),
          await repo.history(),
          await repo.serviceRecords(),
        );
        expect(visits.map((v) => v.title), [
          'Thay ắc quy',
          'Bảo dưỡng định kỳ',
        ]);
        expect(visits.first.cost, 2400000);
        expect(visits.last.record, isNull);
        final backup = await repo.snapshot();
        await EquipmentRepository(other).restore(backup);
        expect(await EquipmentRepository(other).snapshot(), backup);
        final bytes = SpreadsheetService().itemsReport(
          [],
          await repo.history(),
          const AppSettings(),
          equipment: [e],
          serviceRecords: await repo.serviceRecords(),
          serviceItems: await repo.items(),
        );
        final sheet = Excel.decodeBytes(bytes)['Bảo trì sửa chữa'];
        expect(sheet.rows.length, 6);
        expect(sheet.rows[4][3]!.value.toString(), 'Thay ắc quy');
        expect(sheet.rows[4][5]!.value, isA<IntCellValue>());
        await repo.deleteItem(item.id);
        expect(await repo.serviceRecords(), hasLength(1));
        await repo.deleteServiceRecord(record.id);
        expect(await repo.serviceRecords(), isEmpty);
        await repo.saveServiceRecord(record);
        await repo.deleteEquipment(e.id);
        expect(await repo.serviceRecords(), isEmpty);
      } finally {
        await db.close();
        await other.close();
      }
    },
  );

  test('Nâng schema v1 lên v2 giữ thiết bị, hạn và lịch sử cũ', () async {
    final directory = await Directory.systemTemp.createTemp(
      'equipment-migration-',
    );
    final file = File('${directory.path}/v1.db');
    final original = AppDatabase.open(file);
    final e = Equipment(name: 'Dữ liệu phiên bản trước');
    final item = DeadlineItem(
      equipmentId: e.id,
      kind: ItemKind.repair,
      title: 'Sửa máy',
    );
    final repo = EquipmentRepository(original);
    await repo.saveEquipment(e);
    await repo.saveItem(item);
    final completed = completeItem(
      item,
      doneDate: DateTime(2026),
      provider: '',
    );
    await repo.recordCompletion(completed.item, completed.history);
    await original.customStatement('DROP TABLE service_records');
    await original.customStatement('DROP TABLE attachments');
    await original.customStatement('PRAGMA user_version = 1');
    await original.close();
    final upgraded = AppDatabase.open(file);
    try {
      final next = EquipmentRepository(upgraded);
      expect((await next.equipment()).single.toJson(), e.toJson());
      expect((await next.items()).single.toJson(), completed.item.toJson());
      expect(
        (await next.history()).single.toJson(),
        completed.history.toJson(),
      );
      expect(await next.serviceRecords(), isEmpty);
      await next.saveServiceRecord(
        ServiceRecord(
          equipmentId: e.id,
          kind: ItemKind.repair,
          title: 'Sửa sau nâng cấp',
          doneDate: DateTime(2026),
        ),
      );
      expect(await next.serviceRecords(), hasLength(1));
    } finally {
      await upgraded.close();
    }
    // Delete only the explicitly created fixture files, without recursive paths.
    for (final entry in await directory.list().toList()) {
      await entry.delete();
    }
    await directory.delete();
  });

  test(
    'Khôi phục backup v1; backup v2 sai liên kết không thay dữ liệu hiện tại',
    () async {
      final db = AppDatabase.memory();
      final repo = EquipmentRepository(db);
      try {
        final e = Equipment(name: 'Thiết bị nguồn');
        await repo.saveEquipment(e);
        final legacy = await repo.snapshot();
        legacy['version'] = 1;
        legacy.remove('serviceRecords');
        await repo.restore(legacy);
        expect((await repo.equipment()).single.id, e.id);
        final record = ServiceRecord(
          equipmentId: e.id,
          kind: ItemKind.maintenance,
          title: 'Bảo trì',
          doneDate: DateTime(2026),
        );
        await repo.saveServiceRecord(record);
        final baseline = await repo.snapshot();
        final broken = {
          ...baseline,
          'serviceRecords': [
            {...record.toJson(), 'equipmentId': 'missing'},
          ],
        };
        await expectLater(repo.restore(broken), throwsFormatException);
        expect(await repo.snapshot(), baseline);
        final invalid = {
          ...baseline,
          'serviceRecords': [
            {...record.toJson(), 'cost': -1},
          ],
        };
        await expectLater(repo.restore(invalid), throwsFormatException);
        expect(await repo.snapshot(), baseline);
      } finally {
        await db.close();
      }
    },
  );
}

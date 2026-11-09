import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/domain/updates.dart';
import 'package:equipment_manager/services/update_installer.dart';

void main() {
  test('Backup OTA nhất quán và khôi phục được toàn bộ sổ bảo trì', () async {
    final root = await Directory.systemTemp.createTemp('equipment-ota-backup-');
    final db = AppDatabase.memory();
    final other = AppDatabase.memory();
    final repo = EquipmentRepository(db);
    try {
      final e = Equipment(name: 'Thiết bị trước cập nhật');
      await repo.saveEquipment(e);
      await repo.saveServiceRecord(
        ServiceRecord(
          equipmentId: e.id,
          kind: ItemKind.repair,
          title: 'Sửa máy',
          doneDate: DateTime(2026, 11, 1),
          cost: 250000,
        ),
      );
      final before = await repo.snapshot();
      final file = await createUpdateBackup(
        repo,
        root,
        const AppVersion(0, 1, 5),
      );
      final data = jsonDecode(await file.readAsString()) as Json;
      expect(data, before);
      await EquipmentRepository(other).restore(data);
      expect(await EquipmentRepository(other).snapshot(), before);
      expect((await repo.settings()).lastBackup, isNotNull);
      expect(await File('${file.path}.part').exists(), false);
    } finally {
      await db.close();
      await other.close();
      for (final file in await root.list().toList()) {
        await file.delete();
      }
      await root.delete();
    }
  });
}

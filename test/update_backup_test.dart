import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:equipment_manager/data/backup_archive.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/domain/updates.dart';
import 'package:equipment_manager/services/update_installer.dart';

void main() {
  test(
    'Backup OTA nhất quán, kèm tệp đính kèm, khôi phục được toàn bộ',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'equipment-ota-backup-',
      );
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
        final pdf = Uint8List.fromList(utf8.encode('%PDF-1.4 giấy đăng kiểm'));
        await repo.addAttachment(
          Attachment(
            equipmentId: e.id,
            fileName: 'dang-kiem.pdf',
            size: pdf.length,
            sha256: sha256.convert(pdf).toString(),
          ),
          pdf,
        );
        final before = await repo.snapshot();
        final file = await createUpdateBackup(
          repo,
          root,
          const AppVersion(0, 3, 0),
        );
        expect(file.path, endsWith('.backup.zip'));
        final bundle = await readBackupFile(file);
        expect(bundle.data, before);
        expect(bundle.files.values.single, pdf);
        await restoreBundle(EquipmentRepository(other), bundle);
        expect(await EquipmentRepository(other).snapshot(), before);
        final copy = (await EquipmentRepository(other).attachments()).single;
        expect(await EquipmentRepository(other).attachmentData(copy.id), pdf);
        expect((await repo.settings()).lastBackup, isNotNull);
        expect(await File('${file.path}.part').exists(), false);
      } finally {
        await db.close();
        await other.close();
        await root.delete(recursive: true);
      }
    },
  );
}

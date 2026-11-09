import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:equipment_manager/data/backup_archive.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/services/auto_backup.dart';

void main() {
  late Directory root;
  late AppDatabase db;
  late EquipmentRepository repo;
  late AutoBackupService service;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('equipment-auto-backup-');
    db = AppDatabase.memory();
    repo = EquipmentRepository(db);
    service = AutoBackupService(root: () async => root, keep: 3);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  test('Đến hạn theo chu kỳ, tắt được và mặc định bật 7 ngày', () {
    const defaults = AppSettings();
    expect(defaults.autoBackupEnabled, isTrue);
    expect(defaults.autoBackupDays, 7);
    final now = DateTime(2026, 11, 9, 8);
    expect(AutoBackupService.due(defaults, now), isTrue);
    final recent = defaults.copy({
      'lastAutoBackup': DateTime(2026, 11, 3, 23).toIso8601String(),
    });
    expect(AutoBackupService.due(recent, now), isFalse);
    final old = defaults.copy({
      'lastAutoBackup': DateTime(2026, 11, 2).toIso8601String(),
    });
    expect(AutoBackupService.due(old, now), isTrue);
    expect(
      AutoBackupService.due(old.copy({'autoBackupEnabled': false}), now),
      isFalse,
    );
  });

  test('Bỏ qua dữ liệu trống, xoay vòng và khôi phục được', () async {
    expect(await service.runIfDue(repo, DateTime(2026, 11, 1)), isNull);
    final e = Equipment(name: 'Xe nâng thử');
    await repo.saveEquipment(e);
    await repo.saveItem(
      DeadlineItem(equipmentId: e.id, kind: ItemKind.repair, title: 'Sửa'),
    );
    final first = await service.runIfDue(repo, DateTime(2026, 11, 1, 7));
    expect(first, isNotNull);
    expect((await repo.settings()).lastAutoBackup, DateTime(2026, 11, 1, 7));
    expect((await repo.settings()).lastBackup, isNull);
    expect(await service.runIfDue(repo, DateTime(2026, 11, 3)), isNull);
    for (var day = 8; day <= 29; day += 7) {
      expect(await service.runIfDue(repo, DateTime(2026, 11, day)), isNotNull);
    }
    await service.create(
      repo,
      DateTime(2026, 11, 30, 9, 15),
      beforeRestore: true,
    );
    // Unrelated files in the folder are never listed or removed.
    final foreign = File(
      p.join((await service.directory()).path, 'ghi-chu.txt'),
    );
    await foreign.writeAsString('giữ nguyên');
    final files = await service.list();
    expect(files.length, 3);
    expect(files.first.created, DateTime(2026, 11, 30, 9, 15));
    expect(files.first.beforeRestore, isTrue);
    expect(files.last.created, DateTime(2026, 11, 22));
    expect(await foreign.exists(), isTrue);
    expect(
      (await service.directory()).listSync().where(
        (f) => f.path.endsWith('.part'),
      ),
      isEmpty,
    );

    final other = AppDatabase.memory();
    final restored = EquipmentRepository(other);
    await restoreBundle(restored, await service.read(files.last));
    expect((await restored.equipment()).single.name, 'Xe nâng thử');
    expect((await restored.items()).single.title, 'Sửa');
    await other.close();
  });
}

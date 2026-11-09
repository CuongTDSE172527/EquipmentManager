import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:equipment_manager/data/backup_archive.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/services/attachment_files.dart';
import 'package:equipment_manager/services/auto_backup.dart';

Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

Attachment draft(String equipmentId, Uint8List data, {String name = 'a.pdf'}) =>
    Attachment(
      equipmentId: equipmentId,
      fileName: name,
      size: data.length,
      sha256: sha256.convert(data).toString(),
    );

void main() {
  late AppDatabase db;
  late EquipmentRepository repo;
  late Equipment e;
  setUp(() async {
    db = AppDatabase.memory();
    repo = EquipmentRepository(db);
    e = Equipment(name: 'Xe cá»©u há»a');
    await repo.saveEquipment(e);
  });
  tearDown(() => db.close());

  test(
    'ThÃªm, Ä‘á»c, sá»­a, xÃ³a; tá»« chá»‘i tá»‡p sai ná»™i dung, loáº¡i hoáº·c kÃ­ch thÆ°á»›c',
    () async {
      final data = bytesOf('%PDF há»£p Ä‘á»“ng báº£o hiá»ƒm');
      final a = draft(e.id, data);
      await repo.addAttachment(a, data);
      expect((await repo.attachments()).single.title, 'a.pdf');
      expect(await repo.attachmentData(a.id), data);
      await repo.updateAttachment(
        a.copy({'title': 'Há»£p Ä‘á»“ng 2026', 'note': 'Báº£n scan'}),
      );
      expect((await repo.attachments()).single.title, 'Há»£p Ä‘á»“ng 2026');
      await expectLater(
        repo.updateAttachment(a.copy({'sha256': '0' * 64})),
        throwsFormatException,
      );
      await expectLater(
        repo.addAttachment(draft(e.id, data), bytesOf('khÃ¡c')),
        throwsFormatException,
      );
      await expectLater(
        repo.addAttachment(draft(e.id, data, name: 'virus.exe'), data),
        throwsFormatException,
      );
      await expectLater(
        repo.addAttachment(draft(e.id, data, name: '../x.pdf'), data),
        throwsFormatException,
      );
      final big = Uint8List(maxAttachmentBytes + 1);
      await expectLater(
        repo.addAttachment(draft(e.id, big), big),
        throwsFormatException,
      );
      await repo.deleteAttachment(a.id);
      expect(await repo.attachments(), isEmpty);
    },
  );

  test(
    'XÃ³a háº¡ng má»¥c/sá»• báº£o trÃ¬ giá»¯ tá»‡p; xÃ³a thiáº¿t bá»‹ xÃ³a tá»‡p',
    () async {
      final item = DeadlineItem(
        equipmentId: e.id,
        kind: ItemKind.inspection,
        title: 'ÄÄƒng kiá»ƒm',
      );
      await repo.saveItem(item);
      final record = ServiceRecord(
        equipmentId: e.id,
        kind: ItemKind.repair,
        title: 'Thay lá»‘p',
        doneDate: DateTime(2026, 10, 1),
      );
      await repo.saveServiceRecord(record);
      final d1 = bytesOf('giáº¥y Ä‘Äƒng kiá»ƒm'), d2 = bytesOf('biÃªn báº£n');
      await repo.addAttachment(draft(e.id, d1).copy({'linkId': item.id}), d1);
      await repo.addAttachment(
        draft(e.id, d2, name: 'b.jpg').copy({'linkId': record.id}),
        d2,
      );
      await repo.deleteItem(item.id);
      await repo.deleteServiceRecord(record.id);
      final kept = await repo.attachments();
      expect(kept.length, 2);
      expect(kept.every((a) => a.linkId == null), isTrue);
      await repo.deleteEquipment(e.id);
      expect(await repo.attachments(), isEmpty);
    },
  );

  test(
    'Sao lÆ°u ZIP khÃ´i phá»¥c Ä‘á»§ tá»‡p; thiáº¿u/há»ng tá»‡p khÃ´ng Ä‘á»¥ng dá»¯ liá»‡u',
    () async {
      final data = bytesOf('áº£nh giáº¥y tá»');
      await repo.addAttachment(draft(e.id, data, name: 'giay.png'), data);
      final zip = await encodeBackup(repo);
      final bundle = decodeBackup(zip);
      expect(bundle.data['version'], 3);
      expect(bundle.attachmentCount, 1);

      final other = AppDatabase.memory();
      final target = EquipmentRepository(other);
      try {
        final keep = Equipment(name: 'Äang cÃ³');
        await target.saveEquipment(keep);
        final missing = BackupBundle(bundle.data);
        await expectLater(
          restoreBundle(target, missing),
          throwsFormatException,
        );
        final corrupt = BackupBundle(bundle.data, {
          for (final id in bundle.files.keys) id: bytesOf('sai'),
        });
        await expectLater(
          restoreBundle(target, corrupt),
          throwsFormatException,
        );
        expect((await target.equipment()).single.name, 'Äang cÃ³');

        await restoreBundle(target, bundle);
        expect(await target.snapshot(), await repo.snapshot());
        final a = (await target.attachments()).single;
        expect(await target.attachmentData(a.id), data);

        // Formats 1â€“2 have no attachments: restoring one replaces them too.
        final legacy = await repo.snapshot()
          ..['version'] = 2
          ..remove('attachments');
        await target.restore(legacy);
        expect(await target.attachments(), isEmpty);
        expect((await target.equipment()).single.name, 'Xe cá»©u há»a');
      } finally {
        await other.close();
      }
    },
  );

  test(
    'Äá»c JSON cÅ©; cháº·n ZIP thiáº¿u backup.json hoáº·c tÃªn tá»‡p vÆ°á»£t thÆ° má»¥c',
    () {
      final legacy = decodeBackup(
        bytesOf(jsonEncode({'format': 'EquipmentManager', 'version': 2})),
      );
      expect(legacy.files, isEmpty);
      expect(legacy.data['version'], 2);
      Uint8List zip(Map<String, List<int>> files) {
        final archive = Archive();
        for (final f in files.entries) {
          archive.addFile(ArchiveFile(f.key, f.value.length, f.value));
        }
        return Uint8List.fromList(ZipEncoder().encode(archive)!);
      }

      expect(
        () => decodeBackup(zip({'attachments/x': bytesOf('a')})),
        throwsFormatException,
      );
      expect(
        () => decodeBackup(
          zip({
            'backup.json': bytesOf('{}'),
            'attachments/../../evil': bytesOf('a'),
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => decodeBackup(bytesOf('khÃ´ng pháº£i json')),
        throwsFormatException,
      );
    },
  );

  test(
    'NÃ¢ng database schema 2 lÃªn 3 giá»¯ nguyÃªn dá»¯ liá»‡u cÅ©',
    () async {
      final root = await Directory.systemTemp.createTemp('equipment-schema-');
      final path = p.join(root.path, 'equipment_manager.db');
      try {
        final legacy = AppDatabase.open(File(path));
        final old = EquipmentRepository(legacy);
        final kept = Equipment(name: 'Thiáº¿t bá»‹ tá»« 0.2.0');
        await old.saveEquipment(kept);
        await legacy.close();
        // Turn the file back into the 0.2.0 layout.
        final raw = sqlite3.open(path);
        raw.execute('DROP TABLE attachments');
        raw.execute('PRAGMA user_version = 2');
        raw.close();

        final upgraded = AppDatabase.open(File(path));
        final repo3 = EquipmentRepository(upgraded);
        expect((await repo3.equipment()).single.id, kept.id);
        final data = bytesOf('tá»‡p sau nÃ¢ng cáº¥p');
        await repo3.addAttachment(draft(kept.id, data), data);
        expect((await repo3.attachments()).length, 1);
        await upgraded.close();
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'Sao lÆ°u tá»± Ä‘á»™ng: Ä‘á»c báº£n JSON cá»§a 0.2.0, giá»›i háº¡n tá»•ng dung lÆ°á»£ng',
    () async {
      final root = await Directory.systemTemp.createTemp('equipment-auto-zip-');
      try {
        final service = AutoBackupService(
          root: () async => root,
          keep: 10,
          maxTotalBytes: 1,
          minKeep: 2,
        );
        final folder = await service.directory();
        await folder.create(recursive: true);
        final old = File(
          p.join(folder.path, 'auto-20261101-080000000000.backup.json'),
        );
        await old.writeAsString(
          jsonEncode(
            await repo.snapshot()
              ..['version'] = 2,
          ),
        );
        expect((await service.list()).single.file.path, old.path);
        expect(
          (await service.read((await service.list()).single)).data['version'],
          2,
        );
        for (var day = 2; day <= 4; day++) {
          await service.create(repo, DateTime(2026, 11, day));
        }
        final files = await service.list();
        // Over the size cap, only the newest two are kept.
        expect(files.length, 2);
        expect(files.first.file.path, endsWith('.backup.zip'));
        expect(files.last.created, DateTime(2026, 11, 3));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'TÃªn tá»‡p má»Ÿ táº¡m an toÃ n, giá»¯ tiáº¿ng Viá»‡t vÃ  pháº§n má»Ÿ rá»™ng',
    () {
      final a = draft(
        'x',
        bytesOf('a'),
        name: 'scan.PDF',
      ).copy({'title': 'Giáº¥y Ä‘Äƒng kiá»ƒm: xe/kÃ©o*01'});
      expect(
        AttachmentOpener.safeName(a),
        'Giáº¥y Ä‘Äƒng kiá»ƒm xe kÃ©o 01.pdf',
      );
      expect(
        AttachmentOpener.safeName(a.copy({'title': 'hop-dong.pdf'})),
        'hop-dong.pdf',
      );
    },
  );
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:equipment_manager/data/backup_archive.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/models.dart';

Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

Attachment draft(
  String equipmentId,
  Uint8List data, {
  String name = 'a.pdf',
  String folder = '',
}) => Attachment(
  equipmentId: equipmentId,
  fileName: name,
  size: data.length,
  sha256: sha256.convert(data).toString(),
  folder: folder,
);

void main() {
  late AppDatabase db;
  late EquipmentRepository repo;
  late Equipment e;
  setUp(() async {
    db = AppDatabase.memory();
    repo = EquipmentRepository(db);
    e = Equipment(name: 'Xe cứu hỏa');
    await repo.saveEquipment(e);
  });
  tearDown(() => db.close());

  test('Tên thư mục được chuẩn hóa và kiểm tra', () {
    expect(
      normalizeFolder(r' Pháp lý\Đăng kiểm/ 2026 /'),
      'Pháp lý/Đăng kiểm/2026',
    );
    expect(folderProblem(''), isNull);
    expect(folderProblem('Pháp lý/Đăng kiểm'), isNull);
    expect(folderProblem('a/../b'), isNotNull);
    expect(folderProblem('a:b'), isNotNull);
    expect(folderProblem(List.filled(9, 'a').join('/')), isNotNull);
  });

  test('Nhận mọi loại tệp trừ chương trình/script; giới hạn mới', () async {
    for (final name in ['ban-ve.dwg', 'video.mp4', 'ho-so.zip', 'GHI-CHU']) {
      final data = bytesOf('nội dung $name');
      await repo.addAttachment(draft(e.id, data, name: name), data);
    }
    expect(await repo.attachments(), hasLength(4));
    for (final name in ['cai-dat.exe', 'chay.bat', 'x.ps1', 'lien-ket.lnk']) {
      final data = bytesOf(name);
      await expectLater(
        repo.addAttachment(draft(e.id, data, name: name), data),
        throwsFormatException,
      );
    }
    expect(maxAttachmentBytes, 100 * 1024 * 1024);
    final data = bytesOf('x');
    await expectLater(
      repo.addAttachment(draft(e.id, data, folder: 'a/../b'), data),
      throwsFormatException,
    );
    await expectLater(
      repo.addAttachment(draft(e.id, data, folder: ' Pháp lý '), data),
      throwsFormatException,
      reason: 'Thư mục phải được chuẩn hóa trước khi lưu',
    );
  });

  test(
    'Đổi tên, chuyển và xóa thư mục kèm thư mục con; sao lưu giữ thư mục',
    () async {
      final other = Equipment(name: 'Xe nâng');
      await repo.saveEquipment(other);
      final files = {
        'Pháp lý': draft(e.id, bytesOf('1'), name: '1.pdf', folder: 'Pháp lý'),
        'Pháp lý/Đăng kiểm': draft(
          e.id,
          bytesOf('2'),
          name: '2.pdf',
          folder: 'Pháp lý/Đăng kiểm',
        ),
        'Pháp lý cũ': draft(
          e.id,
          bytesOf('3'),
          name: '3.pdf',
          folder: 'Pháp lý cũ',
        ),
        'khác thiết bị': draft(
          other.id,
          bytesOf('4'),
          name: '4.pdf',
          folder: 'Pháp lý',
        ),
      };
      for (final a in files.values) {
        await repo.addAttachment(a, bytesOf(a.fileName.substring(0, 1)));
      }
      await repo.renameAttachmentFolder(e.id, 'Pháp lý', 'Hồ sơ/Pháp lý');
      Future<String> folderOf(String key) async => (await repo.attachments())
          .singleWhere((a) => a.id == files[key]!.id)
          .folder;
      expect(await folderOf('Pháp lý'), 'Hồ sơ/Pháp lý');
      expect(await folderOf('Pháp lý/Đăng kiểm'), 'Hồ sơ/Pháp lý/Đăng kiểm');
      expect(await folderOf('Pháp lý cũ'), 'Pháp lý cũ');
      expect(await folderOf('khác thiết bị'), 'Pháp lý');
      await expectLater(
        repo.renameAttachmentFolder(e.id, 'Hồ sơ', 'Hồ sơ/Con'),
        throwsFormatException,
      );

      final backup = decodeBackup(await encodeBackup(repo));
      final restoredDb = AppDatabase.memory();
      try {
        final restored = EquipmentRepository(restoredDb);
        await restored.restore(backup.data, files: backup.files);
        expect((await restored.attachments()).map((a) => a.folder).toSet(), {
          'Hồ sơ/Pháp lý',
          'Hồ sơ/Pháp lý/Đăng kiểm',
          'Pháp lý cũ',
          'Pháp lý',
        });
      } finally {
        await restoredDb.close();
      }

      expect(await repo.deleteAttachmentFolder(e.id, 'Hồ sơ'), 2);
      final left = await repo.attachments();
      expect(left.map((a) => a.id).toSet(), {
        files['Pháp lý cũ']!.id,
        files['khác thiết bị']!.id,
      });
    },
  );
}

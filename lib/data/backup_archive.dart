import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../domain/models.dart';
import 'database.dart';

/// A decoded backup: the JSON document plus attachment bytes by id.
class BackupBundle {
  const BackupBundle(this.data, [this.files = const {}]);
  final Json data;
  final Map<String, Uint8List> files;
  int get equipmentCount => (data['equipment'] as List?)?.length ?? 0;
  int get itemCount => (data['items'] as List?)?.length ?? 0;
  int get attachmentCount => (data['attachments'] as List?)?.length ?? 0;
}

const maxBackupBytes = 1024 * 1024 * 1024;
const _jsonName = 'backup.json';
const _filePrefix = 'attachments/';

/// Read the database and every attachment inside one SQLite transaction so a
/// reminder or edit running at the same time cannot produce a mixed backup.
Future<Uint8List> encodeBackup(
  EquipmentRepository repository, {
  void Function(Json data)? edit,
}) async {
  final archive = Archive();
  await repository.db.transaction(() async {
    final data = await repository.snapshot();
    edit?.call(data);
    final json = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
    archive.addFile(ArchiveFile(_jsonName, json.length, json));
    for (final a in data['attachments'] as List) {
      final id = (a as Map)['id'] as String;
      final bytes = await repository.attachmentData(id);
      // Photos and PDFs are already compressed; store them as they are.
      archive.addFile(
        ArchiveFile.noCompress('$_filePrefix$id', bytes.length, bytes),
      );
    }
  });
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

/// Write through a `.part` file so a crash never leaves a truncated backup.
Future<File> writeBackupFile(
  EquipmentRepository repository,
  File target, {
  void Function(Json data)? edit,
}) async {
  final bytes = await encodeBackup(repository, edit: edit);
  await target.parent.create(recursive: true);
  final temporary = File('${target.path}.part');
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    return await temporary.rename(target.path);
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
}

/// Accepts the ZIP format 3 and the plain JSON of formats 1–2.
BackupBundle decodeBackup(Uint8List bytes) {
  if (bytes.length > maxBackupBytes) {
    throw const FormatException('File sao lưu quá lớn.');
  }
  if (bytes.length < 2 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
    return BackupBundle(_json(bytes));
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: true);
  } catch (_) {
    throw const FormatException('File sao lưu ZIP bị hỏng.');
  }
  Json? data;
  final files = <String, Uint8List>{};
  for (final entry in archive.files) {
    if (!entry.isFile) continue;
    if (entry.name == _jsonName) {
      if (entry.size > 200 * 1024 * 1024) {
        throw const FormatException('Dữ liệu sao lưu quá lớn.');
      }
      data = _json(Uint8List.fromList(entry.content as List<int>));
    } else if (entry.name.startsWith(_filePrefix)) {
      final id = entry.name.substring(_filePrefix.length);
      if (id.isEmpty || id.contains('/') || id.contains('\\')) {
        throw const FormatException('Tên tệp trong sao lưu không hợp lệ.');
      }
      // Checked before decompressing so a crafted archive cannot exhaust memory.
      if (entry.size > maxAttachmentBytes) {
        throw const FormatException('Tệp đính kèm trong sao lưu quá lớn.');
      }
      files[id] = Uint8List.fromList(entry.content as List<int>);
    }
  }
  if (data == null) {
    throw const FormatException('Sao lưu ZIP thiếu backup.json.');
  }
  return BackupBundle(data, files);
}

Future<BackupBundle> readBackupFile(File file) async {
  if (await file.length() > maxBackupBytes) {
    throw const FormatException('File sao lưu quá lớn.');
  }
  return decodeBackup(await file.readAsBytes());
}

Json _json(Uint8List bytes) {
  try {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is Map<String, dynamic>) return value;
  } on FormatException {
    // Reported below with a message the user can act on.
  }
  throw const FormatException('File sao lưu không đúng định dạng.');
}

Future<void> restoreBundle(
  EquipmentRepository repository,
  BackupBundle bundle,
) => repository.restore(bundle.data, files: bundle.files);

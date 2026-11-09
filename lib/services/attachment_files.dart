import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../domain/models.dart';

/// Opens an attachment with the system's default app. The bytes are written
/// to a private temporary folder that is cleared on each open.
class AttachmentOpener {
  const AttachmentOpener();
  static const channel = MethodChannel('vn.cah.equipment_manager/files');

  /// Keeps letters (including Vietnamese) but drops path and reserved chars.
  static String safeName(Attachment a) {
    final base = a.title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final stem = base.isEmpty ? 'tep-dinh-kem' : base;
    final short = stem.length > 80 ? stem.substring(0, 80).trim() : stem;
    final ext = '.${a.extension}';
    return short.toLowerCase().endsWith(ext) ? short : '$short$ext';
  }

  Future<Directory> _folder() async => Platform.isAndroid
      ? Directory(p.join((await getTemporaryDirectory()).path, 'opened'))
      : Directory(p.join(Directory.systemTemp.path, 'EquipmentManager-opened'));

  Future<void> open(Attachment a, Uint8List data) async {
    final folder = await _folder();
    if (await folder.exists()) {
      try {
        await folder.delete(recursive: true);
      } on FileSystemException {
        // A viewer may still hold an older copy; a fresh subfolder is used.
      }
    }
    final file = File(p.join(folder.path, a.id, safeName(a)));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data, flush: true);
    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('open', {
        'path': file.path,
        'mime': a.mimeType,
      });
    } else if (Platform.isWindows) {
      await Process.start('explorer.exe', [file.path]);
    } else {
      throw const FileSystemException('Máy này chưa hỗ trợ mở tệp đính kèm.');
    }
  }
}

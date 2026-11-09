import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/database.dart';
import '../domain/deadlines.dart';
import '../domain/models.dart';

class AutoBackupFile {
  const AutoBackupFile(this.file, this.created, this.size, this.beforeRestore);
  final File file;
  final DateTime created;
  final int size;
  final bool beforeRestore;
}

/// Rotating JSON copies inside the app support folder. They protect against
/// mistakes and failed edits, not against losing the device.
class AutoBackupService {
  AutoBackupService({Future<Directory> Function()? root, this.keep = 10})
    : _root = root;
  final Future<Directory> Function()? _root;
  final int keep;
  static final _name = RegExp(
    r'^auto-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})(\d{6})(-truoc-khoi-phuc)?\.backup\.json$',
  );

  Future<Directory> directory() async => Directory(
    p.join(
      (await (_root?.call() ?? getApplicationSupportDirectory())).path,
      'backups',
      'auto',
    ),
  );

  static bool due(AppSettings settings, DateTime now) {
    if (!settings.autoBackupEnabled) return false;
    final last = settings.lastAutoBackup;
    return last == null ||
        calendarDaysBetween(last, now) >= settings.autoBackupDays;
  }

  /// Back up when the interval has passed. An empty database is skipped so a
  /// broken or fresh install never rotates out copies holding real data.
  Future<File?> runIfDue(EquipmentRepository repository, DateTime now) async {
    final settings = await repository.settings();
    if (!due(settings, now) || (await repository.equipment()).isEmpty) {
      return null;
    }
    return create(repository, now);
  }

  Future<File> create(
    EquipmentRepository repository,
    DateTime now, {
    bool beforeRestore = false,
  }) async {
    final data = await repository.db.transaction(() => repository.snapshot());
    final folder = await directory();
    await folder.create(recursive: true);
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}'
        '${(now.millisecond * 1000 + now.microsecond).toString().padLeft(6, '0')}';
    final target = File(
      p.join(
        folder.path,
        'auto-$stamp${beforeRestore ? '-truoc-khoi-phuc' : ''}.backup.json',
      ),
    );
    final temporary = File('${target.path}.part');
    try {
      await temporary.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
        flush: true,
      );
      await temporary.rename(target.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    await repository.saveSettings(
      (await repository.settings()).copy({
        'lastAutoBackup': now.toIso8601String(),
      }),
    );
    await prune();
    return target;
  }

  /// Newest first. Only files written by this service are listed or removed.
  Future<List<AutoBackupFile>> list() async {
    final folder = await directory();
    if (!await folder.exists()) return [];
    final result = <AutoBackupFile>[];
    await for (final entity in folder.list()) {
      if (entity is! File) continue;
      final m = _name.firstMatch(p.basename(entity.path));
      if (m == null) continue;
      final v = [for (var n = 1; n <= 7; n++) int.parse(m[n]!)];
      result.add(
        AutoBackupFile(
          entity,
          DateTime(v[0], v[1], v[2], v[3], v[4], v[5], 0, v[6]),
          await entity.length(),
          m[8] != null,
        ),
      );
    }
    result.sort((a, b) => b.created.compareTo(a.created));
    return result;
  }

  Future<void> prune() async {
    for (final old in (await list()).skip(keep)) {
      await old.file.delete();
    }
  }

  Future<Json> read(AutoBackupFile backup) async {
    if (await backup.file.length() > 50 * 1024 * 1024) {
      throw const FormatException('File sao lưu quá lớn.');
    }
    return jsonDecode(await backup.file.readAsString()) as Json;
  }
}

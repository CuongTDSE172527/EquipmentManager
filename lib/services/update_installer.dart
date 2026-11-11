import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/backup_archive.dart';
import '../data/database.dart';
import '../domain/updates.dart';

class UpdateInstaller {
  const UpdateInstaller();
  static const channel = MethodChannel('vn.cah.equipment_manager/updates');
  Future<UpdateTarget> target() async {
    if (Platform.isAndroid) return UpdateTarget.android;
    if (Platform.isWindows) {
      return await File(
            p.join(p.dirname(Platform.resolvedExecutable), 'unins000.exe'),
          ).exists()
          ? UpdateTarget.windowsSetup
          : UpdateTarget.windowsPortable;
    }
    throw const UpdateFailure('Máy này chưa hỗ trợ cài cập nhật.');
  }

  Future<Directory> directory() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'updates'),
  );
  Future<bool> canInstall(UpdateTarget target) async =>
      target != UpdateTarget.android ||
      await channel.invokeMethod<bool>('canInstall') == true;
  Future<void> openPermission() => channel.invokeMethod<void>('openPermission');
  Future<void> verify(File file, AppUpdate update, UpdateTarget target) async {
    if (target != UpdateTarget.android) return;
    await channel.invokeMethod<void>('verify', _arguments(file, update));
  }

  Map<String, Object> _arguments(File file, AppUpdate update) => {
    'path': file.path,
    'version': update.version.toString(),
    'code': update.version.code,
    'sha256': update.asset.sha256,
  };

  Future<File> backup(EquipmentRepository repository, AppUpdate update) async {
    final root = await directory();
    return createUpdateBackup(
      repository,
      Directory(p.join(root.parent.path, 'backups')),
      update.version,
    );
  }

  /// Return true only when Windows has a ready helper waiting for this process.
  Future<bool> launch(File file, AppUpdate update, UpdateTarget target) async {
    if (target == UpdateTarget.android) {
      await channel.invokeMethod<void>('install', _arguments(file, update));
      return false;
    }
    final stage = file.parent;
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final script = File(p.join(stage.path, 'windows-update-$suffix.ps1'));
    await script.writeAsString(
      await rootBundle.loadString('assets/updates/windows-update.ps1'),
      flush: true,
    );
    final ready = File(p.join(stage.path, 'ready-$suffix.txt'));
    final status = File(p.join(stage.path, 'update-status.json'));
    if (await status.exists()) await status.delete();
    final process = await startWindowsHelper(script.path, [
      '-ParentPid',
      '$pid',
      '-Mode',
      target == UpdateTarget.windowsSetup ? 'setup' : 'portable',
      '-Package',
      file.path,
      '-Destination',
      p.dirname(Platform.resolvedExecutable),
      '-ExpectedHash',
      update.asset.sha256,
      '-ExpectedVersion',
      update.version.toString(),
      '-StatusFile',
      status.path,
      '-ReadyFile',
      ready.path,
    ]);
    for (var i = 0; i < 300; i++) {
      if (await ready.exists()) return true;
      if (await status.exists()) {
        try {
          final value =
              jsonDecode(
                    (await status.readAsString()).replaceFirst('\uFEFF', ''),
                  )
                  as Map;
          if (value['state'] == 'error') {
            throw const UpdateFailure(
              'Windows chưa chuẩn bị được cập nhật. Hãy đóng các cửa sổ EquipmentManager khác và thử lại. Nhật ký nằm cạnh bộ cài đã tải.',
            );
          }
        } on FormatException {
          // PowerShell may still be flushing this small status file; retry.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    process.kill();
    throw const UpdateFailure(
      'Windows chưa sẵn sàng cập nhật. Ứng dụng vẫn mở, chưa thay tệp. Hãy thử lại.',
    );
  }

  Future<void> quit() async => exit(0);
}

/// Starts the Windows update helper script with PowerShell 5.1.
///
/// Uses [ProcessStartMode.normal]: with `detached` (DETACHED_PROCESS, no
/// console) Windows PowerShell can hang during startup before running any
/// script line, which made OTA time out ("Windows chưa sẵn sàng cập nhật").
/// A normally started child still keeps running after the app exits, which
/// the helper needs in order to replace the app files.
Future<Process> startWindowsHelper(
  String script,
  List<String> arguments,
) async {
  final process = await Process.start('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-File',
    script,
    ...arguments,
  ]);
  // Drain the pipes so the helper never blocks on a full buffer.
  process.stdout.drain<void>().ignore();
  process.stderr.drain<void>().ignore();
  return process;
}

Future<File> createUpdateBackup(
  EquipmentRepository repository,
  Directory directory,
  AppVersion version,
) async {
  // One SQLite read transaction gives a consistent copy, attachments included,
  // even if a reminder is running.
  final result = await writeBackupFile(
    repository,
    File(
      p.join(
        directory.path,
        'before-update-$version-${DateTime.now().microsecondsSinceEpoch}.backup.zip',
      ),
    ),
  );
  await repository.saveSettings(
    (await repository.settings()).copy({
      'lastBackup': DateTime.now().toIso8601String(),
    }),
  );
  return result;
}

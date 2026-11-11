@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:equipment_manager/services/update_installer.dart';

/// Starts the real helper script the same way the app does (from Dart, not
/// from a console PowerShell) with a deliberately invalid version. The helper
/// must start, reach its first check and write an error status without
/// touching any files. A hang here is what broke OTA on Windows in 0.4.1.
void main() {
  test('Helper cập nhật Windows khởi động được khi app gọi từ Dart', () async {
    final stage = await Directory.systemTemp.createTemp('em-ota-');
    try {
      final script = File(p.join(stage.path, 'windows-update.ps1'));
      await File('assets/updates/windows-update.ps1').copy(script.path);
      final package = File(p.join(stage.path, 'package.exe'))
        ..writeAsStringSync('not an installer');
      final status = File(p.join(stage.path, 'update-status.json'));
      final process = await startWindowsHelper(script.path, [
        '-ParentPid',
        '$pid',
        '-Mode',
        'setup',
        '-Package',
        package.path,
        '-Destination',
        stage.path,
        '-ExpectedHash',
        '0' * 64,
        '-ExpectedVersion',
        'invalid',
        '-StatusFile',
        status.path,
        '-ReadyFile',
        p.join(stage.path, 'ready.txt'),
        '-NoRelaunch',
      ]);
      final watch = Stopwatch()..start();
      while (!status.existsSync() && watch.elapsed.inSeconds < 20) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!status.existsSync()) process.kill();
      expect(
        status.existsSync(),
        isTrue,
        reason: 'PowerShell không chạy helper trong 20 giây',
      );
      String text = '';
      for (var i = 0; i < 20; i++) {
        text = status.readAsStringSync().replaceFirst('﻿', '');
        if (text.trim().endsWith('}')) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final value = jsonDecode(text) as Map;
      expect(value['state'], 'error');
      expect(value['message'], 'Invalid update metadata.');
      expect(await process.exitCode, 1);
      expect(File(p.join(stage.path, 'ready.txt')).existsSync(), isFalse);
    } finally {
      await stage.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}

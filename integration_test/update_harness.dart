// Native update QA entry point. Never included in a release build.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/domain/updates.dart';
import 'package:equipment_manager/services/storage.dart';
import 'package:equipment_manager/services/update_installer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('OTA native test fixture'))),
    ),
  );
  unawaited(runFixture());
}

Future<void> runFixture() async {
  const installer = UpdateInstaller();
  final root = await installer.directory();
  final evidence = File('${root.path}/evidence.txt');
  Future<void> log(String value) =>
      evidence.writeAsString('$value\n', mode: FileMode.append, flush: true);
  AppDatabase? db;
  try {
    final fixture = File('${root.path}/fixture.json');
    for (var i = 0; i < 120 && !await fixture.exists(); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final data = jsonDecode(await fixture.readAsString()) as Map;
    final valid = File('${root.path}/valid.apk');
    final bad = File('${root.path}/wrong-signer.apk');
    AppUpdate update(String hash, {String version = '0.1.4'}) => AppUpdate(
      version: AppVersion.tryParse(version)!,
      prerelease: true,
      notes: '',
      asset: UpdateAsset(
        name: 'fixture.apk',
        url: Uri.https('github.com', '/fixture'),
        size: 0,
        sha256: hash,
      ),
    );
    final candidate = update(data['validHash'] as String);
    await installer.verify(valid, candidate, UpdateTarget.android);
    await log('PASS valid package/version/signature');
    for (final pair in [
      (valid, update('0' * 64)),
      (valid, update(data['validHash'] as String, version: '0.1.5')),
      (bad, update(data['wrongHash'] as String)),
    ]) {
      var rejected = false;
      try {
        await installer.verify(pair.$1, pair.$2, UpdateTarget.android);
      } on PlatformException {
        rejected = true;
      }
      if (!rejected) throw StateError('Invalid APK was accepted');
    }
    await log('PASS wrong hash/version/signer blocked');
    if (await installer.canInstall(UpdateTarget.android)) {
      throw StateError('Fixture unexpectedly has install permission');
    }
    await installer.openPermission();
    await log('PASS permission settings opened');
    db = await openAppDatabase();
    final repo = EquipmentRepository(db);
    await repo.saveEquipment(
      Equipment(id: 'ota-preserved-fixture', name: 'OTA fixture preserved'),
    );
    final backup = await installer.backup(repo, candidate);
    if (!await backup.exists()) throw StateError('Backup was not created');
    await log('PASS backup created');
    await log('READY');
    for (
      var i = 0;
      i < 180 && !await File('${root.path}/install-now').exists();
      i++
    ) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!await installer.canInstall(UpdateTarget.android)) {
      throw StateError('Install permission not granted');
    }
    await db.close();
    db = null;
    await installer.launch(valid, candidate, UpdateTarget.android);
    await log('PASS native installer opened');
  } catch (e, stack) {
    await log('FAIL $e\n$stack');
  } finally {
    await db?.close();
  }
}

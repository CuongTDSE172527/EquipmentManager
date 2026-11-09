import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/domain/updates.dart';
import 'package:equipment_manager/services/updates.dart';
import 'package:equipment_manager/services/update_installer.dart';
import 'package:equipment_manager/ui/controller.dart';
import 'package:equipment_manager/ui/update_card.dart';
import 'updates_test.dart' as fixture;

class UIUpdates extends UpdateService {
  bool tampered = false;
  @override
  Future<AppUpdate?> check(
    AppVersion current,
    UpdateTarget target, {
    required bool includePrereleases,
    required UpdateCancellation cancel,
  }) async => selectUpdate(
    [fixture.release('0.1.5', prerelease: true)],
    current,
    target,
    includePrereleases: includePrereleases,
  );
  @override
  Future<File> download(
    AppUpdate update,
    Directory root,
    UpdateCancellation cancel,
    void Function(int, int) onProgress,
  ) async {
    onProgress(22, 22);
    return File('fixture-update.apk');
  }

  @override
  Future<bool> verified(File file, UpdateAsset asset) async => !tampered;
}

class UIInstaller extends UpdateInstaller {
  bool permission = false, backupFails = false;
  final events = <String>[];
  @override
  Future<UpdateTarget> target() async => UpdateTarget.android;
  @override
  Future<Directory> directory() async => Directory('fixture-updates');
  @override
  Future<bool> canInstall(UpdateTarget target) async => permission;
  @override
  Future<void> openPermission() async {
    permission = true;
  }

  @override
  Future<void> verify(File file, AppUpdate update, UpdateTarget target) async {
    events.add('verify');
  }

  @override
  Future<File> backup(EquipmentRepository repository, AppUpdate update) async {
    if (backupFails) throw const FileSystemException('Fixture backup failure');
    events.add('backup');
    return File('fixture-backup.json');
  }

  @override
  Future<bool> launch(File file, AppUpdate update, UpdateTarget target) async {
    events.add('launch');
    return false;
  }
}

void main() {
  for (final failure in ['none', 'hash', 'backup']) {
    testWidgets(
      'OTA UI: quyền, xác nhận, backup trước cài; trường hợp $failure',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 740));
        final db = AppDatabase.memory();
        final repo = EquipmentRepository(db);
        final c = AppController(repo);
        await repo.saveEquipment(Equipment(name: 'Dữ liệu giữ lại'));
        await c.load();
        final updates = UIUpdates();
        final installer = UIInstaller();
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('vi', 'VN'),
            supportedLocales: const [Locale('vi', 'VN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: SingleChildScrollView(
                child: UpdateCard(
                  controller: c,
                  service: updates,
                  installer: installer,
                  packageInfo: () async => PackageInfo(
                    appName: 'EquipmentManager',
                    packageName: 'fixture',
                    version: '0.1.4',
                    buildNumber: '1004',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kiểm tra cập nhật'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Có bản 0.1.5'), findsOneWidget);
        await tester.ensureVisible(find.text('Tải bản cập nhật'));
        await tester.tap(find.text('Tải bản cập nhật'));
        await tester.pumpAndSettle();
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Cài đặt bản cập nhật'),
        );
        expect(button.onPressed, isNull);
        await tester.ensureVisible(
          find.text('Cho phép cài từ EquipmentManager'),
        );
        await tester.tap(find.text('Cho phép cài từ EquipmentManager'));
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Cài đặt bản cập nhật'));
        await tester.tap(find.text('Cài đặt bản cập nhật'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hủy'));
        await tester.pumpAndSettle();
        expect(installer.events, ['verify']);
        updates.tampered = failure == 'hash';
        installer.backupFails = failure == 'backup';
        await tester.tap(find.text('Cài đặt bản cập nhật'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sao lưu và cài đặt'));
        await tester.pumpAndSettle();
        if (failure == 'none') {
          expect(installer.events, containsAllInOrder(['backup', 'launch']));
          expect(
            find.textContaining('Đã mở trình cài Android'),
            findsOneWidget,
          );
        } else {
          expect(installer.events, isNot(contains('launch')));
          if (failure == 'hash') {
            expect(installer.events, isNot(contains('backup')));
          }
        }
        expect((await repo.equipment()).single.name, 'Dữ liệu giữ lại');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await db.close();
        await tester.binding.setSurfaceSize(null);
      },
    );
  }
}

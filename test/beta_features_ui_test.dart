import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/deadlines.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/domain/updates.dart';
import 'package:equipment_manager/services/update_installer.dart';
import 'package:equipment_manager/services/updates.dart';
import 'package:equipment_manager/ui/app.dart';
import 'package:equipment_manager/ui/controller.dart';
import 'ui_test.dart' show SilentNotifications;
import 'updates_test.dart' as fixture;
import 'session_helper.dart';

class CountingUpdates extends UpdateService {
  int calls = 0;
  bool? prerelease;
  @override
  Future<AppUpdate?> check(
    AppVersion current,
    UpdateTarget target, {
    required bool includePrereleases,
    required UpdateCancellation cancel,
  }) async {
    calls++;
    prerelease = includePrereleases;
    return selectUpdate(
      [fixture.release('0.2.0', prerelease: true)],
      current,
      target,
      includePrereleases: includePrereleases,
    );
  }
}

class AndroidInstaller extends UpdateInstaller {
  @override
  Future<UpdateTarget> target() async => UpdateTarget.android;
}

void mockVersion() => PackageInfo.setMockInitialValues(
  appName: 'EquipmentManager',
  packageName: 'vn.cah.equipment_manager',
  version: '0.1.4',
  buildNumber: '1004',
  buildSignature: '',
);

void main() {
  final today = DateTime(2026, 11, 9, 8);

  test('Xác nhận giữ nguyên hạn, ghi vết vào ghi chú', () {
    final item = DeadlineItem(
      equipmentId: 'x',
      kind: ItemKind.inspection,
      title: 'Đăng kiểm',
      dueDate: DateTime(2026, 9, 1),
      note: 'Theo sổ cũ',
      requiresConfirmation: true,
    );
    final confirmed = confirmDeadline(item, today);
    expect(confirmed.requiresConfirmation, isFalse);
    expect(confirmed.dueDate, item.dueDate);
    expect(confirmed.note, 'Theo sổ cũ\nĐã xác nhận dữ liệu ngày 09/11/2026.');
    expect(() => confirmDeadline(confirmed, today), throwsStateError);
  });

  for (final size in [const Size(1440, 1000), const Size(412, 915)]) {
    testWidgets('Hàng chờ Cần xác nhận ở $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      mockVersion();
      final db = AppDatabase.memory();
      final repo = EquipmentRepository(db);
      final e = Equipment(name: 'Xe thang');
      await repo.saveEquipment(e);
      await repo.saveItem(
        DeadlineItem(
          equipmentId: e.id,
          kind: ItemKind.inspection,
          title: 'Đăng kiểm',
          dueDate: DateTime(2026, 9, 1),
          requiresConfirmation: true,
        ),
      );
      await repo.saveItem(
        DeadlineItem(
          equipmentId: e.id,
          kind: ItemKind.maintenance,
          title: 'Bảo dưỡng',
          dueDate: DateTime(2027, 3, 1),
        ),
      );
      final c = AppController(repo, clock: () => today);
      await signInForTest(c);
      await tester.pumpWidget(
        EquipmentManagerApp(
          controller: c,
          notifications: SilentNotifications(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 mốc cần xác nhận'), findsOneWidget);
      await tester.ensureVisible(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 hạng mục • Cần xác nhận'), findsOneWidget);
      final action = size.width >= 960
          ? find.byTooltip('Xác nhận dữ liệu')
          : find.text('Xác nhận dữ liệu');
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận dữ liệu hạng mục'), findsOneWidget);
      expect(find.text('Quá hạn'), findsWidgets);
      await tester.tap(find.text('Xác nhận đúng'));
      await tester.pumpAndSettle();
      final saved = (await repo.items()).firstWhere(
        (i) => i.title == 'Đăng kiểm',
      );
      expect(saved.requiresConfirmation, isFalse);
      expect(saved.dueDate, DateTime(2026, 9, 1));
      expect(saved.note, contains('09/11/2026'));
      expect(find.textContaining('0 hạng mục • Cần xác nhận'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await db.close();
      await tester.binding.setSurfaceSize(null);
    });
  }

  test('Tự kiểm tra cập nhật tối đa 1 lần mỗi ngày và mặc định tắt', () {
    const off = AppSettings();
    expect(off.autoUpdateCheck, isFalse);
    expect(updateCheckDue(off, today), isFalse);
    final on = off.copy({'autoUpdateCheck': true});
    expect(updateCheckDue(on, today), isTrue);
    final checked = on.copy({
      'lastUpdateCheck': DateTime(2026, 11, 9, 1).toIso8601String(),
    });
    expect(updateCheckDue(checked, today), isFalse);
    expect(updateCheckDue(checked, DateTime(2026, 11, 10)), isTrue);
  });

  for (final enabled in [true, false]) {
    testWidgets('Khi mở app chỉ báo bản mới; bật=$enabled', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      mockVersion();
      final db = AppDatabase.memory();
      final repo = EquipmentRepository(db);
      await repo.saveSettings(
        const AppSettings().copy({'autoUpdateCheck': enabled}),
      );
      final c = AppController(repo, clock: () => today);
      await signInForTest(c);
      final updates = CountingUpdates();
      await tester.pumpWidget(
        EquipmentManagerApp(
          controller: c,
          notifications: SilentNotifications(),
          updates: updates,
          installer: AndroidInstaller(),
        ),
      );
      await tester.pumpAndSettle();
      expect(updates.calls, enabled ? 1 : 0);
      expect(
        find.text('Có bản cập nhật 0.2.0'),
        enabled ? findsOneWidget : findsNothing,
      );
      expect(find.text('Mới'), enabled ? findsOneWidget : findsNothing);
      expect((await repo.settings()).lastUpdateCheck, enabled ? today : isNull);
      if (enabled) {
        expect(updates.prerelease, isTrue);
        await tester.tap(find.text('Xem'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Có bản 0.2.0'), findsOneWidget);
        expect(find.text('Tải bản cập nhật'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await db.close();
      await tester.binding.setSurfaceSize(null);
    });
  }
}

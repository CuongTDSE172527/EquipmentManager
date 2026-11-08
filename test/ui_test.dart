import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/services/notifications.dart';
import 'package:equipment_manager/ui/controller.dart';
import 'package:equipment_manager/ui/app.dart';

class SilentNotifications extends NotificationService {
  VoidCallback? open;
  @override
  Future<void> initialize({VoidCallback? onOpen}) async {
    if (onOpen != null) open = onOpen;
  }

  @override
  Future<bool> launchedFromNotification() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [
    const Size(1440, 1000),
    const Size(412, 915),
    const Size(360, 640),
  ]) {
    testWidgets('Giao diện rỗng, thêm thiết bị và 200 hạng mục ở $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      final db = AppDatabase.memory();
      final repo = EquipmentRepository(db);
      final c = AppController(repo);
      PackageInfo.setMockInitialValues(
        appName: 'EquipmentManager',
        packageName: 'vn.cah.equipment_manager',
        version: '0.1.0',
        buildNumber: '1',
        buildSignature: '',
      );
      await c.load();
      final notifications = SilentNotifications();
      await tester.pumpWidget(
        EquipmentManagerApp(controller: c, notifications: notifications),
      );
      await tester.pumpAndSettle();
      if (size.width < 960) {
        await tester.scrollUntilVisible(
          find.text('Chưa có dữ liệu thiết bị'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('Chưa có dữ liệu thiết bị'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(
        size.width >= 960
            ? find.text('Thêm thiết bị').first
            : find.byTooltip('Thêm thiết bị').first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Lưu thiết bị'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Thiết bị nhập qua giao diện',
      );
      await tester.tap(find.text('Lưu thiết bị'));
      await tester.pumpAndSettle();
      expect(
        (await repo.equipment()).single.name,
        'Thiết bị nhập qua giao diện',
      );
      expect(tester.takeException(), isNull);
      await repo.deleteEquipment((await repo.equipment()).single.id);
      for (var n = 0; n < 50; n++) {
        final e = Equipment(name: 'Thiết bị thử $n');
        await repo.saveEquipment(e);
        for (var k = 0; k < 4; k++) {
          await repo.saveItem(
            DeadlineItem(
              equipmentId: e.id,
              kind: ItemKind.maintenance,
              title: 'Bảo dưỡng $k',
              dueDate: DateTime.now().add(const Duration(days: 2)),
            ),
          );
        }
      }
      await c.load();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theo dõi hạn').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('200 hạng mục'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byType(TextField).first,
        'từ khóa không có thiết bị nào',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('0 hạng mục'), findsOneWidget);
      notifications.open!();
      await tester.pumpAndSettle();
      expect(find.textContaining('200 hạng mục'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      if (size.width < 960) {
        await tester.tap(find.text('Bộ lọc'));
        await tester.pumpAndSettle();
        expect(find.text('Lọc hạng mục'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = FakeViewPadding(
          bottom: 280 * tester.view.devicePixelRatio,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
      }
      await repo.saveSettings(c.settings.copy({'theme': 'dark'}));
      await c.load();
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await db.close();
      await tester.binding.setSurfaceSize(null);
    });
  }
}

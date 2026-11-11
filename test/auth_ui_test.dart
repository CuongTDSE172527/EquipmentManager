import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/accounts.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/services/auth.dart';
import 'package:equipment_manager/ui/app.dart';
import 'package:equipment_manager/ui/controller.dart';
import 'session_helper.dart';
import 'ui_test.dart' show SilentNotifications;

Finder field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: 'EquipmentManager',
      packageName: 'vn.cah.equipment_manager',
      version: '0.4.0',
      buildNumber: '4000',
      buildSignature: '',
    ),
  );

  Future<(AppDatabase, AppController)> start(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    final db = AppDatabase.memory();
    final repo = EquipmentRepository(db);
    final c = AppController(repo, auth: AuthService(repo, iterations: 1000));
    await repo.saveEquipment(Equipment(name: 'Xe dữ liệu cũ'));
    await c.load();
    return (db, c);
  }

  Future<void> finish(
    WidgetTester tester,
    AppDatabase db,
    AppController c,
  ) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
    await tester.binding.setSurfaceSize(null);
  }

  testWidgets(
    'Lần đầu tạo Quản trị, lưu mã khôi phục, đăng xuất và đăng nhập lại',
    (tester) async {
      final (db, c) = await start(tester);
      await tester.pumpWidget(
        EquipmentManagerApp(
          controller: c,
          notifications: SilentNotifications(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tạo tài khoản Quản trị'), findsOneWidget);
      await tester.enterText(field('Tên đăng nhập'), 'QuanTri');
      await tester.enterText(field('Họ và tên'), 'Nguyễn Quản Trị');
      await tester.enterText(field('Mật khẩu'), 'yeu');
      await tester.enterText(field('Nhập lại mật khẩu'), 'yeu');
      await tester.ensureVisible(find.text('Tạo tài khoản').last);
      await tester.tap(find.text('Tạo tài khoản').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('ít nhất 8 ký tự'), findsWidgets);
      await tester.enterText(field('Mật khẩu'), 'Bimat2026Ok');
      await tester.enterText(field('Nhập lại mật khẩu'), 'Bimat2026Ok');
      await tester.tap(find.text('Tạo tài khoản').last);
      await tester.pumpAndSettle();
      expect(find.text('Mã khôi phục'), findsOneWidget);
      final next = find.widgetWithText(FilledButton, 'Tiếp tục');
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      await tester.tap(find.text('Tôi đã lưu mã khôi phục'));
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(c.user!.role, Role.admin);
      expect(find.text('Nguyễn Quản Trị'), findsOneWidget);
      expect(find.text('Xe dữ liệu cũ'), findsNothing);
      expect(find.text('Thêm thiết bị'), findsOneWidget);

      await tester.tap(find.byTooltip('Tài khoản'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đăng xuất'));
      await tester.pumpAndSettle();
      expect(c.user, isNull);
      expect(find.text('Đăng nhập'), findsWidgets);
      await tester.enterText(field('Tên đăng nhập'), 'quantri');
      await tester.enterText(field('Mật khẩu'), 'Saimatkhau1');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Còn 4 lần thử'), findsOneWidget);
      await tester.enterText(field('Mật khẩu'), 'Bimat2026Ok');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();
      expect(c.user?.username, 'quantri');
      expect(find.text('Tổng quan'), findsWidgets);
      expect(tester.takeException(), isNull);
      await finish(tester, db, c);
    },
  );

  testWidgets(
    'Vai trò Chỉ xem không thấy nút sửa, nhập, sao lưu hay quản trị',
    (tester) async {
      final (db, c) = await start(tester);
      final e = c.equipment.single;
      await c.repository.saveItem(
        DeadlineItem(equipmentId: e.id, kind: ItemKind.inspection, title: 'ĐK'),
      );
      await signInForTest(c, role: Role.viewer);
      await tester.pumpWidget(
        EquipmentManagerApp(
          controller: c,
          notifications: SilentNotifications(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Thêm thiết bị'), findsNothing);
      await tester.tap(find.text('Theo dõi hạn').last);
      await tester.pumpAndSettle();
      expect(find.text('Thêm hạng mục'), findsNothing);
      expect(find.byTooltip('Sửa hạng mục'), findsNothing);
      expect(find.byTooltip('Gia hạn / Hoàn thành'), findsNothing);
      await tester.tap(find.text('Dữ liệu & báo cáo').last);
      await tester.pumpAndSettle();
      expect(find.text('Nhập Excel / CSV'), findsNothing);
      expect(find.text('Sao lưu toàn bộ dữ liệu'), findsNothing);
      expect(find.text('Khôi phục từ bản sao lưu'), findsNothing);
      expect(find.text('Xuất kế hoạch đến hạn'), findsOneWidget);
      await tester.tap(find.text('Cài đặt').last);
      await tester.pumpAndSettle();
      expect(find.text('Hồ sơ của tôi'), findsOneWidget);
      expect(find.textContaining('Quản lý tài khoản'), findsNothing);
      expect(find.text('Lưu cài đặt'), findsNothing);
      await expectLater(
        c.saveEquipment(Equipment(name: 'Không được thêm')),
        throwsA(isA<AuthException>()),
      );
      expect(tester.takeException(), isNull);
      await finish(tester, db, c);
    },
  );

  testWidgets('Tự khóa khi không thao tác, mở khóa đúng mật khẩu', (
    tester,
  ) async {
    final (db, c) = await start(tester);
    final account = (await c.auth.register(
      username: 'kythuat',
      password: 'Bimat2026Ok',
      displayName: 'Kỹ thuật viên',
    )).account;
    c.signIn(
      await c.auth.updateProfile(
        account,
        displayName: account.displayName,
        autoLockMinutes: 1,
      ),
    );
    await tester.pumpWidget(
      EquipmentManagerApp(controller: c, notifications: SilentNotifications()),
    );
    await tester.pumpAndSettle();
    expect(c.locked, isFalse);
    await tester.pump(const Duration(seconds: 50));
    await tester.tap(find.text('Thiết bị').last);
    await tester.pump(const Duration(seconds: 50));
    expect(c.locked, isFalse, reason: 'thao tác đã đếm lại từ đầu');
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(c.locked, isTrue);
    expect(find.text('Đã khóa'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Saimatkhau1');
    await tester.tap(find.text('Mở khóa'));
    await tester.pumpAndSettle();
    expect(c.locked, isTrue);
    expect(find.textContaining('không đúng'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Bimat2026Ok');
    await tester.tap(find.text('Mở khóa'));
    await tester.pumpAndSettle();
    expect(c.locked, isFalse);
    expect(find.text('Đã khóa'), findsNothing);
    expect(find.text('Xe dữ liệu cũ'), findsOneWidget);

    c.lock();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đăng xuất / đổi người dùng'));
    await tester.pumpAndSettle();
    expect(c.user, isNull);
    expect(find.text('Đăng nhập'), findsWidgets);
    expect(tester.takeException(), isNull);
    await finish(tester, db, c);
  });
}

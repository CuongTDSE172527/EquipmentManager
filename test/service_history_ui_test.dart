import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/domain/deadlines.dart';
import 'package:equipment_manager/ui/controller.dart';
import 'package:equipment_manager/ui/service_history_page.dart';
import 'session_helper.dart';

void main() {
  for (final size in [const Size(1280, 900), const Size(360, 640)]) {
    testWidgets('Sổ bảo trì: ghi, tìm, sửa, xóa, không đổi hạn ở $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      final db = AppDatabase.memory();
      final repo = EquipmentRepository(db);
      final c = AppController(repo, clock: () => DateTime(2026, 11, 9));
      final e = Equipment(
        name: 'Thiết bị thử giao diện',
        roadPlate: '69A-99999',
      );
      await repo.saveEquipment(e);
      final item = DeadlineItem(
        equipmentId: e.id,
        kind: ItemKind.maintenance,
        title: 'Thay dầu',
        cycleMonths: 6,
        dueDate: DateTime(2026, 12, 1),
      );
      await repo.saveItem(item);
      final done = completeItem(
        item,
        doneDate: DateTime(2026, 10, 1),
        cost: 200000,
        provider: 'Đơn vị cũ',
      );
      await repo.recordCompletion(done.item, done.history);
      await signInForTest(c);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('vi', 'VN'),
          supportedLocales: const [Locale('vi', 'VN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: ServiceHistoryPage(controller: c, equipment: e),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1 lần'), findsOneWidget);
      expect(find.text('Từ hoàn thành hạng mục'), findsOneWidget);
      await tester.tap(find.text('Ghi công việc'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nội dung công việc *'),
        'Thay lốp',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ngày thực hiện *'),
        '10/2026',
      );
      await tester.tap(find.text('Lưu lịch sử'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập ngày cụ thể dd/MM/yyyy.'), findsOneWidget);
      expect(await repo.serviceRecords(), isEmpty);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ngày thực hiện *'),
        '02/11/2026',
      );
      await tester.ensureVisible(
        find.widgetWithText(TextFormField, 'Chi phí (VND)'),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Chi phí (VND)'),
        '1.500.000',
      );
      await tester.ensureVisible(
        find.widgetWithText(TextFormField, 'Đơn vị thực hiện'),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Đơn vị thực hiện'),
        'Đơn vị thử mới',
      );
      await tester.tap(find.text('Lưu lịch sử'));
      await tester.pumpAndSettle();
      expect((await repo.serviceRecords()).single.cost, 1500000);
      expect((await repo.items()).single.toJson(), done.item.toJson());
      expect(find.textContaining('2 lần'), findsOneWidget);
      expect(find.textContaining('1.700.000 VND'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'lốp');
      await tester.pumpAndSettle();
      expect(find.textContaining('1 lần'), findsOneWidget);
      if (size.width < 600) {
        tester.view.viewInsets = FakeViewPadding(
          bottom: 280 * tester.view.devicePixelRatio,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Thao tác lịch sử'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nội dung công việc *'),
        'Thay lốp sau',
      );
      await tester.tap(find.text('Lưu lịch sử'));
      await tester.pumpAndSettle();
      expect((await repo.serviceRecords()).single.title, 'Thay lốp sau');
      await tester.tap(find.byTooltip('Thao tác lịch sử'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa lịch sử'));
      await tester.pumpAndSettle();
      expect(await repo.serviceRecords(), isEmpty);
      expect(await repo.history(), hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await db.close();
      await tester.binding.setSurfaceSize(null);
    });
  }
}

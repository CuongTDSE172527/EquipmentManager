import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/services/attachment_files.dart';
import 'package:equipment_manager/ui/app.dart';
import 'package:equipment_manager/ui/controller.dart';
import 'ui_test.dart' show SilentNotifications;
import 'session_helper.dart';

class FakeOpener extends AttachmentOpener {
  FakeOpener();
  final opened = <String, Uint8List>{};
  @override
  Future<void> open(Attachment a, Uint8List data) async => opened[a.id] = data;
}

void main() {
  for (final size in [const Size(1440, 1000), const Size(412, 915)]) {
    testWidgets('Tệp đính kèm trong chi tiết thiết bị ở $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      PackageInfo.setMockInitialValues(
        appName: 'EquipmentManager',
        packageName: 'vn.cah.equipment_manager',
        version: '0.3.0',
        buildNumber: '3000',
        buildSignature: '',
      );
      final db = AppDatabase.memory();
      final repo = EquipmentRepository(db);
      final e = Equipment(name: 'Xe nâng hàng');
      await repo.saveEquipment(e);
      final item = DeadlineItem(
        equipmentId: e.id,
        kind: ItemKind.inspection,
        title: 'Đăng kiểm',
      );
      await repo.saveItem(item);
      final data = Uint8List.fromList(utf8.encode('%PDF giấy đăng kiểm'));
      final a = Attachment(
        equipmentId: e.id,
        fileName: 'dk.pdf',
        size: data.length,
        sha256: sha256.convert(data).toString(),
        title: 'Giấy đăng kiểm 2026',
        linkId: item.id,
      );
      await repo.addAttachment(a, data);
      final c = AppController(repo);
      await signInForTest(c);
      final opener = FakeOpener();
      await tester.pumpWidget(
        EquipmentManagerApp(
          controller: c,
          notifications: SilentNotifications(),
          opener: opener,
        ),
      );
      await tester.pumpAndSettle();
      if (size.width >= 960) {
        expect(find.text('Ngoại tuyến • Phiên bản 0.3.0 Beta'), findsOneWidget);
      }
      await tester.tap(find.text('Thiết bị').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xe nâng hàng'));
      await tester.pumpAndSettle();
      expect(find.text('Tệp đính kèm (1)'), findsOneWidget);
      expect(
        find.textContaining('Liên quan: Đăng kiểm/Kiểm định: Đăng kiểm'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Giấy đăng kiểm 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Giấy đăng kiểm 2026'));
      await tester.pumpAndSettle();
      expect(opener.opened[a.id], data);
      await tester.tap(find.byTooltip('Thao tác tệp'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa tệp').last);
      await tester.pumpAndSettle();
      expect(find.text('Xóa tệp đính kèm?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Xóa tệp'));
      await tester.pumpAndSettle();
      expect(await repo.attachments(), isEmpty);
      expect(find.text('Tệp đính kèm (0)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await db.close();
      await tester.binding.setSurfaceSize(null);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/domain/deadlines.dart';
import 'package:equipment_manager/ui/controller.dart';
import 'package:equipment_manager/ui/forms.dart';

void main() {
  testWidgets('Sửa bảo hiểm Hết sang hạn mới không còn cờ hết hạn cũ', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1100));
    final db = AppDatabase.memory();
    final repo = EquipmentRepository(db);
    final c = AppController(repo);
    final e = Equipment(name: 'Xe thử');
    await repo.saveEquipment(e);
    final item = DeadlineItem(
      equipmentId: e.id,
      kind: ItemKind.insurance,
      title: 'Bảo hiểm',
      insuranceMode: InsuranceMode.expired,
      expiredWithoutDate: true,
    );
    await repo.saveItem(item);
    await c.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => itemForm(context, c, item: item),
              child: const Text('Sửa'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sửa'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<InsuranceMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Có ngày hết hạn').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '01/01/2030');
    await tester.tap(find.text('Lưu hạng mục'));
    await tester.pumpAndSettle();
    final saved = (await repo.items()).single;
    expect(saved.expiredWithoutDate, false);
    expect(saved.insuranceMode, InsuranceMode.dated);
    expect(
      statusOf(saved, e, const AppSettings(), DateTime(2026, 11, 8)),
      DeadlineStatus.valid,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
    await tester.binding.setSurfaceSize(null);
  });
}

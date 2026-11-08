import 'package:flutter_test/flutter_test.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/domain/deadlines.dart';

void main() {
  late AppDatabase db;
  late EquipmentRepository repo;
  setUp(() {
    db = AppDatabase.memory();
    repo = EquipmentRepository(db);
  });
  tearDown(() async {
    await db.close();
  });
  test('Ghi đọc và xóa dây chuyền thiết bị, hạng mục, lịch sử', () async {
    final e = Equipment(name: 'Xe thử nghiệm');
    await repo.saveEquipment(e);
    final i = DeadlineItem(
      equipmentId: e.id,
      kind: ItemKind.maintenance,
      title: 'Bảo dưỡng',
    );
    await repo.saveItem(i);
    final result = completeItem(
      i,
      doneDate: DateTime(2026),
      provider: 'Đơn vị thử',
    );
    await repo.recordCompletion(result.item, result.history);
    expect((await repo.history()).length, 1);
    await repo.deleteEquipment(e.id);
    expect(await repo.equipment(), isEmpty);
    expect(await repo.items(), isEmpty);
    expect(await repo.history(), isEmpty);
  });
  test(
    'Sao lưu khôi phục toàn bộ sang database khác giữ nguyên dữ liệu',
    () async {
      final e = Equipment(name: 'Dữ liệu giả lập');
      await repo.saveEquipment(e);
      await repo.saveItem(
        DeadlineItem(
          equipmentId: e.id,
          kind: ItemKind.insurance,
          title: 'Bảo hiểm',
          insuranceMode: InsuranceMode.centralized,
        ),
      );
      await repo.saveSettings(const AppSettings(warnDays: 45, theme: 'dark'));
      final backup = await repo.snapshot();
      final other = AppDatabase.memory();
      final otherRepo = EquipmentRepository(other);
      try {
        await otherRepo.restore(backup);
        expect(await otherRepo.snapshot(), backup);
      } finally {
        await other.close();
      }
    },
  );
  test('Sao lưu hỏng không xóa dữ liệu hiện tại', () async {
    await repo.saveEquipment(Equipment(name: 'Giữ nguyên'));
    final broken = await repo.snapshot();
    broken['items'] = [
      DeadlineItem(
        equipmentId: 'missing',
        kind: ItemKind.other,
        title: 'Sai liên kết',
      ).toJson(),
    ];
    await expectLater(repo.restore(broken), throwsFormatException);
    expect((await repo.equipment()).single.name, 'Giữ nguyên');
  });
  test('Ghi lịch sử thất bại rollback thay đổi hạng mục', () async {
    final e = Equipment(name: 'Xe thử');
    await repo.saveEquipment(e);
    final i = DeadlineItem(
      equipmentId: e.id,
      kind: ItemKind.other,
      title: 'Một lần',
    );
    await repo.saveItem(i);
    final result = completeItem(i, doneDate: DateTime(2026), provider: '');
    await repo.recordCompletion(result.item, result.history);
    await repo.saveItem(i);
    await expectLater(
      repo.recordCompletion(result.item, result.history),
      throwsA(anything),
    );
    expect((await repo.items()).single.isDone, false);
  });
}

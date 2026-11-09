import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/database.dart';
import '../domain/models.dart';
import '../domain/deadlines.dart';
import '../domain/importing.dart';

class AppController extends ChangeNotifier {
  AppController(this.repository, {this.clock = DateTime.now}) {
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => notifyListeners(),
    );
  }
  final EquipmentRepository repository;
  final DateTime Function() clock;
  late final Timer _timer;
  List<Equipment> equipment = [];
  List<DeadlineItem> items = [];
  List<HistoryLog> history = [];
  List<ServiceRecord> serviceRecords = [];
  List<String> groups = [], providers = [];
  AppSettings settings = const AppSettings();
  bool loading = true;
  List<TrackedDeadline> get tracked =>
      trackedDeadlines(equipment, items, settings, clock());
  Future<void> load() async {
    equipment = await repository.equipment();
    items = await repository.items();
    history = await repository.history();
    serviceRecords = await repository.serviceRecords();
    settings = await repository.settings();
    groups = await repository.catalog('group');
    providers = await repository.catalog('provider');
    loading = false;
    notifyListeners();
  }

  Future<void> saveEquipment(Equipment e) async {
    await repository.saveEquipment(e);
    await load();
  }

  Future<void> saveItem(DeadlineItem i) async {
    await repository.saveItem(i);
    await load();
  }

  Future<void> saveServiceRecord(ServiceRecord record) async {
    await repository.saveServiceRecord(record);
    await load();
  }

  Future<void> deleteServiceRecord(String id) async {
    await repository.deleteServiceRecord(id);
    await load();
  }

  Future<void> importPlan(ImportPlan plan, {required bool confirmPast}) async {
    if (!plan.ready) {
      throw StateError('Cần sửa mọi lỗi và xác nhận từng dòng trước khi nhập.');
    }
    final mapped = <String, String>{};
    final current = {for (final e in equipment) e.id: e};
    final currentItems = [...items];
    await repository.db.transaction(() async {
      for (final record in plan.records) {
        final target = record.targetId == null
            ? null
            : (mapped[record.targetId] ?? record.targetId);
        final old = target == null ? null : current[target];
        if (target != null && old == null) {
          throw StateError('Thiết bị ghép chưa tồn tại: ${record.reference}.');
        }
        final json = record.equipment.toJson();
        final merged = old == null
            ? record.equipment
            : old.copy({
                for (final f in record.suppliedFields)
                  if (!(record.metadataOnly && f == 'name')) f: json[f],
                if (record.suppliedFields.contains('note') ||
                    (record.metadataOnly && old.name != record.equipment.name))
                  'note': [
                    old.note,
                    record.equipment.note,
                    if (record.metadataOnly &&
                        old.name != record.equipment.name)
                      'Tên trong phụ lục: ${record.equipment.name}',
                  ].where((v) => v.isNotEmpty).toSet().join('\n'),
              });
        await repository.saveEquipment(merged);
        current[merged.id] = merged;
        mapped[record.equipment.id] = merged.id;
        for (final raw in record.items) {
          var item = raw.copy({'equipmentId': merged.id});
          if (confirmPast && hasPastDeadline(item, clock())) {
            item = item.copy({'requiresConfirmation': true});
          }
          final same = currentItems
              .where(
                (i) =>
                    i.equipmentId == merged.id &&
                    i.kind == item.kind &&
                    i.title == item.title &&
                    !i.isDone,
              )
              .toList();
          if (same.length > 1) {
            throw StateError(
              '${record.reference}: có nhiều hạng mục ${item.title}; cần xử lý trong ứng dụng trước khi nhập.',
            );
          }
          if (same.length == 1) {
            item = same.single.copy({
              'dueDate': item.dueDate?.toIso8601String(),
              'precision': item.precision.name,
              'insuranceMode': item.insuranceMode.name,
              'expiredWithoutDate': item.expiredWithoutDate,
              'requiresConfirmation': item.requiresConfirmation,
              if (item.provider.isNotEmpty) 'provider': item.provider,
            });
            currentItems.removeWhere((i) => i.id == item.id);
          }
          await repository.saveItem(item);
          currentItems.add(item);
        }
      }
    });
    await load();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}

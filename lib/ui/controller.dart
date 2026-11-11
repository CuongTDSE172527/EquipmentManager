import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/database.dart';
import '../domain/accounts.dart';
import '../domain/models.dart';
import '../domain/deadlines.dart';
import '../domain/importing.dart';
import '../services/auth.dart';

class AppController extends ChangeNotifier {
  AppController(this.repository, {this.clock = DateTime.now, AuthService? auth})
    : auth = auth ?? AuthService(repository, clock: clock) {
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => notifyListeners(),
    );
  }
  final EquipmentRepository repository;
  final DateTime Function() clock;
  final AuthService auth;
  late final Timer _timer;

  /// Signed-in account; null shows the sign-in screens.
  UserAccount? user;

  /// Session kept but hidden behind the lock screen (auto-lock).
  bool locked = false;
  bool hasAccounts = false;

  bool can(Permission p) => user?.can(p) ?? false;

  /// UI hides what a role may not do; this is the second line of defence for
  /// every write that goes through the controller.
  void require(Permission p) {
    if (!can(p)) {
      throw const AuthException(
        'Tài khoản của bạn không có quyền thao tác này.',
      );
    }
  }

  void signIn(UserAccount account) {
    user = account;
    locked = false;
    hasAccounts = true;
    repository.actor = Actor(account.id, account.label);
    notifyListeners();
  }

  /// Refreshes the session after the profile or password changed.
  void refreshUser(UserAccount account) {
    if (user?.id != account.id) return;
    user = account;
    repository.actor = Actor(account.id, account.label);
    notifyListeners();
  }

  Future<void> signOut() async {
    if (user != null) await repository.logAudit('logout', entity: 'account');
    user = null;
    locked = false;
    repository.actor = null;
    notifyListeners();
  }

  void lock() {
    if (user == null || locked) return;
    locked = true;
    notifyListeners();
  }

  Future<void> unlock(String password) async {
    final account = await auth.login(user!.username, password);
    signIn(account);
  }

  List<Equipment> equipment = [];
  List<DeadlineItem> items = [];
  List<HistoryLog> history = [];
  List<ServiceRecord> serviceRecords = [];
  List<Attachment> attachments = [];
  List<String> groups = [], providers = [];
  AppSettings settings = const AppSettings();
  bool loading = true;
  List<TrackedDeadline> get tracked =>
      trackedDeadlines(equipment, items, settings, clock());
  Future<void> load() async {
    if (loading) await repository.pruneAudit();
    equipment = await repository.equipment();
    items = await repository.items();
    history = await repository.history();
    serviceRecords = await repository.serviceRecords();
    attachments = await repository.attachments();
    settings = await repository.settings();
    groups = await repository.catalog('group');
    providers = await repository.catalog('provider');
    hasAccounts = (await repository.accounts()).isNotEmpty;
    loading = false;
    notifyListeners();
  }

  Future<void> saveEquipment(Equipment e) async {
    require(Permission.editData);
    await repository.saveEquipment(e);
    await load();
  }

  Future<void> deleteEquipment(String id) async {
    require(Permission.editData);
    await repository.deleteEquipment(id);
    await load();
  }

  Future<void> saveItem(DeadlineItem i) async {
    require(Permission.editData);
    await repository.saveItem(i);
    await load();
  }

  Future<void> deleteItem(String id) async {
    require(Permission.editData);
    await repository.deleteItem(id);
    await load();
  }

  Future<void> recordCompletion(DeadlineItem item, HistoryLog log) async {
    require(Permission.editData);
    await repository.recordCompletion(item, log);
    await load();
  }

  Future<void> saveServiceRecord(ServiceRecord record) async {
    require(Permission.editData);
    await repository.saveServiceRecord(record);
    await load();
  }

  Future<void> confirmItem(DeadlineItem item) async {
    require(Permission.editData);
    await repository.saveItem(
      confirmDeadline(item, clock()),
      action: 'confirm',
    );
    await load();
  }

  Future<void> addAttachment(Attachment a, Uint8List data) async {
    require(Permission.editData);
    await repository.addAttachment(a, data);
    await load();
  }

  Future<void> updateAttachment(Attachment a) async {
    require(Permission.editData);
    await repository.updateAttachment(a);
    await load();
  }

  Future<void> deleteAttachment(String id) async {
    require(Permission.editData);
    await repository.deleteAttachment(id);
    await load();
  }

  Future<void> updateSettings(Json changes) async {
    require(Permission.manageSettings);
    await repository.saveSettings((await repository.settings()).copy(changes));
    await repository.logAudit('settings', summary: changes.keys.join(', '));
    await load();
  }

  Future<void> saveSettings(AppSettings settings) async {
    require(Permission.manageSettings);
    await repository.saveSettings(settings);
    await repository.logAudit('settings', summary: 'Lưu cài đặt');
    await load();
  }

  Future<void> addCatalog(String kind, String name) async {
    require(Permission.manageSettings);
    await repository.addCatalog(kind, name);
    await load();
  }

  Future<void> renameCatalog(String kind, String oldName, String name) async {
    require(Permission.manageSettings);
    await repository.renameCatalog(kind, oldName, name);
    await load();
  }

  Future<void> deleteServiceRecord(String id) async {
    require(Permission.editData);
    await repository.deleteServiceRecord(id);
    await load();
  }

  Future<void> importPlan(ImportPlan plan, {required bool confirmPast}) async {
    require(Permission.editData);
    if (!plan.ready) {
      throw StateError('Cần sửa mọi lỗi và xác nhận từng dòng trước khi nhập.');
    }
    final mapped = <String, String>{};
    final current = {for (final e in equipment) e.id: e};
    final currentItems = [...items];
    await repository.bulk(
      'import',
      'data',
      '${plan.records.length} dòng',
      () async {
        for (final record in plan.records) {
          final target = record.targetId == null
              ? null
              : (mapped[record.targetId] ?? record.targetId);
          final old = target == null ? null : current[target];
          if (target != null && old == null) {
            throw StateError(
              'Thiết bị ghép chưa tồn tại: ${record.reference}.',
            );
          }
          final json = record.equipment.toJson();
          final merged = old == null
              ? record.equipment
              : old.copy({
                  for (final f in record.suppliedFields)
                    if (!(record.metadataOnly && f == 'name')) f: json[f],
                  if (record.suppliedFields.contains('note') ||
                      (record.metadataOnly &&
                          old.name != record.equipment.name))
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
      },
    );
    await load();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}

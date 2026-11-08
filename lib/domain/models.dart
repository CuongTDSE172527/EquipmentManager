import 'package:uuid/uuid.dart';

String newId() => const Uuid().v4();
typedef Json = Map<String, dynamic>;

enum ManagementStatus {
  active('Đang sử dụng'),
  handedOver('Đã bàn giao đơn vị khác'),
  deployed('Chuyển tăng cường'),
  retired('Hết niên hạn / ngừng sử dụng');

  const ManagementStatus(this.label);
  final String label;
}

enum ItemKind {
  insurance('Bảo hiểm'),
  inspection('Đăng kiểm/Kiểm định'),
  maintenance('Bảo dưỡng'),
  repair('Sửa chữa'),
  lifespan('Niên hạn sử dụng'),
  other('Khác');

  const ItemKind(this.label);
  final String label;
}

enum DatePrecision { day, month }

enum InsuranceMode {
  dated('Có ngày hết hạn'),
  centralized('ACV mua tập trung'),
  notApplicable('Không áp dụng'),
  expired('Đã hết'),
  unknown('Chưa có thông tin');

  const InsuranceMode(this.label);
  final String label;
}

enum DeadlineStatus {
  overdue('Quá hạn'),
  upcoming('Sắp đến hạn'),
  needsUpdate('Cần cập nhật'),
  valid('Còn hạn'),
  done('Đã xong'),
  excluded('Không cảnh báo');

  const DeadlineStatus(this.label);
  final String label;
}

T enumValue<T extends Enum>(List<T> values, dynamic value, T fallback) =>
    values.where((v) => v.name == value).firstOrNull ?? fallback;

DateTime? readDate(dynamic value) {
  if (value == null || value == '') return null;
  if (value is! String) {
    throw const FormatException('Ngày trong dữ liệu không phải chuỗi.');
  }
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:T|$)').firstMatch(value);
  if (match == null) {
    throw const FormatException('Ngày trong dữ liệu phải theo ISO-8601.');
  }
  final y = int.parse(match[1]!),
      m = int.parse(match[2]!),
      d = int.parse(match[3]!);
  final day = DateTime(y, m, d);
  if (day.year != y || day.month != m || day.day != d) {
    throw const FormatException('Ngày trong dữ liệu không tồn tại.');
  }
  return DateTime.parse(value);
}

class Equipment {
  Equipment({
    String? id,
    required this.name,
    this.group = 'I. Phục vụ bay',
    this.type = '',
    this.brandModel = '',
    this.country = '',
    this.yearMade,
    this.chassisNo = '',
    this.engineNo = '',
    this.controlPlate = '',
    this.oldControlPlate = '',
    this.roadPlate = '',
    this.purpose = '',
    this.operatingAt = 'Cảng HK Cà Mau',
    this.selfPropelled = true,
    this.managementStatus = ManagementStatus.active,
    this.note = '',
    DateTime? createdAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? DateTime.now();

  final String id, name, group, type, brandModel, country;
  final String chassisNo, engineNo, controlPlate, oldControlPlate, roadPlate;
  final String purpose, operatingAt, note;
  final int? yearMade;
  final bool selfPropelled;
  final ManagementStatus managementStatus;
  final DateTime createdAt;

  String get displayPlate => roadPlate.isNotEmpty
      ? roadPlate
      : controlPlate.isNotEmpty
      ? controlPlate
      : oldControlPlate;
  String get searchText =>
      '$name $type $brandModel $controlPlate $oldControlPlate $roadPlate'
          .toLowerCase();
  Equipment copy(Json changes) => Equipment.fromJson({...toJson(), ...changes});

  Json toJson() => {
    'id': id,
    'name': name,
    'group': group,
    'type': type,
    'brandModel': brandModel,
    'country': country,
    'yearMade': yearMade,
    'chassisNo': chassisNo,
    'engineNo': engineNo,
    'controlPlate': controlPlate,
    'oldControlPlate': oldControlPlate,
    'roadPlate': roadPlate,
    'purpose': purpose,
    'operatingAt': operatingAt,
    'selfPropelled': selfPropelled,
    'managementStatus': managementStatus.name,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
  };
  factory Equipment.fromJson(Json j) => Equipment(
    id: j['id'] as String?,
    name: j['name'] as String,
    group: j['group'] as String? ?? 'I. Phục vụ bay',
    type: j['type'] as String? ?? '',
    brandModel: j['brandModel'] as String? ?? '',
    country: j['country'] as String? ?? '',
    yearMade: j['yearMade'] as int?,
    chassisNo: j['chassisNo'] as String? ?? '',
    engineNo: j['engineNo'] as String? ?? '',
    controlPlate: j['controlPlate'] as String? ?? '',
    oldControlPlate: j['oldControlPlate'] as String? ?? '',
    roadPlate: j['roadPlate'] as String? ?? '',
    purpose: j['purpose'] as String? ?? '',
    operatingAt: j['operatingAt'] as String? ?? 'Cảng HK Cà Mau',
    selfPropelled: j['selfPropelled'] as bool? ?? true,
    managementStatus: enumValue(
      ManagementStatus.values,
      j['managementStatus'],
      ManagementStatus.active,
    ),
    note: j['note'] as String? ?? '',
    createdAt: readDate(j['createdAt']),
  );
}

class DeadlineItem {
  DeadlineItem({
    String? id,
    required this.equipmentId,
    required this.kind,
    required this.title,
    this.dueDate,
    this.precision = DatePrecision.day,
    this.cycleMonths = 0,
    this.isDone = false,
    this.cost,
    this.note = '',
    this.provider = '',
    this.insuranceMode = InsuranceMode.unknown,
    this.requiresConfirmation = false,
    this.expiredWithoutDate = false,
  }) : id = id ?? newId();
  final String id, equipmentId, title, note, provider;
  final ItemKind kind;
  final DateTime? dueDate;
  final DatePrecision precision;
  final int cycleMonths;
  final bool isDone, requiresConfirmation, expiredWithoutDate;
  final int? cost;
  final InsuranceMode insuranceMode;
  DeadlineItem copy(Json changes) =>
      DeadlineItem.fromJson({...toJson(), ...changes});
  Json toJson() => {
    'id': id,
    'equipmentId': equipmentId,
    'kind': kind.name,
    'title': title,
    'dueDate': dueDate?.toIso8601String(),
    'precision': precision.name,
    'cycleMonths': cycleMonths,
    'isDone': isDone,
    'cost': cost,
    'note': note,
    'provider': provider,
    'insuranceMode': insuranceMode.name,
    'requiresConfirmation': requiresConfirmation,
    'expiredWithoutDate': expiredWithoutDate,
  };
  factory DeadlineItem.fromJson(Json j) => DeadlineItem(
    id: j['id'] as String?,
    equipmentId: j['equipmentId'] as String,
    kind: enumValue(ItemKind.values, j['kind'], ItemKind.other),
    title: j['title'] as String,
    dueDate: readDate(j['dueDate']),
    precision: enumValue(
      DatePrecision.values,
      j['precision'],
      DatePrecision.day,
    ),
    cycleMonths: j['cycleMonths'] as int? ?? 0,
    isDone: j['isDone'] as bool? ?? false,
    cost: j['cost'] as int?,
    note: j['note'] as String? ?? '',
    provider: j['provider'] as String? ?? '',
    insuranceMode: enumValue(
      InsuranceMode.values,
      j['insuranceMode'],
      InsuranceMode.unknown,
    ),
    requiresConfirmation: j['requiresConfirmation'] as bool? ?? false,
    expiredWithoutDate: j['expiredWithoutDate'] as bool? ?? false,
  );
}

class HistoryLog {
  HistoryLog({
    String? id,
    required this.itemId,
    required this.doneDate,
    this.cost,
    this.provider = '',
    this.note = '',
    this.previousDueDate,
    this.nextDueDate,
  }) : id = id ?? newId();
  final String id, itemId, provider, note;
  final DateTime doneDate;
  final DateTime? previousDueDate, nextDueDate;
  final int? cost;
  Json toJson() => {
    'id': id,
    'itemId': itemId,
    'doneDate': doneDate.toIso8601String(),
    'cost': cost,
    'provider': provider,
    'note': note,
    'previousDueDate': previousDueDate?.toIso8601String(),
    'nextDueDate': nextDueDate?.toIso8601String(),
  };
  factory HistoryLog.fromJson(Json j) => HistoryLog(
    id: j['id'] as String?,
    itemId: j['itemId'] as String,
    doneDate: readDate(j['doneDate'])!,
    cost: j['cost'] as int?,
    provider: j['provider'] as String? ?? '',
    note: j['note'] as String? ?? '',
    previousDueDate: readDate(j['previousDueDate']),
    nextDueDate: readDate(j['nextDueDate']),
  );
}

class AppSettings {
  const AppSettings({
    this.warnDays = 30,
    this.lifespanWarnDays = 180,
    this.notifyHour = 8,
    this.notifyMinute = 0,
    this.theme = 'system',
    this.agency = 'CẢNG HÀNG KHÔNG CÀ MAU',
    this.team = 'TỔ VHTTBMĐ - ĐỘI KỸ THUẬT',
    this.notificationsEnabled = false,
    this.lastBackup,
  });
  final int warnDays, lifespanWarnDays, notifyHour, notifyMinute;
  final String theme, agency, team;
  final bool notificationsEnabled;
  final DateTime? lastBackup;
  AppSettings copy(Json changes) =>
      AppSettings.fromJson({...toJson(), ...changes});
  Json toJson() => {
    'warnDays': warnDays,
    'lifespanWarnDays': lifespanWarnDays,
    'notifyHour': notifyHour,
    'notifyMinute': notifyMinute,
    'theme': theme,
    'agency': agency,
    'team': team,
    'notificationsEnabled': notificationsEnabled,
    'lastBackup': lastBackup?.toIso8601String(),
  };
  factory AppSettings.fromJson(Json j) => AppSettings(
    warnDays: j['warnDays'] as int? ?? 30,
    lifespanWarnDays: j['lifespanWarnDays'] as int? ?? 180,
    notifyHour: j['notifyHour'] as int? ?? 8,
    notifyMinute: j['notifyMinute'] as int? ?? 0,
    theme: j['theme'] as String? ?? 'system',
    agency: j['agency'] as String? ?? 'CẢNG HÀNG KHÔNG CÀ MAU',
    team: j['team'] as String? ?? 'TỔ VHTTBMĐ - ĐỘI KỸ THUẬT',
    notificationsEnabled: j['notificationsEnabled'] as bool? ?? false,
    lastBackup: readDate(j['lastBackup']),
  );
}

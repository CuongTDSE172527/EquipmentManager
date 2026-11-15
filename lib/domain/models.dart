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

/// A past maintenance/repair event, independent of future deadline scheduling.
class ServiceRecord {
  ServiceRecord({
    String? id,
    required this.equipmentId,
    required this.kind,
    required this.title,
    required this.doneDate,
    this.cost,
    this.provider = '',
    this.note = '',
  }) : id = id ?? newId();
  final String id, equipmentId, title, provider, note;
  final ItemKind kind;
  final DateTime doneDate;
  final int? cost;
  Json toJson() => {
    'id': id,
    'equipmentId': equipmentId,
    'kind': kind.name,
    'title': title,
    'doneDate': doneDate.toIso8601String(),
    'cost': cost,
    'provider': provider,
    'note': note,
  };
  factory ServiceRecord.fromJson(Json j) => ServiceRecord(
    id: j['id'] as String?,
    equipmentId: j['equipmentId'] as String,
    kind: enumValue(ItemKind.values, j['kind'], ItemKind.other),
    title: j['title'] as String,
    doneDate: readDate(j['doneDate'])!,
    cost: j['cost'] as int?,
    provider: j['provider'] as String? ?? '',
    note: j['note'] as String? ?? '',
  );
}

void validateServiceRecord(ServiceRecord record) {
  if (![ItemKind.maintenance, ItemKind.repair].contains(record.kind) ||
      record.title.trim().isEmpty ||
      record.equipmentId.isEmpty ||
      (record.cost ?? 0) < 0 ||
      record.doneDate.year < 1900 ||
      record.doneDate.year > 9999) {
    throw const FormatException('Lịch sử bảo trì/sửa chữa không hợp lệ.');
  }
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
    this.autoBackupEnabled = true,
    this.autoBackupDays = 7,
    this.lastAutoBackup,
    this.autoUpdateCheck = false,
    this.updateIncludePrereleases = true,
    this.lastUpdateCheck,
  });
  final int warnDays, lifespanWarnDays, notifyHour, notifyMinute;
  final String theme, agency, team;
  final bool notificationsEnabled;

  /// Last backup saved by the user outside the app (or before an OTA install).
  final DateTime? lastBackup;

  /// Rotating copies kept inside the app folder; they do not count as an
  /// external backup because they are lost together with the device.
  final bool autoBackupEnabled;
  final int autoBackupDays;
  final DateTime? lastAutoBackup;

  /// Opt-in: the app stays offline unless the user enables this.
  final bool autoUpdateCheck, updateIncludePrereleases;
  final DateTime? lastUpdateCheck;
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
    'autoBackupEnabled': autoBackupEnabled,
    'autoBackupDays': autoBackupDays,
    'lastAutoBackup': lastAutoBackup?.toIso8601String(),
    'autoUpdateCheck': autoUpdateCheck,
    'updateIncludePrereleases': updateIncludePrereleases,
    'lastUpdateCheck': lastUpdateCheck?.toIso8601String(),
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
    autoBackupEnabled: j['autoBackupEnabled'] as bool? ?? true,
    autoBackupDays: j['autoBackupDays'] as int? ?? 7,
    lastAutoBackup: readDate(j['lastAutoBackup']),
    autoUpdateCheck: j['autoUpdateCheck'] as bool? ?? false,
    updateIncludePrereleases: j['updateIncludePrereleases'] as bool? ?? true,
    lastUpdateCheck: readDate(j['lastUpdateCheck']),
  );
}

/// MIME types used to open common record files with the right app. Any other
/// type is still accepted and opened as `application/octet-stream`.
const attachmentTypes = {
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'gif': 'image/gif',
  'bmp': 'image/bmp',
  'tif': 'image/tiff',
  'tiff': 'image/tiff',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'odt': 'application/vnd.oasis.opendocument.text',
  'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'rtf': 'application/rtf',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'xml': 'text/xml',
  'json': 'application/json',
  'zip': 'application/zip',
  'rar': 'application/vnd.rar',
  '7z': 'application/x-7z-compressed',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'dwg': 'image/vnd.dwg',
  'eml': 'message/rfc822',
};

/// Programs and scripts run when "opened", so they are never kept as records.
const blockedAttachmentTypes = {
  'exe',
  'com',
  'bat',
  'cmd',
  'msi',
  'msp',
  'msix',
  'appx',
  'scr',
  'pif',
  'cpl',
  'dll',
  'sys',
  'ps1',
  'psm1',
  'vbs',
  'vbe',
  'js',
  'jse',
  'wsf',
  'wsh',
  'hta',
  'lnk',
  'url',
  'reg',
  'inf',
  'scf',
  'jar',
  'apk',
  'msc',
  'application',
  'gadget',
  'sh',
};

/// Per file. Backups are built in memory (up to [maxBackupBytes] in all), so
/// a hard limit stays to keep backup and restore working on phones.
const maxAttachmentBytes = 100 * 1024 * 1024;
const maxAttachmentLabel = '100 MB';

String fileExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// `Hồ sơ\Đăng kiểm/ 2026 ` → `Hồ sơ/Đăng kiểm/2026`.
String normalizeFolder(String folder) => folder
    .replaceAll(r'\', '/')
    .split('/')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .join('/');

/// Null when [folder] (already normalized, '' = top level) is acceptable.
String? folderProblem(String folder) {
  if (folder.isEmpty) return null;
  final parts = folder.split('/');
  if (folder.length > 255 || parts.length > 8) {
    return 'Thư mục lồng quá sâu hoặc tên quá dài.';
  }
  for (final s in parts) {
    if (s.isEmpty ||
        s == '.' ||
        s == '..' ||
        s.length > 100 ||
        s.contains(RegExp(r'[<>:"|?*\x00-\x1F\\]'))) {
      return 'Tên thư mục không hợp lệ: “$s”.';
    }
  }
  return null;
}

/// A record document (hồ sơ) kept with a piece of equipment, optionally in a
/// folder and linked to one of its deadline items or service records. The
/// bytes live in SQLite next to it.
class Attachment {
  Attachment({
    String? id,
    required this.equipmentId,
    required this.fileName,
    required this.size,
    required this.sha256,
    String? title,
    this.linkId,
    this.note = '',
    this.folder = '',
    DateTime? createdAt,
  }) : id = id ?? newId(),
       title = (title == null || title.trim().isEmpty) ? fileName : title,
       createdAt = createdAt ?? DateTime.now();
  final String id, equipmentId, fileName, sha256, title, note;

  /// Folder path inside the equipment's records, `/`-separated; '' = top.
  final String folder;
  final String? linkId;
  final int size;
  final DateTime createdAt;
  String get extension => fileExtension(fileName);
  String get mimeType =>
      attachmentTypes[extension] ?? 'application/octet-stream';
  bool get isImage => mimeType.startsWith('image/') && extension != 'dwg';
  Attachment copy(Json changes) =>
      Attachment.fromJson({...toJson(), ...changes});
  Json toJson() => {
    'id': id,
    'equipmentId': equipmentId,
    'fileName': fileName,
    'size': size,
    'sha256': sha256,
    'title': title,
    'linkId': linkId,
    'note': note,
    'folder': folder,
    'createdAt': createdAt.toIso8601String(),
  };
  factory Attachment.fromJson(Json j) => Attachment(
    id: j['id'] as String?,
    equipmentId: j['equipmentId'] as String,
    fileName: j['fileName'] as String,
    size: j['size'] as int,
    sha256: j['sha256'] as String,
    title: j['title'] as String?,
    linkId: j['linkId'] as String?,
    note: j['note'] as String? ?? '',
    folder: j['folder'] as String? ?? '',
    createdAt: readDate(j['createdAt']),
  );
}

void validateAttachment(Attachment a) {
  if (a.equipmentId.isEmpty ||
      a.fileName.trim().isEmpty ||
      a.fileName.contains(RegExp(r'[\\/]')) ||
      blockedAttachmentTypes.contains(a.extension) ||
      a.size <= 0 ||
      a.size > maxAttachmentBytes ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(a.sha256) ||
      a.title.trim().isEmpty ||
      a.folder != normalizeFolder(a.folder) ||
      folderProblem(a.folder) != null) {
    throw const FormatException('Tệp hồ sơ không hợp lệ.');
  }
}

import 'models.dart';

enum Permission {
  /// Equipment, items, service book, attachments, completion, confirmation, import.
  editData,

  /// Excel reports. Every role may export what it can see.
  exportReports,

  /// A full backup holds every record, so it is not open to read-only users.
  exportBackup,

  /// Replaces all data on the device.
  restoreBackup,

  /// Accounts, roles, approvals, password resets.
  manageUsers,

  viewAudit,

  /// Organisation, reminder, backup and catalog settings.
  manageSettings,

  installUpdates,
}

enum Role {
  admin('Quản trị', Permission.values),
  technician('Cán bộ kỹ thuật', [
    Permission.editData,
    Permission.exportReports,
    Permission.exportBackup,
  ]),
  viewer('Chỉ xem', [Permission.exportReports]);

  const Role(this.label, this.permissions);
  final String label;
  final List<Permission> permissions;
  bool can(Permission p) => permissions.contains(p);
}

enum AccountStatus {
  active('Đang hoạt động'),
  pending('Chờ duyệt'),
  disabled('Đã khóa');

  const AccountStatus(this.label);
  final String label;
}

/// Auto-lock choices offered to each user; 0 turns it off.
const autoLockChoices = [0, 1, 5, 10, 15, 30, 60];

/// A person who signs in on this device. Accounts never leave the device:
/// they are not in backups, so restoring data cannot replace who may log in.
class UserAccount {
  UserAccount({
    String? id,
    required this.username,
    required this.displayName,
    required this.passwordHash,
    this.recoveryHash = '',
    this.position = '',
    this.unit = '',
    this.phone = '',
    this.role = Role.viewer,
    this.status = AccountStatus.pending,
    this.mustChangePassword = false,
    this.failedAttempts = 0,
    this.lockCount = 0,
    this.lockedUntil,
    this.autoLockMinutes = 10,
    DateTime? createdAt,
    this.lastLoginAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? DateTime.now();
  final String id, username, displayName, passwordHash, recoveryHash;
  final String position, unit, phone;
  final Role role;
  final AccountStatus status;
  final bool mustChangePassword;
  final int failedAttempts, lockCount, autoLockMinutes;
  final DateTime? lockedUntil, lastLoginAt;
  final DateTime createdAt;

  bool can(Permission p) => status == AccountStatus.active && role.can(p);
  bool lockedAt(DateTime now) =>
      lockedUntil != null && lockedUntil!.isAfter(now);
  String get label => displayName.isEmpty ? username : displayName;

  UserAccount copy(Json changes) =>
      UserAccount.fromJson({...toJson(), ...changes});
  Json toJson() => {
    'id': id,
    'username': username,
    'displayName': displayName,
    'passwordHash': passwordHash,
    'recoveryHash': recoveryHash,
    'position': position,
    'unit': unit,
    'phone': phone,
    'role': role.name,
    'status': status.name,
    'mustChangePassword': mustChangePassword,
    'failedAttempts': failedAttempts,
    'lockCount': lockCount,
    'lockedUntil': lockedUntil?.toIso8601String(),
    'autoLockMinutes': autoLockMinutes,
    'createdAt': createdAt.toIso8601String(),
    'lastLoginAt': lastLoginAt?.toIso8601String(),
  };
  factory UserAccount.fromJson(Json j) => UserAccount(
    id: j['id'] as String?,
    username: j['username'] as String,
    displayName: j['displayName'] as String? ?? '',
    passwordHash: j['passwordHash'] as String,
    recoveryHash: j['recoveryHash'] as String? ?? '',
    position: j['position'] as String? ?? '',
    unit: j['unit'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    role: enumValue(Role.values, j['role'], Role.viewer),
    status: enumValue(AccountStatus.values, j['status'], AccountStatus.pending),
    mustChangePassword: j['mustChangePassword'] as bool? ?? false,
    failedAttempts: j['failedAttempts'] as int? ?? 0,
    lockCount: j['lockCount'] as int? ?? 0,
    lockedUntil: readDate(j['lockedUntil']),
    autoLockMinutes: j['autoLockMinutes'] as int? ?? 10,
    createdAt: readDate(j['createdAt']),
    lastLoginAt: readDate(j['lastLoginAt']),
  );
}

/// One line of the audit trail: who did what, to which record, and when.
class AuditEntry {
  AuditEntry({
    String? id,
    required this.at,
    required this.action,
    this.userId = '',
    this.userName = '',
    this.entity = '',
    this.entityId = '',
    this.summary = '',
  }) : id = id ?? newId();
  final String id, action, userId, userName, entity, entityId, summary;
  final DateTime at;
  Json toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'action': action,
    'userId': userId,
    'userName': userName,
    'entity': entity,
    'entityId': entityId,
    'summary': summary,
  };
  factory AuditEntry.fromJson(Json j) => AuditEntry(
    id: j['id'] as String?,
    at: readDate(j['at'])!,
    action: j['action'] as String,
    userId: j['userId'] as String? ?? '',
    userName: j['userName'] as String? ?? '',
    entity: j['entity'] as String? ?? '',
    entityId: j['entityId'] as String? ?? '',
    summary: j['summary'] as String? ?? '',
  );
}

const auditActionLabels = {
  'create': 'Thêm',
  'update': 'Sửa',
  'delete': 'Xóa',
  'complete': 'Hoàn thành',
  'confirm': 'Xác nhận dữ liệu',
  'import': 'Nhập Excel',
  'restore': 'Khôi phục',
  'backup': 'Sao lưu',
  'settings': 'Cài đặt',
  'login': 'Đăng nhập',
  'logout': 'Đăng xuất',
  'login_failed': 'Đăng nhập sai',
  'lockout': 'Tạm khóa',
  'register': 'Đăng ký',
  'account': 'Tài khoản',
  'password': 'Mật khẩu',
  'sync': 'Đồng bộ',
};

const auditEntityLabels = {
  'equipment': 'Thiết bị',
  'item': 'Hạng mục',
  'history': 'Lịch sử hoàn thành',
  'service': 'Sổ bảo trì',
  'attachment': 'Tệp đính kèm',
  'catalog': 'Danh mục',
  'account': 'Tài khoản',
  'data': 'Dữ liệu',
};

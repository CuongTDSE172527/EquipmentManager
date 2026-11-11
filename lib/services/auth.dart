import 'dart:math';
import '../data/database.dart';
import '../domain/accounts.dart';
import '../domain/models.dart';
import '../domain/security.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Local accounts: registration, sign-in with lockout, recovery codes and the
/// administrator's user management. Every decision is written to the audit log.
class AuthService {
  AuthService(
    this.repo, {
    this.iterations = defaultPasswordIterations,
    DateTime Function()? clock,
  }) : clock = clock ?? repo.clock;
  final EquipmentRepository repo;
  final int iterations;
  final DateTime Function() clock;
  static const maxFailures = 5;
  String? _dummy;

  Actor _actor(UserAccount a) => Actor(a.id, a.label);

  Future<bool> hasAccounts() async => (await repo.accounts()).isNotEmpty;

  /// The first account on a device becomes an active administrator; later
  /// self-registrations wait for an administrator to approve them.
  Future<({UserAccount account, String recoveryCode})> register({
    required String username,
    required String password,
    required String displayName,
    String position = '',
    String unit = '',
    String phone = '',
  }) async {
    final name = normalizeUsername(username);
    final problem =
        usernameProblem(name) ?? passwordProblem(password, username: name);
    if (problem != null) throw AuthException(problem);
    if (displayName.trim().isEmpty) {
      throw const AuthException('Hãy nhập họ tên.');
    }
    if (await repo.accountByUsername(name) != null) {
      throw const AuthException('Tên đăng nhập đã được dùng.');
    }
    final first = !await hasAccounts();
    final code = newRecoveryCode();
    final account = UserAccount(
      username: name,
      displayName: displayName.trim(),
      position: position.trim(),
      unit: unit.trim(),
      phone: phone.trim(),
      passwordHash: await hashSecret(password, iterations),
      recoveryHash: await hashSecret(normalizeRecoveryCode(code), iterations),
      role: first ? Role.admin : Role.viewer,
      status: first ? AccountStatus.active : AccountStatus.pending,
      createdAt: clock(),
    );
    await repo.saveAccount(account);
    await repo.logAudit(
      'register',
      entity: 'account',
      entityId: account.id,
      summary: first
          ? '${account.label} (Quản trị đầu tiên)'
          : '${account.label} chờ duyệt',
      as: _actor(account),
    );
    return (account: account, recoveryCode: code);
  }

  Future<UserAccount> login(String username, String password) async {
    final now = clock();
    final account = await repo.accountByUsername(normalizeUsername(username));
    if (account == null) {
      // Spend the same time as a real check so names cannot be probed.
      _dummy ??= await hashSecret('khong-co-tai-khoan', iterations);
      await verifySecret(password, _dummy!);
      await repo.logAudit(
        'login_failed',
        entity: 'account',
        summary: 'Tên không tồn tại: ${normalizeUsername(username)}',
      );
      throw const AuthException('Tên đăng nhập hoặc mật khẩu không đúng.');
    }
    if (account.lockedAt(now)) {
      throw AuthException(
        'Tài khoản tạm khóa đến ${_time(account.lockedUntil!)} do nhập sai nhiều lần.',
      );
    }
    if (!await verifySecret(password, account.passwordHash)) {
      final failed = account.failedAttempts + 1;
      if (failed >= maxFailures) {
        final count = account.lockCount + 1;
        final minutes = min(5 * pow(2, count - 1).toInt(), 60);
        final until = now.add(Duration(minutes: minutes));
        await repo.saveAccount(
          account.copy({
            'failedAttempts': 0,
            'lockCount': count,
            'lockedUntil': until.toIso8601String(),
          }),
        );
        await repo.logAudit(
          'lockout',
          entity: 'account',
          entityId: account.id,
          summary: '$minutes phút',
          as: _actor(account),
        );
        throw AuthException(
          'Sai mật khẩu $maxFailures lần. Tài khoản tạm khóa $minutes phút (đến ${_time(until)}).',
        );
      }
      await repo.saveAccount(account.copy({'failedAttempts': failed}));
      await repo.logAudit(
        'login_failed',
        entity: 'account',
        entityId: account.id,
        as: _actor(account),
      );
      throw AuthException(
        'Tên đăng nhập hoặc mật khẩu không đúng. Còn ${maxFailures - failed} lần thử.',
      );
    }
    // Status is revealed only to someone who knows the password.
    if (account.status == AccountStatus.pending) {
      throw const AuthException('Tài khoản đang chờ Quản trị duyệt.');
    }
    if (account.status == AccountStatus.disabled) {
      throw const AuthException('Tài khoản đã bị khóa. Liên hệ Quản trị.');
    }
    final signedIn = account.copy({
      'failedAttempts': 0,
      'lockCount': 0,
      'lockedUntil': null,
      'lastLoginAt': now.toIso8601String(),
    });
    await repo.saveAccount(signedIn);
    await repo.logAudit(
      'login',
      entity: 'account',
      entityId: account.id,
      as: _actor(account),
    );
    return signedIn;
  }

  /// Returns a new recovery code when the account had none (admin-created).
  Future<({UserAccount account, String? recoveryCode})> changePassword(
    UserAccount account,
    String current,
    String next,
  ) async {
    final fresh = await _fresh(account);
    if (!await verifySecret(current, fresh.passwordHash)) {
      throw const AuthException('Mật khẩu hiện tại không đúng.');
    }
    final problem = passwordProblem(next, username: fresh.username);
    if (problem != null) throw AuthException(problem);
    if (next == current) {
      throw const AuthException('Mật khẩu mới phải khác mật khẩu cũ.');
    }
    final code = fresh.recoveryHash.isEmpty ? newRecoveryCode() : null;
    final updated = fresh.copy({
      'passwordHash': await hashSecret(next, iterations),
      'mustChangePassword': false,
      if (code != null)
        'recoveryHash': await hashSecret(
          normalizeRecoveryCode(code),
          iterations,
        ),
    });
    await repo.saveAccount(updated);
    await repo.logAudit(
      'password',
      entity: 'account',
      entityId: fresh.id,
      summary: 'Đổi mật khẩu',
      as: _actor(fresh),
    );
    return (account: updated, recoveryCode: code);
  }

  /// Offline reset with the recovery code shown at registration. The code is
  /// single-use: a new one is issued with the new password.
  Future<String> recover(String username, String code, String next) async {
    final account = await repo.accountByUsername(normalizeUsername(username));
    final valid =
        account != null &&
        account.recoveryHash.isNotEmpty &&
        !account.lockedAt(clock()) &&
        await verifySecret(normalizeRecoveryCode(code), account.recoveryHash);
    if (!valid) {
      if (account != null && !account.lockedAt(clock())) {
        final failed = account.failedAttempts + 1;
        await repo.saveAccount(
          account.copy({
            'failedAttempts': failed >= maxFailures ? 0 : failed,
            if (failed >= maxFailures)
              'lockedUntil': clock()
                  .add(const Duration(minutes: 15))
                  .toIso8601String(),
          }),
        );
      }
      await repo.logAudit(
        'login_failed',
        entity: 'account',
        entityId: account?.id ?? '',
        summary: 'Mã khôi phục sai',
      );
      throw const AuthException(
        'Tên đăng nhập hoặc mã khôi phục không đúng, hoặc tài khoản đang tạm khóa.',
      );
    }
    final problem = passwordProblem(next, username: account.username);
    if (problem != null) throw AuthException(problem);
    final fresh = newRecoveryCode();
    await repo.saveAccount(
      account.copy({
        'passwordHash': await hashSecret(next, iterations),
        'recoveryHash': await hashSecret(
          normalizeRecoveryCode(fresh),
          iterations,
        ),
        'mustChangePassword': false,
        'failedAttempts': 0,
        'lockCount': 0,
        'lockedUntil': null,
      }),
    );
    await repo.logAudit(
      'password',
      entity: 'account',
      entityId: account.id,
      summary: 'Đặt lại bằng mã khôi phục',
      as: _actor(account),
    );
    return fresh;
  }

  Future<String> regenerateRecoveryCode(
    UserAccount account,
    String password,
  ) async {
    final fresh = await _fresh(account);
    if (!await verifySecret(password, fresh.passwordHash)) {
      throw const AuthException('Mật khẩu không đúng.');
    }
    final code = newRecoveryCode();
    await repo.saveAccount(
      fresh.copy({
        'recoveryHash': await hashSecret(
          normalizeRecoveryCode(code),
          iterations,
        ),
      }),
    );
    await repo.logAudit(
      'password',
      entity: 'account',
      entityId: fresh.id,
      summary: 'Tạo mã khôi phục mới',
      as: _actor(fresh),
    );
    return code;
  }

  Future<UserAccount> updateProfile(
    UserAccount account, {
    required String displayName,
    String position = '',
    String unit = '',
    String phone = '',
    int? autoLockMinutes,
  }) async {
    if (displayName.trim().isEmpty) {
      throw const AuthException('Hãy nhập họ tên.');
    }
    if (autoLockMinutes != null && !autoLockChoices.contains(autoLockMinutes)) {
      throw const AuthException('Thời gian tự khóa không hợp lệ.');
    }
    final updated = (await _fresh(account)).copy({
      'displayName': displayName.trim(),
      'position': position.trim(),
      'unit': unit.trim(),
      'phone': phone.trim(),
      'autoLockMinutes': ?autoLockMinutes,
    });
    await repo.saveAccount(updated);
    await repo.logAudit(
      'account',
      entity: 'account',
      entityId: updated.id,
      summary: 'Cập nhật hồ sơ',
      as: _actor(updated),
    );
    return updated;
  }

  // ---- administrator ---------------------------------------------------

  Future<UserAccount> _fresh(UserAccount a) async =>
      await repo.accountByUsername(a.username) ??
      (throw const AuthException('Không tìm thấy tài khoản.'));

  Future<void> _requireAdmin(UserAccount admin) async {
    final fresh = await _fresh(admin);
    if (!fresh.can(Permission.manageUsers)) {
      throw const AuthException('Chỉ Quản trị được quản lý tài khoản.');
    }
  }

  /// At least one active administrator must remain, or nobody could approve
  /// accounts or restore data on this device again.
  Future<void> _keepAnAdmin(UserAccount target, Json changes) async {
    final after = target.copy(changes);
    if (target.role != Role.admin || target.status != AccountStatus.active) {
      return;
    }
    if (after.role == Role.admin && after.status == AccountStatus.active) {
      return;
    }
    final admins = (await repo.accounts()).where(
      (a) => a.role == Role.admin && a.status == AccountStatus.active,
    );
    if (admins.length <= 1) {
      throw const AuthException(
        'Phải còn ít nhất một Quản trị đang hoạt động.',
      );
    }
  }

  Future<UserAccount> _adminUpdate(
    UserAccount admin,
    UserAccount target,
    Json changes,
    String summary,
  ) async {
    await _requireAdmin(admin);
    final fresh = await _fresh(target);
    await _keepAnAdmin(fresh, changes);
    final updated = fresh.copy(changes);
    await repo.saveAccount(updated);
    await repo.logAudit(
      'account',
      entity: 'account',
      entityId: updated.id,
      summary: '${updated.label}: $summary',
      as: _actor(admin),
    );
    return updated;
  }

  Future<UserAccount> approve(
    UserAccount admin,
    UserAccount target,
    Role role,
  ) => _adminUpdate(admin, target, {
    'status': AccountStatus.active.name,
    'role': role.name,
  }, 'duyệt, vai trò ${role.label}');

  Future<UserAccount> setRole(
    UserAccount admin,
    UserAccount target,
    Role role,
  ) =>
      _adminUpdate(admin, target, {'role': role.name}, 'vai trò ${role.label}');

  Future<UserAccount> setStatus(
    UserAccount admin,
    UserAccount target,
    AccountStatus status,
  ) => _adminUpdate(admin, target, {
    'status': status.name,
  }, status.label.toLowerCase());

  Future<UserAccount> unlock(UserAccount admin, UserAccount target) =>
      _adminUpdate(admin, target, {
        'failedAttempts': 0,
        'lockCount': 0,
        'lockedUntil': null,
      }, 'mở khóa tạm thời');

  /// Issues a one-time password that must be changed at the next sign-in.
  Future<String> resetPassword(UserAccount admin, UserAccount target) async {
    final temporary = temporaryPassword();
    await _adminUpdate(admin, target, {
      'passwordHash': await hashSecret(temporary, iterations),
      'mustChangePassword': true,
      'failedAttempts': 0,
      'lockCount': 0,
      'lockedUntil': null,
    }, 'đặt lại mật khẩu');
    return temporary;
  }

  Future<({UserAccount account, String password})> createAccount(
    UserAccount admin, {
    required String username,
    required String displayName,
    required Role role,
    String position = '',
    String unit = '',
  }) async {
    await _requireAdmin(admin);
    final name = normalizeUsername(username);
    final problem = usernameProblem(name);
    if (problem != null) throw AuthException(problem);
    if (displayName.trim().isEmpty) {
      throw const AuthException('Hãy nhập họ tên.');
    }
    if (await repo.accountByUsername(name) != null) {
      throw const AuthException('Tên đăng nhập đã được dùng.');
    }
    final temporary = temporaryPassword();
    final account = UserAccount(
      username: name,
      displayName: displayName.trim(),
      position: position.trim(),
      unit: unit.trim(),
      passwordHash: await hashSecret(temporary, iterations),
      role: role,
      status: AccountStatus.active,
      mustChangePassword: true,
      createdAt: clock(),
    );
    await repo.saveAccount(account);
    await repo.logAudit(
      'account',
      entity: 'account',
      entityId: account.id,
      summary: 'Tạo ${account.label}, vai trò ${role.label}',
      as: _actor(admin),
    );
    return (account: account, password: temporary);
  }
}

/// 12 characters with letters and digits, no look-alikes.
String temporaryPassword() {
  const letters = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ';
  const digits = '23456789';
  final random = Random.secure();
  final chars = [
    for (var i = 0; i < 10; i++) letters[random.nextInt(letters.length)],
    for (var i = 0; i < 2; i++) digits[random.nextInt(digits.length)],
  ]..shuffle(random);
  return chars.join();
}

String _time(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

import 'package:equipment_manager/domain/accounts.dart';
import 'package:equipment_manager/ui/controller.dart';

/// Signs a test user in without hashing, so widget tests stay fast and need
/// no isolate. Real password handling is covered in auth_test.dart.
Future<UserAccount> signInForTest(
  AppController c, {
  Role role = Role.admin,
  int autoLockMinutes = 0,
}) async {
  final account = UserAccount(
    username: 'thu.${role.name}',
    displayName: 'Người thử ${role.label}',
    passwordHash: 'pbkdf2-sha256\$1\$AA==\$AA==',
    role: role,
    status: AccountStatus.active,
    autoLockMinutes: autoLockMinutes,
  );
  await c.repository.saveAccount(account);
  await c.load();
  c.signIn(account);
  return account;
}

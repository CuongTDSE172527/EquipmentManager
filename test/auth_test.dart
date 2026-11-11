import 'package:flutter_test/flutter_test.dart';
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/accounts.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/services/auth.dart';

void main() {
  late AppDatabase db;
  late EquipmentRepository repo;
  late AuthService auth;
  var now = DateTime(2026, 11, 11, 8);
  setUp(() {
    now = DateTime(2026, 11, 11, 8);
    db = AppDatabase.memory();
    repo = EquipmentRepository(db, clock: () => now);
    auth = AuthService(repo, iterations: 1000);
  });
  tearDown(() => db.close());

  Future<UserAccount> admin() async => (await auth.register(
    username: 'QuanTri',
    password: 'Bimat2026Ok',
    displayName: 'Nguyễn Quản Trị',
  )).account;

  test('Tài khoản đầu tiên là Quản trị; đăng ký sau phải chờ duyệt', () async {
    final first = await admin();
    expect(first.username, 'quantri');
    expect(first.role, Role.admin);
    expect(first.status, AccountStatus.active);
    expect(first.passwordHash, isNot(contains('Bimat2026Ok')));
    final second = await auth.register(
      username: 'kythuat1',
      password: 'Kythuat2026',
      displayName: 'Trần Kỹ Thuật',
    );
    expect(second.account.status, AccountStatus.pending);
    expect(second.account.role, Role.viewer);
    await expectLater(
      auth.register(
        username: 'KYTHUAT1',
        password: 'Khac20261',
        displayName: 'Trùng tên',
      ),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      auth.login('kythuat1', 'Kythuat2026'),
      throwsA(predicate((e) => e.toString().contains('chờ Quản trị duyệt'))),
    );
    final approved = await auth.approve(first, second.account, Role.technician);
    expect(approved.can(Permission.editData), isTrue);
    expect(approved.can(Permission.restoreBackup), isFalse);
    expect((await auth.login('kythuat1', 'Kythuat2026')).lastLoginAt, now);
    await expectLater(
      auth.approve(approved, first, Role.viewer),
      throwsA(isA<AuthException>()),
    );
  });

  test('Sai 5 lần thì tạm khóa, tăng dần, hết hạn tự mở', () async {
    await admin();
    for (var i = 1; i < AuthService.maxFailures; i++) {
      await expectLater(
        auth.login('quantri', 'sai-mat-khau-1'),
        throwsA(predicate((e) => e.toString().contains('Còn'))),
      );
    }
    await expectLater(
      auth.login('quantri', 'sai-mat-khau-1'),
      throwsA(predicate((e) => e.toString().contains('tạm khóa 5 phút'))),
    );
    // Even the right password is refused while locked.
    await expectLater(
      auth.login('quantri', 'Bimat2026Ok'),
      throwsA(predicate((e) => e.toString().contains('tạm khóa đến'))),
    );
    now = now.add(const Duration(minutes: 6));
    for (var i = 0; i < AuthService.maxFailures; i++) {
      await expectLater(
        auth.login('quantri', 'sai-mat-khau-1'),
        throwsA(isA<AuthException>()),
      );
    }
    final locked = (await repo.accountByUsername('quantri'))!;
    expect(locked.lockedUntil, now.add(const Duration(minutes: 10)));
    now = now.add(const Duration(minutes: 11));
    final ok = await auth.login('quantri', 'Bimat2026Ok');
    expect(ok.lockCount, 0);
    expect(ok.failedAttempts, 0);
    final log = await repo.auditEntries();
    expect(log.where((e) => e.action == 'lockout').length, 2);
    expect(log.first.action, 'login');
  });

  test('Tên không tồn tại báo lỗi giống sai mật khẩu', () async {
    await admin();
    Object? unknown, wrong;
    try {
      await auth.login('khong-co', 'Bimat2026Ok');
    } catch (e) {
      unknown = e;
    }
    try {
      await auth.login('quantri', 'Saimatkhau1');
    } catch (e) {
      wrong = e;
    }
    expect(
      unknown.toString(),
      startsWith('Tên đăng nhập hoặc mật khẩu không đúng'),
    );
    expect(
      wrong.toString(),
      startsWith('Tên đăng nhập hoặc mật khẩu không đúng'),
    );
  });

  test('Mã khôi phục đặt lại mật khẩu một lần rồi đổi mã mới', () async {
    final result = await auth.register(
      username: 'quantri',
      password: 'Bimat2026Ok',
      displayName: 'Quản trị',
    );
    final code = result.recoveryCode.toLowerCase().replaceAll('-', ' ');
    final fresh = await auth.recover('quantri', code, 'Matkhaumoi2026');
    expect(fresh, isNot(result.recoveryCode));
    expect((await auth.login('quantri', 'Matkhaumoi2026')).username, 'quantri');
    await expectLater(
      auth.recover('quantri', result.recoveryCode, 'Lanthuhai2026'),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      auth.recover('quantri', fresh, 'yeu'),
      throwsA(isA<AuthException>()),
    );
  });

  test(
    'Quản trị tạo tài khoản, đặt lại mật khẩu tạm, khóa/mở; giữ Quản trị cuối',
    () async {
      final boss = await admin();
      final created = await auth.createAccount(
        boss,
        username: 'xem.bao.cao',
        displayName: 'Người xem',
        role: Role.viewer,
      );
      expect(created.account.mustChangePassword, isTrue);
      expect(created.account.recoveryHash, isEmpty);
      final signed = await auth.login('xem.bao.cao', created.password);
      final changed = await auth.changePassword(
        signed,
        created.password,
        'Nguoixem2026',
      );
      expect(changed.account.mustChangePassword, isFalse);
      expect(changed.recoveryCode, isNotNull);
      final temporary = await auth.resetPassword(boss, changed.account);
      await expectLater(
        auth.login('xem.bao.cao', 'Nguoixem2026'),
        throwsA(isA<AuthException>()),
      );
      expect(
        (await auth.login('xem.bao.cao', temporary)).mustChangePassword,
        isTrue,
      );
      await auth.setStatus(boss, changed.account, AccountStatus.disabled);
      await expectLater(
        auth.login('xem.bao.cao', temporary),
        throwsA(predicate((e) => e.toString().contains('đã bị khóa'))),
      );
      await expectLater(
        auth.setRole(boss, boss, Role.technician),
        throwsA(
          predicate((e) => e.toString().contains('ít nhất một Quản trị')),
        ),
      );
      await expectLater(
        auth.setStatus(boss, boss, AccountStatus.disabled),
        throwsA(isA<AuthException>()),
      );
      final deputy = await auth.createAccount(
        boss,
        username: 'pho.quan.tri',
        displayName: 'Phó',
        role: Role.admin,
      );
      expect(
        (await auth.setRole(boss, boss, Role.technician)).role,
        Role.technician,
      );
      expect(deputy.account.role, Role.admin);
    },
  );

  test(
    'Nhật ký ghi người thao tác; tài khoản và nhật ký không vào bản sao lưu',
    () async {
      final boss = await admin();
      repo.actor = Actor(boss.id, boss.label);
      final e = Equipment(name: 'Xe kéo tàu bay');
      await repo.saveEquipment(e);
      await repo.saveEquipment(e.copy({'note': 'Đã sửa'}));
      await repo.deleteEquipment(e.id);
      final log = await repo.auditEntries();
      expect(
        log.where((x) => x.entity == 'equipment').map((x) => x.action).toList(),
        ['delete', 'update', 'create'],
      );
      expect(log.first.userName, 'Nguyễn Quản Trị');
      final snapshot = await repo.snapshot();
      expect(snapshot.keys, isNot(contains('accounts')));
      expect(snapshot.toString(), isNot(contains(boss.passwordHash)));
      await repo.restore(snapshot);
      expect((await repo.accounts()).single.id, boss.id);
      expect((await repo.auditEntries()).first.action, 'restore');
    },
  );
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:equipment_manager/data/backup_crypto.dart';
import 'package:equipment_manager/domain/security.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('PBKDF2-HMAC-SHA256 khớp vector tính bằng .NET Rfc2898DeriveBytes', () {
    expect(
      hex(pbkdf2Sha256(utf8.encode('passwd'), utf8.encode('saltsalt'), 1, 64)),
      '94398fe91b85307f185a879f884a2ae1e4ea297415e4e7a9d2fa22c6a327a41c'
      'c04e0434d4f60077d4a111cdba6715b98e48ed08948a56c23a73b88126e3010d',
    );
    expect(
      hex(
        pbkdf2Sha256(
          utf8.encode('Password123!'),
          List.generate(16, (i) => i),
          1000,
          32,
        ),
      ),
      '27adc8a8516246bbf1c92dfcd005dd4bb57abb93680aa8a827ec796a4b8e634c',
    );
  });

  test(
    'Băm có muối ngẫu nhiên, kiểm tra đúng/sai, từ chối chuỗi hỏng',
    () async {
      final a = await hashSecret('Mật khẩu 2026', 1000);
      final b = await hashSecret('Mật khẩu 2026', 1000);
      expect(a, startsWith(r'pbkdf2-sha256$1000$'));
      expect(a, isNot(b));
      expect(await verifySecret('Mật khẩu 2026', a), isTrue);
      expect(await verifySecret('Mật khẩu 2027', a), isFalse);
      expect(await verifySecret('x', 'md5\$abc'), isFalse);
      expect(await verifySecret('x', r'pbkdf2-sha256$0$AA==$AA=='), isFalse);
      expect(await verifySecret('x', r'pbkdf2-sha256$10$@@$AA=='), isFalse);
      expect(constantTimeEquals([1, 2], [1, 2]), isTrue);
      expect(constantTimeEquals([1, 2], [1, 3]), isFalse);
      expect(constantTimeEquals([1], [1, 2]), isFalse);
    },
  );

  test('Quy tắc tên đăng nhập, mật khẩu và mã khôi phục', () {
    expect(usernameProblem('Nguyen.Van_A'), isNull);
    expect(normalizeUsername('  Nguyen.Van_A '), 'nguyen.van_a');
    expect(usernameProblem('ab'), isNotNull);
    expect(usernameProblem('người dùng'), isNotNull);
    expect(passwordProblem('ngan1'), isNotNull);
    expect(passwordProblem('chiconchu'), isNotNull);
    expect(passwordProblem('12345678'), isNotNull);
    expect(passwordProblem('Kythuat2026'), isNull);
    expect(passwordProblem('quanly2026x', username: 'quanly'), isNotNull);
    final code = newRecoveryCode();
    expect(
      code,
      matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{5}(-[0-9A-HJKMNP-TV-Z]{5}){3}$')),
    );
    expect(
      normalizeRecoveryCode(' ${code.toLowerCase().replaceAll('-', ' ')} '),
      code.replaceAll('-', ''),
    );
    expect(normalizeRecoveryCode('O1L-i'), '0111');
  });

  test(
    'Sao lưu mã hóa: đúng mật khẩu mới mở được, sửa 1 byte là bị phát hiện',
    () {
      final plain = Uint8List.fromList(
        utf8.encode('PK nội dung sao lưu' * 200),
      );
      final sealed = encryptBackupSync(
        plain,
        'mat-khau-sao-luu',
        iterations: 1000,
      );
      expect(isEncryptedBackup(sealed), isTrue);
      expect(isEncryptedBackup(plain), isFalse);
      expect(
        String.fromCharCodes(sealed.take(400)).contains('nội dung'),
        isFalse,
      );
      expect(decryptBackupSync(sealed, 'mat-khau-sao-luu'), plain);
      expect(
        () => decryptBackupSync(sealed, 'mat-khau-khac-1'),
        throwsFormatException,
      );
      for (final position in [10, sealed.length ~/ 2, sealed.length - 1]) {
        final tampered = Uint8List.fromList(sealed)..[position] ^= 0x01;
        expect(
          () => decryptBackupSync(tampered, 'mat-khau-sao-luu'),
          throwsFormatException,
          reason: 'byte $position',
        );
      }
      final again = encryptBackupSync(
        plain,
        'mat-khau-sao-luu',
        iterations: 1000,
      );
      expect(again, isNot(sealed));
      expect(backupPasswordProblem('ngan'), isNotNull);
      expect(backupPasswordProblem('du-dai-roi-12'), isNull);
    },
  );
}

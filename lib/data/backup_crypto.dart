import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import '../domain/security.dart';

/// Password-protected backup container:
///   "EMENC" | version (1 byte) | header length (4 bytes, big endian) |
///   header JSON | AES-256-GCM ciphertext with 16-byte tag.
/// The header (KDF parameters, salt, nonce) is authenticated as associated
/// data, so changing any byte of the file makes decryption fail.
const _magic = [0x45, 0x4D, 0x45, 0x4E, 0x43]; // EMENC
const _formatVersion = 1;
const backupPasswordIterations = 310000;

bool isEncryptedBackup(List<int> bytes) =>
    bytes.length > _magic.length + 5 &&
    Iterable.generate(_magic.length).every((i) => bytes[i] == _magic[i]);

String? backupPasswordProblem(String password) => password.length < 10
    ? 'Mật khẩu sao lưu cần ít nhất 10 ký tự.'
    : password.length > 256
    ? 'Mật khẩu sao lưu tối đa 256 ký tự.'
    : null;

Uint8List _gcm(
  bool encrypt,
  Uint8List key,
  Uint8List nonce,
  Uint8List aad,
  Uint8List input,
) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(encrypt, AEADParameters(KeyParameter(key), 128, nonce, aad));
  return cipher.process(input);
}

Uint8List encryptBackupSync(
  Uint8List plain,
  String password, {
  int iterations = backupPasswordIterations,
}) {
  final salt = randomBytes(16), nonce = randomBytes(12);
  final header = utf8.encode(
    jsonEncode({
      'kdf': 'pbkdf2-sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'cipher': 'aes-256-gcm',
      'nonce': base64Encode(nonce),
    }),
  );
  final prefix = BytesBuilder()
    ..add(_magic)
    ..addByte(_formatVersion)
    ..add((ByteData(4)..setUint32(0, header.length)).buffer.asUint8List())
    ..add(header);
  final aad = prefix.toBytes();
  final key = pbkdf2Sha256(utf8.encode(password), salt, iterations, 32);
  return (BytesBuilder()
        ..add(aad)
        ..add(_gcm(true, key, nonce, aad, plain)))
      .toBytes();
}

Uint8List decryptBackupSync(Uint8List data, String password) {
  if (!isEncryptedBackup(data) || data[_magic.length] != _formatVersion) {
    throw const FormatException('Không phải file sao lưu mã hóa hợp lệ.');
  }
  final start = _magic.length + 5;
  final length = ByteData.sublistView(
    data,
    _magic.length + 1,
    start,
  ).getUint32(0);
  if (length > 4096 || start + length + 16 > data.length) {
    throw const FormatException('File sao lưu mã hóa bị hỏng.');
  }
  final aad = Uint8List.sublistView(data, 0, start + length);
  final Map header;
  try {
    header =
        jsonDecode(
              utf8.decode(Uint8List.sublistView(data, start, start + length)),
            )
            as Map;
  } catch (_) {
    throw const FormatException('File sao lưu mã hóa bị hỏng.');
  }
  final iterations = header['iterations'];
  if (header['kdf'] != 'pbkdf2-sha256' ||
      header['cipher'] != 'aes-256-gcm' ||
      iterations is! int ||
      iterations < 1000 ||
      iterations > 10000000) {
    throw const FormatException('File sao lưu dùng cách mã hóa không hỗ trợ.');
  }
  final key = pbkdf2Sha256(
    utf8.encode(password),
    base64Decode(header['salt'] as String),
    iterations,
    32,
  );
  try {
    return _gcm(
      false,
      key,
      base64Decode(header['nonce'] as String),
      aad,
      Uint8List.sublistView(data, start + length),
    );
  } on InvalidCipherTextException {
    throw const FormatException(
      'Sai mật khẩu sao lưu hoặc file đã bị thay đổi.',
    );
  }
}

/// Key derivation and AES over a large file run off the UI isolate.
Future<Uint8List> encryptBackup(Uint8List plain, String password) =>
    Isolate.run(() => encryptBackupSync(plain, password));

Future<Uint8List> decryptBackup(Uint8List data, String password) =>
    Isolate.run(() => decryptBackupSync(data, password));

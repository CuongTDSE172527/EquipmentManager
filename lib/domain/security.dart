import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// OWASP-style work factor for PBKDF2-HMAC-SHA256 that still unlocks within
/// about a second on the slowest supported Android phones. Stored per hash, so
/// it can be raised later without invalidating existing passwords.
const defaultPasswordIterations = 210000;
const minPasswordLength = 8;

final _random = Random.secure();

Uint8List randomBytes(int length) =>
    Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

Uint8List pbkdf2Sha256(
  List<int> password,
  List<int> salt,
  int iterations,
  int length,
) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(Uint8List.fromList(salt), iterations, length));
  return derivator.process(Uint8List.fromList(password));
}

/// Compares every byte so the time taken does not reveal where they differ.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Turns a secret into `pbkdf2-sha256$<iterations>$<salt>$<hash>` (base64).
typedef SecretHasher = Future<String> Function(String secret, int iterations);

Future<String> hashSecret(String secret, int iterations) async {
  final salt = randomBytes(16);
  final hash = await _derive(secret, salt, iterations);
  return 'pbkdf2-sha256\$$iterations\$${base64Encode(salt)}\$${base64Encode(hash)}';
}

/// Runs off the UI isolate when the work factor is high enough to be felt.
Future<Uint8List> _derive(String secret, List<int> salt, int iterations) {
  final bytes = utf8.encode(secret);
  if (iterations < 20000) {
    return Future.value(pbkdf2Sha256(bytes, salt, iterations, 32));
  }
  return Isolate.run(() => pbkdf2Sha256(bytes, salt, iterations, 32));
}

Future<bool> verifySecret(String secret, String stored) async {
  final parts = stored.split(r'$');
  if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 1 || iterations > 10000000) {
    return false;
  }
  final List<int> salt, expected;
  try {
    salt = base64Decode(parts[2]);
    expected = base64Decode(parts[3]);
  } on FormatException {
    return false;
  }
  final actual = await _derive(secret, salt, iterations);
  return constantTimeEquals(actual, expected);
}

/// Usernames are case-insensitive and limited to characters that are safe in
/// file names, logs and a future server API.
String normalizeUsername(String raw) => raw.trim().toLowerCase();

String? usernameProblem(String raw) {
  final name = normalizeUsername(raw);
  if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$').hasMatch(name)) {
    return 'Tên đăng nhập 3–32 ký tự: chữ không dấu, số, dấu chấm, gạch ngang hoặc gạch dưới.';
  }
  return null;
}

String? passwordProblem(String password, {String username = ''}) {
  if (password.length < minPasswordLength) {
    return 'Mật khẩu cần ít nhất $minPasswordLength ký tự.';
  }
  if (password.length > 128) return 'Mật khẩu tối đa 128 ký tự.';
  if (!RegExp(r'[A-Za-zÀ-ỹ]').hasMatch(password) ||
      !RegExp(r'\d').hasMatch(password)) {
    return 'Mật khẩu cần có cả chữ và số.';
  }
  final user = normalizeUsername(username);
  if (user.isNotEmpty && password.toLowerCase().contains(user)) {
    return 'Mật khẩu không được chứa tên đăng nhập.';
  }
  return null;
}

/// Crockford base32 without I, L, O, U: easy to read aloud and copy by hand.
const _recoveryAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// 20 symbols = 100 bits, shown as four groups of five.
String newRecoveryCode() {
  final chars = List.generate(
    20,
    (_) => _recoveryAlphabet[_random.nextInt(_recoveryAlphabet.length)],
  ).join();
  return [for (var i = 0; i < 20; i += 5) chars.substring(i, i + 5)].join('-');
}

/// Accepts lower case, spaces or missing dashes, and the usual look-alikes.
String normalizeRecoveryCode(String raw) => raw
    .toUpperCase()
    .replaceAll(RegExp(r'[\s-]'), '')
    .replaceAll('O', '0')
    .replaceAll(RegExp('[IL]'), '1');

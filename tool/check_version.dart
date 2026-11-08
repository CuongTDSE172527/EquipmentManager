import 'dart:io';

void main(List<String> args) {
  final raw = args.single;
  final match = RegExp(
    r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$',
  ).firstMatch(raw);
  if (match == null) {
    throw const FormatException('Phiên bản phải có dạng v1.2.3');
  }
  final major = int.parse(match[1]!);
  final minor = int.parse(match[2]!);
  final patch = int.parse(match[3]!);
  if (minor > 999 || patch > 999) {
    throw const FormatException('Minor và patch tối đa 999.');
  }
  final code = major * 1000000 + minor * 1000 + patch;
  if (code < 1 || code > 2100000000) {
    throw const FormatException('versionCode vượt giới hạn Android.');
  }
  final version = '$major.$minor.$patch';
  final output = Platform.environment['GITHUB_OUTPUT'];
  if (output != null) {
    File(output).writeAsStringSync(
      'version=$version\ncode=$code\n',
      mode: FileMode.append,
    );
  }
  stdout.writeln('$version ($code)');
}

import 'models.dart';

const updateRepository = 'CuongTDSE172527/EquipmentManager';

/// Opt-in background check: at most once per calendar day.
bool updateCheckDue(AppSettings settings, DateTime now) {
  if (!settings.autoUpdateCheck) return false;
  final last = settings.lastUpdateCheck;
  return last == null ||
      last.year != now.year ||
      last.month != now.month ||
      last.day != now.day;
}

enum UpdateTarget { android, windowsSetup, windowsPortable }

class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);
  final int major, minor, patch;
  static AppVersion? tryParse(String value) {
    final match = RegExp(
      r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$',
    ).firstMatch(value);
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 3; i++) int.tryParse(match[i]!)];
    if (parts.any((p) => p == null)) return null;
    final version = AppVersion(parts[0]!, parts[1]!, parts[2]!);
    if (version.minor > 999 ||
        version.patch > 999 ||
        version.code < 1 ||
        version.code > 2100000000) {
      return null;
    }
    return version;
  }

  int get code => major * 1000000 + minor * 1000 + patch;
  @override
  int compareTo(AppVersion other) => code.compareTo(other.code);
  @override
  String toString() => '$major.$minor.$patch';
}

class UpdateFailure implements Exception {
  const UpdateFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateCancelled implements Exception {
  const UpdateCancelled();
}

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    required this.sha256,
  });
  final String name, sha256;
  final Uri url;
  final int size;
}

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.asset,
    required this.notes,
    required this.prerelease,
  });
  final AppVersion version;
  final UpdateAsset asset;
  final String notes;
  final bool prerelease;
}

String updateAssetName(AppVersion version, UpdateTarget target) =>
    switch (target) {
      UpdateTarget.android => 'EquipmentManager-$version.apk',
      UpdateTarget.windowsSetup =>
        'EquipmentManager-$version-windows-setup.exe',
      UpdateTarget.windowsPortable =>
        'EquipmentManager-$version-windows-portable.zip',
    };

AppUpdate? selectUpdate(
  List<Map<String, dynamic>> releases,
  AppVersion current,
  UpdateTarget target, {
  required bool includePrereleases,
}) {
  final candidates = <({AppVersion version, Map<String, dynamic> release})>[];
  for (final release in releases) {
    if (release['draft'] != false ||
        (!includePrereleases && release['prerelease'] != false)) {
      continue;
    }
    final version = AppVersion.tryParse(release['tag_name']?.toString() ?? '');
    if (version != null && version.compareTo(current) > 0) {
      candidates.add((version: version, release: release));
    }
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => b.version.compareTo(a.version));
  final selected = candidates.first;
  final name = updateAssetName(selected.version, target);
  final assets = selected.release['assets'];
  final matches = assets is List
      ? assets.whereType<Map>().where((a) => a['name'] == name).toList()
      : <Map>[];
  if (matches.length != 1) {
    throw UpdateFailure(
      'Bản ${selected.version} chưa có đủ bộ cài cho máy này. Vui lòng thử lại sau.',
    );
  }
  final asset = matches.single;
  final digest = asset['digest'];
  final size = asset['size'];
  final expectedUrl = Uri.https(
    'github.com',
    '/$updateRepository/releases/download/v${selected.version}/$name',
  );
  final url = Uri.tryParse(asset['browser_download_url']?.toString() ?? '');
  if (asset['state'] != 'uploaded' ||
      digest is! String ||
      !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest) ||
      size is! int ||
      size <= 0 ||
      size > 512 * 1024 * 1024 ||
      url != expectedUrl) {
    throw const UpdateFailure(
      'Bộ cài thiếu thông tin xác minh hoặc có địa chỉ không hợp lệ. Chưa tải/cài cập nhật.',
    );
  }
  final body = selected.release['body']?.toString() ?? '';
  return AppUpdate(
    version: selected.version,
    asset: UpdateAsset(
      name: name,
      url: expectedUrl,
      size: size,
      sha256: digest.substring(7).toLowerCase(),
    ),
    notes: body.length > 12000 ? '${body.substring(0, 12000)}…' : body,
    prerelease: selected.release['prerelease'] == true,
  );
}

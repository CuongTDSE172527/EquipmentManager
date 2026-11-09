import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../domain/updates.dart';

class UpdateCancellation {
  bool cancelled = false;
  void Function()? _abort;
  void cancel() {
    cancelled = true;
    _abort?.call();
  }

  void check() {
    if (cancelled) throw const UpdateCancelled();
  }
}

abstract class UpdateTransport {
  Future<List<Map<String, dynamic>>> releasesPage(
    int page,
    UpdateCancellation cancel,
  );
  Future<void> download(
    UpdateAsset asset,
    File partial,
    UpdateCancellation cancel,
    void Function(int received, int total) onProgress,
  );
}

class GitHubUpdateTransport implements UpdateTransport {
  GitHubUpdateTransport({
    HttpClient Function()? clientFactory,
    Uri? apiBase,
    bool Function(Uri)? allowedDownload,
  }) : _clientFactory = clientFactory ?? HttpClient.new,
       _apiBase =
           apiBase ??
           Uri.https('api.github.com', '/repos/$updateRepository/releases'),
       _allowedDownload = allowedDownload ?? _trustedDownload;
  final HttpClient Function() _clientFactory;
  final Uri _apiBase;
  final bool Function(Uri) _allowedDownload;
  static bool _trustedDownload(Uri uri) =>
      uri.scheme == 'https' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      {
        'github.com',
        'api.github.com',
        'release-assets.githubusercontent.com',
        'objects.githubusercontent.com',
        'releases.githubusercontent.com',
      }.contains(uri.host);

  HttpClient _client(UpdateCancellation cancel) {
    cancel.check();
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 20);
    cancel._abort = () => client.close(force: true);
    return client;
  }

  Future<HttpClientResponse> _request(
    HttpClient client,
    Uri uri,
    UpdateCancellation cancel, {
    required bool binary,
  }) async {
    for (var redirects = 0; redirects < 6; redirects++) {
      cancel.check();
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 25));
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'EquipmentManager-Updater',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        binary ? 'application/octet-stream' : 'application/vnd.github+json',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) {
          throw const UpdateFailure(
            'Máy chủ tải không có địa chỉ chuyển tiếp.',
          );
        }
        final next = uri.resolve(location);
        if (!binary || !_allowedDownload(next)) {
          throw const UpdateFailure(
            'Đã chặn chuyển tiếp tải đến địa chỉ không được phép.',
          );
        }
        // No Authorization header is used or forwarded by this updater.
        uri = next;
        continue;
      }
      if (response.statusCode == 403 || response.statusCode == 429) {
        throw const UpdateFailure(
          'GitHub đang giới hạn yêu cầu. Hãy thử lại sau.',
        );
      }
      if (response.statusCode != 200) {
        throw UpdateFailure(
          'Không tải được dữ liệu cập nhật (HTTP ${response.statusCode}).',
        );
      }
      return response;
    }
    throw const UpdateFailure('Máy chủ chuyển tiếp quá nhiều lần.');
  }

  @override
  Future<List<Map<String, dynamic>>> releasesPage(
    int page,
    UpdateCancellation cancel,
  ) async {
    final client = _client(cancel);
    try {
      final response = await _request(
        client,
        _apiBase.replace(queryParameters: {'per_page': '100', 'page': '$page'}),
        cancel,
        binary: false,
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 25))) {
        cancel.check();
        bytes.addAll(chunk);
        if (bytes.length > 8 * 1024 * 1024) {
          throw const UpdateFailure('Thông tin cập nhật quá lớn.');
        }
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! List) {
        throw const UpdateFailure(
          'GitHub trả thông tin cập nhật không đúng định dạng.',
        );
      }
      return data.map((r) => Map<String, dynamic>.from(r as Map)).toList();
    } finally {
      cancel._abort = null;
      client.close(force: true);
    }
  }

  @override
  Future<void> download(
    UpdateAsset asset,
    File partial,
    UpdateCancellation cancel,
    void Function(int, int) onProgress,
  ) async {
    if (!_allowedDownload(asset.url)) {
      throw const UpdateFailure('Địa chỉ tải cập nhật không được phép.');
    }
    final client = _client(cancel);
    IOSink? sink;
    var expired = false;
    final deadline = Timer(const Duration(minutes: 10), () {
      expired = true;
      client.close(force: true);
    });
    try {
      final response = await _request(client, asset.url, cancel, binary: true);
      if (response.contentLength >= 0 && response.contentLength != asset.size) {
        throw const UpdateFailure('Kích thước bộ cài trên máy chủ không khớp.');
      }
      sink = partial.openWrite();
      var received = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        cancel.check();
        received += chunk.length;
        if (received > asset.size) {
          throw const UpdateFailure(
            'Bộ cài tải về lớn hơn kích thước đã công bố.',
          );
        }
        sink.add(chunk);
        await sink
            .flush(); // Apply disk backpressure instead of buffering the APK in memory.
        onProgress(received, asset.size);
      }
      if (received != asset.size) {
        throw const UpdateFailure('Bộ cài tải chưa đầy đủ. Hãy tải lại.');
      }
      await sink.close();
      sink = null;
    } catch (e) {
      if (expired) {
        throw const UpdateFailure('Tải quá lâu. Kiểm tra kết nối và thử lại.');
      }
      rethrow;
    } finally {
      deadline.cancel();
      if (sink != null) await sink.close();
      cancel._abort = null;
      client.close(force: true);
    }
  }
}

class UpdateService {
  UpdateService({UpdateTransport? transport})
    : transport = transport ?? GitHubUpdateTransport();
  final UpdateTransport transport;

  Future<AppUpdate?> check(
    AppVersion current,
    UpdateTarget target, {
    required bool includePrereleases,
    required UpdateCancellation cancel,
  }) async {
    try {
      final releases = <Map<String, dynamic>>[];
      for (var page = 1; page <= 10; page++) {
        cancel.check();
        final rows = await transport.releasesPage(page, cancel);
        releases.addAll(rows);
        if (rows.length < 100) {
          return selectUpdate(
            releases,
            current,
            target,
            includePrereleases: includePrereleases,
          );
        }
      }
      throw const UpdateFailure(
        'Có quá nhiều bản phát hành để kiểm tra. Hãy mở GitHub Releases.',
      );
    } catch (e) {
      cancel.check();
      throw _friendly(e);
    }
  }

  Future<bool> verified(File file, UpdateAsset asset) async =>
      await file.exists() &&
      await file.length() == asset.size &&
      (await sha256.bind(file.openRead()).first).toString() == asset.sha256;

  Future<File> download(
    AppUpdate update,
    Directory root,
    UpdateCancellation cancel,
    void Function(int, int) onProgress,
  ) async {
    final directory = Directory(p.join(root.path, update.version.toString()));
    final file = File(p.join(directory.path, update.asset.name));
    final partial = File('${file.path}.part');
    try {
      cancel.check();
      await directory.create(recursive: true);
      if (await verified(file, update.asset)) {
        cancel.check();
        return file;
      }
      if (await partial.exists()) await partial.delete();
      await transport.download(update.asset, partial, cancel, onProgress);
      cancel.check();
      if (!await verified(partial, update.asset)) {
        throw const UpdateFailure(
          'SHA-256 không khớp. Bộ cài đã bị loại bỏ; chưa cài cập nhật.',
        );
      }
      cancel.check();
      if (await file.exists()) await file.delete();
      return await partial.rename(file.path);
    } catch (e) {
      if (await partial.exists()) await partial.delete();
      if (e is UpdateFailure) rethrow;
      cancel.check();
      throw _friendly(e);
    }
  }
}

Exception _friendly(Object e) => switch (e) {
  UpdateFailure() => e,
  UpdateCancelled() => e,
  SocketException() || TimeoutException() => const UpdateFailure(
    'Không kết nối được GitHub. Kiểm tra Internet và thử lại; dữ liệu trên máy vẫn dùng được.',
  ),
  FileSystemException() => const UpdateFailure(
    'Không ghi/đọc được bộ cài. Kiểm tra dung lượng và quyền ghi thư mục ứng dụng.',
  ),
  _ => const UpdateFailure(
    'Không đọc được thông tin cập nhật. Hãy thử lại sau.',
  ),
};

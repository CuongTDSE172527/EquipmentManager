import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:equipment_manager/domain/updates.dart';
import 'package:equipment_manager/services/updates.dart';

final bytes = utf8.encode('fixture update package');
Map<String, dynamic> release(
  String version, {
  bool prerelease = false,
  bool draft = false,
}) => {
  'tag_name': 'v$version',
  'draft': draft,
  'prerelease': prerelease,
  'body': 'Thay đổi thử',
  'assets': [
    for (final target in UpdateTarget.values)
      <String, dynamic>{
        'name': updateAssetName(AppVersion.tryParse(version)!, target),
        'state': 'uploaded',
        'size': bytes.length,
        'digest': 'sha256:${sha256.convert(bytes)}',
        'browser_download_url':
            'https://github.com/$updateRepository/releases/download/v$version/${updateAssetName(AppVersion.tryParse(version)!, target)}',
      },
  ],
};

class FakeTransport implements UpdateTransport {
  int downloads = 0;
  bool corrupt = false, cancelDownload = false;
  final List<int> pages = [];
  @override
  Future<List<Map<String, dynamic>>> releasesPage(
    int page,
    UpdateCancellation cancel,
  ) async {
    pages.add(page);
    return page == 1
        ? List.generate(100, (_) => release('0.1.3'))
        : [release('0.1.10')];
  }

  @override
  Future<void> download(
    UpdateAsset asset,
    File partial,
    UpdateCancellation cancel,
    void Function(int, int) onProgress,
  ) async {
    downloads++;
    await partial.writeAsBytes(corrupt ? utf8.encode('bad hash') : bytes);
    if (cancelDownload) {
      cancel.cancel();
      cancel.check();
    }
    onProgress(bytes.length, bytes.length);
  }
}

void main() {
  test('Chọn phiên bản theo số, kênh, nền tảng; không hạ/cài lại bản cũ', () {
    final rows = [
      release('0.1.9'),
      release('0.1.10'),
      release('1.0.0', draft: true),
      release('0.2.0', prerelease: true),
    ];
    final current = AppVersion.tryParse('0.1.4')!;
    for (final target in UpdateTarget.values) {
      final stable = selectUpdate(
        rows,
        current,
        target,
        includePrereleases: false,
      )!;
      expect(stable.version.toString(), '0.1.10');
      expect(stable.asset.name, updateAssetName(stable.version, target));
      expect(
        selectUpdate(
          rows,
          current,
          target,
          includePrereleases: true,
        )!.version.toString(),
        '0.2.0',
      );
    }
    expect(
      selectUpdate(
        [release('0.1.3'), release('0.1.4')],
        current,
        UpdateTarget.android,
        includePrereleases: true,
      ),
      isNull,
    );
    expect(AppVersion.tryParse('0.1.1000'), isNull);
    expect(AppVersion.tryParse('01.1.2'), isNull);
  });
  test('Chặn thiếu asset/digest, URL ngoài repo, kích thước sai', () {
    for (final mutation in [
      (Map<String, dynamic> r) => r['assets'] = [],
      (Map<String, dynamic> r) => (r['assets'] as List).first['digest'] = null,
      (Map<String, dynamic> r) =>
          (r['assets'] as List).first['browser_download_url'] =
              'https://example.com/update.apk',
      (Map<String, dynamic> r) => (r['assets'] as List).first['size'] = -1,
    ]) {
      final row = release('0.1.5');
      mutation(row);
      expect(
        () => selectUpdate(
          [row],
          AppVersion.tryParse('0.1.4')!,
          UpdateTarget.android,
          includePrereleases: true,
        ),
        throwsA(isA<UpdateFailure>()),
      );
    }
  });
  test('Đọc hết các trang release thay vì chỉ phần tử đầu / latest', () async {
    final transport = FakeTransport();
    final result = await UpdateService(transport: transport).check(
      AppVersion.tryParse('0.1.4')!,
      UpdateTarget.android,
      includePrereleases: true,
      cancel: UpdateCancellation(),
    );
    expect(transport.pages, [1, 2]);
    expect(result!.version.toString(), '0.1.10');
  });
  test('Tải, xác minh, dùng cache; hash sai/hủy xóa phần tải dở', () async {
    final root = await Directory.systemTemp.createTemp(
      'equipment-update-test-',
    );
    final transport = FakeTransport();
    final service = UpdateService(transport: transport);
    final update = selectUpdate(
      [release('0.1.5')],
      AppVersion.tryParse('0.1.4')!,
      UpdateTarget.android,
      includePrereleases: true,
    )!;
    try {
      final file = await service.download(
        update,
        root,
        UpdateCancellation(),
        (_, _) {},
      );
      expect(await service.verified(file, update.asset), true);
      await service.download(update, root, UpdateCancellation(), (_, _) {});
      expect(transport.downloads, 1);
      await file.writeAsString('changed');
      transport.corrupt = true;
      await expectLater(
        service.download(update, root, UpdateCancellation(), (_, _) {}),
        throwsA(isA<UpdateFailure>()),
      );
      expect(await File('${file.path}.part').exists(), false);
      transport.corrupt = false;
      transport.cancelDownload = true;
      await expectLater(
        service.download(update, root, UpdateCancellation(), (_, _) {}),
        throwsA(isA<UpdateCancelled>()),
      );
      expect(await File('${file.path}.part').exists(), false);
    } finally {
      // Only remove fixture leaf files/directories created in this test.
      for (final version in await root.list().toList()) {
        if (version is Directory) {
          for (final entry in await version.list().toList()) {
            await entry.delete();
          }
        }
        await version.delete();
      }
      await root.delete();
    }
  });
  test(
    'HTTP streaming: không gửi token, xử lý rate limit và chặn redirect lạ',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final root = await Directory.systemTemp.createTemp(
        'equipment-http-test-',
      );
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      final requests = <String>[];
      server.listen((request) async {
        expect(request.headers.value(HttpHeaders.authorizationHeader), isNull);
        requests.add(request.uri.path);
        if (request.uri.path == '/rate') {
          request.response.statusCode = 429;
        } else if (request.uri.path == '/redirect') {
          request.response.statusCode = 302;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            'https://example.com/not-allowed',
          );
        } else if (request.uri.path == '/releases') {
          request.response.write(jsonEncode([release('0.1.5')]));
        } else {
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
        }
        await request.response.close();
      });
      try {
        final transport = GitHubUpdateTransport(
          apiBase: base.resolve('/releases'),
          allowedDownload: (uri) => uri.host == '127.0.0.1',
        );
        expect(
          await transport.releasesPage(1, UpdateCancellation()),
          hasLength(1),
        );
        final file = File('${root.path}/test.part');
        UpdateAsset asset(String path) => UpdateAsset(
          name: 'test',
          url: base.resolve(path),
          size: bytes.length,
          sha256: sha256.convert(bytes).toString(),
        );
        await transport.download(
          asset('/package'),
          file,
          UpdateCancellation(),
          (_, _) {},
        );
        expect(await file.readAsBytes(), bytes);
        await expectLater(
          transport.download(
            asset('/redirect'),
            file,
            UpdateCancellation(),
            (_, _) {},
          ),
          throwsA(isA<UpdateFailure>()),
        );
        final limited = GitHubUpdateTransport(apiBase: base.resolve('/rate'));
        await expectLater(
          limited.releasesPage(1, UpdateCancellation()),
          throwsA(isA<UpdateFailure>()),
        );
        expect(
          requests,
          containsAll(['/releases', '/package', '/redirect', '/rate']),
        );
        await file.delete();
      } finally {
        await server.close(force: true);
        await root.delete();
      }
    },
  );
}

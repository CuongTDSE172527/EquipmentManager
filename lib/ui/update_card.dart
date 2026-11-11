import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../domain/updates.dart';
import '../services/updates.dart';
import '../services/update_installer.dart';
import 'controller.dart';
import 'forms.dart';

class UpdateCard extends StatefulWidget {
  const UpdateCard({
    super.key,
    required this.controller,
    this.service,
    this.installer,
    this.packageInfo,
    this.initialUpdate,
    this.canManage = true,
  });
  final AppController controller;

  /// Found by the opt-in check on launch; still requires the user to download.
  final AppUpdate? initialUpdate;

  /// Only administrators change update options, download or install.
  final bool canManage;
  final UpdateService? service;
  final UpdateInstaller? installer;
  final Future<PackageInfo> Function()? packageInfo;
  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> with WidgetsBindingObserver {
  late final service = widget.service ?? UpdateService();
  late final installer = widget.installer ?? const UpdateInstaller();
  AppVersion? current;
  UpdateTarget? target;
  AppUpdate? update;
  File? downloaded;
  bool includePrereleases = true, allowed = false;
  String? phase, message, error, backupPath;
  int received = 0, total = 0;
  var lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
  UpdateCancellation? cancellation;
  bool get busy => phase != null;
  @override
  void initState() {
    super.initState();
    includePrereleases = widget.controller.settings.updateIncludePrereleases;
    update = widget.initialUpdate;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(UpdateCard old) {
    super.didUpdateWidget(old);
    final found = widget.initialUpdate;
    if (found != null &&
        found != old.initialUpdate &&
        !busy &&
        update == null) {
      update = found;
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    try {
      await widget.controller.updateSettings({key: value});
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _initialize() async {
    try {
      final info =
          await (widget.packageInfo?.call() ?? PackageInfo.fromPlatform());
      final version = AppVersion.tryParse(info.version);
      if (version == null) {
        throw const UpdateFailure(
          'Không đọc được phiên bản ứng dụng đang chạy.',
        );
      }
      final platform = await installer.target();
      if (mounted) {
        setState(() {
          current = version;
          target = platform;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        target != null &&
        downloaded != null) {
      unawaited(_permission());
    }
  }

  Future<void> _permission() async {
    try {
      final value = await installer.canInstall(target!);
      if (mounted) setState(() => allowed = value);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Không đọc được quyền cài đặt. Hãy kiểm tra quyền trong Cài đặt Android.',
        );
      }
    }
  }

  @override
  void dispose() {
    cancellation?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _run(
    String initialPhase,
    Future<void> Function(UpdateCancellation) action,
  ) async {
    if (busy) return;
    final token = UpdateCancellation();
    cancellation = token;
    setState(() {
      phase = initialPhase;
      error = null;
      message = null;
    });
    try {
      await action(token);
    } on UpdateCancelled {
      if (mounted) setState(() => message = 'Đã hủy. Chưa cài cập nhật.');
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () => error = e.message ?? 'Không mở được trình cài cập nhật.',
        );
      }
    } on FileSystemException {
      if (mounted) {
        setState(
          () => error =
              'Không ghi được bộ cài hoặc sao lưu. Kiểm tra dung lượng và quyền ghi; chưa cài cập nhật.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => phase = null);
    }
  }

  void _check() => unawaited(
    _run('Đang kiểm tra GitHub…', (token) async {
      final result = await service.check(
        current!,
        target!,
        includePrereleases: includePrereleases,
        cancel: token,
      );
      if (mounted) {
        setState(() {
          update = result;
          downloaded = null;
          received = 0;
          total = 0;
          message = result == null
              ? 'Không có bản mới hơn trong kênh đã chọn.'
              : null;
        });
      }
    }),
  );

  void _download() => unawaited(
    _run('Đang tải bộ cài…', (token) async {
      final file = await service.download(
        update!,
        await installer.directory(),
        token,
        (count, size) {
          final now = DateTime.now();
          if (mounted &&
              (count == size ||
                  now.difference(lastProgress).inMilliseconds >= 100)) {
            lastProgress = now;
            setState(() {
              received = count;
              total = size;
              if (count == size) phase = 'Đang xác minh bộ cài…';
            });
          }
        },
      );
      token.check();
      await installer.verify(file, update!, target!);
      token.check();
      final permission = await installer.canInstall(target!);
      if (mounted) {
        setState(() {
          downloaded = file;
          allowed = permission;
          message =
              'Đã tải và xác minh SHA-256${target == UpdateTarget.android ? ', tên gói và khóa ký APK' : ''}.';
        });
      }
    }),
  );

  Future<void> _install() async {
    final confirmed = await confirmAction(
      context,
      'Cài bản ${update!.version}?',
      target == UpdateTarget.android
          ? 'Ứng dụng sẽ sao lưu toàn bộ dữ liệu rồi mở trình cài Android. Hãy chọn Cài đặt để cập nhật; không gỡ ứng dụng cũ.'
          : 'Ứng dụng sẽ sao lưu toàn bộ dữ liệu, đóng cửa sổ, cập nhật vào thư mục đang dùng rồi mở lại. Hãy đóng các cửa sổ EquipmentManager khác.',
      action: 'Sao lưu và cài đặt',
    );
    if (!confirmed || !mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        animationStyle: AnimationStyle.noAnimation,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text('Chuẩn bị cập nhật'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(),
                SizedBox(height: 16),
                Text('Đang sao lưu và chuẩn bị trình cài. Vui lòng chờ…'),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      await _run('Đang sao lưu và chuẩn bị cài…', (token) async {
        if (!await service.verified(downloaded!, update!.asset)) {
          throw const UpdateFailure(
            'Bộ cài đã thay đổi. Hãy kiểm tra và tải lại.',
          );
        }
        await installer.verify(downloaded!, update!, target!);
        if (!await installer.canInstall(target!)) {
          setState(() => allowed = false);
          throw const UpdateFailure(
            'Hãy cấp quyền cài đặt cho EquipmentManager trước.',
          );
        }
        final backup = await installer.backup(
          widget.controller.repository,
          update!,
        );
        backupPath = backup.path;
        await widget.controller.load();
        final exits = await installer.launch(downloaded!, update!, target!);
        if (exits) {
          await widget.controller.repository.db.close();
          await installer.quit();
        } else if (mounted) {
          setState(
            () => message =
                'Đã mở trình cài Android. Chọn Cài đặt để hoàn tất; hủy trình cài sẽ giữ bản hiện tại.',
          );
        }
      });
    } finally {
      if (mounted) nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cập nhật ứng dụng',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Phiên bản đang dùng: ${current ?? 'đang đọc…'}${current?.major == 0 ? ' Beta' : ''}',
          ),
          const Text(
            'Kiểm tra và tải từ GitHub khi có Internet. Dữ liệu thiết bị được giữ trên máy.',
          ),
          if (!widget.canManage)
            const Text('Chỉ Quản trị tải và cài bản cập nhật trên máy này.'),
          const SizedBox(height: 12),
          if (widget.canManage)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bao gồm bản thử nghiệm'),
              subtitle: const Text(
                'Từ 0.3.0, bản Beta phát hành như bản chính thức. Bật để nhận thêm bản thử nghiệm (pre-release) nếu có.',
              ),
              value: includePrereleases,
              onChanged: busy
                  ? null
                  : (value) {
                      setState(() {
                        includePrereleases = value;
                        update = null;
                        downloaded = null;
                        message = null;
                      });
                      unawaited(
                        _saveSetting('updateIncludePrereleases', value),
                      );
                    },
            ),
          if (widget.canManage)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tự kiểm tra khi mở ứng dụng'),
              subtitle: const Text(
                'Tối đa 1 lần/ngày, chỉ báo khi có bản mới. Không tự tải hoặc cài. Tắt để ứng dụng không dùng Internet.',
              ),
              value: widget.controller.settings.autoUpdateCheck,
              onChanged: busy
                  ? null
                  : (value) =>
                        unawaited(_saveSetting('autoUpdateCheck', value)),
            ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: current == null || target == null || busy
                    ? null
                    : _check,
                icon: const Icon(Icons.refresh),
                label: const Text('Kiểm tra cập nhật'),
              ),
              if (widget.canManage && update != null && downloaded == null)
                FilledButton.icon(
                  onPressed: busy ? null : _download,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Tải bản cập nhật'),
                ),
              if (widget.canManage && downloaded != null && !allowed)
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _run(
                          'Đang mở quyền cài đặt…',
                          (_) => installer.openPermission(),
                        ),
                  icon: const Icon(Icons.security_outlined),
                  label: const Text('Cho phép cài từ EquipmentManager'),
                ),
              if (widget.canManage && downloaded != null)
                FilledButton.icon(
                  onPressed: busy || !allowed ? null : _install,
                  icon: const Icon(Icons.install_desktop),
                  label: const Text('Cài đặt bản cập nhật'),
                ),
              if (busy && phase != 'Đang sao lưu và chuẩn bị cài…')
                TextButton(
                  onPressed: () => cancellation?.cancel(),
                  child: const Text('Hủy'),
                ),
            ],
          ),
          if (update != null) ...[
            const SizedBox(height: 12),
            Text(
              'Có bản ${update!.version}${update!.prerelease ? ' (thử nghiệm)' : ''} • ${(update!.asset.size / 1048576).toStringAsFixed(1)} MB',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (update!.notes.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Thay đổi trong bản mới'),
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: SelectableText(update!.notes),
                    ),
                  ),
                ],
              ),
          ],
          if (busy) ...[
            const SizedBox(height: 12),
            Text(phase!),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: total > 0 && received < total ? received / total : null,
            ),
            if (total > 0)
              Text(
                '${(received / 1048576).toStringAsFixed(1)} / ${(total / 1048576).toStringAsFixed(1)} MB',
              ),
          ],
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(message!),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (backupPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText('Sao lưu trước cập nhật: $backupPath'),
            ),
        ],
      ),
    ),
  );
}

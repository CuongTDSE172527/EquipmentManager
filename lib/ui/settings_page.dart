import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../services/notifications.dart';
import 'controller.dart';
import 'forms.dart';
import 'update_card.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.notifications,
    required this.onError,
  });
  final AppController controller;
  final NotificationService notifications;
  final ValueChanged<String> onError;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController warn, lifespan, agency, team;
  late String theme;
  late TimeOfDay time;
  bool busy = false;
  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    final s = c.settings;
    warn = TextEditingController(text: s.warnDays.toString());
    lifespan = TextEditingController(text: s.lifespanWarnDays.toString());
    agency = TextEditingController(text: s.agency);
    team = TextEditingController(text: s.team);
    theme = s.theme;
    time = TimeOfDay(hour: s.notifyHour, minute: s.notifyMinute);
  }

  @override
  void dispose() {
    for (final field in [warn, lifespan, agency, team]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      widget.onError(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  AppSettings _settings() {
    final w = int.tryParse(warn.text), l = int.tryParse(lifespan.text);
    if (w == null || l == null || w < 0 || l < 0) {
      throw const FormatException(
        'Số ngày báo trước phải là số nguyên không âm.',
      );
    }
    return c.settings.copy({
      'warnDays': w,
      'lifespanWarnDays': l,
      'notifyHour': time.hour,
      'notifyMinute': time.minute,
      'agency': agency.text.trim(),
      'team': team.text.trim(),
      'theme': theme,
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      if (busy) const LinearProgressIndicator(),
      UpdateCard(controller: c),
      const SizedBox(height: 24),
      Text(
        'Theo dõi và nhắc hạn',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: warn,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Báo trước (ngày)'),
            ),
          ),
          SizedBox(
            width: 280,
            child: TextField(
              controller: lifespan,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Báo trước niên hạn (ngày)',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Giờ nhắc hằng ngày'),
        subtitle: Text(time.format(context)),
        trailing: const Icon(Icons.schedule),
        onTap: () async {
          final selected = await showTimePicker(
            context: context,
            initialTime: time,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(alwaysUse24HourFormat: true),
              child: child!,
            ),
          );
          if (selected != null) setState(() => time = selected);
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Bật thông báo khi ứng dụng đã đóng'),
        value: c.settings.notificationsEnabled,
        onChanged: busy
            ? null
            : (enabled) => _run(() async {
                final settings = _settings();
                if (enabled) {
                  final message = await widget.notifications.enable(settings);
                  await c.repository.saveSettings(
                    settings.copy({'notificationsEnabled': true}),
                  );
                  await c.load();
                  widget.onError(message);
                } else {
                  await widget.notifications.disable(settings);
                  await c.repository.saveSettings(
                    settings.copy({'notificationsEnabled': false}),
                  );
                  await c.load();
                }
              }),
      ),
      const Text(
        'Android: cho phép Thông báo và Báo thức/lời nhắc; tránh Buộc dừng ứng dụng. Nếu máy hạn chế pin, cho phép ứng dụng chạy nền. Windows: máy cần đang bật và bạn đã đăng nhập; kiểm tra cài đặt Thông báo của Windows.',
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: busy
              ? null
              : () => _run(() async {
                  await widget.notifications.initialize();
                  await widget.notifications.showSummary(
                    c.repository,
                    test: true,
                  );
                  widget.onError(
                    'Đã yêu cầu gửi thông báo thử. Nếu chưa thấy, hãy kiểm tra quyền thông báo của hệ điều hành.',
                  );
                }),
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('Gửi thông báo thử'),
        ),
      ),
      const SizedBox(height: 28),
      Text(
        'Giao diện và tiêu đề báo cáo',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        initialValue: theme,
        decoration: const InputDecoration(labelText: 'Giao diện'),
        items: const [
          DropdownMenuItem(value: 'system', child: Text('Theo hệ thống')),
          DropdownMenuItem(value: 'light', child: Text('Sáng')),
          DropdownMenuItem(value: 'dark', child: Text('Tối')),
        ],
        onChanged: (v) => theme = v!,
      ),
      const SizedBox(height: 16),
      TextField(
        controller: agency,
        decoration: const InputDecoration(labelText: 'Tên cơ quan'),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: team,
        decoration: const InputDecoration(labelText: 'Tên tổ / đội'),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: busy
              ? null
              : () => _run(() async {
                  final settings = _settings();
                  if (settings.notificationsEnabled) {
                    await widget.notifications.refresh(settings);
                  }
                  await c.repository.saveSettings(settings);
                  await c.load();
                  widget.onError('Đã lưu cài đặt.');
                }),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Lưu cài đặt'),
        ),
      ),
      const SizedBox(height: 28),
      _catalog(context, 'group', 'Nhóm thiết bị', c.groups),
      const SizedBox(height: 20),
      _catalog(context, 'provider', 'Đơn vị thực hiện', c.providers),
      const SizedBox(height: 24),
      const Text(
        'Niên hạn mặc định báo trước 180 ngày; có thể chỉnh ở trên. Thiết bị đã bàn giao, chuyển tăng cường hoặc ngừng sử dụng được giữ dữ liệu và loại khỏi thống kê/cảnh báo.',
      ),
    ],
  );
  Widget _catalog(
    BuildContext context,
    String kind,
    String title,
    List<String> values,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          TextButton.icon(
            onPressed: busy ? null : () => _catalogDialog(kind),
            icon: const Icon(Icons.add),
            label: const Text('Thêm'),
          ),
        ],
      ),
      for (final name in values)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(name),
          trailing: IconButton(
            tooltip: 'Sửa tên danh mục',
            onPressed: busy ? null : () => _catalogDialog(kind, oldName: name),
            icon: const Icon(Icons.edit_outlined),
          ),
        ),
    ],
  );
  Future<void> _catalogDialog(String kind, {String? oldName}) async {
    final field = TextEditingController(text: oldName ?? '');
    final name = await showFormDialog<String>(
      controllers: [field],
      context: context,
      builder: (context) => AlertDialog(
        title: Text(oldName == null ? 'Thêm danh mục' : 'Sửa tên danh mục'),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên danh mục'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (name == null) return;
    await _run(() async {
      if (name.isEmpty) throw const FormatException('Tên không được trống.');
      if (oldName == null) {
        await c.repository.addCatalog(kind, name);
      } else {
        await c.repository.renameCatalog(kind, oldName, name);
      }
      await c.load();
    });
  }
}

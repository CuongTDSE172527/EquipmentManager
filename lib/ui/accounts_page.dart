import 'dart:async';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/accounts.dart';
import '../domain/deadlines.dart';
import '../domain/security.dart';
import 'auth_screens.dart';
import 'controller.dart';
import 'data_page.dart' show saveBytes;
import 'forms.dart';

String _stamp(DateTime t) =>
    '${displayDate(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "Hồ sơ của tôi": every user edits their own details, password, recovery
/// code and auto-lock preference.
class ProfileSection extends StatelessWidget {
  const ProfileSection({
    super.key,
    required this.controller,
    required this.run,
  });
  final AppController controller;
  final Future<void> Function(Future<void> Function()) run;
  AppController get c => controller;

  @override
  Widget build(BuildContext context) {
    final user = c.user!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_circle_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Hồ sơ của tôi',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              [
                user.label,
                user.username,
                user.role.label,
                if (user.position.isNotEmpty) user.position,
                if (user.unit.isNotEmpty) user.unit,
              ].join(' • '),
            ),
            if (user.lastLoginAt != null)
              Text('Đăng nhập lúc ${_stamp(user.lastLoginAt!)}'),
            const SizedBox(height: 12),
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<int>(
                initialValue: autoLockChoices.contains(user.autoLockMinutes)
                    ? user.autoLockMinutes
                    : 10,
                decoration: const InputDecoration(
                  labelText: 'Tự khóa khi không dùng',
                ),
                items: [
                  for (final m in autoLockChoices)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m == 0 ? 'Tắt' : 'Sau $m phút'),
                    ),
                ],
                onChanged: (v) => run(() async {
                  c.refreshUser(
                    await c.auth.updateProfile(
                      user,
                      displayName: user.displayName,
                      position: user.position,
                      unit: user.unit,
                      phone: user.phone,
                      autoLockMinutes: v,
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Khóa màn hình sau thời gian không thao tác hoặc khi quay lại ứng dụng. Mở khóa bằng mật khẩu của bạn.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => run(() => _editProfile(context)),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Sửa hồ sơ'),
                ),
                OutlinedButton.icon(
                  onPressed: () => run(() => _changePassword(context)),
                  icon: const Icon(Icons.password),
                  label: const Text('Đổi mật khẩu'),
                ),
                OutlinedButton.icon(
                  onPressed: () => run(() => _newRecoveryCode(context)),
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Tạo mã khôi phục mới'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editProfile(BuildContext context) async {
    final user = c.user!;
    final name = TextEditingController(text: user.displayName);
    final position = TextEditingController(text: user.position);
    final unit = TextEditingController(text: user.unit);
    final phone = TextEditingController(text: user.phone);
    final ok = await showFormDialog<bool>(
      controllers: [name, position, unit, phone],
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sửa hồ sơ'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (field, label) in [
                  (name, 'Họ và tên'),
                  (position, 'Chức vụ'),
                  (unit, 'Đơn vị'),
                  (phone, 'Điện thoại'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: field,
                      decoration: InputDecoration(labelText: label),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    c.refreshUser(
      await c.auth.updateProfile(
        user,
        displayName: name.text,
        position: position.text,
        unit: unit.text,
        phone: phone.text,
      ),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final again = TextEditingController();
    final values = await showFormDialog<(String, String)>(
      controllers: [current, next, again],
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Đổi mật khẩu'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (field, label) in [
                    (current, 'Mật khẩu hiện tại'),
                    (next, 'Mật khẩu mới'),
                    (again, 'Nhập lại mật khẩu mới'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: field,
                        obscureText: true,
                        decoration: InputDecoration(labelText: label),
                      ),
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () {
                  final problem =
                      passwordProblem(next.text, username: c.user!.username) ??
                      (next.text != again.text
                          ? 'Mật khẩu nhập lại không khớp.'
                          : null);
                  if (problem != null) {
                    setState(() => error = problem);
                    return;
                  }
                  Navigator.pop(context, (current.text, next.text));
                },
                child: const Text('Đổi mật khẩu'),
              ),
            ],
          ),
        );
      },
    );
    if (values == null) return;
    final result = await c.auth.changePassword(c.user!, values.$1, values.$2);
    c.refreshUser(result.account);
    if (result.recoveryCode != null && context.mounted) {
      await showRecoveryCode(context, result.recoveryCode!);
    }
  }

  Future<void> _newRecoveryCode(BuildContext context) async {
    final password = await _askPassword(
      context,
      'Tạo mã khôi phục mới',
      'Mã cũ sẽ hết hiệu lực. Nhập mật khẩu để xác nhận.',
    );
    if (password == null) return;
    final code = await c.auth.regenerateRecoveryCode(c.user!, password);
    if (context.mounted) await showRecoveryCode(context, code);
  }
}

Future<String?> _askPassword(
  BuildContext context,
  String title,
  String message,
) {
  final field = TextEditingController();
  return showFormDialog<String>(
    controllers: [field],
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 12),
            TextField(
              controller: field,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Mật khẩu'),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, field.text),
          child: const Text('Xác nhận'),
        ),
      ],
    ),
  );
}

/// Administrator's list of accounts: approve registrations, set roles,
/// lock/unlock, reset passwords and create accounts.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<UserAccount> accounts = [];
  bool busy = false;
  AppController get c => widget.controller;
  UserAccount get admin => c.user!;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final list = await c.repository.accounts();
    if (mounted) setState(() => accounts = list);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Role?> _pickRole(String title, Role current) =>
      showInstantDialog<Role>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(title),
          children: [
            for (final r in Role.values)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, r),
                child: Text('${r.label}${r == current ? ' (hiện tại)' : ''}'),
              ),
          ],
        ),
      );

  Future<void> _showSecret(String title, String secret, String note) =>
      showInstantDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(note),
              const SizedBox(height: 12),
              SelectableText(
                secret,
                style: const TextStyle(
                  fontSize: 20,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: secret)),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Sao chép'),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đã ghi lại'),
            ),
          ],
        ),
      );

  Future<void> _action(UserAccount target, String action) async {
    switch (action) {
      case 'approve':
        final role = await _pickRole('Duyệt với vai trò', Role.viewer);
        if (role != null) await c.auth.approve(admin, target, role);
      case 'role':
        final role = await _pickRole('Đổi vai trò', target.role);
        if (role != null) await c.auth.setRole(admin, target, role);
      case 'disable':
        if (mounted &&
            await confirmAction(
              context,
              'Khóa tài khoản ${target.label}?',
              'Người này không đăng nhập được cho đến khi mở lại. Dữ liệu và nhật ký giữ nguyên.',
              action: 'Khóa tài khoản',
            )) {
          await c.auth.setStatus(admin, target, AccountStatus.disabled);
        }
      case 'enable':
        await c.auth.setStatus(admin, target, AccountStatus.active);
      case 'unlock':
        await c.auth.unlock(admin, target);
      case 'reset':
        if (mounted &&
            await confirmAction(
              context,
              'Đặt lại mật khẩu cho ${target.label}?',
              'Mật khẩu hiện tại hết hiệu lực. Người dùng phải đổi mật khẩu tạm ở lần đăng nhập tới.',
              action: 'Đặt lại',
            )) {
          final temporary = await c.auth.resetPassword(admin, target);
          await _showSecret(
            'Mật khẩu tạm',
            temporary,
            'Đưa mật khẩu này trực tiếp cho ${target.label}. Mật khẩu chỉ hiện lần này.',
          );
        }
    }
    if (target.id == admin.id) {
      final me = await c.repository.accountByUsername(admin.username);
      if (me != null) c.refreshUser(me);
    }
  }

  Future<void> _create() async {
    final username = TextEditingController();
    final name = TextEditingController();
    final position = TextEditingController();
    var role = Role.technician;
    final ok = await showFormDialog<bool>(
      controllers: [username, name, position],
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Thêm tài khoản'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: username,
                    decoration: const InputDecoration(
                      labelText: 'Tên đăng nhập',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Họ và tên'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: position,
                    decoration: const InputDecoration(labelText: 'Chức vụ'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Role>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Vai trò'),
                    items: [
                      for (final r in Role.values)
                        DropdownMenuItem(value: r, child: Text(r.label)),
                    ],
                    onChanged: (v) => setState(() => role = v!),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Tạo'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final created = await c.auth.createAccount(
      admin,
      username: username.text,
      displayName: name.text,
      position: position.text,
      role: role,
    );
    await _showSecret(
      'Mật khẩu tạm',
      created.password,
      'Tài khoản ${created.account.username} đã tạo. Người dùng phải đổi mật khẩu này ở lần đăng nhập đầu và sẽ nhận mã khôi phục khi đổi.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = c.clock();
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý tài khoản')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: busy ? null : () => _run(_create),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Thêm tài khoản'),
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                for (final a in accounts)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(a.label.characters.first.toUpperCase()),
                      ),
                      title: Text('${a.label} (${a.username})'),
                      subtitle: Text(
                        [
                          a.role.label,
                          a.status.label,
                          if (a.lockedAt(now))
                            'Tạm khóa đến ${_stamp(a.lockedUntil!)}',
                          if (a.mustChangePassword) 'Chờ đổi mật khẩu tạm',
                          if (a.position.isNotEmpty) a.position,
                          if (a.lastLoginAt != null)
                            'Đăng nhập ${_stamp(a.lastLoginAt!)}',
                        ].join(' • '),
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Thao tác tài khoản',
                        enabled: !busy,
                        onSelected: (v) => _run(() => _action(a, v)),
                        itemBuilder: (_) => [
                          if (a.status == AccountStatus.pending)
                            const PopupMenuItem(
                              value: 'approve',
                              child: Text('Duyệt'),
                            ),
                          if (a.status != AccountStatus.pending)
                            const PopupMenuItem(
                              value: 'role',
                              child: Text('Đổi vai trò'),
                            ),
                          if (a.status == AccountStatus.disabled)
                            const PopupMenuItem(
                              value: 'enable',
                              child: Text('Mở lại tài khoản'),
                            )
                          else if (a.id != admin.id)
                            const PopupMenuItem(
                              value: 'disable',
                              child: Text('Khóa tài khoản'),
                            ),
                          if (a.lockedAt(now))
                            const PopupMenuItem(
                              value: 'unlock',
                              child: Text('Mở tạm khóa'),
                            ),
                          if (a.id != admin.id)
                            const PopupMenuItem(
                              value: 'reset',
                              child: Text('Đặt lại mật khẩu'),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Administrator's view of who did what; newest first, searchable, exportable.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  final search = TextEditingController();
  List<AuditEntry> entries = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await widget.controller.repository.auditEntries(limit: 2000);
    if (mounted) {
      setState(() {
        entries = list;
        loading = false;
      });
    }
  }

  String _describe(AuditEntry e) => [
    auditActionLabels[e.action] ?? e.action,
    if (e.entity.isNotEmpty) auditEntityLabels[e.entity] ?? e.entity,
    if (e.summary.isNotEmpty) e.summary,
  ].join(' • ');

  List<AuditEntry> get _visible {
    final q = search.text.trim().toLowerCase();
    return q.isEmpty
        ? entries
        : entries
              .where(
                (e) =>
                    '${e.userName} ${_describe(e)}'.toLowerCase().contains(q),
              )
              .toList();
  }

  Future<void> _export() async {
    final book = Excel.createExcel();
    final sheet = book['Nhật ký'];
    sheet.appendRow([
      for (final h in [
        'Thời gian',
        'Người thực hiện',
        'Thao tác',
        'Đối tượng',
        'Nội dung',
      ])
        TextCellValue(h),
    ]);
    for (final e in _visible) {
      sheet.appendRow([
        TextCellValue(_stamp(e.at)),
        TextCellValue(e.userName.isEmpty ? 'Hệ thống' : e.userName),
        TextCellValue(auditActionLabels[e.action] ?? e.action),
        TextCellValue(auditEntityLabels[e.entity] ?? e.entity),
        TextCellValue(e.summary),
      ]);
    }
    book.delete('Sheet1');
    await saveBytes(
      'EquipmentManager-nhat-ky-${DateTime.now().toIso8601String().substring(0, 10)}.xlsx',
      Uint8List.fromList(book.encode()!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhật ký thao tác'),
        actions: [
          IconButton(
            tooltip: 'Xuất Excel',
            onPressed: rows.isEmpty ? null : () => unawaited(_export()),
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Tìm người, thao tác, thiết bị…',
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, n) {
                      final e = rows[n];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          e.action.startsWith('login') || e.action == 'lockout'
                              ? Icons.login
                              : Icons.history,
                        ),
                        title: Text(_describe(e)),
                        subtitle: Text(
                          '${_stamp(e.at)} • ${e.userName.isEmpty ? 'Hệ thống' : e.userName}',
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

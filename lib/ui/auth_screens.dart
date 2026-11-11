import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/security.dart';
import 'controller.dart';

enum _Mode { login, register, recover }

/// Shown instead of the app until someone signs in: first-run setup, sign in,
/// self-registration, recovery and the forced password change.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.controller});
  final AppController controller;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  final displayName = TextEditingController();
  final position = TextEditingController();
  final unit = TextEditingController();
  final code = TextEditingController();
  final current = TextEditingController();
  var mode = _Mode.login;
  bool busy = false, hide = true;
  String? error, info;
  AppController get c => widget.controller;
  bool get setup => !c.hasAccounts;
  bool get changing => c.user?.mustChangePassword ?? false;

  @override
  void dispose() {
    for (final field in [
      username,
      password,
      confirm,
      displayName,
      position,
      unit,
      code,
      current,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  void _switch(_Mode next) => setState(() {
    mode = next;
    error = null;
    info = null;
    password.clear();
    confirm.clear();
    code.clear();
  });

  Future<void> _submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (changing) {
        final result = await c.auth.changePassword(
          c.user!,
          current.text,
          password.text,
        );
        if (result.recoveryCode != null && mounted) {
          await showRecoveryCode(context, result.recoveryCode!);
        }
        c.signIn(result.account);
      } else if (setup || mode == _Mode.register) {
        final result = await c.auth.register(
          username: username.text,
          password: password.text,
          displayName: displayName.text,
          position: position.text,
          unit: unit.text,
        );
        if (mounted) await showRecoveryCode(context, result.recoveryCode);
        if (setup) {
          c.signIn(result.account);
        } else {
          _switch(_Mode.login);
          setState(
            () =>
                info = 'Đã gửi đăng ký. Hãy chờ Quản trị duyệt rồi đăng nhập.',
          );
        }
      } else if (mode == _Mode.recover) {
        final fresh = await c.auth.recover(
          username.text,
          code.text,
          password.text,
        );
        if (mounted) await showRecoveryCode(context, fresh);
        _switch(_Mode.login);
        setState(() => info = 'Đã đặt mật khẩu mới. Hãy đăng nhập.');
      } else {
        c.signIn(await c.auth.login(username.text, password.text));
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? _required(String? v) =>
      v == null || v.trim().isEmpty ? 'Bắt buộc.' : null;

  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = false,
    String? Function(String?)? validator,
    bool autofocus = false,
    TextInputAction action = TextInputAction.next,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      obscureText: secret && hide,
      autofocus: autofocus,
      enableSuggestions: !secret,
      autocorrect: false,
      textInputAction: action,
      onFieldSubmitted: action == TextInputAction.done
          ? (_) => _submit()
          : null,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: secret
            ? IconButton(
                tooltip: hide ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                onPressed: () => setState(() => hide = !hide),
                icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
              )
            : null,
      ),
    ),
  );

  List<Widget> _newPassword() => [
    _field(
      password,
      changing || mode == _Mode.recover ? 'Mật khẩu mới' : 'Mật khẩu',
      secret: true,
      validator: (v) => passwordProblem(
        v ?? '',
        username: changing ? c.user!.username : username.text,
      ),
    ),
    _field(
      confirm,
      'Nhập lại mật khẩu',
      secret: true,
      action: TextInputAction.done,
      validator: (v) =>
          v != password.text ? 'Mật khẩu nhập lại không khớp.' : null,
    ),
    Text(
      'Ít nhất $minPasswordLength ký tự, có chữ và số, không chứa tên đăng nhập.',
      style: Theme.of(context).textTheme.bodySmall,
    ),
    const SizedBox(height: 8),
  ];

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, button) = changing
        ? (
            'Đổi mật khẩu',
            'Quản trị đã đặt mật khẩu tạm cho ${c.user!.label}. Hãy đặt mật khẩu của riêng bạn.',
            'Lưu mật khẩu',
          )
        : setup
        ? (
            'Tạo tài khoản Quản trị',
            'Máy này chưa có tài khoản. Người tạo đầu tiên là Quản trị: duyệt tài khoản khác, khôi phục dữ liệu và chỉnh cài đặt. Dữ liệu hiện có được giữ nguyên.',
            'Tạo tài khoản',
          )
        : switch (mode) {
            _Mode.register => (
              'Đăng ký tài khoản',
              'Tài khoản mới cần Quản trị duyệt và cấp vai trò trước khi dùng.',
              'Gửi đăng ký',
            ),
            _Mode.recover => (
              'Quên mật khẩu',
              'Nhập mã khôi phục đã nhận khi đăng ký. Mỗi mã dùng được một lần.',
              'Đặt mật khẩu mới',
            ),
            _Mode.login => (
              'Đăng nhập',
              'Dữ liệu được lưu trên máy này.',
              'Đăng nhập',
            ),
          };
    final registering = setup || mode == _Mode.register;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AutofillGroup(
                    child: Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Image(
                            image: AssetImage('assets/brand/logo.png'),
                            width: 56,
                            height: 56,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(subtitle, textAlign: TextAlign.center),
                          const SizedBox(height: 20),
                          if (info != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                info!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          if (changing) ...[
                            _field(
                              current,
                              'Mật khẩu tạm',
                              secret: true,
                              autofocus: true,
                              validator: _required,
                            ),
                            ..._newPassword(),
                          ] else ...[
                            _field(
                              username,
                              'Tên đăng nhập',
                              autofocus: true,
                              validator: registering
                                  ? (v) => usernameProblem(v ?? '')
                                  : _required,
                            ),
                            if (registering) ...[
                              _field(
                                displayName,
                                'Họ và tên',
                                validator: _required,
                              ),
                              _field(position, 'Chức vụ'),
                              _field(unit, 'Đơn vị'),
                              ..._newPassword(),
                            ] else if (mode == _Mode.recover) ...[
                              _field(
                                code,
                                'Mã khôi phục',
                                validator: _required,
                              ),
                              ..._newPassword(),
                            ] else
                              _field(
                                password,
                                'Mật khẩu',
                                secret: true,
                                action: TextInputAction.done,
                                validator: _required,
                              ),
                          ],
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          FilledButton(
                            onPressed: busy ? null : _submit,
                            child: Text(busy ? 'Đang xử lý…' : button),
                          ),
                          if (changing)
                            TextButton(
                              onPressed: busy ? null : c.signOut,
                              child: const Text('Đăng xuất'),
                            )
                          else if (!setup) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              alignment: WrapAlignment.center,
                              children: [
                                if (mode != _Mode.login)
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => _switch(_Mode.login),
                                    child: const Text('Quay lại đăng nhập'),
                                  ),
                                if (mode != _Mode.register)
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => _switch(_Mode.register),
                                    child: const Text('Đăng ký tài khoản'),
                                  ),
                                if (mode != _Mode.recover)
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => _switch(_Mode.recover),
                                    child: const Text('Quên mật khẩu'),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The code is shown once; only its hash is stored.
Future<void> showRecoveryCode(BuildContext context, String code) async {
  var saved = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    animationStyle: AnimationStyle.noAnimation,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Mã khôi phục'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dùng mã này để tự đặt lại mật khẩu khi quên. Mã chỉ hiện một lần; hãy chép ra giấy hoặc lưu ở nơi an toàn, không lưu chung máy.',
                ),
                const SizedBox(height: 16),
                SelectableText(
                  code,
                  style: const TextStyle(
                    fontSize: 22,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: code)),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Sao chép'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: saved,
                  onChanged: (v) => setState(() => saved = v ?? false),
                  title: const Text('Tôi đã lưu mã khôi phục'),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: saved ? () => Navigator.pop(context) : null,
              child: const Text('Tiếp tục'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Covers everything while the session is locked; only the same user's
/// password unlocks it, and wrong attempts count toward the lockout.
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.controller,
    required this.onSignOut,
  });
  final AppController controller;
  final Future<void> Function() onSignOut;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final password = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (busy || password.text.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.controller.unlock(password.text);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      password.clear();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.controller.user!;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.lock_outline, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Đã khóa',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${user.label} (${user.username})',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: password,
                        autofocus: true,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        onSubmitted: (_) => _unlock(),
                        decoration: const InputDecoration(
                          labelText: 'Mật khẩu',
                        ),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: busy ? null : _unlock,
                        child: const Text('Mở khóa'),
                      ),
                      TextButton(
                        onPressed: busy ? null : widget.onSignOut,
                        child: const Text('Đăng xuất / đổi người dùng'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

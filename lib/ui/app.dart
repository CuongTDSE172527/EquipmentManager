import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../domain/accounts.dart';
import '../domain/models.dart';
import '../domain/deadlines.dart';
import '../domain/updates.dart';
import '../services/attachment_files.dart';
import '../services/auto_backup.dart';
import '../services/notifications.dart';
import '../services/update_installer.dart';
import '../services/updates.dart';
import 'controller.dart';
import 'attachments_section.dart';
import 'auth_screens.dart';
import 'forms.dart';
import 'data_page.dart';
import 'settings_page.dart';
import 'service_history_page.dart';
import 'responsive_motion.dart';

Color statusColor(
  DeadlineStatus s, [
  Brightness brightness = Brightness.light,
]) => brightness == Brightness.dark
    ? switch (s) {
        DeadlineStatus.overdue => const Color(0xFFFF948B),
        DeadlineStatus.upcoming => const Color(0xFFFFD166),
        DeadlineStatus.valid => const Color(0xFF7FDFAB),
        _ => const Color(0xFFBEC7D6),
      }
    : switch (s) {
        DeadlineStatus.overdue => const Color(0xFFB42318),
        DeadlineStatus.upcoming => const Color(0xFF996300),
        DeadlineStatus.valid => const Color(0xFF157347),
        _ => const Color(0xFF667085),
      };

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final DeadlineStatus status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: statusColor(
        status,
        Theme.of(context).brightness,
      ).withValues(alpha: .12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      status.label,
      style: TextStyle(
        color: statusColor(status, Theme.of(context).brightness),
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    ),
  );
}

class EquipmentManagerApp extends StatefulWidget {
  const EquipmentManagerApp({
    super.key,
    required this.controller,
    required this.notifications,
    this.autoBackup,
    this.updates,
    this.installer,
    this.opener = const AttachmentOpener(),
  });
  final AppController controller;
  final NotificationService notifications;

  /// Null disables automatic backups (tests); main passes the real service.
  final AutoBackupService? autoBackup;
  final UpdateService? updates;
  final UpdateInstaller? installer;
  final AttachmentOpener opener;
  @override
  State<EquipmentManagerApp> createState() => _AppState();
}

class _AppState extends State<EquipmentManagerApp> with WidgetsBindingObserver {
  final navigator = GlobalKey<NavigatorState>();
  Timer? _idle;
  DateTime? _backgroundAt;
  String? _sessionUser;
  final search = TextEditingController();
  final searchFocus = FocusNode();
  int page = 0, sortColumn = 0;
  bool alertsOnly = false, byProvider = false, ascending = true;
  bool confirmOnly = false;
  AppUpdate? pendingUpdate;
  DeadlineStatus? status;
  ItemKind? kind;
  String? group, provider;
  String version = '';
  late final lightTheme = _theme(Brightness.light);
  late final darkTheme = _theme(Brightness.dark);
  ManagementStatus? management = ManagementStatus.active;
  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    c.addListener(_onSession);
    _onSession();
    unawaited(_initialize());
  }

  bool get _canEdit => c.can(Permission.editData);
  int get _lockMinutes => c.user?.autoLockMinutes ?? 0;

  bool _onKey(KeyEvent _) {
    _activity();
    return false;
  }

  /// Restarts the idle countdown on any pointer or key input.
  void _activity() {
    _idle?.cancel();
    if (c.user == null || c.locked || _lockMinutes == 0) return;
    _idle = Timer(Duration(minutes: _lockMinutes), c.lock);
  }

  /// The controller also notifies every minute for the clock, so the idle
  /// countdown restarts only on real session changes, never on that tick.
  void _onSession() {
    final id = c.user?.id;
    final key = '$id|${c.locked}|$_lockMinutes';
    if (key == _sessionKey) return;
    if (id != _sessionUser) {
      // Signed out or another user: nothing of the previous session stays open.
      if (_sessionUser != null) {
        navigator.currentState?.popUntil((r) => r.isFirst);
        if (mounted) setState(() => page = 0);
      }
      _sessionUser = id;
    }
    _sessionKey = key;
    if (c.locked) {
      _idle?.cancel();
    } else {
      _activity();
    }
  }

  String? _sessionKey;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Timers may not run while the app is in the background, so the elapsed
    // time is checked again when it comes back.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundAt ??= c.clock();
    } else if (state == AppLifecycleState.resumed) {
      final away = _backgroundAt;
      _backgroundAt = null;
      if (away != null &&
          _lockMinutes > 0 &&
          c.clock().difference(away).inMinutes >= _lockMinutes) {
        c.lock();
      } else {
        _activity();
      }
    }
  }

  Future<void> _signOut() async {
    navigator.currentState?.popUntil((r) => r.isFirst);
    await c.signOut();
  }

  void _later(String text) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _message(text);
  });

  Future<void> _initialize() async {
    try {
      await widget.notifications.initialize(onOpen: _openAlerts);
      if (await widget.notifications.launchedFromNotification()) _openAlerts();
      if (c.settings.notificationsEnabled) {
        await widget.notifications.refresh(c.settings);
      }
    } catch (e) {
      _later(e.toString());
    }
    final auto = widget.autoBackup;
    if (auto != null) {
      try {
        if (await auto.runIfDue(c.repository, c.clock()) != null) {
          await c.load();
        }
      } catch (e) {
        _later('Chưa tự sao lưu được: $e');
      }
    }
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => version = info.version);
      if (updateCheckDue(c.settings, c.clock())) {
        await _checkUpdate(info.version);
      }
    } catch (e) {
      _later(e.toString());
    }
  }

  /// Opt-in daily check. It only reports a newer version; downloading and
  /// installing always stay a user action in Settings.
  Future<void> _checkUpdate(String running) async {
    final current = AppVersion.tryParse(running);
    if (current == null) return;
    try {
      final target = await (widget.installer ?? const UpdateInstaller())
          .target();
      final result = await (widget.updates ?? UpdateService()).check(
        current,
        target,
        includePrereleases: c.settings.updateIncludePrereleases,
        cancel: UpdateCancellation(),
      );
      // A background bookkeeping write, allowed before anyone signs in.
      await c.repository.saveSettings(
        c.settings.copy({'lastUpdateCheck': c.clock().toIso8601String()}),
      );
      await c.load();
      if (mounted) setState(() => pendingUpdate = result);
    } catch (_) {
      // Offline or rate-limited: stay quiet and try again on the next launch.
    }
  }

  void _resetFilters() {
    search.clear();
    confirmOnly = false;
    group = null;
    provider = null;
    kind = null;
    status = null;
    management = ManagementStatus.active;
    alertsOnly = false;
    byProvider = false;
  }

  void _openAlerts() {
    if (mounted) {
      setState(() {
        _resetFilters();
        page = 1;
        alertsOnly = true;
        status = null;
        management = ManagementStatus.active;
      });
    }
  }

  void _message(String text) {
    final ctx = navigator.currentContext;
    if (ctx != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 6)),
      );
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _message(e.toString());
    }
  }

  void _navigate(int n) => setState(() {
    page = n;
    search.clear();
    alertsOnly = false;
    confirmOnly = false;
    status = null;
  });

  void _openConfirmations() => setState(() {
    _resetFilters();
    page = 1;
    confirmOnly = true;
  });

  Widget _userMenu(BuildContext context, {required bool sidebar}) {
    final user = c.user!;
    final menu = PopupMenuButton<String>(
      tooltip: 'Tài khoản',
      onSelected: (v) {
        switch (v) {
          case 'profile':
            _navigate(4);
          case 'lock':
            c.lock();
          case 'logout':
            unawaited(_run(_signOut));
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'profile', child: Text('Hồ sơ của tôi')),
        PopupMenuItem(value: 'lock', child: Text('Khóa màn hình')),
        PopupMenuItem(value: 'logout', child: Text('Đăng xuất')),
      ],
      icon: sidebar
          ? const Icon(Icons.more_vert, color: Color(0xFFB5CBD5))
          : CircleAvatar(
              radius: 15,
              child: Text(user.label.characters.first.toUpperCase()),
            ),
    );
    if (!sidebar) return menu;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 12),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: const Color(0xFF244958),
        foregroundColor: Colors.white,
        child: Text(user.label.characters.first.toUpperCase()),
      ),
      title: Text(
        user.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      subtitle: Text(
        user.role.label,
        style: const TextStyle(color: Color(0xFF91ACBA), fontSize: 11),
      ),
      trailing: menu,
    );
  }

  Widget _navIcon(int n, IconData icon) => n == 4 && pendingUpdate != null
      ? Badge(label: const Text('Mới'), child: Icon(icon))
      : Icon(icon);

  void _confirmData(BuildContext context, TrackedDeadline r) => unawaited(
    _run(() async {
      final after = statusOf(
        confirmDeadline(r.item, c.clock()),
        r.equipment,
        c.settings,
        c.clock(),
      );
      final choice = await showInstantDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Xác nhận dữ liệu hạng mục'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r.equipment.name} • ${r.item.title}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Hạn đang ghi: ${_dueLabel(r.item)}'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Sau khi xác nhận:'),
                    StatusChip(after),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Chỉ xác nhận khi đã đối chiếu giấy tờ. Hạn được giữ nguyên; ghi chú lưu ngày xác nhận. Nếu hạn chưa đúng, chọn Sửa hạn.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'edit'),
              child: const Text('Sửa hạn'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'confirm'),
              child: const Text('Xác nhận đúng'),
            ),
          ],
        ),
      );
      if (choice == 'edit' && context.mounted) {
        await itemForm(context, c, item: r.item);
      } else if (choice == 'confirm') {
        await c.confirmItem(r.item);
        _message('Đã xác nhận. Trạng thái hiện tại: ${after.label}.');
      }
    }),
  );
  void _new() {
    if (!_canEdit || page > 2) return;
    final ctx = navigator.currentContext!;
    unawaited(_run(() => page == 1 ? itemForm(ctx, c) : equipmentForm(ctx, c)));
  }

  @override
  void dispose() {
    _idle?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    c.removeListener(_onSession);
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF087F8C),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      splashFactory: NoSplash.splashFactory,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: const ImmediatePageTransitionsBuilder(),
        },
      ),
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF4F7FA)
          : const Color(0xFF111820),
      textTheme: ThemeData(brightness: brightness).textTheme.copyWith(
        bodyMedium: const TextStyle(fontSize: 15),
        bodyLarge: const TextStyle(fontSize: 16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => MaterialApp(
      navigatorKey: navigator,
      title: 'EquipmentManager',
      debugShowCheckedModeBanner: false,
      locale: const Locale('vi', 'VN'),
      supportedLocales: const [Locale('vi', 'VN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeAnimationDuration: Duration.zero,
      themeMode: switch (c.settings.theme) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      },
      // The lock screen covers every route, dialogs included, and keeps any
      // half-filled form underneath for when the same user unlocks.
      builder: (context, child) => Listener(
        onPointerDown: (_) => _activity(),
        onPointerSignal: (_) => _activity(),
        child: Stack(
          children: [
            ExcludeSemantics(excluding: c.locked, child: child!),
            if (c.locked && c.user != null)
              // Its own Overlay: the text field needs one for selection
              // handles, and this layer sits above the app's Navigator.
              Positioned.fill(
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) =>
                          LockScreen(controller: c, onSignOut: _signOut),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      home: c.loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : !c.hasAccounts || c.user == null || c.user!.mustChangePassword
          ? AuthGate(controller: c)
          : Builder(
              builder: (context) => CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.keyN, control: true):
                      _new,
                  const SingleActivator(
                    LogicalKeyboardKey.keyF,
                    control: true,
                  ): () {
                    if (page > 2) setState(() => page = 1);
                    searchFocus.requestFocus();
                  },
                },
                child: Focus(
                  autofocus: true,
                  child: LayoutBuilder(
                    builder: (context, bounds) {
                      final wide = bounds.maxWidth >= 960;
                      const titles = [
                        'Tổng quan',
                        'Theo dõi hạn',
                        'Thiết bị',
                        'Dữ liệu & báo cáo',
                        'Cài đặt',
                      ];
                      const icons = [
                        Icons.dashboard_outlined,
                        Icons.event_note_outlined,
                        Icons.airport_shuttle_outlined,
                        Icons.folder_outlined,
                        Icons.settings_outlined,
                      ];
                      return Scaffold(
                        appBar: wide
                            ? null
                            : AppBar(
                                title: Text(titles[page]),
                                actions: [
                                  IconButton(
                                    tooltip: 'Làm mới',
                                    onPressed: () => _run(c.load),
                                    icon: const Icon(Icons.refresh),
                                  ),
                                  _userMenu(context, sidebar: false),
                                ],
                              ),
                        body: SafeArea(
                          child: Row(
                            children: [
                              if (wide)
                                Container(
                                  width: 240,
                                  color: const Color(0xFF122B3A),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 28,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(left: 12),
                                        child: Image(
                                          image: AssetImage(
                                            'assets/brand/logo.png',
                                          ),
                                          width: 52,
                                          height: 52,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      const Padding(
                                        padding: EdgeInsets.only(left: 12),
                                        child: Text(
                                          'EquipmentManager',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          12,
                                          5,
                                          0,
                                          28,
                                        ),
                                        child: Text(
                                          'QUẢN LÝ TRANG THIẾT BỊ',
                                          style: TextStyle(
                                            color: Color(0xFF91ACBA),
                                            fontSize: 10,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ),
                                      for (var n = 0; n < titles.length; n++)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 6,
                                          ),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: ListTile(
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              selected: page == n,
                                              selectedTileColor: const Color(
                                                0xFF244958,
                                              ),
                                              selectedColor: Colors.white,
                                              textColor: const Color(
                                                0xFFB5CBD5,
                                              ),
                                              iconColor: const Color(
                                                0xFFB5CBD5,
                                              ),
                                              leading: _navIcon(n, icons[n]),
                                              title: Text(titles[n]),
                                              onTap: () => _navigate(n),
                                            ),
                                          ),
                                        ),
                                      const Spacer(),
                                      const Divider(color: Color(0xFF35505F)),
                                      _userMenu(context, sidebar: true),
                                      if (version.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 12,
                                          ),
                                          child: Text(
                                            'Ngoại tuyến • Phiên bản $version${version.startsWith('0.') ? ' Beta' : ''}',
                                            style: const TextStyle(
                                              color: Color(0xFF91ACBA),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (wide)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 32,
                                          vertical: 22,
                                        ),
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surface,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    titles[page],
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .headlineSmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    c.settings.agency,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Text(displayDate(c.clock())),
                                            const SizedBox(width: 16),
                                            IconButton(
                                              tooltip: 'Làm mới',
                                              onPressed: () => _run(c.load),
                                              icon: const Icon(Icons.refresh),
                                            ),
                                            if (page < 3 && _canEdit)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 12,
                                                ),
                                                child: FilledButton.icon(
                                                  onPressed: _new,
                                                  icon: const Icon(Icons.add),
                                                  label: Text(
                                                    page == 1
                                                        ? 'Thêm hạng mục'
                                                        : 'Thêm thiết bị',
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    Expanded(
                                      child: c.loading
                                          ? const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            )
                                          : switch (page) {
                                              0 => _overview(context),
                                              1 => _deadlines(context, wide),
                                              2 => _equipment(context),
                                              3 => DataPage(
                                                controller: c,
                                                onError: _message,
                                                autoBackup: widget.autoBackup,
                                              ),
                                              _ => SettingsPage(
                                                controller: c,
                                                notifications:
                                                    widget.notifications,
                                                onError: _message,
                                                pendingUpdate: pendingUpdate,
                                                updates: widget.updates,
                                                installer: widget.installer,
                                              ),
                                            },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        floatingActionButton: !wide && page < 3 && _canEdit
                            ? FloatingActionButton(
                                heroTag: null,
                                onPressed: _new,
                                tooltip: page == 1
                                    ? 'Thêm hạng mục'
                                    : 'Thêm thiết bị',
                                child: const Icon(Icons.add),
                              )
                            : null,
                        bottomNavigationBar: wide
                            ? null
                            : NavigationBar(
                                animationDuration: Duration.zero,
                                selectedIndex: page,
                                onDestinationSelected: _navigate,
                                destinations: [
                                  for (var n = 0; n < titles.length; n++)
                                    NavigationDestination(
                                      icon: _navIcon(n, icons[n]),
                                      label: titles[n],
                                    ),
                                ],
                              ),
                      );
                    },
                  ),
                ),
              ),
            ),
    ),
  );
  Widget _empty(BuildContext context, String title, String detail) => Card(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(detail, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
  Widget _overview(BuildContext context) {
    final rows = c.tracked;
    final active = c.equipment
        .where((e) => e.managementStatus == ManagementStatus.active)
        .length;
    final alerts = rows
        .where(
          (r) => [
            DeadlineStatus.overdue,
            DeadlineStatus.upcoming,
          ].contains(r.status),
        )
        .toList();
    final backup = c.settings.lastBackup;
    final pendingConfirm = rows
        .where(
          (r) =>
              r.item.requiresConfirmation &&
              r.status != DeadlineStatus.excluded &&
              r.status != DeadlineStatus.done,
        )
        .length;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Chủ động theo dõi, không bỏ lỡ hạn',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text('Thống kê hạng mục của thiết bị đang sử dụng.'),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, bounds) {
            final count = bounds.maxWidth > 900
                ? 5
                : bounds.maxWidth > 550
                ? 3
                : 2;
            final width = (bounds.maxWidth - (count - 1) * 12) / count;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final s in [
                  DeadlineStatus.overdue,
                  DeadlineStatus.upcoming,
                  DeadlineStatus.valid,
                  DeadlineStatus.needsUpdate,
                ])
                  SizedBox(
                    width: width,
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() {
                          _resetFilters();
                          page = 1;
                          status = s;
                          alertsOnly = false;
                          management = ManagementStatus.active;
                        }),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                s == DeadlineStatus.overdue
                                    ? Icons.error_outline
                                    : s == DeadlineStatus.upcoming
                                    ? Icons.schedule
                                    : s == DeadlineStatus.valid
                                    ? Icons.check_circle_outline
                                    : Icons.help_outline,
                                color: statusColor(
                                  s,
                                  Theme.of(context).brightness,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '${rows.where((r) => r.status == s).length}',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor(
                                    s,
                                    Theme.of(context).brightness,
                                  ),
                                ),
                              ),
                              Text(s.label),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  width: width,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: InkWell(
                      onTap: () => setState(() {
                        _resetFilters();
                        page = 2;
                      }),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.inventory_2_outlined),
                            const SizedBox(height: 16),
                            Text(
                              '$active',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text('Tổng thiết bị'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        if (pendingUpdate != null)
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: Text('Có bản cập nhật ${pendingUpdate!.version}'),
              subtitle: const Text(
                'Ứng dụng chỉ kiểm tra. Bạn chủ động tải và cài trong Cài đặt.',
              ),
              trailing: TextButton(
                onPressed: () => _navigate(4),
                child: const Text('Xem'),
              ),
            ),
          ),
        if (pendingConfirm > 0)
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: Text('$pendingConfirm mốc cần xác nhận'),
              subtitle: const Text(
                'Đối chiếu giấy tờ rồi xác nhận đúng hoặc sửa hạn.',
              ),
              trailing: TextButton(
                onPressed: _openConfirmations,
                child: const Text('Xác nhận'),
              ),
            ),
          ),
        if (backup == null || calendarDaysBetween(backup, c.clock()) >= 30)
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Sao lưu ra ngoài định kỳ'),
              subtitle: Text(
                '${backup == null ? 'Bạn chưa lưu bản sao lưu ra ngoài.' : 'Lần sao lưu ra ngoài gần nhất: ${displayDate(backup)}.'} Bản tự động chỉ nằm trên máy này; hãy lưu thêm ra USB hoặc Drive.',
              ),
              trailing: TextButton(
                onPressed: () => setState(() => page = 3),
                child: const Text('Sao lưu'),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Các hạng mục cần xử lý',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(onPressed: _openAlerts, child: const Text('Xem tất cả')),
          ],
        ),
        const SizedBox(height: 12),
        if (alerts.isEmpty)
          _empty(
            context,
            c.equipment.isEmpty
                ? 'Chưa có dữ liệu thiết bị'
                : 'Chưa có hạng mục quá hạn hoặc sắp đến hạn',
            c.equipment.isEmpty
                ? 'Thêm thiết bị hoặc nhập Excel trong Dữ liệu & báo cáo.'
                : 'Các hạng mục chưa rõ thông tin vẫn cần được cập nhật.',
          ),
        for (final row in alerts.take(8)) _deadlineCard(context, row),
      ],
    );
  }

  Widget _searchField() => TextField(
    controller: search,
    focusNode: searchFocus,
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(
      hintText: 'Tìm tên thiết bị, biển số, hạng mục…',
      prefixIcon: const Icon(Icons.search),
      suffixIcon: search.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Xóa tìm kiếm',
              onPressed: () => setState(search.clear),
              icon: const Icon(Icons.close),
            ),
    ),
  );
  Widget _filter<T>(
    String label,
    T? selected,
    List<T> values,
    String Function(T) title,
    void Function(T?) changed,
  ) => SizedBox(
    width: 205,
    child: DropdownButtonFormField<T>(
      key: ValueKey('$label-$selected'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<T>(value: null, child: const Text('Tất cả')),
        for (final v in values)
          DropdownMenuItem(
            value: v,
            child: Text(title(v), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => setState(() => changed(v)),
    ),
  );
  List<TrackedDeadline> get _filteredRows => c.tracked.where((r) {
    final query = search.text.trim().toLowerCase();
    return (query.isEmpty ||
            '${r.equipment.searchText} ${r.item.title.toLowerCase()} ${r.item.kind.label.toLowerCase()}'
                .contains(query)) &&
        (group == null || r.equipment.group == group) &&
        (provider == null || r.item.provider == provider) &&
        (kind == null || r.item.kind == kind) &&
        (status == null || r.status == status) &&
        (management == null || r.equipment.managementStatus == management) &&
        (!confirmOnly ||
            (r.item.requiresConfirmation && r.status != DeadlineStatus.done)) &&
        (!alertsOnly ||
            [
              DeadlineStatus.overdue,
              DeadlineStatus.upcoming,
            ].contains(r.status));
  }).toList();
  Widget _deadlines(BuildContext context, bool wide) {
    final rows = _filteredRows;
    if (byProvider) {
      rows.sort((a, b) {
        final n = a.item.provider.compareTo(b.item.provider);
        return n == 0 ? a.status.index.compareTo(b.status.index) : n;
      });
    }
    return LayoutBuilder(
      builder: (context, bounds) => Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: bounds.maxHeight * .6),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _searchField(),
                    const SizedBox(height: 16),
                    Builder(
                      builder: (context) {
                        final filters = Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _filter<String>(
                              'Nhóm',
                              group,
                              c.groups,
                              (v) => v,
                              (v) => group = v,
                            ),
                            _filter<ItemKind>(
                              'Loại hạng mục',
                              kind,
                              ItemKind.values,
                              (v) => v.label,
                              (v) => kind = v,
                            ),
                            _filter<DeadlineStatus>(
                              'Trạng thái',
                              status,
                              DeadlineStatus.values,
                              (v) => v.label,
                              (v) {
                                status = v;
                                alertsOnly = false;
                              },
                            ),
                            _filter<String>(
                              'Đơn vị thực hiện',
                              provider,
                              c.providers,
                              (v) => v,
                              (v) => provider = v,
                            ),
                            _filter<ManagementStatus>(
                              'Trạng thái quản lý',
                              management,
                              ManagementStatus.values,
                              (v) => v.label,
                              (v) => management = v,
                            ),
                            FilterChip(
                              label: const Text('Chỉ mốc cần xác nhận'),
                              selected: confirmOnly,
                              onSelected: (v) => setState(() {
                                confirmOnly = v;
                                if (v) {
                                  alertsOnly = false;
                                  status = null;
                                }
                              }),
                            ),
                          ],
                        );
                        if (wide) return filters;
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.filter_alt_outlined),
                            label: const Text('Bộ lọc'),
                            onPressed: () => showInstantDialog<void>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Lọc hạng mục'),
                                content: SizedBox(
                                  width: 480,
                                  child: SingleChildScrollView(child: filters),
                                ),
                                actions: [
                                  FilledButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Đóng'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${rows.length} hạng mục${alertsOnly ? ' • Chỉ cảnh báo' : ''}${confirmOnly ? ' • Cần xác nhận' : ''}',
                          ),
                        ),
                        Flexible(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Gom theo đơn vị',
                              style: TextStyle(fontSize: 13),
                            ),
                            value: byProvider,
                            onChanged: (v) => setState(() => byProvider = v),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Xóa bộ lọc',
                          onPressed: () => setState(_resetFilters),
                          icon: const Icon(Icons.filter_alt_off_outlined),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _empty(
                      context,
                      'Không có hạng mục phù hợp',
                      'Thử đổi bộ lọc hoặc thêm hạng mục.',
                    ),
                  )
                : wide
                ? _deadlineTable(context, rows)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    itemCount: rows.length,
                    itemBuilder: (context, n) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (byProvider &&
                            (n == 0 ||
                                rows[n - 1].item.provider !=
                                    rows[n].item.provider))
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              rows[n].item.provider.isEmpty
                                  ? 'Chưa chọn đơn vị'
                                  : rows[n].item.provider,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        _deadlineCard(context, rows[n]),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _dueLabel(DeadlineItem i) =>
      i.kind == ItemKind.insurance && i.insuranceMode != InsuranceMode.dated
      ? i.insuranceMode.label
      : i.expiredWithoutDate
      ? 'Đã hết, chưa rõ ngày'
      : displayDate(i.dueDate, i.precision);
  bool _needsConfirm(TrackedDeadline r) =>
      r.item.requiresConfirmation && !r.item.isDone;
  Widget _deadlineCard(BuildContext context, TrackedDeadline r) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.equipment.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_canEdit)
                PopupMenuButton<String>(
                  tooltip: 'Thao tác',
                  onSelected: (v) => _itemAction(context, r.item, v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Sửa hạng mục')),
                    PopupMenuItem(value: 'delete', child: Text('Xóa hạng mục')),
                  ],
                ),
            ],
          ),
          Text('${r.equipment.displayPlate} • ${r.item.title}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip(r.status),
              if (_needsConfirm(r))
                const Chip(
                  avatar: Icon(Icons.fact_check_outlined, size: 18),
                  label: Text('Cần xác nhận'),
                  visualDensity: VisualDensity.compact,
                ),
              Text(_dueLabel(r.item)),
              if (r.item.provider.isNotEmpty) Text(r.item.provider),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: () => _details(context, r.equipment),
                child: const Text('Xem thiết bị'),
              ),
              if (_canEdit && _needsConfirm(r))
                TextButton.icon(
                  onPressed: () => _confirmData(context, r),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Xác nhận dữ liệu'),
                ),
              if (_canEdit && !r.item.isDone)
                TextButton.icon(
                  onPressed: () =>
                      _run(() => completionForm(context, c, r.item)),
                  icon: const Icon(Icons.task_alt, size: 18),
                  label: const Text('Gia hạn / Hoàn thành'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  Widget _deadlineTable(BuildContext context, List<TrackedDeadline> rows) {
    final sorted = [...rows];
    if (!byProvider) {
      sorted.sort((a, b) {
        final value = switch (sortColumn) {
          1 => a.equipment.name.compareTo(b.equipment.name),
          2 => a.equipment.displayPlate.compareTo(b.equipment.displayPlate),
          3 => a.item.title.compareTo(b.item.title),
          4 => (effectiveDue(a.item) ?? DateTime(9999)).compareTo(
            effectiveDue(b.item) ?? DateTime(9999),
          ),
          5 => a.item.provider.compareTo(b.item.provider),
          _ => a.status.index.compareTo(b.status.index),
        };
        if (value == 0) {
          return (effectiveDue(a.item) ?? DateTime(9999)).compareTo(
            effectiveDue(b.item) ?? DateTime(9999),
          );
        }
        return ascending ? value : -value;
      });
    }
    DataColumn column(String text, int index) => DataColumn(
      label: Text(text),
      onSort: (n, asc) => setState(() {
        sortColumn = index;
        ascending = asc;
      }),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: PaginatedDataTable(
        key: ValueKey(
          '${search.text}-$group-$kind-$status-$provider-$management-${rows.length}-$byProvider-$confirmOnly',
        ),
        header: const Text('Danh sách hạng mục'),
        rowsPerPage: 10,
        availableRowsPerPage: const [10],
        showCheckboxColumn: false,
        sortColumnIndex: sortColumn,
        sortAscending: ascending,
        columns: [
          column('Trạng thái', 0),
          column('Thiết bị', 1),
          column('Biển số', 2),
          column('Hạng mục', 3),
          column('Hạn', 4),
          column('Đơn vị thực hiện', 5),
          const DataColumn(label: Text('Thao tác')),
        ],
        source: _TableSource(sorted.length, (index) {
          final r = sorted[index];
          return DataRow.byIndex(
            index: index,
            cells: [
              DataCell(StatusChip(r.status)),
              DataCell(
                SizedBox(
                  width: 200,
                  child: Text(
                    r.equipment.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                onTap: () => _details(context, r.equipment),
              ),
              DataCell(Text(r.equipment.displayPlate)),
              DataCell(
                SizedBox(width: 160, child: Text(r.item.title, maxLines: 2)),
              ),
              DataCell(Text(_dueLabel(r.item))),
              DataCell(Text(r.item.provider)),
              DataCell(
                Row(
                  children: [
                    if (_canEdit && _needsConfirm(r))
                      IconButton(
                        tooltip: 'Xác nhận dữ liệu',
                        onPressed: () => _confirmData(context, r),
                        icon: const Icon(Icons.fact_check_outlined),
                      ),
                    if (_canEdit && !r.item.isDone)
                      IconButton(
                        tooltip: 'Gia hạn / Hoàn thành',
                        onPressed: () =>
                            _run(() => completionForm(context, c, r.item)),
                        icon: const Icon(Icons.task_alt),
                      ),
                    if (_canEdit)
                      IconButton(
                        tooltip: 'Sửa hạng mục',
                        onPressed: () => _itemAction(context, r.item, 'edit'),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (_canEdit)
                      IconButton(
                        tooltip: 'Xóa hạng mục',
                        onPressed: () => _itemAction(context, r.item, 'delete'),
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  void _itemAction(BuildContext context, DeadlineItem item, String action) =>
      unawaited(
        _run(() async {
          if (action == 'edit') {
            await itemForm(context, c, item: item);
            return;
          }
          if (await confirmAction(
            context,
            'Xóa hạng mục?',
            'Hạng mục và toàn bộ lịch sử của nó sẽ bị xóa.',
            action: 'Xóa',
          )) {
            await c.deleteItem(item.id);
          }
        }),
      );
  Widget _equipment(BuildContext context) {
    final alertsByEquipment = <String, int>{};
    for (final row in c.tracked) {
      if ([
        DeadlineStatus.overdue,
        DeadlineStatus.upcoming,
      ].contains(row.status)) {
        alertsByEquipment.update(
          row.equipment.id,
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final rows =
        c.equipment
            .where(
              (e) =>
                  (management == null || e.managementStatus == management) &&
                  (group == null || group == e.group) &&
                  e.searchText.contains(search.text.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _searchField(),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _filter<String>(
                    'Nhóm',
                    group,
                    c.groups,
                    (v) => v,
                    (v) => group = v,
                  ),
                  _filter<ManagementStatus>(
                    'Trạng thái quản lý',
                    management,
                    ManagementStatus.values,
                    (v) => v.label,
                    (v) => management = v,
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _empty(
                    context,
                    'Chưa có thiết bị phù hợp',
                    'Thêm thiết bị hoặc nhập từ mẫu Excel.',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 80),
                  itemCount: rows.length,
                  itemBuilder: (context, n) {
                    final e = rows[n];
                    final alerts = alertsByEquipment[e.id] ?? 0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          child: Icon(
                            e.selfPropelled
                                ? Icons.airport_shuttle_outlined
                                : Icons.local_shipping_outlined,
                          ),
                        ),
                        title: Text(
                          e.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${e.displayPlate.isEmpty ? 'Chưa có biển số' : e.displayPlate}\n${e.group}\n${e.managementStatus.label}',
                        ),
                        isThreeLine: true,
                        trailing: alerts > 0
                            ? Badge(
                                label: Text('$alerts'),
                                child: const Icon(Icons.notifications_outlined),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: () => _details(context, e),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _details(BuildContext context, Equipment equipment) => unawaited(
    _run(() async {
      await showInstantDialog<void>(
        context: context,
        builder: (dialogContext) => ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final e =
                c.equipment.where((e) => e.id == equipment.id).firstOrNull ??
                equipment;
            final rows = c.tracked
                .where((r) => r.equipment.id == e.id)
                .toList();
            final ids = rows.map((r) => r.item.id).toSet();
            final logs = c.history.where((l) => ids.contains(l.itemId)).toList()
              ..sort((a, b) => b.doneDate.compareTo(a.doneDate));
            final details = {
              'Nhóm': e.group,
              'Loại': e.type,
              'Hãng / Model': e.brandModel,
              'Nước sản xuất': e.country,
              'Năm sản xuất': e.yearMade?.toString() ?? '',
              'Số khung': e.chassisNo,
              'Số động cơ': e.engineNo,
              'Biển kiểm soát': e.controlPlate,
              'Biển cũ': e.oldControlPlate,
              'Biển giao thông': e.roadPlate,
              'Mục đích': e.purpose,
              'Hoạt động tại': e.operatingAt,
              'Tự hành': e.selfPropelled ? 'Có' : 'Không',
              'Quản lý': e.managementStatus.label,
              'Ghi chú': e.note,
            };
            return AlertDialog(
              title: Text(e.name),
              content: SizedBox(
                width: 840,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.handyman_outlined),
                          label: const Text('Lịch sử bảo trì / sửa chữa'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ServiceHistoryPage(
                                controller: c,
                                equipment: e,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 24,
                        runSpacing: 12,
                        children: [
                          for (final d in details.entries)
                            if (d.value.isNotEmpty)
                              SizedBox(
                                width: 240,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.key,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelMedium,
                                    ),
                                    Text(d.value),
                                  ],
                                ),
                              ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      AttachmentsSection(
                        controller: c,
                        equipment: e,
                        run: _run,
                        canEdit: _canEdit,
                        opener: widget.opener,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Hạng mục theo dõi',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          if (_canEdit)
                            TextButton.icon(
                              onPressed: () => _run(
                                () => itemForm(context, c, equipmentId: e.id),
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('Thêm'),
                            ),
                        ],
                      ),
                      if (rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Chưa có hạng mục. Chỉ thêm những hạng mục áp dụng cho thiết bị.',
                          ),
                        ),
                      for (final r in rows) _deadlineCard(context, r),
                      const SizedBox(height: 16),
                      Text(
                        'Lịch sử thực hiện (${logs.length})',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (logs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Chưa có lịch sử thực hiện.'),
                        ),
                      for (final l in logs)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.history),
                          title: Text(
                            '${displayDate(l.doneDate)} • ${rows.firstWhere((r) => r.item.id == l.itemId).item.title}',
                          ),
                          subtitle: Text(
                            [
                              l.provider,
                              if (l.cost != null)
                                '${NumberFormat.decimalPattern('vi_VN').format(l.cost)} VND',
                              l.note,
                            ].where((v) => v.isNotEmpty).join(' • '),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (_canEdit)
                  TextButton(
                    onPressed: () => _run(() async {
                      if (await confirmAction(
                        context,
                        'Xóa thiết bị?',
                        'Toàn bộ hạng mục và lịch sử của ${e.name} cũng sẽ bị xóa.',
                        action: 'Xóa thiết bị',
                      )) {
                        await c.deleteEquipment(e.id);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      }
                    }),
                    child: Text(
                      'Xóa thiết bị',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_canEdit)
                  TextButton(
                    onPressed: () =>
                        _run(() => equipmentForm(context, c, equipment: e)),
                    child: const Text('Sửa thông tin'),
                  ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Đóng'),
                ),
              ],
            );
          },
        ),
      );
    }),
  );
}

class _TableSource extends DataTableSource {
  _TableSource(this.count, this.builder);
  final int count;
  final DataRow Function(int) builder;
  @override
  DataRow? getRow(int index) => index < count ? builder(index) : null;
  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => count;
  @override
  int get selectedRowCount => 0;
}

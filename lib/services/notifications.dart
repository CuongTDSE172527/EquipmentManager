import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../data/database.dart';
import '../domain/models.dart';
import '../domain/deadlines.dart';
import 'storage.dart';

const _alarmId = 6172026;
const notificationGuid = '1dc82fbb-cd57-4bb3-a0e2-cc96b4cb3d94';

@pragma('vm:entry-point')
Future<void> dailyReminder() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final db = await openAppDatabase();
  try {
    final repo = EquipmentRepository(db);
    final settings = await repo.settings();
    if (!settings.notificationsEnabled) return;
    final service = NotificationService();
    await service.initialize();
    // Re-arm before reading data, so a notification error does not lose tomorrow.
    await service.scheduleAndroid(settings);
    await service.showSummary(repo);
  } finally {
    await db.close();
  }
}

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin plugin;
  VoidCallback? _onOpen;
  Future<void> initialize({VoidCallback? onOpen}) async {
    if (onOpen != null) _onOpen = onOpen;
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        windows: WindowsInitializationSettings(
          appName: 'EquipmentManager',
          appUserModelId: 'CAH.EquipmentManager',
          guid: notificationGuid,
        ),
      ),
      onDidReceiveNotificationResponse: (_) => _onOpen?.call(),
    );
  }

  Future<bool> launchedFromNotification() async =>
      (await plugin.getNotificationAppLaunchDetails())
          ?.didNotificationLaunchApp ??
      false;

  Future<String> enable(AppSettings settings) async {
    if (Platform.isAndroid) {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()!;
      final allowed = await android.requestNotificationsPermission();
      if (allowed == false) {
        throw StateError(
          'Quyền thông báo đang tắt. Vào Cài đặt điện thoại → Ứng dụng → EquipmentManager → Thông báo để bật.',
        );
      }
      await android.requestExactAlarmsPermission();
      await AndroidAlarmManager.initialize();
      final exact = await android.canScheduleExactNotifications() ?? false;
      await scheduleAndroid(settings);
      return exact
          ? 'Đã bật lịch nhắc hằng ngày.'
          : 'Đã bật nhắc; hệ điều hành có thể nhắc trễ vì chưa cấp quyền Báo thức và lời nhắc.';
    }
    if (Platform.isWindows) {
      await _windowsTask(settings, true);
      return 'Đã đăng ký nhắc hằng ngày với Windows Task Scheduler.';
    }
    return 'Nền tảng chưa hỗ trợ nhắc hạn.';
  }

  Future<void> disable(AppSettings settings) async {
    if (Platform.isAndroid) {
      await AndroidAlarmManager.cancel(_alarmId);
    }
    if (Platform.isWindows) {
      await _windowsTask(settings, false);
    }
  }

  Future<void> scheduleAndroid(AppSettings settings) async {
    final now = DateTime.now();
    var next = DateTime(
      now.year,
      now.month,
      now.day,
      settings.notifyHour,
      settings.notifyMinute,
    );
    if (!next.isAfter(now)) {
      next = DateTime(
        now.year,
        now.month,
        now.day + 1,
        settings.notifyHour,
        settings.notifyMinute,
      );
    }
    final exact =
        await plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.canScheduleExactNotifications() ??
        false;
    final ok = await AndroidAlarmManager.oneShotAt(
      next,
      _alarmId,
      dailyReminder,
      exact: exact,
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );
    if (!ok) throw StateError('Không đăng ký được lịch nhắc Android.');
  }

  Future<void> refresh(AppSettings settings) async {
    if (!settings.notificationsEnabled) return;
    if (Platform.isAndroid) {
      await AndroidAlarmManager.initialize();
      await scheduleAndroid(settings);
    }
    if (Platform.isWindows) await _windowsTask(settings, true);
  }

  Future<void> showSummary(
    EquipmentRepository repo, {
    bool test = false,
  }) async {
    final now = DateTime.now();
    final settings = await repo.settings();
    final receipt = File(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'last-notification.txt',
      ),
    );
    final today = '${now.year}-${now.month}-${now.day}';
    if (!test) {
      final scheduled = DateTime(
        now.year,
        now.month,
        now.day,
        settings.notifyHour,
        settings.notifyMinute,
      );
      if (now.isBefore(scheduled)) return;
      if (await receipt.exists() && (await receipt.readAsString()) == today) {
        return;
      }
    }
    final rows = trackedDeadlines(
      await repo.equipment(),
      await repo.items(),
      await repo.settings(),
      DateTime.now(),
    );
    final overdue = rows
        .where((r) => r.status == DeadlineStatus.overdue)
        .length;
    final upcoming = rows
        .where((r) => r.status == DeadlineStatus.upcoming)
        .length;
    if (!test && overdue + upcoming == 0) return;
    await plugin.show(
      id: 100,
      title: 'EquipmentManager • Nhắc hạn TTB',
      body: test
          ? 'Thông báo thử. $overdue quá hạn, $upcoming sắp đến hạn.'
          : '$overdue quá hạn, $upcoming sắp đến hạn',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'equipment_deadlines',
          'Nhắc hạn trang thiết bị',
          channelDescription: 'Tổng hợp các hạng mục quá hạn và sắp đến hạn',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: 'alerts',
    );
    if (!test) await receipt.writeAsString(today, flush: true);
  }

  Future<void> _windowsTask(AppSettings settings, bool enabled) async {
    // A UTF-16 encoded script avoids shell interpolation of executable paths.
    final exe = Platform.resolvedExecutable.replaceAll("'", "''");
    final time =
        '${settings.notifyHour.toString().padLeft(2, '0')}:${settings.notifyMinute.toString().padLeft(2, '0')}';
    final script = enabled
        ? '''
\$ErrorActionPreference='Stop'
\$identity=[System.Security.Principal.WindowsIdentity]::GetCurrent().Name
\$taskName='EquipmentManager-'+[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
\$action=New-ScheduledTaskAction -Execute '$exe' -Argument '--notify-only' -WorkingDirectory ([IO.Path]::GetDirectoryName('$exe'))
\$daily=New-ScheduledTaskTrigger -Daily -At '$time'
\$login=New-ScheduledTaskTrigger -AtLogOn -User \$identity
\$principal=New-ScheduledTaskPrincipal -UserId \$identity -LogonType Interactive -RunLevel Limited
\$options=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
Register-ScheduledTask -TaskName \$taskName -Action \$action -Trigger @(\$daily,\$login) -Principal \$principal -Settings \$options -Force | Out-Null
'''
        : r'''
$ErrorActionPreference='Stop'
$taskName='EquipmentManager-'+[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if($task){Unregister-ScheduledTask -TaskName $taskName -Confirm:$false}
''';
    final bytes = <int>[];
    for (final c in script.codeUnits) {
      bytes.add(c & 255);
      bytes.add(c >> 8);
    }
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-EncodedCommand',
      base64Encode(bytes),
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'Windows chưa cho đăng ký lịch nhắc. Chi tiết: ${result.stderr}',
      );
    }
  }
}

// Isolated emulator harness. Never used as the product's release entry point.
import 'dart:io';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:equipment_manager/data/database.dart';
import 'package:equipment_manager/domain/models.dart';
import 'package:equipment_manager/services/storage.dart';
import 'package:equipment_manager/services/notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openAppDatabase();
  final repo = EquipmentRepository(db);
  final equipment = Equipment(name: 'KIỂM THỬ NHẮC HẠN TRÊN EMULATOR');
  await repo.saveEquipment(equipment);
  await repo.saveItem(
    DeadlineItem(
      equipmentId: equipment.id,
      kind: ItemKind.inspection,
      title: 'Hạng mục kiểm thử',
      dueDate: DateTime.now().subtract(const Duration(days: 1)),
    ),
  );
  await repo.saveSettings(
    const AppSettings(
      notificationsEnabled: true,
      notifyHour: 0,
      notifyMinute: 0,
    ),
  );
  await db.close();
  final service = NotificationService();
  await service.initialize();
  await AndroidAlarmManager.initialize();
  final ok = await AndroidAlarmManager.oneShotAt(
    DateTime.now().add(const Duration(seconds: 45)),
    6172026,
    dailyReminder,
    exact: true,
    wakeup: true,
    allowWhileIdle: true,
    rescheduleOnReboot: true,
  );
  if (!ok) throw StateError('Không đăng ký được alarm trong harness.');
  await File(
    p.join((await getApplicationSupportDirectory()).path, 'smoke-ready.txt'),
  ).writeAsString('ARMED', flush: true);
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Đã đặt lịch kiểm thử; host sẽ đóng tiến trình trước khi alarm chạy.',
          ),
        ),
      ),
    ),
  );
}

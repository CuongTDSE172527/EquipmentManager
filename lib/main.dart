import 'dart:io';
import 'package:flutter/material.dart';
import 'data/database.dart';
import 'services/auto_backup.dart';
import 'services/storage.dart';
import 'services/notifications.dart';
import 'ui/controller.dart';
import 'ui/app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final db = await openAppDatabase();
    final controller = AppController(EquipmentRepository(db));
    await controller.load();
    final notifications = NotificationService();
    if (args.contains('--notify-only')) {
      try {
        if (controller.settings.notificationsEnabled) {
          await notifications.initialize();
          await notifications.showSummary(controller.repository);
        }
      } finally {
        controller.dispose();
        await db.close();
      }
      exit(0);
    }
    runApp(
      EquipmentManagerApp(
        controller: controller,
        notifications: notifications,
        autoBackup: AutoBackupService(),
      ),
    );
  } catch (error) {
    if (args.contains('--notify-only')) exit(1);
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Không mở được dữ liệu EquipmentManager.\n$error\n\nHãy kiểm tra quyền ghi thư mục ứng dụng và dung lượng ổ đĩa.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

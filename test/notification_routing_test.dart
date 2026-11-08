import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:equipment_manager/services/notifications.dart';

class FakeNotificationPlugin implements FlutterLocalNotificationsPlugin {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  DidReceiveNotificationResponseCallback? callback;
  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    callback = onDidReceiveNotificationResponse;
    return true;
  }
}

void main() {
  test(
    'Gửi thông báo thử không làm mất handler mở danh sách cảnh báo',
    () async {
      final plugin = FakeNotificationPlugin();
      final service = NotificationService(plugin: plugin);
      var opened = 0;
      await service.initialize(onOpen: () => opened++);
      await service.initialize();
      plugin.callback!(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'alerts',
        ),
      );
      expect(opened, 1);
    },
  );
}

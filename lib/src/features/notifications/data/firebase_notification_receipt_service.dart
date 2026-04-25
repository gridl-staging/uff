import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:uff/src/features/notifications/data/notification_receipt_service.dart';

/// Firebase-backed adapter that maps RemoteMessage into ReceivedNotification.
///
/// On iOS, FCM swizzles UNUserNotificationCenterDelegate so both onMessage and
/// onMessageOpenedApp fire for APNs deliveries that route through Firebase.
/// On Android, onMessage fires for payloads delivered to the app process and
/// onMessageOpenedApp fires when the user taps the tray notification.
///
/// Known gap: notifications that launch the app from a terminated state do
/// not arrive via onMessageOpenedApp. `FirebaseMessaging.instance.getInitialMessage()`
/// is the correct API for that case. The v1 seam does not handle terminated-
/// launch receipts because active delivery proof is a post-v1 follow-up, and
/// the baseline smoke assertion does not exercise that path. When active
/// delivery proof lands, extend this adapter with getInitialMessage support
/// and add a matching entry on the NotificationReceiptService interface.
class FirebaseNotificationReceiptService implements NotificationReceiptService {
  const FirebaseNotificationReceiptService();

  @override
  Stream<ReceivedNotification> onForegroundMessage() {
    return FirebaseMessaging.onMessage.map(
      (message) => _toReceivedNotification(
        message,
        NotificationDeliveryType.foreground,
      ),
    );
  }

  @override
  Stream<ReceivedNotification> onNotificationOpened() {
    return FirebaseMessaging.onMessageOpenedApp.map(
      (message) => _toReceivedNotification(
        message,
        NotificationDeliveryType.opened,
      ),
    );
  }
}

ReceivedNotification _toReceivedNotification(
  RemoteMessage message,
  NotificationDeliveryType deliveryType,
) {
  final notification = message.notification;
  return ReceivedNotification(
    receivedAt: DateTime.now().toUtc(),
    deliveryType: deliveryType,
    messageId: message.messageId,
    title: notification?.title,
    body: notification?.body,
    data: Map<String, Object?>.from(message.data),
  );
}

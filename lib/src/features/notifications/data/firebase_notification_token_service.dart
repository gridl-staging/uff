import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:uff/src/features/notifications/data/notification_token_service.dart';

/// Firebase-backed notification token IO implementation.
class FirebaseNotificationTokenService implements NotificationTokenService {
  FirebaseNotificationTokenService({
    FirebaseMessaging? firebaseMessaging,
  }) : _firebaseMessaging = firebaseMessaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _firebaseMessaging;

  @override
  Future<String?> getToken() {
    return _firebaseMessaging.getToken();
  }

  @override
  Stream<String> onTokenRefresh() {
    return _firebaseMessaging.onTokenRefresh;
  }

  @override
  Future<void> requestPermission() async {
    await _firebaseMessaging.requestPermission();
  }
}

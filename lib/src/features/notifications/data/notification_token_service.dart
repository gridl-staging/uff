abstract interface class NotificationTokenService {
  Future<void> requestPermission();

  Future<String?> getToken();

  Stream<String> onTokenRefresh();
}

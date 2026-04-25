import 'dart:async';

import 'package:uff/src/features/notifications/data/notification_token_service.dart';

/// NOTE(stuart): Document FakeNotificationTokenService.
class FakeNotificationTokenService implements NotificationTokenService {
  FakeNotificationTokenService() {
    _refreshController = StreamController<String>.broadcast(
      onListen: () {
        refreshListenerCount++;
      },
      onCancel: () {
        refreshCancelCount++;
      },
    );
  }

  late final StreamController<String> _refreshController;

  int requestPermissionCallCount = 0;
  int getTokenCallCount = 0;
  int refreshListenerCount = 0;
  int refreshCancelCount = 0;
  String? tokenToReturn;
  Completer<String?>? pendingTokenCompleter;
  final List<String> callOrder = <String>[];

  /// When set, `requestPermission()` throws this error instead of succeeding.
  Object? throwOnRequestPermissionError;

  @override
  Future<String?> getToken() async {
    getTokenCallCount++;
    callOrder.add('getToken');
    final pendingCompleter = pendingTokenCompleter;
    if (pendingCompleter != null) {
      return pendingCompleter.future;
    }
    return tokenToReturn;
  }

  @override
  Stream<String> onTokenRefresh() {
    return _refreshController.stream;
  }

  @override
  Future<void> requestPermission() async {
    requestPermissionCallCount++;
    callOrder.add('requestPermission');
    final errorToThrow = throwOnRequestPermissionError;
    if (errorToThrow != null) {
      // ignore: only_throw_errors -- Test fake re-throws caller-supplied Object.
      throw errorToThrow;
    }
  }

  void emitRefreshToken(String token) {
    _refreshController.add(token);
  }

  Future<void> dispose() async {
    await _refreshController.close();
  }
}

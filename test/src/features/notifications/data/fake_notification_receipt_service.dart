import 'dart:async';

import 'package:uff/src/features/notifications/data/notification_receipt_service.dart';

/// Test double for [NotificationReceiptService].
///
/// Exposes broadcast controllers so tests can emit synthetic foreground and
/// opened messages and assert against downstream observers.
class FakeNotificationReceiptService implements NotificationReceiptService {
  FakeNotificationReceiptService()
    : _foregroundController =
          StreamController<ReceivedNotification>.broadcast(),
      _openedController = StreamController<ReceivedNotification>.broadcast();

  final StreamController<ReceivedNotification> _foregroundController;
  final StreamController<ReceivedNotification> _openedController;

  int foregroundListenerCount = 0;
  int openedListenerCount = 0;

  /// When set, `onForegroundMessage()` throws this error synchronously.
  Object? throwOnForegroundAccess;

  /// When set, `onNotificationOpened()` throws this error synchronously.
  Object? throwOnOpenedAccess;

  @override
  Stream<ReceivedNotification> onForegroundMessage() {
    final error = throwOnForegroundAccess;
    if (error != null) {
      // ignore: only_throw_errors -- Test fake re-throws caller-supplied Object.
      throw error;
    }
    foregroundListenerCount++;
    return _foregroundController.stream;
  }

  @override
  Stream<ReceivedNotification> onNotificationOpened() {
    final error = throwOnOpenedAccess;
    if (error != null) {
      // ignore: only_throw_errors -- Test fake re-throws caller-supplied Object.
      throw error;
    }
    openedListenerCount++;
    return _openedController.stream;
  }

  void emitForeground(ReceivedNotification message) {
    _foregroundController.add(message);
  }

  void emitOpened(ReceivedNotification message) {
    _openedController.add(message);
  }

  Future<void> dispose() async {
    await _foregroundController.close();
    await _openedController.close();
  }
}

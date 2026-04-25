import 'dart:async';

import 'package:meta/meta.dart';

/// How a notification reached the app.
enum NotificationDeliveryType {
  /// Delivered while the app was in the foreground.
  foreground,

  /// Delivered via a tap that opened the app from background or terminated state.
  opened,
}

/// Snapshot of a notification observed by the app.
///
/// Mirrors the fields the receipt seam needs from platform push payloads,
/// decoupled from Firebase types so tests can construct and compare instances
/// without pulling in FirebaseMessaging.
@immutable
class ReceivedNotification {
  ReceivedNotification({
    required this.receivedAt,
    required this.deliveryType,
    this.messageId,
    this.title,
    this.body,
    Map<String, Object?>? data,
  }) : data = Map<String, Object?>.unmodifiable(
         data ?? const <String, Object?>{},
       );

  final DateTime receivedAt;
  final NotificationDeliveryType deliveryType;
  final String? messageId;
  final String? title;
  final String? body;
  final Map<String, Object?> data;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ReceivedNotification) return false;
    if (other.receivedAt != receivedAt) return false;
    if (other.deliveryType != deliveryType) return false;
    if (other.messageId != messageId) return false;
    if (other.title != title) return false;
    if (other.body != body) return false;
    if (other.data.length != data.length) return false;
    for (final entry in data.entries) {
      if (other.data[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    receivedAt,
    deliveryType,
    messageId,
    title,
    body,
    data.length,
  );

  @override
  String toString() =>
      'ReceivedNotification('
      'deliveryType: $deliveryType, '
      'messageId: $messageId, '
      'title: $title, '
      'receivedAt: $receivedAt)';
}

/// Platform-neutral seam for observing push notification receipt.
///
/// Foreground stream fires when a notification arrives while the app is
/// active. Opened stream fires when the user taps a notification and the app
/// routes the tap to the app (background or terminated launches).
abstract interface class NotificationReceiptService {
  Stream<ReceivedNotification> onForegroundMessage();

  Stream<ReceivedNotification> onNotificationOpened();
}

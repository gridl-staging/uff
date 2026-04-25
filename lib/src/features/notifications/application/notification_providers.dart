import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/notifications/data/firebase_notification_receipt_service.dart';
import 'package:uff/src/features/notifications/data/firebase_notification_token_service.dart';
import 'package:uff/src/features/notifications/data/notification_receipt_service.dart';
import 'package:uff/src/features/notifications/data/notification_service.dart';
import 'package:uff/src/features/notifications/data/notification_token_service.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';

final notificationTokenServiceProvider = Provider<NotificationTokenService>((
  ref,
) {
  return FirebaseNotificationTokenService();
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final notificationService = NotificationService(
    notificationTokenService: ref.watch(notificationTokenServiceProvider),
    profileRepository: ref.watch(profileRepositoryProvider),
  );
  ref.onDispose(() {
    unawaited(notificationService.dispose());
  });
  return notificationService;
});

final notificationRegistrarProvider = FutureProvider<void>((ref) async {
  final notificationService = ref.watch(notificationServiceProvider);
  final authState = ref.watch(authProvider).asData?.value;

  switch (authState) {
    case Authenticated():
      await notificationService.syncAuthenticatedSession();
    case _:
      await notificationService.stopForUnauthenticatedSession();
  }
});

final notificationReceiptServiceProvider = Provider<NotificationReceiptService>(
  (ref) {
    return const FirebaseNotificationReceiptService();
  },
);

/// Tracks the most recently observed push notification delivery.
///
/// State is `null` until a notification arrives via either foreground
/// delivery or a tap that opened the app. Later deliveries replace older
/// state with latest-wins semantics. The receipt Semantics bootstrap reads
/// this state so automated device-lane tests can assert truthful end-to-end
/// receipt.
class NotificationReceiptNotifier extends Notifier<ReceivedNotification?> {
  @override
  ReceivedNotification? build() {
    final service = ref.watch(notificationReceiptServiceProvider);
    // Wrap both the service access and the stream subscription in fault
    // isolation so a Firebase-not-initialized path (SKIP_FIREBASE=true,
    // platform channel unavailable) leaves the notifier in its initial
    // `null` state instead of propagating an error up the provider tree.
    // The receipt Semantics reads "none" in that case, which is the
    // truthful no-delivery-observed state.
    StreamSubscription<ReceivedNotification>? foregroundSub;
    StreamSubscription<ReceivedNotification>? openedSub;
    try {
      foregroundSub = service.onForegroundMessage().listen(
        (message) {
          state = message;
        },
        onError: (Object _, StackTrace __) {},
      );
      openedSub = service.onNotificationOpened().listen(
        (message) {
          state = message;
        },
        onError: (Object _, StackTrace __) {},
      );
    } on Object {
      unawaited(foregroundSub?.cancel());
      unawaited(openedSub?.cancel());
      foregroundSub = null;
      openedSub = null;
    }
    ref.onDispose(() {
      unawaited(foregroundSub?.cancel());
      unawaited(openedSub?.cancel());
    });
    return null;
  }
}

final notificationReceiptProvider =
    NotifierProvider<NotificationReceiptNotifier, ReceivedNotification?>(
      NotificationReceiptNotifier.new,
    );

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/notifications/application/notification_providers.dart';
import 'package:uff/src/features/notifications/data/notification_receipt_service.dart';

import '../data/fake_notification_receipt_service.dart';

/// ## Test Scenarios
/// - `[edge]` Initial receipt state is null before any message is emitted.
/// - `[positive]` Provider publishes the latest ReceivedNotification after a foreground emission.
/// - `[positive]` Provider publishes the latest ReceivedNotification after an opened emission.
/// - `[edge]` Successive emissions replace the prior state (latest-wins).
/// - `[negative]` Emissions on a service after its owning container is disposed must not update any state reachable from a fresh container.
/// - `[negative]` Service-side subscription errors (SKIP_FIREBASE=true or Firebase unavailable) leave the notifier in initial null state without propagating an error.
/// - `[isolation]` Disposing the provider container cancels the receipt subscriptions with no cross-container leakage.
void main() {
  late FakeNotificationReceiptService fakeService;

  setUp(() {
    fakeService = FakeNotificationReceiptService();
  });

  tearDown(() async {
    await fakeService.dispose();
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        notificationReceiptServiceProvider.overrideWithValue(fakeService),
      ],
    );
  }

  test('initial state is null before any message arrives', () {
    final container = makeContainer();
    addTearDown(container.dispose);

    expect(container.read(notificationReceiptProvider), isNull);
  });

  test('publishes latest foreground message into provider state', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    // Ensure the notifier has subscribed before emitting.
    container.read(notificationReceiptProvider);
    await Future<void>.delayed(Duration.zero);

    final now = DateTime.utc(2026, 4, 24, 12, 0, 0);
    final message = ReceivedNotification(
      receivedAt: now,
      deliveryType: NotificationDeliveryType.foreground,
      messageId: 'fg-1',
      title: 'Kudos!',
      body: 'Alex gave you kudos',
      data: const <String, Object?>{'type': 'kudos', 'activity_id': '42'},
    );

    fakeService.emitForeground(message);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(notificationReceiptProvider);
    expect(state?.messageId, 'fg-1');
    expect(state?.deliveryType, NotificationDeliveryType.foreground);
    expect(state?.title, 'Kudos!');
    expect(state?.body, 'Alex gave you kudos');
    expect(state?.data['type'], 'kudos');
    expect(state?.data['activity_id'], '42');
    expect(state?.receivedAt, now);
  });

  test('publishes latest opened message into provider state', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    container.read(notificationReceiptProvider);
    await Future<void>.delayed(Duration.zero);

    final now = DateTime.utc(2026, 4, 24, 12, 5, 0);
    final message = ReceivedNotification(
      receivedAt: now,
      deliveryType: NotificationDeliveryType.opened,
      messageId: 'op-7',
      title: 'New follower',
      body: 'Taylor followed you',
      data: const <String, Object?>{'type': 'follow', 'actor_id': 'u-99'},
    );

    fakeService.emitOpened(message);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(notificationReceiptProvider);
    expect(state?.messageId, 'op-7');
    expect(state?.deliveryType, NotificationDeliveryType.opened);
    expect(state?.data['type'], 'follow');
    expect(state?.data['actor_id'], 'u-99');
    expect(state?.receivedAt, now);
  });

  test('latest emission replaces prior state (latest-wins)', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    container.read(notificationReceiptProvider);
    await Future<void>.delayed(Duration.zero);

    final first = ReceivedNotification(
      receivedAt: DateTime.utc(2026, 4, 24, 12, 0, 0),
      deliveryType: NotificationDeliveryType.foreground,
      messageId: 'first',
    );
    final second = ReceivedNotification(
      receivedAt: DateTime.utc(2026, 4, 24, 12, 0, 5),
      deliveryType: NotificationDeliveryType.opened,
      messageId: 'second',
    );
    final third = ReceivedNotification(
      receivedAt: DateTime.utc(2026, 4, 24, 12, 0, 10),
      deliveryType: NotificationDeliveryType.foreground,
      messageId: 'third',
    );

    fakeService
      ..emitForeground(first)
      ..emitOpened(second)
      ..emitForeground(third);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(notificationReceiptProvider);
    expect(state?.messageId, 'third');
    expect(state?.deliveryType, NotificationDeliveryType.foreground);
    expect(state?.receivedAt, DateTime.utc(2026, 4, 24, 12, 0, 10));
  });

  test(
    'service-side subscription error leaves state at initial null',
    () async {
      fakeService.throwOnForegroundAccess = StateError(
        'Firebase not initialized',
      );
      fakeService.throwOnOpenedAccess = StateError(
        'Firebase not initialized',
      );

      final container = makeContainer();
      addTearDown(container.dispose);

      expect(container.read(notificationReceiptProvider), isNull);
      // Clearing the errors and emitting after the fact must not recover the
      // subscription because it was never established. State stays null.
      fakeService.throwOnForegroundAccess = null;
      fakeService.emitForeground(
        ReceivedNotification(
          receivedAt: DateTime.utc(2026, 4, 24, 13, 0, 0),
          deliveryType: NotificationDeliveryType.foreground,
          messageId: 'after-error',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(notificationReceiptProvider), isNull);
    },
  );

  test(
    'disposing container cancels subscriptions without cross-leakage',
    () async {
      final firstContainer = makeContainer();

      firstContainer.read(notificationReceiptProvider);
      await Future<void>.delayed(Duration.zero);
      expect(fakeService.foregroundListenerCount, 1);
      expect(fakeService.openedListenerCount, 1);

      firstContainer.dispose();

      final secondContainer = makeContainer();
      addTearDown(secondContainer.dispose);

      secondContainer.read(notificationReceiptProvider);
      await Future<void>.delayed(Duration.zero);
      expect(fakeService.foregroundListenerCount, 2);
      expect(fakeService.openedListenerCount, 2);

      // Messages emitted after firstContainer disposal must only update
      // secondContainer state.
      final postDisposal = ReceivedNotification(
        receivedAt: DateTime.utc(2026, 4, 24, 12, 30, 0),
        deliveryType: NotificationDeliveryType.foreground,
        messageId: 'post-disposal',
      );
      fakeService.emitForeground(postDisposal);
      await Future<void>.delayed(Duration.zero);

      expect(
        secondContainer.read(notificationReceiptProvider)?.messageId,
        'post-disposal',
      );
    },
  );
}

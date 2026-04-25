import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/main.dart' as app;
import 'package:uff/src/features/notifications/application/notification_providers.dart';
import 'package:uff/src/features/notifications/data/notification_receipt_service.dart';

import '../data/fake_notification_receipt_service.dart';

/// ## Test Scenarios
/// - `[positive]` Bootstrap renders the wrapped child when registrar state is synced.
/// - `[error]` Bootstrap renders the wrapped child when registrar state is error.
/// - `[edge]` Bootstrap renders the wrapped child while registrar state is loading.
/// - `[positive]` Bootstrap emits a deterministic semantics identifier for synced/error/loading states.
/// - `[negative]` Bootstrap does not crash or block rendering when provider enters error state (SKIP_FIREBASE degradation).
/// - `[isolation]` Each provider state override produces an independent, deterministic Semantics identifier with no cross-state leakage.
/// - `[positive]` Receipt Semantics starts at `notification-receipt-none` with empty value before any delivery.
/// - `[positive]` Foreground receipt flips identifier to `notification-receipt-present` and exposes the messageId via Semantics.value.
/// - `[positive]` Opened receipt flips identifier to `notification-receipt-present` and exposes the messageId via Semantics.value.
void main() {
  testWidgets('renders child with synced semantics when registrar completes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRegistrarProvider.overrideWith((ref) async {}),
        ],
        child: MaterialApp(
          home: app.buildNotificationRegistrarBootstrapForTesting(
            child: const Text('bootstrap-child'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('bootstrap-child'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier('notification-status-synced'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('renders child with error semantics when registrar throws', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRegistrarProvider.overrideWith((ref) {
            throw StateError('sync failed');
          }),
        ],
        child: MaterialApp(
          home: app.buildNotificationRegistrarBootstrapForTesting(
            child: const Text('bootstrap-child'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('bootstrap-child'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier('notification-status-error'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('renders child with loading semantics while registrar pending', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final pendingSync = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRegistrarProvider.overrideWith(
            (ref) => pendingSync.future,
          ),
        ],
        child: MaterialApp(
          home: app.buildNotificationRegistrarBootstrapForTesting(
            child: const Text('bootstrap-child'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('bootstrap-child'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier('notification-status-loading'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('receipt semantics starts at none with empty value', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final fakeService = FakeNotificationReceiptService();
    addTearDown(fakeService.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRegistrarProvider.overrideWith((ref) async {}),
          notificationReceiptServiceProvider.overrideWithValue(fakeService),
        ],
        child: MaterialApp(
          home: app.buildNotificationRegistrarBootstrapForTesting(
            child: const Text('bootstrap-child'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier('notification-receipt-none'),
      findsOneWidget,
    );
    final noneNode = tester.getSemantics(
      find.bySemanticsIdentifier('notification-receipt-none'),
    );
    expect(noneNode.value, '');
    handle.dispose();
  });

  testWidgets(
    'foreground receipt flips identifier to present and exposes messageId',
    (tester) async {
      final handle = tester.ensureSemantics();
      final fakeService = FakeNotificationReceiptService();
      addTearDown(fakeService.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationRegistrarProvider.overrideWith((ref) async {}),
            notificationReceiptServiceProvider.overrideWithValue(fakeService),
          ],
          child: MaterialApp(
            home: app.buildNotificationRegistrarBootstrapForTesting(
              child: const Text('bootstrap-child'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      fakeService.emitForeground(
        ReceivedNotification(
          receivedAt: DateTime.utc(2026, 4, 24, 12, 0, 0),
          deliveryType: NotificationDeliveryType.foreground,
          messageId: 'fg-msg-1',
          title: 'Kudos',
          body: 'Alex gave you kudos',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('notification-receipt-present'),
        findsOneWidget,
      );
      final presentNode = tester.getSemantics(
        find.bySemanticsIdentifier('notification-receipt-present'),
      );
      expect(presentNode.value, 'fg-msg-1');
      handle.dispose();
    },
  );

  testWidgets(
    'opened receipt flips identifier to present and exposes messageId',
    (tester) async {
      final handle = tester.ensureSemantics();
      final fakeService = FakeNotificationReceiptService();
      addTearDown(fakeService.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationRegistrarProvider.overrideWith((ref) async {}),
            notificationReceiptServiceProvider.overrideWithValue(fakeService),
          ],
          child: MaterialApp(
            home: app.buildNotificationRegistrarBootstrapForTesting(
              child: const Text('bootstrap-child'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      fakeService.emitOpened(
        ReceivedNotification(
          receivedAt: DateTime.utc(2026, 4, 24, 12, 5, 0),
          deliveryType: NotificationDeliveryType.opened,
          messageId: 'open-msg-9',
          title: 'New follower',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('notification-receipt-present'),
        findsOneWidget,
      );
      final presentNode = tester.getSemantics(
        find.bySemanticsIdentifier('notification-receipt-present'),
      );
      expect(presentNode.value, 'open-msg-9');
      handle.dispose();
    },
  );
}

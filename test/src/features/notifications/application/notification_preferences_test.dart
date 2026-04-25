import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uff/src/core/theme/theme_providers.dart';
import 'package:uff/src/features/notifications/application/notification_preferences.dart';

/// ## Test Scenarios
/// - [positive] Default preference is true when no stored value exists
/// - [positive] Stored false preference is loaded correctly
/// - [positive] Toggle persists updated value to SharedPreferences
/// - [negative] Provider reads notification pref, not unrelated keys
/// - [isolation] Fresh container with cleared prefs returns default

Future<void> _waitForNotificationPreference(
  ProviderContainer container, {
  required bool expectedValue,
}) async {
  final completer = Completer<void>();
  final subscription = container.listen<bool>(notificationPreferencesProvider, (
    previous,
    next,
  ) {
    if (next == expectedValue && !completer.isCompleted) {
      completer.complete();
    }
  }, fireImmediately: true);
  await completer.future.timeout(const Duration(seconds: 1));
  subscription.close();
}

Future<void> _allowAsyncHydration() async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

// ## Test Scenarios
// - [positive] Defaults to enabled (`true`) when no value is persisted.
// - [positive] Hydrates persisted enabled value on a fresh container.
// - [positive] Hydrates persisted disabled value on a fresh container.
// - [isolation] Fresh containers seeded from the same mocked persistence hydrate independently.
// - [error] Persistence failures keep in-memory toggled state stable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('notificationPreferencesProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('defaults to true when no preference is persisted', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(notificationPreferencesProvider), true);
    });

    test('hydrates persisted true on a fresh container', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        notificationPreferencesEnabledKey: true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _waitForNotificationPreference(container, expectedValue: true);

      expect(container.read(notificationPreferencesProvider), true);

      final restartedContainer = ProviderContainer();
      addTearDown(restartedContainer.dispose);
      await _waitForNotificationPreference(
        restartedContainer,
        expectedValue: true,
      );
      expect(restartedContainer.read(notificationPreferencesProvider), true);
    });

    test('hydrates persisted false on a fresh container', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        notificationPreferencesEnabledKey: false,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _waitForNotificationPreference(container, expectedValue: false);

      expect(container.read(notificationPreferencesProvider), false);

      final restartedContainer = ProviderContainer();
      addTearDown(restartedContainer.dispose);
      await _waitForNotificationPreference(
        restartedContainer,
        expectedValue: false,
      );
      expect(restartedContainer.read(notificationPreferencesProvider), false);
    });

    test(
      'setNotificationsEnabled keeps in-memory state when writes fail',
      () async {
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesLoaderProvider.overrideWithValue(
              () => Future<SharedPreferences>.error(
                StateError('shared preferences unavailable'),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(notificationPreferencesProvider.notifier)
            .setNotificationsEnabled(isEnabled: false);
        await _allowAsyncHydration();
        expect(container.read(notificationPreferencesProvider), false);

        await container
            .read(notificationPreferencesProvider.notifier)
            .setNotificationsEnabled(isEnabled: true);
        await _allowAsyncHydration();
        expect(container.read(notificationPreferencesProvider), true);
      },
    );
  });
}

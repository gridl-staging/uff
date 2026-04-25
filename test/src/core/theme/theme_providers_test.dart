import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uff/src/core/theme/theme_providers.dart';

Future<void> _waitForThemeMode(
  ProviderContainer container,
  ThemeMode expected,
) async {
  final completer = Completer<void>();
  final subscription = container.listen<ThemeMode>(
    themeModeProvider,
    (previous, next) {
      if (next == expected && !completer.isCompleted) {
        completer.complete();
      }
    },
    fireImmediately: true,
  );

  await completer.future.timeout(const Duration(seconds: 1));
  subscription.close();
}

Future<void> _allowThemeAsyncWork() async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('themeModeProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('defaults to ThemeMode.system when no value is persisted', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('restores ThemeMode.dark from persisted value', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_theme_mode': ThemeMode.dark.name,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _waitForThemeMode(container, ThemeMode.dark);

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test(
      'setThemeMode persists non-system values across container restarts',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container
            .read(themeModeProvider.notifier)
            .setThemeMode(
              ThemeMode.light,
            );

        expect(container.read(themeModeProvider), ThemeMode.light);

        final restartedContainer = ProviderContainer();
        addTearDown(restartedContainer.dispose);

        await _waitForThemeMode(restartedContainer, ThemeMode.light);

        expect(restartedContainer.read(themeModeProvider), ThemeMode.light);
      },
    );

    test('setThemeMode(ThemeMode.system) clears persisted override', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(themeModeProvider.notifier)
          .setThemeMode(
            ThemeMode.dark,
          );
      await container
          .read(themeModeProvider.notifier)
          .setThemeMode(
            ThemeMode.system,
          );

      expect(container.read(themeModeProvider), ThemeMode.system);

      final restartedContainer = ProviderContainer();
      addTearDown(restartedContainer.dispose);

      expect(restartedContainer.read(themeModeProvider), ThemeMode.system);
    });

    test(
      'local selection wins if set before persisted hydration finishes',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'app_theme_mode': ThemeMode.dark.name,
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container
            .read(themeModeProvider.notifier)
            .setThemeMode(
              ThemeMode.light,
            );
        await _allowThemeAsyncWork();

        expect(container.read(themeModeProvider), ThemeMode.light);

        final restartedContainer = ProviderContainer();
        addTearDown(restartedContainer.dispose);

        await _waitForThemeMode(restartedContainer, ThemeMode.light);

        expect(restartedContainer.read(themeModeProvider), ThemeMode.light);
      },
    );

    test('immediate system selection clears stale persisted value', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_theme_mode': ThemeMode.dark.name,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(themeModeProvider.notifier)
          .setThemeMode(
            ThemeMode.system,
          );
      await _allowThemeAsyncWork();

      expect(container.read(themeModeProvider), ThemeMode.system);

      final restartedContainer = ProviderContainer();
      addTearDown(restartedContainer.dispose);

      expect(restartedContainer.read(themeModeProvider), ThemeMode.system);
    });

    test(
      'setThemeMode keeps in-memory selection when persistence fails',
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
            .read(themeModeProvider.notifier)
            .setThemeMode(
              ThemeMode.dark,
            );
        await _allowThemeAsyncWork();

        expect(container.read(themeModeProvider), ThemeMode.dark);
      },
    );

    test('hydration failures keep ThemeMode.system without crashing', () async {
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

      expect(container.read(themeModeProvider), ThemeMode.system);
      await _allowThemeAsyncWork();
      expect(container.read(themeModeProvider), ThemeMode.system);
    });
  });
}

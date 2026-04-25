import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uff/src/core/theme/theme_providers.dart';

part 'notification_preferences.g.dart';

const notificationPreferencesEnabledKey = 'notifications_enabled';

/// App-facing source of truth for local notifications preference state.
@Riverpod(keepAlive: true)
class NotificationPreferencesNotifier
    extends _$NotificationPreferencesNotifier {
  bool _hasLocalOverride = false;
  Future<SharedPreferences>? _sharedPreferencesFuture;

  @override
  bool build() {
    unawaited(_hydratePersistedPreference());
    return true;
  }

  Future<void> setNotificationsEnabled({required bool isEnabled}) async {
    _hasLocalOverride = true;
    if (state != isEnabled) {
      state = isEnabled;
    }

    try {
      final preferences = await _sharedPreferences();
      await preferences.setBool(notificationPreferencesEnabledKey, isEnabled);
    } on Object {
      // Keep the in-memory setting stable when persistence is unavailable.
    }
  }

  Future<void> _hydratePersistedPreference() async {
    try {
      final preferences = await _sharedPreferences();
      if (_hasLocalOverride) {
        return;
      }

      final persistedValue = preferences.getBool(
        notificationPreferencesEnabledKey,
      );
      if (persistedValue == null || state == persistedValue) {
        return;
      }

      state = persistedValue;
    } on Object {
      // Fall back to enabled when hydration fails.
    }
  }

  Future<SharedPreferences> _sharedPreferences() {
    final cachedFuture = _sharedPreferencesFuture;
    if (cachedFuture != null) {
      return cachedFuture;
    }

    final createdFuture = ref.read(sharedPreferencesLoaderProvider)();
    _sharedPreferencesFuture = createdFuture;

    return createdFuture.onError((Object error, StackTrace stackTrace) {
      if (identical(_sharedPreferencesFuture, createdFuture)) {
        _sharedPreferencesFuture = null;
      }
      return Future<SharedPreferences>.error(error, stackTrace);
    });
  }
}

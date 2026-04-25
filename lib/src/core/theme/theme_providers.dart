import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_providers.g.dart';

const _themeModePreferenceKey = 'app_theme_mode';
typedef SharedPreferencesLoader = Future<SharedPreferences> Function();

final sharedPreferencesLoaderProvider = Provider<SharedPreferencesLoader>(
  (ref) => SharedPreferences.getInstance,
);

/// App-wide persisted theme mode state.
@Riverpod(keepAlive: true)
class ThemeModeNotifier extends _$ThemeModeNotifier {
  bool _hasLocalOverride = false;
  Future<SharedPreferences>? _sharedPreferencesFuture;

  @override
  ThemeMode build() {
    unawaited(_hydratePersistedThemeMode());
    return ThemeMode.system;
  }

  Future<void> setThemeMode(ThemeMode themeMode) async {
    _hasLocalOverride = true;
    if (state != themeMode) {
      state = themeMode;
    }

    try {
      final preferences = await _sharedPreferences();
      await _persistThemeMode(preferences, themeMode);
    } on Object {
      // Keep the in-memory selection even if persistence is temporarily
      // unavailable (for example during platform channel failures).
    }
  }

  Future<void> _hydratePersistedThemeMode() async {
    try {
      final preferences = await _sharedPreferences();
      if (_hasLocalOverride || state != ThemeMode.system) {
        return;
      }

      final persistedValue = preferences.getString(_themeModePreferenceKey);
      final persistedThemeMode = _deserializeThemeMode(persistedValue);
      if (persistedThemeMode == null || state == persistedThemeMode) {
        return;
      }

      state = persistedThemeMode;
    } on Object {
      // Fall back to ThemeMode.system when persisted hydration fails.
    }
  }

  Future<bool> _persistThemeMode(
    SharedPreferences preferences,
    ThemeMode themeMode,
  ) {
    if (themeMode == ThemeMode.system) {
      return preferences.remove(_themeModePreferenceKey);
    }

    return preferences.setString(_themeModePreferenceKey, themeMode.name);
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

  ThemeMode? _deserializeThemeMode(String? persistedValue) {
    return switch (persistedValue) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => null,
    };
  }
}

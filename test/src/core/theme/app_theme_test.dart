import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/core/theme/app_theme.dart';

/// ## Test Scenarios
/// - `[positive]` Light and dark themes expose expected brightness values.
/// - `[positive]` Seed-based color tokens remain stable across brightness modes.
/// - `[positive]` Recovery chrome and button style tokens use explicit theme contracts.
void main() {
  group('AppTheme', () {
    test('light theme uses light brightness', () {
      final lightTheme = AppTheme.light();

      expect(lightTheme.brightness, Brightness.light);
      expect(lightTheme.colorScheme.brightness, Brightness.light);
    });

    test('dark theme uses dark brightness', () {
      final darkTheme = AppTheme.dark();

      expect(darkTheme.brightness, Brightness.dark);
      expect(darkTheme.colorScheme.brightness, Brightness.dark);
    });

    test('light and dark themes share the same seed source', () {
      final expectedLight = ColorScheme.fromSeed(
        seedColor: AppTheme.seedColor,
      );
      final expectedDark = ColorScheme.fromSeed(
        seedColor: AppTheme.seedColor,
        brightness: Brightness.dark,
      );

      final lightTheme = AppTheme.light();
      final darkTheme = AppTheme.dark();

      expect(lightTheme.colorScheme.primary, expectedLight.primary);
      expect(lightTheme.colorScheme.secondary, expectedLight.secondary);
      expect(darkTheme.colorScheme.primary, expectedDark.primary);
      expect(darkTheme.colorScheme.secondary, expectedDark.secondary);
    });

    test('light and dark themes define shared recovery chrome tokens', () {
      final lightTheme = AppTheme.light();
      final darkTheme = AppTheme.dark();

      for (final theme in [lightTheme, darkTheme]) {
        expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
        expect(theme.appBarTheme.backgroundColor, theme.colorScheme.surface);
        expect(theme.appBarTheme.foregroundColor, theme.colorScheme.onSurface);
        expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
        expect(theme.cardTheme.color, theme.colorScheme.surfaceContainerLow);
        expect(theme.cardTheme.surfaceTintColor, Colors.transparent);
        final filledButtonStyle = theme.filledButtonTheme.style;
        final textButtonStyle = theme.textButtonTheme.style;
        expect(
          filledButtonStyle?.minimumSize?.resolve(const <WidgetState>{}),
          const Size(140, 48),
        );
        expect(
          textButtonStyle?.foregroundColor?.resolve(const <WidgetState>{}),
          theme.colorScheme.primary,
        );
      }
    });
  });
}

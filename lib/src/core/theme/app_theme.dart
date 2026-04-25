import 'package:flutter/material.dart';

/// Shared app theme builders used by the app shell and settings surfaces.
class AppTheme {
  const AppTheme._();

  /// The app-wide color seed. Light and dark themes derive from this source.
  static const Color seedColor = Colors.blue;

  static ThemeData light() => _buildTheme();

  static ThemeData dark() => _buildTheme(brightness: Brightness.dark);

  static ThemeData _buildTheme({Brightness? brightness}) {
    final colorScheme = brightness == null
        ? ColorScheme.fromSeed(seedColor: seedColor)
        : ColorScheme.fromSeed(
            seedColor: seedColor,
            brightness: brightness,
          );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(140, 48),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
        ),
      ),
    );
  }
}

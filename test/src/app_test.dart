import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/app.dart';
import 'package:uff/src/core/theme/app_theme.dart';
import 'package:uff/src/core/theme/theme_providers.dart';
import 'package:uff/src/routing/app_router.dart';

void main() {
  testWidgets(
    'UffApp wires theme, darkTheme, themeMode, and appRouterProvider',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Text('Router Ready')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appRouterProvider.overrideWithValue(router),
            themeModeProvider.overrideWithValue(ThemeMode.dark),
          ],
          child: const UffApp(),
        ),
      );
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));

      expect(app.routerConfig, same(router));
      expect(app.themeMode, ThemeMode.dark);
      expect(app.theme?.brightness, Brightness.light);
      expect(app.darkTheme?.brightness, Brightness.dark);
      expect(
        app.theme?.appBarTheme.backgroundColor,
        AppTheme.light().appBarTheme.backgroundColor,
      );
      expect(
        app.darkTheme?.appBarTheme.backgroundColor,
        AppTheme.dark().appBarTheme.backgroundColor,
      );
      // Verify filledButtonTheme minimumSize matches AppTheme._buildTheme
      expect(
        app.theme?.filledButtonTheme.style?.minimumSize?.resolve(
          <WidgetState>{},
        ),
        const Size(140, 48),
      );
      expect(
        app.darkTheme?.filledButtonTheme.style?.minimumSize?.resolve(
          <WidgetState>{},
        ),
        const Size(140, 48),
      );
      expect(find.text('Router Ready'), findsOneWidget);
    },
  );
}

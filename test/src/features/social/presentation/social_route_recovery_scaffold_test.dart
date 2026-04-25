import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/core/theme/app_theme.dart';
import 'package:uff/src/features/social/presentation/social_route_recovery_scaffold.dart';

/// ## Test Scenarios
/// - [positive] Recovery scaffold renders default chrome and optional retry/go-home actions.
/// - [positive] Go-home action routes to the configured home path.
/// - [edge] Go-back action only appears when router pop is available.
/// - [error] Loading mode renders progress UI while preserving recovery layout.
/// - [isolation] Light and dark themes both preserve readable recovery token styling.
const _recoveryRoutePath = '/recovery';
const _homeRoutePath = '/home';
const _originRoutePath = '/origin';
const _openRecoveryButtonKey = Key('open_recovery_button');

({GoRouter router, Widget app}) _buildRouterHarness({
  required Widget recovery,
  String initialLocation = _recoveryRoutePath,
  ThemeMode themeMode = ThemeMode.light,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: _originRoutePath,
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: _openRecoveryButtonKey,
              onPressed: () => context.push(_recoveryRoutePath),
              child: const Text('Open recovery'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: _homeRoutePath,
        builder: (context, state) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: _recoveryRoutePath,
        builder: (context, state) => recovery,
      ),
    ],
  );

  final app = MaterialApp.router(
    routerConfig: router,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: themeMode,
  );

  return (router: router, app: app);
}

void main() {
  group('SocialRouteRecoveryScaffold', () {
    testWidgets('renders message and hides optional actions by default', (
      tester,
    ) async {
      final harness = _buildRouterHarness(
        recovery: const SocialRouteRecoveryScaffold(
          stateKey: Key('state'),
          message: 'Unable to open route.',
        ),
      );
      addTearDown(harness.router.dispose);

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text('Unable to open route.'), findsOneWidget);
      expect(
        find.byKey(SocialRouteRecoveryScaffold.retryButtonKey),
        findsNothing,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.byKey(SocialRouteRecoveryScaffold.goHomeButtonKey),
        findsOneWidget,
      );
      expect(
        find.byKey(SocialRouteRecoveryScaffold.goBackButtonKey),
        findsNothing,
      );
    });

    testWidgets(
      'shows retry only when onRetry is provided and invokes callback',
      (
        tester,
      ) async {
        var retryCount = 0;
        final harness = _buildRouterHarness(
          recovery: SocialRouteRecoveryScaffold(
            stateKey: const Key('state'),
            message: 'Could not load profile.',
            onRetry: () {
              retryCount++;
            },
          ),
        );
        addTearDown(harness.router.dispose);

        await tester.pumpWidget(harness.app);
        await tester.pumpAndSettle();

        final retryButton = find.byKey(
          SocialRouteRecoveryScaffold.retryButtonKey,
        );
        expect(retryButton, findsOneWidget);

        await tester.tap(retryButton);
        await tester.pump();

        expect(retryCount, 1);
      },
    );

    testWidgets('shows loading indicator only when requested', (tester) async {
      final hiddenHarness = _buildRouterHarness(
        recovery: const SocialRouteRecoveryScaffold(
          stateKey: Key('hidden-loading'),
          message: 'Hidden loading indicator',
        ),
      );
      addTearDown(hiddenHarness.router.dispose);

      await tester.pumpWidget(hiddenHarness.app);
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);

      final visibleHarness = _buildRouterHarness(
        recovery: const SocialRouteRecoveryScaffold(
          stateKey: Key('visible-loading'),
          message: 'Visible loading indicator',
          showLoadingIndicator: true,
        ),
      );
      addTearDown(visibleHarness.router.dispose);

      await tester.pumpWidget(visibleHarness.app);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('go home action routes to /home', (tester) async {
      final harness = _buildRouterHarness(
        recovery: const SocialRouteRecoveryScaffold(
          stateKey: Key('state'),
          message: 'Can recover via home',
        ),
      );
      addTearDown(harness.router.dispose);

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(SocialRouteRecoveryScaffold.goHomeButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('go back action only shows when router can pop', (
      tester,
    ) async {
      final directEntryHarness = _buildRouterHarness(
        recovery: const SocialRouteRecoveryScaffold(
          stateKey: Key('direct-entry-state'),
          message: 'Direct route entry',
        ),
      );
      addTearDown(directEntryHarness.router.dispose);

      await tester.pumpWidget(directEntryHarness.app);
      await tester.pumpAndSettle();

      expect(
        find.byKey(SocialRouteRecoveryScaffold.goBackButtonKey),
        findsNothing,
      );

      final pushedHarness = _buildRouterHarness(
        initialLocation: _originRoutePath,
        recovery: const SocialRouteRecoveryScaffold(
          stateKey: Key('pushed-state'),
          message: 'Pushed route entry',
        ),
      );
      addTearDown(pushedHarness.router.dispose);

      await tester.pumpWidget(pushedHarness.app);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_openRecoveryButtonKey));
      await tester.pumpAndSettle();

      final goBackButton = find.byKey(
        SocialRouteRecoveryScaffold.goBackButtonKey,
      );
      expect(goBackButton, findsOneWidget);

      await tester.tap(goBackButton);
      await tester.pumpAndSettle();

      expect(find.byKey(_openRecoveryButtonKey), findsOneWidget);
    });

    testWidgets('dark theme uses recovery chrome tokens with readable text', (
      tester,
    ) async {
      final darkTheme = AppTheme.dark();
      final harness = _buildRouterHarness(
        recovery: const SocialRouteRecoveryScaffold(
          stateKey: Key('dark-state'),
          message: 'Dark mode recovery message',
        ),
        themeMode: ThemeMode.dark,
      );
      addTearDown(harness.router.dispose);

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      final card = tester.widget<Card>(find.byType(Card));
      final themedContext = tester.element(
        find.byType(SocialRouteRecoveryScaffold),
      );
      final resolvedTheme = Theme.of(themedContext);

      expect(scaffold.backgroundColor, isNull);
      expect(card.color, isNull);
      expect(resolvedTheme.brightness, Brightness.dark);
      expect(
        resolvedTheme.scaffoldBackgroundColor,
        darkTheme.colorScheme.surface,
      );
      expect(
        resolvedTheme.appBarTheme.backgroundColor,
        darkTheme.colorScheme.surface,
      );
      expect(
        resolvedTheme.appBarTheme.foregroundColor,
        darkTheme.colorScheme.onSurface,
      );
      expect(
        resolvedTheme.cardTheme.color,
        darkTheme.colorScheme.surfaceContainerLow,
      );

      final messageElement = tester.element(
        find.text('Dark mode recovery message'),
      );
      final resolvedMessageColor = DefaultTextStyle.of(
        messageElement,
      ).style.color;
      expect(resolvedMessageColor, resolvedTheme.textTheme.bodyMedium?.color);
      expect(resolvedMessageColor, isNot(darkTheme.colorScheme.surface));
    });
  });
}

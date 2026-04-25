import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/auth/presentation/auth_legal_links.dart';
import 'package:uff/src/features/legal/presentation/legal_routes.dart';

const _authEntryPath = '/auth';
const _privacyButtonKey = Key('auth_legal_privacy_button');
const _termsButtonKey = Key('auth_legal_terms_button');
const _privacyDestinationKey = Key('privacy_destination');
const _termsDestinationKey = Key('terms_destination');

({GoRouter router, Widget app}) _buildRouterHarness({bool isLoading = false}) {
  final router = GoRouter(
    initialLocation: _authEntryPath,
    routes: [
      GoRoute(
        path: _authEntryPath,
        builder: (context, state) => Scaffold(
          body: Center(
            child: AuthLegalLinks(
              privacyPolicyButtonKey: _privacyButtonKey,
              termsOfServiceButtonKey: _termsButtonKey,
              isLoading: isLoading,
            ),
          ),
        ),
      ),
      GoRoute(
        path: LegalRoutes.privacyPath,
        builder: (context, state) => const Scaffold(
          body: Text('privacy destination', key: _privacyDestinationKey),
        ),
      ),
      GoRoute(
        path: LegalRoutes.termsPath,
        builder: (context, state) => const Scaffold(
          body: Text('terms destination', key: _termsDestinationKey),
        ),
      ),
    ],
  );

  return (
    router: router,
    app: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  /// ## Test Scenarios
  /// - `[positive]` Legal link labels render from route constants.
  /// - `[positive]` Privacy and Terms buttons navigate to the expected destinations.
  /// - `[edge]` Loading mode disables both legal-link interactions.
  group('AuthLegalLinks', () {
    testWidgets('renders both legal link labels from LegalRoutes', (
      tester,
    ) async {
      final harness = _buildRouterHarness();
      addTearDown(harness.router.dispose);

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text(LegalRoutes.privacyTitle), findsOneWidget);
      expect(find.text(LegalRoutes.termsTitle), findsOneWidget);
    });

    testWidgets('privacy button navigates to LegalRoutes.privacyPath', (
      tester,
    ) async {
      final harness = _buildRouterHarness();
      addTearDown(harness.router.dispose);

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_privacyButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(_privacyDestinationKey), findsOneWidget);
    });

    testWidgets('terms button navigates to LegalRoutes.termsPath', (
      tester,
    ) async {
      final harness = _buildRouterHarness();
      addTearDown(harness.router.dispose);

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_termsButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(_termsDestinationKey), findsOneWidget);
    });

    testWidgets('isLoading true disables both legal link buttons', (
      tester,
    ) async {
      final harness = _buildRouterHarness(isLoading: true);
      addTearDown(harness.router.dispose);

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      final privacyButton = tester.widget<TextButton>(
        find.byKey(_privacyButtonKey),
      );
      final termsButton = tester.widget<TextButton>(
        find.byKey(_termsButtonKey),
      );

      expect(privacyButton.onPressed, isNull);
      expect(termsButton.onPressed, isNull);
    });

    testWidgets(
      'default isLoading false keeps both legal link buttons enabled',
      (
        tester,
      ) async {
        final harness = _buildRouterHarness();
        addTearDown(harness.router.dispose);

        await tester.pumpWidget(harness.app);
        await tester.pumpAndSettle();

        final privacyButton = tester.widget<TextButton>(
          find.byKey(_privacyButtonKey),
        );
        final termsButton = tester.widget<TextButton>(
          find.byKey(_termsButtonKey),
        );

        expect(privacyButton.enabled, isTrue);
        expect(termsButton.enabled, isTrue);
      },
    );
  });
}

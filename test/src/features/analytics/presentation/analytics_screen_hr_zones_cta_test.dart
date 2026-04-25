import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/analytics/presentation/analytics_screen.dart';
import 'package:uff/src/features/analytics/presentation/pmc_chart_widget.dart';
import 'package:uff/src/features/analytics/presentation/race_predictions_card.dart';
import 'package:uff/src/features/analytics/presentation/training_load_card.dart';
import 'package:uff/src/features/settings/presentation/settings_routes.dart';
import 'analytics_screen_test_support.dart';

void main() {
  group('AnalyticsScreen HR zones CTA', () {
    testWidgets(
      'shows HR zones setup CTA only for settled missing-lthr profile state',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: successfulAnalyticsScreenOverrides(),
            child: const MaterialApp(home: AnalyticsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expectHrZonesSetupCtaPresent();
        expect(find.byType(TrainingLoadCard), findsOneWidget);
        expect(find.byType(PmcChartWidget), findsOneWidget);
        expect(
          find.byType(RacePredictionsCard, skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'hides HR zones setup CTA when profile has configured lthrBpm',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: successfulAnalyticsScreenOverrides(
              profileState: AnalyticsProfileState.configuredLthr,
            ),
            child: const MaterialApp(home: AnalyticsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expectHrZonesSetupCtaAbsent();
      },
    );

    testWidgets(
      'hides HR zones setup CTA while profile state is loading',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: successfulAnalyticsScreenOverrides(
              profileState: AnalyticsProfileState.loading,
            ),
            child: const MaterialApp(home: AnalyticsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expectHrZonesSetupCtaAbsent();
      },
    );

    testWidgets(
      'hides HR zones setup CTA when profile state errors',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: successfulAnalyticsScreenOverrides(
              profileState: AnalyticsProfileState.error,
            ),
            child: const MaterialApp(home: AnalyticsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expectHrZonesSetupCtaAbsent();
      },
    );

    testWidgets(
      'navigates to SettingsRoutes.hrZonesPath when CTA is tapped',
      (tester) async {
        final router = GoRouter(
          initialLocation: '/analytics',
          routes: [
            GoRoute(
              path: '/analytics',
              builder: (_, __) => const AnalyticsScreen(),
            ),
            GoRoute(
              path: SettingsRoutes.hrZonesPath,
              builder: (_, __) => const Scaffold(
                body: Center(child: Text('HR Zones Destination')),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: successfulAnalyticsScreenOverrides(),
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        final ctaFinder = findHrZonesSetupCta();
        expectHrZonesSetupCtaPresent();
        await bringIntoView(tester, ctaFinder);
        await tester.tap(ctaFinder);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), expectedHrZonesRoutePath);
        expect(find.text('HR Zones Destination'), findsOneWidget);
      },
    );
  });
}

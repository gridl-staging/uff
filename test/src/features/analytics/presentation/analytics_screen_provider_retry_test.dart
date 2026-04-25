import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/analytics/application/analytics_providers.dart';
import 'package:uff/src/features/analytics/presentation/analytics_screen.dart';
import 'package:uff/src/features/analytics/presentation/pmc_chart_widget.dart';
import 'package:uff/src/features/analytics/presentation/race_predictions_card.dart';
import 'package:uff/src/features/analytics/presentation/training_load_card.dart';

import 'analytics_screen_test_support.dart';

void main() {
  group('AnalyticsScreen provider-specific retries', () {
    testWidgets(
      'shows VDOT data with predictions error and retries only predictions provider',
      (tester) async {
        var predictionsLoadCount = 0;
        var vdotLoadCount = 0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pmcProvider.overrideWith((ref) async => pmcSampleDays()),
              racePredictionsProvider.overrideWith(
                (ref) async {
                  predictionsLoadCount++;
                  throw StateError('predictions failed');
                },
              ),
              vdotEstimateProvider.overrideWith(
                (ref) async {
                  vdotLoadCount++;
                  return 47.24;
                },
              ),
            ],
            child: const MaterialApp(home: AnalyticsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(AnalyticsScreen.contentListViewKey), findsOneWidget);
        expect(find.byType(TrainingLoadCard), findsOneWidget);
        expect(find.byType(PmcChartWidget), findsOneWidget);
        expect(
          find.byType(RacePredictionsCard, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byKey(
            AnalyticsScreen.raceDeferredStatusKey,
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        expect(find.text('47.2', skipOffstage: false), findsOneWidget);
        expect(
          find.text(expectedRacePredictionsErrorMessage, skipOffstage: false),
          findsOneWidget,
        );
        final retryPredictionsButton = find.byKey(
          AnalyticsScreen.racePredictionsRetryButtonKey,
          skipOffstage: false,
        );
        expect(retryPredictionsButton, findsOneWidget);
        expect(
          find.descendant(
            of: retryPredictionsButton,
            matching: find.text('Try Again', skipOffstage: false),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('predictions failed'), findsNothing);
        expect(predictionsLoadCount, 1);
        expect(vdotLoadCount, 1);
        expect(
          find.text(expectedNoPredictionsWithVdotMessage, skipOffstage: false),
          findsNothing,
        );

        await bringIntoView(tester, retryPredictionsButton);
        await tester.tap(retryPredictionsButton);
        await tester.pumpAndSettle();

        expect(find.byKey(AnalyticsScreen.contentListViewKey), findsOneWidget);
        expect(
          find.byType(TrainingLoadCard, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byType(PmcChartWidget, skipOffstage: false),
          findsOneWidget,
        );
        expect(predictionsLoadCount, 2);
        expect(vdotLoadCount, 1);
      },
    );
  });
}

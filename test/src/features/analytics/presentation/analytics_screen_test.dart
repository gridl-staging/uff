import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/analytics/application/analytics_providers.dart';
import 'package:uff/src/features/analytics/domain/pmc_day.dart';
import 'package:uff/src/features/analytics/domain/race_prediction.dart';
import 'package:uff/src/features/analytics/presentation/analytics_screen.dart';
import 'package:uff/src/features/analytics/presentation/pmc_chart_widget.dart';
import 'package:uff/src/features/analytics/presentation/race_predictions_card.dart';
import 'package:uff/src/features/analytics/presentation/training_load_card.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import '../../../test_helpers/saved_activities_probe.dart';
import 'analytics_screen_test_support.dart';

/// ## Test Scenarios
/// - `[positive]` Renders loading indicator while pmcProvider is unresolved
/// - `[positive]` Renders scrollable ListView with training load, PMC chart, and race predictions in order
/// - `[positive]` Pull-to-refresh reloads pmc, predictions, and vdot providers
/// - `[positive]` Shows resolved VDOT while race predictions are still loading
/// - `[positive]` Shows resolved race predictions while VDOT is still loading
/// - `[negative]` Retry button reloads upstream saved activities after an error
/// - `[negative]` Pull-to-refresh from load-error branch retries only pmc provider
/// - `[negative]` Shows section fallback with both deferred errors
/// - `[isolation]` Pull-to-refresh from content list does not reload upstream saved activities
/// - `[edge]` Renders full-screen empty state when no activities exist
/// - `[edge]` Renders analytics content in dark theme

void main() {
  group('AnalyticsScreen', () {
    testWidgets('renders loading indicator '
        'while pmcProvider is unresolved', (tester) async {
      final completer = Completer<List<PmcDay>>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pmcProvider.overrideWith((ref) => completer.future),
            racePredictionsProvider.overrideWith((ref) async => const []),
            vdotEstimateProvider.overrideWith((ref) async => null),
            profileProvider.overrideWith(
              () => FakeAnalyticsProfileNotifier(
                profileStateFor(AnalyticsProfileState.missingLthr),
              ),
            ),
          ],
          child: const MaterialApp(home: AnalyticsScreen()),
        ),
      );
      await tester.pump();

      expectAnalyticsScreenRendered(tester);

      final loadingIndicator = find.byKey(AnalyticsScreen.loadingIndicatorKey);
      expect(loadingIndicator, findsOneWidget);
      expect(find.byKey(AnalyticsScreen.loadingStateKey), findsOneWidget);
      expect(find.byKey(AnalyticsScreen.contentListViewKey), findsNothing);
      expect(find.byKey(AnalyticsScreen.loadErrorRetryButtonKey), findsNothing);
      expectHrZonesSetupCtaAbsent();
      expect(
        find.text('Unable to load analytics data. Please try again.'),
        findsNothing,
      );

      completer.complete([]);
      await tester.pumpAndSettle();
    });

    testWidgets(
      'retry button reloads upstream saved activities after an error',
      (tester) async {
        var savedActivitiesLoadCount = 0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              savedActivitiesProvider.overrideWith((ref) async {
                savedActivitiesLoadCount++;
                if (savedActivitiesLoadCount == 1) {
                  throw StateError('test error');
                }

                return savedActivitiesSample();
              }),
              profileProvider.overrideWith(
                () => FakeAnalyticsProfileNotifier(
                  profileStateFor(AnalyticsProfileState.missingLthr),
                ),
              ),
            ],
            child: const MaterialApp(home: AnalyticsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expectAnalyticsScreenRendered(tester);
        final genericErrorMessage = find.text(
          'Unable to load analytics data. Please try again.',
        );
        expect(genericErrorMessage, findsOneWidget);
        expect(find.byKey(AnalyticsScreen.loadErrorStateKey), findsOneWidget);
        expect(find.textContaining('test error'), findsNothing);
        expect(
          find.byKey(AnalyticsScreen.loadErrorRetryButtonKey),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(AnalyticsScreen.loadErrorRetryButtonKey),
            matching: find.text('Try Again'),
          ),
          findsOneWidget,
        );
        expectHrZonesSetupCtaAbsent();
        expect(find.byKey(AnalyticsScreen.loadingIndicatorKey), findsNothing);
        expect(find.byKey(AnalyticsScreen.contentListViewKey), findsNothing);
        expect(savedActivitiesLoadCount, 1);

        await tester.tap(find.byKey(AnalyticsScreen.loadErrorRetryButtonKey));
        await tester.pumpAndSettle();

        expect(savedActivitiesLoadCount, 2);
        expect(find.byKey(AnalyticsScreen.contentListViewKey), findsOneWidget);
        expect(
          find.text('Unable to load analytics data. Please try again.'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'pull-to-refresh from content list reloads pmc, predictions, and vdot providers',
      (tester) async {
        var pmcLoadCount = 0;
        var predictionsLoadCount = 0;
        var vdotLoadCount = 0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pmcProvider.overrideWith((ref) async {
                pmcLoadCount++;
                return pmcSampleDays();
              }),
              racePredictionsProvider.overrideWith((ref) async {
                predictionsLoadCount++;
                return samplePredictions();
              }),
              vdotEstimateProvider.overrideWith((ref) async {
                vdotLoadCount++;
                return 50.0;
              }),
            ],
            child: const MaterialApp(home: AnalyticsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(AnalyticsScreen.contentListViewKey), findsOneWidget);
        expect(pmcLoadCount, 1);
        expect(predictionsLoadCount, 1);
        expect(vdotLoadCount, 1);

        await dragToRefresh(
          tester,
          find.byKey(AnalyticsScreen.contentListViewKey),
        );
        await tester.pumpAndSettle();

        expect(pmcLoadCount, greaterThan(1));
        expect(predictionsLoadCount, greaterThan(1));
        expect(vdotLoadCount, greaterThan(1));
      },
    );

    testWidgets(
      'pull-to-refresh keeps saved activities untouched when analytics providers are independently overridden',
      (tester) async {
        var savedActivitiesLoadCount = 0;
        var pmcLoadCount = 0;
        var predictionsLoadCount = 0;
        var vdotLoadCount = 0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              savedActivitiesProvider.overrideWith((ref) async {
                savedActivitiesLoadCount++;
                return savedActivitiesSample();
              }),
              pmcProvider.overrideWith((ref) async {
                pmcLoadCount++;
                return pmcSampleDays();
              }),
              racePredictionsProvider.overrideWith((ref) async {
                predictionsLoadCount++;
                return samplePredictions();
              }),
              vdotEstimateProvider.overrideWith((ref) async {
                vdotLoadCount++;
                return 50.0;
              }),
            ],
            child: const MaterialApp(
              home: Stack(
                children: [AnalyticsScreen(), SavedActivitiesProbe()],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(savedActivitiesLoadCount, 1);
        expect(pmcLoadCount, 1);
        expect(predictionsLoadCount, 1);
        expect(vdotLoadCount, 1);

        await dragToRefresh(
          tester,
          find.byKey(AnalyticsScreen.contentListViewKey),
        );
        await tester.pumpAndSettle();

        expect(savedActivitiesLoadCount, 1);
        expect(pmcLoadCount, greaterThan(1));
        expect(predictionsLoadCount, greaterThan(1));
        expect(vdotLoadCount, greaterThan(1));
      },
    );

    testWidgets(
      'pull-to-refresh from content list does not reload upstream saved activities',
      (tester) async {
        var savedActivitiesLoadCount = 0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              savedActivitiesProvider.overrideWith((ref) async {
                savedActivitiesLoadCount++;
                return savedActivitiesSample();
              }),
            ],
            child: const MaterialApp(home: AnalyticsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(AnalyticsScreen.contentListViewKey), findsOneWidget);
        expect(savedActivitiesLoadCount, 1);

        await dragToRefresh(
          tester,
          find.byKey(AnalyticsScreen.contentListViewKey),
        );
        await tester.pumpAndSettle();

        expect(savedActivitiesLoadCount, 1);
      },
    );

    testWidgets(
      'pull-to-refresh from load-error branch retries only pmc provider',
      (tester) async {
        var pmcLoadCount = 0;
        var predictionsLoadCount = 0;
        var vdotLoadCount = 0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pmcProvider.overrideWith((ref) async {
                pmcLoadCount++;
                throw StateError('pmc failed');
              }),
              racePredictionsProvider.overrideWith((ref) async {
                predictionsLoadCount++;
                return const [];
              }),
              vdotEstimateProvider.overrideWith((ref) async {
                vdotLoadCount++;
                return null;
              }),
            ],
            child: const MaterialApp(home: AnalyticsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(AnalyticsScreen.loadErrorStateKey), findsOneWidget);
        expect(pmcLoadCount, 1);
        expect(predictionsLoadCount, 0);
        expect(vdotLoadCount, 0);

        await dragToRefresh(
          tester,
          find.byKey(AnalyticsScreen.loadErrorStateKey),
        );
        await tester.pumpAndSettle();

        expect(pmcLoadCount, greaterThan(1));
        expect(predictionsLoadCount, 0);
        expect(vdotLoadCount, 0);
      },
    );

    testWidgets('race fallback retry actions use explicit Try Again copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pmcProvider.overrideWith((ref) async => pmcSampleDays()),
            racePredictionsProvider.overrideWith(
              (ref) async => throw StateError('predictions failed'),
            ),
            vdotEstimateProvider.overrideWith(
              (ref) async => throw StateError('vdot failed'),
            ),
          ],
          child: const MaterialApp(home: AnalyticsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(
            AnalyticsScreen.racePredictionsRetryButtonKey,
            skipOffstage: false,
          ),
          matching: find.text('Try Again', skipOffstage: false),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            AnalyticsScreen.vdotRetryButtonKey,
            skipOffstage: false,
          ),
          matching: find.text('Try Again', skipOffstage: false),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'pull-to-refresh from load-error branch does not reload upstream saved activities',
      (tester) async {
        var savedActivitiesLoadCount = 0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              savedActivitiesProvider.overrideWith((ref) async {
                savedActivitiesLoadCount++;
                if (savedActivitiesLoadCount == 1) {
                  throw StateError('saved activities failed');
                }
                return savedActivitiesSample();
              }),
            ],
            child: const MaterialApp(home: AnalyticsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(AnalyticsScreen.loadErrorStateKey), findsOneWidget);
        expect(savedActivitiesLoadCount, 1);

        await dragToRefresh(
          tester,
          find.byKey(AnalyticsScreen.loadErrorStateKey),
        );
        await tester.pumpAndSettle();

        expect(savedActivitiesLoadCount, 1);
        expect(find.byKey(AnalyticsScreen.loadErrorStateKey), findsOneWidget);
      },
    );

    testWidgets(
      'renders scrollable ListView with training load, PMC chart, and race predictions in order',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pmcProvider.overrideWith((ref) async => pmcSampleDays()),
              racePredictionsProvider.overrideWith(
                (ref) async => samplePredictions(),
              ),
              vdotEstimateProvider.overrideWith((ref) async => 50.0),
            ],
            child: const MaterialApp(home: AnalyticsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expectAnalyticsScreenRendered(tester);
        final listViewFinder = find.byKey(AnalyticsScreen.contentListViewKey);
        expect(listViewFinder, findsOneWidget);
        expect(find.byType(TrainingLoadCard), findsOneWidget);
        expect(find.byType(PmcChartWidget), findsOneWidget);
        final raceCardFinder = find.byType(
          RacePredictionsCard,
          skipOffstage: false,
        );
        expect(raceCardFinder, findsOneWidget);

        final trainingY = tester.getTopLeft(find.byType(TrainingLoadCard)).dy;
        final chartY = tester.getTopLeft(find.byType(PmcChartWidget)).dy;
        final raceY = tester.getTopLeft(raceCardFinder).dy;
        expect(trainingY, lessThan(chartY));
        expect(chartY, lessThan(raceY));
      },
    );

    testWidgets('renders full-screen empty state when no activities exist', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pmcProvider.overrideWith((ref) async => []),
            racePredictionsProvider.overrideWith((ref) async => const []),
            vdotEstimateProvider.overrideWith((ref) async => null),
          ],
          child: const MaterialApp(home: AnalyticsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expectAnalyticsScreenRendered(tester);
      expect(find.byKey(AnalyticsScreen.emptyStateKey), findsOneWidget);
      expect(find.text(expectedAnalyticsEmptyStateMessage), findsOneWidget);
      expect(find.byKey(AnalyticsScreen.contentListViewKey), findsNothing);
      expect(find.byType(TrainingLoadCard), findsNothing);
      expect(find.byType(PmcChartWidget), findsNothing);
      expect(find.byType(RacePredictionsCard), findsNothing);
    });

    testWidgets(
      'keeps PMC content visible while race and VDOT providers are unresolved',
      (tester) async {
        final predictionsCompleter = Completer<List<RacePrediction>>();
        final vdotCompleter = Completer<double?>();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pmcProvider.overrideWith((ref) async => pmcSampleDays()),
              racePredictionsProvider.overrideWith(
                (ref) => predictionsCompleter.future,
              ),
              vdotEstimateProvider.overrideWith((ref) => vdotCompleter.future),
            ],
            child: const MaterialApp(home: AnalyticsScreen()),
          ),
        );
        await tester.pump();

        expectAnalyticsScreenRendered(tester);
        expect(find.byKey(AnalyticsScreen.contentListViewKey), findsOneWidget);
        expect(find.byType(TrainingLoadCard), findsOneWidget);
        expect(find.byType(PmcChartWidget), findsOneWidget);
        expect(
          find.byType(RacePredictionsCard, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byKey(
            AnalyticsScreen.raceFallbackStatusKey,
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            AnalyticsScreen.raceStatusLoadingIndicatorKey,
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        expect(
          find.text(expectedRacePredictionsLoadingMessage, skipOffstage: false),
          findsOneWidget,
        );

        predictionsCompleter.complete(const []);
        vdotCompleter.complete(null);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'shows resolved VDOT while race predictions are still loading',
      (tester) async {
        final predictionsCompleter = Completer<List<RacePrediction>>();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pmcProvider.overrideWith((ref) async => pmcSampleDays()),
              racePredictionsProvider.overrideWith(
                (ref) => predictionsCompleter.future,
              ),
              vdotEstimateProvider.overrideWith((ref) async => 49.64),
            ],
            child: const MaterialApp(home: AnalyticsScreen()),
          ),
        );
        await tester.pump();
        await tester.pump();

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
        expect(
          find.byKey(
            AnalyticsScreen.raceStatusLoadingIndicatorKey,
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        expect(find.text('49.6', skipOffstage: false), findsOneWidget);
        expect(
          find.text(expectedRacePredictionsLoadingMessage, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.text(expectedNoPredictionsWithVdotMessage, skipOffstage: false),
          findsNothing,
        );

        predictionsCompleter.complete(const []);
        await tester.pumpAndSettle();
      },
    );

    testWidgets('shows resolved race predictions while VDOT is still loading', (
      tester,
    ) async {
      final vdotCompleter = Completer<double?>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pmcProvider.overrideWith((ref) async => pmcSampleDays()),
            racePredictionsProvider.overrideWith(
              (ref) async => samplePredictions(),
            ),
            vdotEstimateProvider.overrideWith((ref) => vdotCompleter.future),
          ],
          child: const MaterialApp(home: AnalyticsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byType(RacePredictionsCard, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(AnalyticsScreen.raceDeferredStatusKey, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(
          AnalyticsScreen.raceStatusLoadingIndicatorKey,
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(find.text('43:10', skipOffstage: false), findsOneWidget);
      expect(find.text('VDOT', skipOffstage: false), findsNothing);
      expect(
        find.text(expectedVdotLoadingMessage, skipOffstage: false),
        findsOneWidget,
      );

      vdotCompleter.complete(null);
      await tester.pumpAndSettle();
    });

    testWidgets(
      'suppresses empty guidance while VDOT is loading after empty predictions resolve',
      (tester) async {
        final vdotCompleter = Completer<double?>();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pmcProvider.overrideWith((ref) async => pmcSampleDays()),
              racePredictionsProvider.overrideWith((ref) async => const []),
              vdotEstimateProvider.overrideWith((ref) => vdotCompleter.future),
            ],
            child: const MaterialApp(home: AnalyticsScreen()),
          ),
        );
        await tester.pump();
        await tester.pump();

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
        expect(
          find.text(expectedNoPredictionsOrVdotMessage, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.text(expectedNoPredictionsWithVdotMessage, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.text(expectedVdotLoadingMessage, skipOffstage: false),
          findsOneWidget,
        );

        vdotCompleter.complete(null);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'suppresses empty guidance while VDOT is errored after empty predictions resolve',
      (tester) async {
        var vdotLoadCount = 0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pmcProvider.overrideWith((ref) async => pmcSampleDays()),
              racePredictionsProvider.overrideWith((ref) async => const []),
              vdotEstimateProvider.overrideWith((ref) async {
                vdotLoadCount++;
                throw StateError('vdot failed');
              }),
            ],
            child: const MaterialApp(home: AnalyticsScreen()),
          ),
        );
        await tester.pumpAndSettle();

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
        expect(
          find.text(expectedNoPredictionsOrVdotMessage, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.text(expectedNoPredictionsWithVdotMessage, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.text(expectedVdotErrorMessage, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byKey(AnalyticsScreen.vdotRetryButtonKey, skipOffstage: false),
          findsOneWidget,
        );
        expect(vdotLoadCount, 1);
      },
    );

    testWidgets(
      'shows section fallback with both deferred errors and keeps retries provider-specific',
      (tester) async {
        var predictionsLoadCount = 0;
        var vdotLoadCount = 0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pmcProvider.overrideWith((ref) async => pmcSampleDays()),
              racePredictionsProvider.overrideWith((ref) async {
                predictionsLoadCount++;
                throw StateError('predictions failed');
              }),
              vdotEstimateProvider.overrideWith((ref) async {
                vdotLoadCount++;
                throw StateError('vdot failed');
              }),
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
          findsNothing,
        );
        expect(
          find.byKey(
            AnalyticsScreen.raceFallbackStatusKey,
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            expectedRacePredictionsUnavailableMessage,
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        final retryPredictionsButton = find.byKey(
          AnalyticsScreen.racePredictionsRetryButtonKey,
          skipOffstage: false,
        );
        final retryVdotButton = find.byKey(
          AnalyticsScreen.vdotRetryButtonKey,
          skipOffstage: false,
        );
        expect(retryPredictionsButton, findsOneWidget);
        expect(retryVdotButton, findsOneWidget);
        expect(find.textContaining('predictions failed'), findsNothing);
        expect(find.textContaining('vdot failed'), findsNothing);
        expect(predictionsLoadCount, 1);
        expect(vdotLoadCount, 1);

        await bringIntoView(tester, retryVdotButton);
        await tester.tap(retryVdotButton);
        await tester.pumpAndSettle();

        expect(predictionsLoadCount, 1);
        expect(vdotLoadCount, 2);
        expect(find.byKey(AnalyticsScreen.contentListViewKey), findsOneWidget);

        await bringIntoView(tester, retryPredictionsButton);
        await tester.tap(retryPredictionsButton);
        await tester.pumpAndSettle();

        expect(predictionsLoadCount, 2);
        expect(vdotLoadCount, 2);
        expect(find.byKey(AnalyticsScreen.contentListViewKey), findsOneWidget);
      },
    );

    testWidgets(
      'shows predictions data with VDOT error and retries only VDOT provider',
      (tester) async {
        var predictionsLoadCount = 0;
        var vdotLoadCount = 0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pmcProvider.overrideWith((ref) async => pmcSampleDays()),
              racePredictionsProvider.overrideWith((ref) async {
                predictionsLoadCount++;
                return samplePredictions();
              }),
              vdotEstimateProvider.overrideWith((ref) async {
                vdotLoadCount++;
                throw StateError('vdot failed');
              }),
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
        expect(find.text('43:10', skipOffstage: false), findsOneWidget);
        expect(
          find.text(expectedVdotErrorMessage, skipOffstage: false),
          findsOneWidget,
        );
        final retryVdotButton = find.byKey(
          AnalyticsScreen.vdotRetryButtonKey,
          skipOffstage: false,
        );
        expect(retryVdotButton, findsOneWidget);
        expect(find.textContaining('vdot failed'), findsNothing);
        expect(predictionsLoadCount, 1);
        expect(vdotLoadCount, 1);
        expect(
          find.text(expectedNoPredictionsWithVdotMessage, skipOffstage: false),
          findsNothing,
        );

        await bringIntoView(tester, retryVdotButton);
        await tester.tap(retryVdotButton);
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
        expect(predictionsLoadCount, 1);
        expect(vdotLoadCount, 2);
      },
    );

    testWidgets('renders analytics content in dark theme', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pmcProvider.overrideWith((ref) async => pmcSampleDays()),
            racePredictionsProvider.overrideWith(
              (ref) async => samplePredictions(),
            ),
            vdotEstimateProvider.overrideWith((ref) async => 50.0),
          ],
          child: MaterialApp(
            darkTheme: ThemeData.dark(),
            themeMode: ThemeMode.dark,
            home: const AnalyticsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expectAnalyticsScreenRendered(tester);
      expect(find.byKey(AnalyticsScreen.contentListViewKey), findsOneWidget);
      expect(find.byType(TrainingLoadCard), findsOneWidget);
      expect(find.byType(PmcChartWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

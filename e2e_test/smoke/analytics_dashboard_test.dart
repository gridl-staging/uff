import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/recording_screen.dart';
import 'package:uff/src/features/analytics/presentation/analytics_screen.dart';
import 'package:uff/src/features/analytics/presentation/pmc_chart_widget.dart';
import 'package:uff/src/features/analytics/presentation/race_predictions_card.dart';
import 'package:uff/src/features/analytics/presentation/training_load_card.dart';
import 'package:uff/src/routing/app_router.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

void main() {
  patrolTest(
    'pre-authenticated user sees analytics dashboard transition after replay recording',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();
      // Pre-authenticate BEFORE pumping the widget to avoid rapid router
      // redirect cycles that cause duplicate GlobalKey errors in
      // go_router's StatefulShellRoute.
      await preAuthenticate();
      await $.pumpWidget(
        await buildTestApp(
          fixturePath: 'e2e_test/test_data/generated/long_easy_run.json',
          // Replay the full 10.91 km fixture quickly so the test can wait for
          // enough distance to trigger VDOT race predictions (≥ 5 km).
          replayEmissionInterval: const Duration(milliseconds: 10),
        ),
      );
      await cleanupTestData($);

      registerAuthCleanup($);

      final analyticsTabFinder = find.byKey(HomeShellScreen.analyticsTabKey);
      await $(analyticsTabFinder).waitUntilVisible();
      await $(analyticsTabFinder).tap();

      // Fresh accounts render the screen-level analytics empty state before
      // any run exists. The per-card widgets only mount after a saved activity
      // populates PMC data and the analytics ListView becomes the active body.
      await $(find.byKey(AnalyticsScreen.emptyStateKey)).waitUntilVisible();

      final recordTabFinder = find.byKey(HomeShellScreen.recordTabKey);
      await $(recordTabFinder).waitUntilVisible();
      await $(recordTabFinder).tap();

      final startButtonFinder = find.byKey(RecordingScreen.startButtonKey);
      final pauseButtonFinder = find.byKey(RecordingScreen.pauseButtonKey);
      final finishButtonFinder = find.byKey(RecordingScreen.finishButtonKey);

      await $(startButtonFinder).waitUntilVisible();
      await $(startButtonFinder).tap();

      // Wait for the full fixture distance so VDOT race predictions populate
      // (requires ≥ 5 km).  With 10 ms emission interval the 721-point fixture
      // completes in ~7 s; 120 polls × 250 ms = 30 s budget is ample.
      await waitForNonZeroDistance(
        $,
        minimumDistanceKilometers: 10,
        maxPollAttempts: 120,
      );

      await $(pauseButtonFinder).waitUntilVisible();
      await $(pauseButtonFinder).tap();
      await $(finishButtonFinder).waitUntilVisible();
      await $(finishButtonFinder).tap();

      final draftSaveFinder = find.byKey(
        ActivityDetailScreen.draftSaveButtonKey,
      );
      await revealDraftSaveButton($);
      await $(draftSaveFinder).waitUntilVisible();
      await $(draftSaveFinder).tap();

      await $(
        find.byKey(ActivityDetailScreen.distanceValueTextKey),
      ).waitUntilVisible();
      final tssValue = await readActivityDetailTssValue($);
      expect(tssValue, greaterThan(0));

      final detailBackButtonFinder = find.byTooltip('Back');
      await $(detailBackButtonFinder).waitUntilVisible();
      await $(detailBackButtonFinder).tap();

      await $(analyticsTabFinder).waitUntilVisible();
      await $(analyticsTabFinder).tap();

      await $(
        find.byKey(AnalyticsScreen.contentListViewKey),
      ).waitUntilVisible();
      await $(find.byKey(TrainingLoadCard.dataStateKey)).waitUntilExists();
      await $(find.byKey(PmcChartWidget.dataStateKey)).waitUntilExists();
      final fitness = await readTrainingLoadMetricValue($, label: 'Fitness');
      final fatigue = await readTrainingLoadMetricValue($, label: 'Fatigue');
      final form = await readTrainingLoadMetricValue($, label: 'Form');
      expect(fitness.abs(), greaterThan(0));
      expect(fatigue.abs(), greaterThan(0));
      expect(form.abs(), greaterThan(0));

      expect(find.text('Fitness'), findsWidgets);
      expect(find.text('Fatigue'), findsWidgets);
      expect(find.text('Form'), findsWidgets);
      expect(
        hasAnyVisibleText($, const [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
        ]),
        isTrue,
      );

      expect(find.byKey(TrainingLoadCard.emptyStateKey), findsNothing);
      expect(find.byKey(PmcChartWidget.emptyStateKey), findsNothing);

      // The analytics list is lazily mounted on smaller emulator viewports, so
      // scroll the race predictions card into view before asserting its data
      // state.
      await $(find.byKey(RacePredictionsCard.cardKey)).scrollTo();
      await $(
        find.byKey(RacePredictionsCard.dataStateKey),
      ).waitUntilExists(timeout: const Duration(seconds: 30));

      expect(find.text('VDOT'), findsOneWidget);
      expect(
        hasAnyVisibleText($, const [
          '10 km',
          '15 km',
          'Half Marathon',
          '30 km',
          'Marathon',
        ]),
        isTrue,
      );

      expect(find.byKey(RacePredictionsCard.emptyStateKey), findsNothing);
    },
  );
}

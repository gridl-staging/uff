import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/recording_screen.dart';
import 'package:uff/src/features/analytics/presentation/training_load_card.dart';
import 'package:uff/src/routing/app_router.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

void main() {
  patrolTest(
    'analytics metrics: rTSS tolerance and training load structural invariants',
    ($) async {
      // ---------------------------------------------------------------
      // Setup: auth → record 5k_run.json → save (same as recording_flow_test)
      // ---------------------------------------------------------------
      await initializeTestServices();
      await clearAuthSession();
      // Pre-authenticate BEFORE pumping the widget to avoid rapid router
      // redirect cycles that cause duplicate GlobalKey errors in
      // go_router's StatefulShellRoute.
      await preAuthenticate();
      // Fast replay: 620 points × 10ms ≈ 6.2s instead of 124s at default 200ms.
      // The test needs the full 5k_run fixture replayed before stopping.
      await $.pumpWidget(
        await buildTestApp(
          replayEmissionInterval: const Duration(milliseconds: 10),
        ),
      );
      await cleanupTestData($);

      addTearDown(() async {
        await unmountTestApp($);
        await cleanupTestData($);
        await clearAuthSession();
      });

      final recordTabFinder = find.text('Record');
      await $(recordTabFinder).waitUntilVisible();
      await $(recordTabFinder).tap();

      final startButtonFinder = find.byKey(RecordingScreen.startButtonKey);
      final pauseButtonFinder = find.byKey(RecordingScreen.pauseButtonKey);
      final finishButtonFinder = find.byKey(RecordingScreen.finishButtonKey);

      await $(startButtonFinder).waitUntilVisible();
      await $(startButtonFinder).tap();

      // Wait for the full 5k replay to complete before stopping.
      // At 10ms emission interval, 620 points takes ~6.2s.
      await waitForNonZeroDistance(
        $,
        minimumDistanceKilometers: 5,
        maxPollAttempts: 80,
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

      // ---------------------------------------------------------------
      // Assert: rTSS on the activity detail screen
      // ---------------------------------------------------------------
      // Wait for the saved detail shell to mount. The shared reader handles
      // revealing the below-fold analytics card before it waits for the exact
      // rTSS/cTSS/TSS label, which avoids broad-text false positives.
      await $(
        find.byKey(ActivityDetailScreen.distanceValueTextKey),
      ).waitUntilVisible();

      final tssValue = await readActivityDetailTssValue($);
      // Derived from unit-tested rTSS computation on the 5k_run fixture:
      // distance ≈ 5.26 km, moving time ≈ 3095 s, threshold pace ≈ 589 s/km
      // (auto-derived from single qualifying session), normalized pace ≈ 346
      // s/km (grade-adjusted 4th-power), IF ≈ 1.70 → rTSS ≈ 248.
      // Distance jitter (5.15–5.30 km) shifts rTSS from ~245 to ~260.
      // Tolerance band widened to 230–275 for E2E replay timing variance.
      expect(tssValue, inInclusiveRange(230, 275));

      // ---------------------------------------------------------------
      // Navigate: detail → home → analytics tab
      // ---------------------------------------------------------------
      final detailBackButtonFinder = find.byTooltip('Back');
      await $(detailBackButtonFinder).waitUntilVisible();
      await $(detailBackButtonFinder).tap();

      final analyticsTabFinder = find.byKey(HomeShellScreen.analyticsTabKey);
      await $(analyticsTabFinder).waitUntilVisible();
      await $(analyticsTabFinder).tap();

      // ---------------------------------------------------------------
      // Assert: CTL/ATL/TSB structural invariants on training load card
      // ---------------------------------------------------------------
      await $(find.byKey(TrainingLoadCard.dataStateKey)).waitUntilExists();

      final fitness = await readTrainingLoadMetricValue($, label: 'Fitness');
      final fatigue = await readTrainingLoadMetricValue($, label: 'Fatigue');
      final form = await readTrainingLoadMetricValue($, label: 'Form');

      // Single-activity invariants for a fresh account:
      // Fatigue (ATL, 7-day EMA) > Fitness (CTL, 42-day EMA) > 0
      // because a single recent activity loads more into the short-term average.
      // Form (TSB = CTL − ATL) < 0 because ATL > CTL.
      expect(fatigue, greaterThan(fitness));
      expect(fitness, greaterThan(0));
      expect(form, lessThan(0));
    },
  );
}

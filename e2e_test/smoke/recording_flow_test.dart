import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/recording_screen.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

// ## Test Scenarios
// - [positive] Pre-authenticated user records and saves a replay-backed run,
//   then opens activity detail.
// - [edge] Saved distance and pace stay within bounded replay ranges and
//   splits render the expected count.
void main() {
  patrolTest(
    'pre-authenticated user records and saves a non-zero distance activity',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();
      // Pre-authenticate BEFORE pumping the widget to avoid rapid router
      // redirect cycles that cause duplicate GlobalKey errors in
      // go_router's StatefulShellRoute.
      await preAuthenticate();
      await $.pumpWidget(await buildTestApp());
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

      // Wait for the full replay route to accumulate enough distance for
      // the assertions below (5.15-5.30 km with 5 splits).
      await waitForNonZeroDistance(
        $,
        minimumDistanceKilometers: 5,
        maxPollAttempts: 720,
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

      final detailDistanceFinder = find.byKey(
        ActivityDetailScreen.distanceValueTextKey,
      );
      await $(detailDistanceFinder).waitUntilVisible();
      final distanceKilometers = await readActivityDetailDistanceKilometers($);
      // UI shows distance with two decimals and replay/save timing introduces
      // jitter — the stop signal can land anywhere in the current poll window
      // so the recorded distance can be slightly above or below the threshold.
      expect(distanceKilometers, inInclusiveRange(5.00, 5.35));

      final averagePaceSecondsPerKm =
          await readActivityDetailAveragePaceSecondsPerKm($);
      // Pace text rounds to whole seconds and can drift slightly across replay runs.
      expect(averagePaceSecondsPerKm, inInclusiveRange(582, 594));

      await revealActivityDetailSplitsSection($);
      final splitRowCount = await readActivityDetailSplitRowCount($);
      expect(splitRowCount, 5);
    },
  );
}

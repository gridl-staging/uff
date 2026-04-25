import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/recording_screen.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

// ## Test Scenarios
// - [positive] Pre-authenticated user can save a replayed run with auto-pause
//   segments and open activity detail.
// - [edge] Auto-pause fixture yields the exact expected moving-time duration
//   after save.
void main() {
  patrolTest(
    'pre-authenticated user sees moving time from auto-pause replay after save',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();
      // Pre-authenticate BEFORE pumping the widget to avoid rapid router
      // redirect cycles that cause duplicate GlobalKey errors in
      // go_router's StatefulShellRoute.
      await preAuthenticate();
      await $.pumpWidget(
        await buildTestApp(
          fixturePath: 'e2e_test/test_data/generated/auto_pause_test.json',
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
      await waitForNonZeroDistance(
        $,
        minimumDistanceKilometers: 0.10,
        maxPollAttempts: 120,
      );

      // 154 fixture points at 10ms each complete in about 1.5 seconds.
      await advanceTestClock($, const Duration(seconds: 4));

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
        find.byKey(ActivityDetailScreen.durationValueTextKey),
      ).waitUntilVisible();

      final duration = await readActivityDetailDuration($);
      expect(duration, const Duration(minutes: 10));
    },
  );
}

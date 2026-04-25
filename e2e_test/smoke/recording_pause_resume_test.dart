import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/recording_screen.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

// ## Test Scenarios
// - [positive] Pre-authenticated user can save a paused and resumed recording.
// - [statemachine] Pause freezes elapsed metrics and resume restarts distance
//   growth before save.
void main() {
  patrolTest('pre-authenticated user can pause and resume a recording', (
    $,
  ) async {
    await initializeTestServices();
    await clearAuthSession();
    // Pre-authenticate BEFORE pumping the widget to avoid rapid router
    // redirect cycles that cause duplicate GlobalKey errors in
    // go_router's StatefulShellRoute.
    await preAuthenticate();
    await $.pumpWidget(
      await buildTestApp(
        replayEmissionInterval: const Duration(milliseconds: 20),
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
    final resumeButtonFinder = find.byKey(RecordingScreen.resumeButtonKey);
    final finishButtonFinder = find.byKey(RecordingScreen.finishButtonKey);

    await $(startButtonFinder).waitUntilVisible();
    await $(startButtonFinder).tap();
    await waitForNonZeroDistance(
      $,
      minimumDistanceKilometers: 0.10,
      maxPollAttempts: 120,
    );

    final distanceBeforePause = await readRecordingDistanceKilometers($);
    final elapsedBeforePause = await readRecordingElapsedDuration($);

    await $(pauseButtonFinder).waitUntilVisible();
    await $(pauseButtonFinder).tap();
    await $(find.text('Paused')).waitUntilVisible();

    await advanceTestClock($, const Duration(seconds: 2));

    final distanceWhilePaused = await readRecordingDistanceKilometers($);
    final elapsedWhilePaused = await readRecordingElapsedDuration($);

    expect(distanceWhilePaused, distanceBeforePause);
    expect(elapsedWhilePaused, elapsedBeforePause);

    await $(resumeButtonFinder).waitUntilVisible();
    await $(resumeButtonFinder).tap();
    await $(find.text('Recording')).waitUntilVisible();

    await waitForRecordingDistanceIncrease(
      $,
      baselineKilometers: distanceWhilePaused,
      minimumDeltaKilometers: 0.02,
    );

    await $(pauseButtonFinder).waitUntilVisible();
    await $(pauseButtonFinder).tap();
    await $(finishButtonFinder).waitUntilVisible();
    await $(finishButtonFinder).tap();

    final draftSaveFinder = find.byKey(ActivityDetailScreen.draftSaveButtonKey);
    await revealDraftSaveButton($);
    await $(draftSaveFinder).waitUntilVisible();
    await $(draftSaveFinder).tap();
    await $(
      find.byKey(ActivityDetailScreen.distanceValueTextKey),
    ).waitUntilVisible();
  });
}

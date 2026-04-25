import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_entry_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_history_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_review_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/recording_screen.dart';
import 'package:uff/src/features/analytics/presentation/analytics_screen.dart';
import 'package:uff/src/features/analytics/presentation/pmc_chart_widget.dart';
import 'package:uff/src/features/analytics/presentation/training_load_card.dart';
import 'package:uff/src/features/social/presentation/feed_screen.dart';
import 'package:uff/src/routing/home_shell_screen.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

const _photoFixturePaths = <String>['e2e_test/test_data/photo_a.jpg'];

// Sentinel directory for file-based test-to-script coordination.
// The wrapper script polls for .ready_<screen> files, captures the screenshot,
// then writes .captured_<screen> acknowledgements.
//
// The project root must be passed via --dart-define=PROJECT_ROOT=<abs_path>
// because the Patrol test runner's CWD on iOS simulator is NOT the project
// root, so relative paths would resolve to the wrong location.
const _projectRoot = String.fromEnvironment('PROJECT_ROOT');
final String _sentinelDir = _projectRoot.isEmpty
    ? (throw StateError(
        'PROJECT_ROOT must be passed via --dart-define=PROJECT_ROOT=<absolute repo path>. '
        'The Patrol test runner CWD is not the repo root, so relative sentinel '
        'paths will not match the fake-ack loop or capture script.',
      ))
    : '$_projectRoot/tmp/screenshots';

// How long to wait for the wrapper script to capture before timing out.
const _captureAckTimeout = Duration(seconds: 60);
const _captureAckPollInterval = Duration(milliseconds: 250);

// Screen names matching the App Store screenshot contract.
const _screenRecording = 'activity-recording';
const _screenDetail = 'activity-detail';
const _screenAnalytics = 'analytics-dashboard';
const _screenFeed = 'social-feed';
const _screenPhoto = 'activity-photo';

// ## Test Scenarios
// - [positive] Sequential navigation through 5 app screens with file-based
//   signaling for external screenshot capture by wrapper script.
void main() {
  patrolTest(
    'navigate 5 screens with file-based screenshot signaling',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();

      // Seed social graph before launching app. seedSocialScenario() creates
      // 4 accounts, sets up follows, and ends authenticated as viewer.
      final scenario = await seedSocialScenario();

      await $.pumpWidget(
        await buildTestApp(
          fixturePath: 'e2e_test/test_data/generated/long_easy_run.json',
          replayEmissionInterval: const Duration(milliseconds: 10),
          fixtureOverrides: await buildPhotoPickerFixtureOverrides(
            _photoFixturePaths,
          ),
        ),
      );
      await cleanupTestData($);

      final seededRemoteActivityIds = <String>{};

      addTearDown(() async {
        await unmountTestApp($);
        await cleanupSeededPhotoArtifacts(
          remoteActivityIds: seededRemoteActivityIds,
        );
        await cleanupSocialScenario(scenario);
        await cleanupTestData($);
        await clearAuthSession();
      });

      // Wait for authenticated home shell to confirm app launched.
      await $(
        find.byKey(HomeShellScreen.openSettingsButtonKey),
      ).waitUntilVisible(timeout: const Duration(seconds: 30));

      // --- Screen 1: Activity Recording ---
      await navigateToHomeShellDestination(
        $,
        HomeShellDestinationId.record,
      );
      await $(
        find.byKey(RecordingScreen.startButtonKey),
      ).waitUntilVisible();
      await $(find.byKey(RecordingScreen.startButtonKey)).tap();

      // Wait for enough distance to show meaningful recording data.
      await waitForNonZeroDistance(
        $,
        minimumDistanceKilometers: 1,
        maxPollAttempts: 120,
      );
      await _signalScreenReady(_screenRecording);
      await _waitForCaptureAck(_screenRecording);

      // --- Screen 2: Activity Detail / Review ---
      // Finishing a recording now routes to ActivityReviewScreen for draft
      // runs. Keep the stable `activity-detail` artifact slug so the wrapper
      // output contract and downstream screenshot naming do not drift.
      await $(find.byKey(RecordingScreen.pauseButtonKey)).waitUntilVisible();
      await $(find.byKey(RecordingScreen.pauseButtonKey)).tap();
      await $(find.byKey(RecordingScreen.finishButtonKey)).waitUntilVisible();
      await $(find.byKey(RecordingScreen.finishButtonKey)).tap();

      // Wait on review-specific keys instead of saved-detail keys. The route
      // split is intentional, and using review keys keeps this test capable of
      // catching a real regression back to the wrong surface.
      await $(
        find.byKey(ActivityReviewScreen.distanceValueTextKey),
      ).waitUntilVisible(timeout: const Duration(seconds: 30));
      // Smaller screenshot devices can place the explanatory review note below
      // the fold while the correct review branch is already active. Waiting on
      // the branch key keeps the readiness gate truthful across viewports
      // without requiring a pre-capture scroll on narrow devices.
      await $(
        find.byKey(ActivityEntryScreen.reviewBranchKey),
      ).waitUntilExists(timeout: const Duration(seconds: 10));
      await _signalScreenReady(_screenDetail);
      await _waitForCaptureAck(_screenDetail);

      // Save the draft only after the screenshot. The CTA lives deep in the
      // review scroll body, so reveal it after capture instead of scrolling
      // away from the intended screenshot framing.
      await revealDraftSaveButton($);
      await $(
        find.byKey(ActivityReviewScreen.draftSaveButtonKey),
      ).waitUntilVisible();
      await $(find.byKey(ActivityReviewScreen.draftSaveButtonKey)).tap();
      // After finalization the wrapper route switches from the review branch
      // to the saved-detail branch. Wait on the branch key directly so the
      // analytics step only runs after the route contract is satisfied.
      await $(
        find.byKey(ActivityEntryScreen.detailBranchKey),
      ).waitUntilExists(timeout: const Duration(seconds: 15));

      // --- Screen 3: Analytics Dashboard ---
      await $(find.byTooltip('Back')).waitUntilVisible();
      await $(find.byTooltip('Back')).tap();

      await navigateToHomeShellDestination(
        $,
        HomeShellDestinationId.analytics,
      );
      // Wait for analytics data to load before checking card states.
      await $(
        find.byKey(AnalyticsScreen.contentListViewKey),
      ).waitUntilVisible(timeout: const Duration(seconds: 30));
      await $(
        find.byKey(TrainingLoadCard.dataStateKey),
      ).waitUntilExists(timeout: const Duration(seconds: 30));
      await $(
        find.byKey(PmcChartWidget.dataStateKey),
      ).waitUntilExists(timeout: const Duration(seconds: 30));
      await _signalScreenReady(_screenAnalytics);
      await _waitForCaptureAck(_screenAnalytics);

      // --- Screen 4: Social Feed ---
      await navigateToHomeShellDestination($, HomeShellDestinationId.feed);
      await $(
        find.byKey(FeedScreen.feedCardKey(scenario.feedActivityId)),
      ).waitUntilVisible(timeout: const Duration(seconds: 30));
      await _signalScreenReady(_screenFeed);
      await _waitForCaptureAck(_screenFeed);

      // --- Screen 5: Activity Photo ---
      await navigateToHomeShellDestination(
        $,
        HomeShellDestinationId.activity,
      );

      final seededActivity = await seedSyncedActivity(
        $,
        distanceMeters: 4200,
        startedAt: DateTime.utc(2026, 1, 22, 7),
      );
      seededRemoteActivityIds.add(seededActivity.remoteActivityId);

      await waitForHomeActivityHistoryLoaded($);
      final activityCardFinder = find.byKey(
        ActivityHistoryScreen.activityCardKey(seededActivity.localSessionId),
      );
      await $(activityCardFinder).waitUntilVisible();
      await $(activityCardFinder).tap();

      // Saved detail is read-first. Enter edit mode before trying to attach a
      // screenshot photo, then scroll the photo section into view because the
      // add button can still start below the viewport on smaller devices.
      await revealActivityDetailPhotoSectionInEditMode($);

      await $(find.byKey(ActivityDetailScreen.photoAddButtonKey)).tap();
      await $(
        find.byKey(ActivityDetailScreen.photoSourceSheetKey),
      ).waitUntilVisible();
      await $(
        find.byKey(ActivityDetailScreen.photoSourceGalleryOptionKey),
      ).waitUntilVisible();
      await $(
        find.byKey(ActivityDetailScreen.photoSourceGalleryOptionKey),
      ).tap();

      await waitForPhotoThumbnailToAppear($);
      await _signalScreenReady(_screenPhoto);
      await _waitForCaptureAck(_screenPhoto);
    },
  );
}

/// Writes a sentinel file to signal the wrapper script that a screen is ready
/// for capture.
Future<void> _signalScreenReady(String screenName) async {
  final dir = Directory(_sentinelDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final sentinel = File('$_sentinelDir/.ready_$screenName');
  await sentinel.writeAsString(
    DateTime.now().toIso8601String(),
    flush: true,
  );
}

/// Polls for the wrapper script's capture acknowledgement file.
/// Throws if the ack is not received within the timeout.
Future<void> _waitForCaptureAck(String screenName) async {
  final ackFile = File('$_sentinelDir/.captured_$screenName');
  final deadline = DateTime.now().add(_captureAckTimeout);

  while (DateTime.now().isBefore(deadline)) {
    if (ackFile.existsSync()) {
      return;
    }
    await Future<void>.delayed(_captureAckPollInterval);
  }

  throw StateError(
    'Timed out waiting for capture acknowledgement: '
    '$_sentinelDir/.captured_$screenName',
  );
}

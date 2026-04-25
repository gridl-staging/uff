import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_history_screen.dart';
import 'package:uff/src/features/social/presentation/remote_activity_detail_screen.dart';
import 'package:uff/src/features/social/presentation/social_user_row.dart';
import 'package:uff/src/features/social/presentation/viewed_user_profile_screen.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

const _photoFixturePaths = <String>['e2e_test/test_data/photo_a.jpg'];
const _hostedProfileLoadTimeout = Duration(seconds: 20);

// ## Test Scenarios
// - [positive] Synced activity detail edit mode shows empty photo state and
//   add affordance before uploads.
// - [positive] Synced activity detail edit mode supports photo add, viewer
//   open, and delete lifecycle end-to-end.
// - [positive] Follower and stranger remote detail show the photo strip only
//   for activities that remain viewer-visible under public/followers privacy.
// - [edge] Unsynced activity detail blocks photo uploads and shows gating copy.
// - [negative] Stranger cannot reach followers-only or private owner activities
//   through visible profile UI, so no leaked remote-detail photo strip exists
//   for those hidden rows. Direct metadata/storage denial stays owned by
//   activity_photo_rls_smoke_test.dart.
// - [isolation] Relaunching as follower then stranger reloads profile/detail
//   state for the authenticated viewer without retaining prior photo access.
void main() {
  patrolTest(
    'synced activity detail edit mode loads photo empty state and add affordance',
    ($) async {
      await _launchPreAuthenticatedApp(
        $,
        fixtureOverrides: await buildPhotoPickerFixtureOverrides(
          _photoFixturePaths,
        ),
      );
      final seededRemoteActivityIds = _registerCommonTearDown($);

      final seededActivity = await seedSyncedActivity(
        $,
        distanceMeters: 4200,
        startedAt: DateTime.utc(2026, 1, 22, 7),
      );
      seededRemoteActivityIds.add(seededActivity.remoteActivityId);

      await _openActivityDetailFromHistory($, seededActivity.localSessionId);
      await revealActivityDetailPhotoSectionInEditMode($);

      await $(
        find.byKey(ActivityDetailScreen.photoEmptyStateKey),
      ).waitUntilVisible();
      await $(
        find.byKey(ActivityDetailScreen.photoAddButtonKey),
      ).waitUntilVisible();
      expect(
        find.byKey(ActivityDetailScreen.photoUnsyncedMessageKey),
        findsNothing,
      );
    },
  );

  patrolTest(
    'synced activity detail edit mode supports photo add, viewer open, and delete lifecycle',
    ($) async {
      await _launchPreAuthenticatedApp(
        $,
        fixtureOverrides: await buildPhotoPickerFixtureOverrides(
          _photoFixturePaths,
        ),
      );
      final seededRemoteActivityIds = _registerCommonTearDown($);

      final seededActivity = await seedSyncedActivity(
        $,
        distanceMeters: 5300,
        startedAt: DateTime.utc(2026, 1, 22, 8),
      );
      seededRemoteActivityIds.add(seededActivity.remoteActivityId);

      await _openActivityDetailFromHistory($, seededActivity.localSessionId);
      await revealActivityDetailPhotoSectionInEditMode($);

      await $(
        find.byKey(ActivityDetailScreen.photoEmptyStateKey),
      ).waitUntilVisible();
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
      expect(find.byKey(ActivityDetailScreen.photoEmptyStateKey), findsNothing);

      await tapFirstPhotoThumbnail($);
      await $(
        find.byKey(ActivityDetailScreen.photoViewerKey),
      ).waitUntilVisible();

      await $(
        find.byKey(ActivityDetailScreen.photoViewerDeleteButtonKey),
      ).waitUntilVisible();
      await $(
        find.byKey(ActivityDetailScreen.photoViewerDeleteButtonKey),
      ).tap();
      await $(
        find.byKey(ActivityDetailScreen.photoDeleteConfirmKey),
      ).waitUntilVisible();
      await $(find.byKey(ActivityDetailScreen.photoDeleteConfirmKey)).tap();

      // After delete confirmation the viewer auto-pops back to activity detail
      // via Navigator.of(context).pop() — no additional Back tap is needed.
      await waitForPhotoThumbnailToDisappear($);
    },
  );

  patrolTest(
    'unsynced activity detail shows photo gating message and hides add action',
    ($) async {
      await _launchPreAuthenticatedApp($);
      _registerCommonTearDown($);

      final localSessionId = await seedActivity(
        $,
        distanceMeters: 2700,
        startedAt: DateTime.utc(2026, 1, 22, 9),
      );

      await _openActivityDetailFromHistory($, localSessionId);
      await revealActivityDetailPhotoSection($);

      await $(
        find.byKey(ActivityDetailScreen.photoUnsyncedMessageKey),
      ).waitUntilVisible();
      expect(find.byKey(ActivityDetailScreen.photoAddButtonKey), findsNothing);
    },
  );

  patrolTest(
    'follower and stranger see remote-detail photos only for allowed owner activities',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();
      final scenario = await seedVisibilityMatrixScenario();
      final seededRemoteActivityIds = <String>{
        scenario.publicActivityId,
        scenario.followersActivityId,
        scenario.privateActivityId,
      };

      await preAuthenticate(
        email: scenario.owner.email,
        password: scenario.owner.password,
      );
      await seedRemoteActivityPhoto(activityId: scenario.publicActivityId);
      await seedRemoteActivityPhoto(activityId: scenario.followersActivityId);
      await seedRemoteActivityPhoto(activityId: scenario.privateActivityId);

      addTearDown(() async {
        await cleanupTestData($);
        await unmountTestApp($);
        await preAuthenticate(
          email: scenario.owner.email,
          password: scenario.owner.password,
        );
        await cleanupSeededPhotoArtifacts(
          remoteActivityIds: seededRemoteActivityIds,
        );
        await cleanupVisibilityMatrixScenario(scenario);
        await clearAuthSession();
      });

      await launchAuthenticatedApp(
        $,
        email: scenario.follower.email,
        password: scenario.follower.password,
      );
      await _openOwnerProfileFromSearch($, scenario);

      expect(
        find.byKey(
          ViewedUserProfileScreen.activityRowKey(scenario.publicActivityId),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ViewedUserProfileScreen.activityRowKey(scenario.followersActivityId),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ViewedUserProfileScreen.activityRowKey(scenario.privateActivityId),
        ),
        findsNothing,
      );

      await _openRemoteDetailFromViewedProfile($, scenario.publicActivityId);
      await $(
        find.byKey(RemoteActivityDetailScreen.photoStripKey),
      ).waitUntilVisible();
      await _returnToViewedUserProfile($);

      await _openRemoteDetailFromViewedProfile($, scenario.followersActivityId);
      await $(
        find.byKey(RemoteActivityDetailScreen.photoStripKey),
      ).waitUntilVisible();
      await _returnToViewedUserProfile($);

      await cleanupTestData($);
      await unmountTestApp($);
      await launchAuthenticatedApp(
        $,
        email: scenario.stranger.email,
        password: scenario.stranger.password,
      );
      await _openOwnerProfileFromSearch($, scenario);

      expect(
        find.byKey(
          ViewedUserProfileScreen.activityRowKey(scenario.publicActivityId),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ViewedUserProfileScreen.activityRowKey(scenario.followersActivityId),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          ViewedUserProfileScreen.activityRowKey(scenario.privateActivityId),
        ),
        findsNothing,
      );

      await _openRemoteDetailFromViewedProfile($, scenario.publicActivityId);
      await $(
        find.byKey(RemoteActivityDetailScreen.photoStripKey),
      ).waitUntilVisible();
    },
  );
}

Future<void> _launchPreAuthenticatedApp(
  PatrolIntegrationTester $, {
  List<Object> fixtureOverrides = const <Object>[],
  String? email,
  String? password,
}) async {
  await initializeTestServices();
  await clearAuthSession();
  // Pre-authenticate BEFORE pumping the widget to avoid rapid router
  // redirect cycles that cause duplicate GlobalKey errors in
  // go_router's StatefulShellRoute.
  await preAuthenticate(email: email, password: password);
  await $.pumpWidget(
    await buildTestApp(
      trackingOverrides: false,
      fixtureOverrides: fixtureOverrides,
    ),
  );
  await cleanupTestData($);
}

Set<String> _registerCommonTearDown(PatrolIntegrationTester $) {
  final seededRemoteActivityIds = <String>{};
  addTearDown(() async {
    await unmountTestApp($);
    await cleanupSeededPhotoArtifacts(
      remoteActivityIds: seededRemoteActivityIds,
    );
    await cleanupTestData($);
    await unmountTestApp($);
    await clearAuthSession();
  });
  return seededRemoteActivityIds;
}

Future<void> _openActivityDetailFromHistory(
  PatrolIntegrationTester $,
  int activityId,
) async {
  // Navigate to Activity tab first — the app defaults to the Feed tab.
  await waitForHomeActivityHistoryLoaded($);
  final activityCardFinder = find.byKey(
    ActivityHistoryScreen.activityCardKey(activityId),
  );
  await $(activityCardFinder).waitUntilVisible();
  await $(activityCardFinder).tap();
}

Future<void> _openOwnerProfileFromSearch(
  PatrolIntegrationTester $,
  VisibilityMatrixScenario scenario,
) async {
  await navigateToSearchScreen($);
  await submitRelationshipSearchQuery($, scenario.owner.displayName);
  final ownerResultFinder = find.byKey(
    SocialUserRow.userRowKey(scenario.ownerUserId),
  );
  await $(
    ownerResultFinder,
  ).waitUntilVisible(timeout: _hostedProfileLoadTimeout);
  await $(ownerResultFinder).tap();
  await _waitForViewedUserProfileHeader($);
}

Future<void> _openRemoteDetailFromViewedProfile(
  PatrolIntegrationTester $,
  String activityId,
) async {
  final activityRowFinder = find.byKey(
    ViewedUserProfileScreen.activityRowKey(activityId),
  );
  await $(activityRowFinder).waitUntilVisible();
  await $(activityRowFinder).tap();
  await $(
    find.byKey(RemoteActivityDetailScreen.contentStateKey),
  ).waitUntilVisible();
}

Future<void> _returnToViewedUserProfile(PatrolIntegrationTester $) async {
  await $(find.byTooltip('Back')).waitUntilVisible();
  await $(find.byTooltip('Back')).tap();
  await _waitForViewedUserProfileHeader($);
}

Future<void> _waitForViewedUserProfileHeader(PatrolIntegrationTester $) {
  return $(
    find.byKey(ViewedUserProfileScreen.headerCardKey),
  ).waitUntilVisible(timeout: _hostedProfileLoadTimeout);
}

// Scenario tags use markdown-style brackets (for example [negative]) that are
// parsed as references by this lint, so we ignore it for the file header block.
// ignore_for_file: comment_references

import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/social/presentation/feed_screen.dart';
import 'package:uff/src/features/social/presentation/social_user_row.dart';
import 'package:uff/src/features/social/presentation/viewed_user_profile_screen.dart';
import 'package:uff/src/routing/app_router.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

const _hostedProfileLoadTimeout = Duration(seconds: 20);

/// ## Test Scenarios
/// - [positive] Owner sees all own activities (public, followers, private) on social profile
/// - [positive] Accepted follower sees public + followers and not private
/// - [negative] Stranger sees only public activity
/// - [negative] Private activity is owner-only
/// - [isolation] Re-authenticated stranger cannot see follower-only or private owner activity
/// - [statemachine] Stranger walks full follow lifecycle and sees visibility change at each transition
void main() {
  patrolTest(
    'core visibility matrix proves owner, accepted follower, and stranger access',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();
      final scenario = await seedVisibilityMatrixScenario();
      expect(
        scenario.owner.displayName,
        matches(RegExp(r'^Matrix Owner [0-9]{6}-[A-Za-z0-9]{8}$')),
      );

      addTearDown(() async {
        await unmountTestApp($);
        await cleanupVisibilityMatrixScenario(scenario);
        await cleanupTestData($);
        await clearAuthSession();
      });

      await launchAuthenticatedApp(
        $,
        email: scenario.owner.email,
        password: scenario.owner.password,
      );

      await navigateToOwnSocialProfile($, ownerUserId: scenario.ownerUserId);
      await _waitForViewedUserProfileHeader($);
      _assertOwnerActivityVisibility(
        scenario: scenario,
        followersVisible: true,
        privateVisible: true,
      );

      await unmountTestApp($);
      await launchAuthenticatedApp(
        $,
        email: scenario.follower.email,
        password: scenario.follower.password,
      );
      await _assertFollowerVisibilityAcrossFeedAndProfile($, scenario);

      await unmountTestApp($);
      await launchAuthenticatedApp(
        $,
        email: scenario.stranger.email,
        password: scenario.stranger.password,
      );
      await _openOwnerProfileFromSearch($, scenario);
      _assertOwnerActivityVisibility(
        scenario: scenario,
        followersVisible: false,
        privateVisible: false,
      );
    },
  );

  patrolTest(
    'transitioner lifecycle moves stranger -> requested -> follower -> unfollowed',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();
      final scenario = await seedVisibilityMatrixScenario();

      addTearDown(() async {
        await unmountTestApp($);
        await cleanupVisibilityMatrixScenario(scenario);
        await cleanupTestData($);
        await clearAuthSession();
      });

      await launchAuthenticatedApp(
        $,
        email: scenario.transitioner.email,
        password: scenario.transitioner.password,
      );
      await _openOwnerProfileFromSearch($, scenario);

      _assertOwnerActivityVisibility(
        scenario: scenario,
        followersVisible: false,
        privateVisible: false,
      );
      expect(
        _followActionLabel(scenario.ownerUserId, 'Follow'),
        findsOneWidget,
      );
      await $(
        find.byKey(SocialUserRow.actionButtonKey(scenario.ownerUserId)),
      ).tap();
      await $(
        _followActionLabel(scenario.ownerUserId, 'Requested'),
      ).waitUntilVisible();
      _assertOwnerActivityVisibility(
        scenario: scenario,
        followersVisible: false,
        privateVisible: false,
      );

      // Owner-side follow acceptance mutates the shared Supabase auth client.
      // Tear down the transitioner app first so the mounted router does not
      // observe an out-of-band user swap and leave a stale shell behind.
      await unmountTestApp($);
      await acceptFollowRequestAsOwner(
        owner: scenario.owner,
        followerId: scenario.transitionerUserId,
        ownerUserId: scenario.ownerUserId,
      );

      await launchAuthenticatedApp(
        $,
        email: scenario.transitioner.email,
        password: scenario.transitioner.password,
      );
      await _openOwnerProfileViaDirectSearch($, scenario);

      _assertOwnerActivityVisibility(
        scenario: scenario,
        followersVisible: true,
        privateVisible: false,
      );
      expect(
        _followActionLabel(scenario.ownerUserId, 'Following'),
        findsOneWidget,
      );
      await $(
        find.byKey(SocialUserRow.actionButtonKey(scenario.ownerUserId)),
      ).tap();

      await $(
        _followActionLabel(scenario.ownerUserId, 'Follow'),
      ).waitUntilVisible();
      _assertOwnerActivityVisibility(
        scenario: scenario,
        followersVisible: false,
        privateVisible: false,
      );
    },
  );
}

Future<void> _openOwnerProfileFromSearch(
  PatrolIntegrationTester $,
  VisibilityMatrixScenario scenario,
) async {
  await navigateToHomeShellDestination($, HomeShellDestinationId.feed);
  // The empty-state sliver can exist before Patrol considers it hit-testable on
  // smaller hosted viewports. The CTA button is the real user action we need.
  await $(
    find.byKey(FeedScreen.searchCtaButtonKey),
  ).waitUntilVisible(timeout: _hostedProfileLoadTimeout);
  await $(find.byKey(FeedScreen.searchCtaButtonKey)).tap();
  await submitRelationshipSearchQuery($, scenario.owner.displayName);
  await _openOwnerProfileFromSearchResults($, scenario);
}

Future<void> _openOwnerProfileViaDirectSearch(
  PatrolIntegrationTester $,
  VisibilityMatrixScenario scenario,
) async {
  await navigateToSearchScreen($);
  await submitRelationshipSearchQuery($, scenario.owner.displayName);
  await _openOwnerProfileFromSearchResults($, scenario);
}

Future<void> _openOwnerProfileFromSearchResults(
  PatrolIntegrationTester $,
  VisibilityMatrixScenario scenario,
) async {
  final ownerResultFinder = find.byKey(
    SocialUserRow.userRowKey(scenario.ownerUserId),
  );
  await $(
    ownerResultFinder,
  ).waitUntilVisible(timeout: _hostedProfileLoadTimeout);
  await $(ownerResultFinder).tap();
  await _waitForViewedUserProfileHeader($);
}

Future<void> _assertFollowerVisibilityAcrossFeedAndProfile(
  PatrolIntegrationTester $,
  VisibilityMatrixScenario scenario,
) async {
  await navigateToHomeShellDestination($, HomeShellDestinationId.feed);
  await $(
    find.byKey(FeedScreen.feedCardKey(scenario.publicActivityId)),
  ).waitUntilVisible();
  expect(
    find.byKey(FeedScreen.feedCardKey(scenario.publicActivityId)),
    findsOneWidget,
  );
  expect(
    find.byKey(FeedScreen.feedCardKey(scenario.followersActivityId)),
    findsOneWidget,
  );
  expect(
    find.byKey(FeedScreen.feedCardKey(scenario.privateActivityId)),
    findsNothing,
  );
  expect(find.text(scenario.publicTitle), findsOneWidget);
  expect(find.text(scenario.followersTitle), findsOneWidget);
  expect(find.text(scenario.privateTitle), findsNothing);

  await $(
    find.byKey(FeedScreen.ownerTapTargetKey(scenario.publicActivityId)),
  ).tap();
  await _waitForViewedUserProfileHeader($);
  _assertOwnerActivityVisibility(
    scenario: scenario,
    followersVisible: true,
    privateVisible: false,
  );
}

Future<void> _waitForViewedUserProfileHeader(PatrolIntegrationTester $) {
  // Hosted signoff runs routinely take longer than Patrol's 10s default to
  // finish loading profile header + activity data after a route push.
  return $(
    find.byKey(ViewedUserProfileScreen.headerCardKey),
  ).waitUntilVisible(timeout: _hostedProfileLoadTimeout);
}

Finder _followActionLabel(String userId, String label) {
  return find.descendant(
    of: find.byKey(SocialUserRow.actionButtonKey(userId)),
    matching: find.text(label),
  );
}

void _assertOwnerActivityVisibility({
  required VisibilityMatrixScenario scenario,
  required bool followersVisible,
  required bool privateVisible,
}) {
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
    followersVisible ? findsOneWidget : findsNothing,
  );
  expect(
    find.byKey(
      ViewedUserProfileScreen.activityRowKey(scenario.privateActivityId),
    ),
    privateVisible ? findsOneWidget : findsNothing,
  );
  expect(find.text(scenario.publicTitle), findsOneWidget);
  expect(
    find.text(scenario.followersTitle),
    followersVisible ? findsOneWidget : findsNothing,
  );
  expect(
    find.text(scenario.privateTitle),
    privateVisible ? findsOneWidget : findsNothing,
  );
}

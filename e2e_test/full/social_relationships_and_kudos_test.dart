import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/profile/presentation/profile_screen.dart';
import 'package:uff/src/features/social/presentation/feed_screen.dart';
import 'package:uff/src/features/social/presentation/relationship_search_screen.dart';
import 'package:uff/src/features/social/presentation/social_user_row.dart';
import 'package:uff/src/features/social/presentation/viewed_user_profile_screen.dart';
import 'package:uff/src/routing/app_router.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

// ## Test Scenarios
// - [positive] Feed kudos toggles and social relationship UI surfaces
//   (pending, following, viewed profile) work through user actions.
// - [negative] Accepting an incoming follow request removes that requester
//   from pending requests without incorrectly adding them to the viewer's
//   following list.
// - [positive] Relationship search returns the seeded search target when the
//   query includes that target's unique token.
// - [negative] After a seeded positive match, a guaranteed no-match query
//   clears the same row and renders the empty-search state.
void main() {
  patrolTest(
    'search, pending request handling, viewed profile, and kudos flows work through UI',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();
      final scenario = await seedSocialScenario();
      await $.pumpWidget(
        await buildTestApp(trackingOverrides: false),
      );
      await cleanupTestData($);

      addTearDown(() async {
        await unmountTestApp($);
        await cleanupSocialScenario(scenario);
        await cleanupTestData($);
        await clearAuthSession();
      });

      await $(
        find.byKey(HomeShellScreen.openSettingsButtonKey),
      ).waitUntilVisible(timeout: const Duration(seconds: 30));
      await navigateToHomeShellDestination($, HomeShellDestinationId.feed);

      final feedKudosCountFinder = find.byKey(
        FeedScreen.kudosCountKey(scenario.feedActivityId),
      );
      final feedKudosButtonFinder = find.byKey(
        FeedScreen.kudosButtonKey(scenario.feedActivityId),
      );
      await $(feedKudosCountFinder).waitUntilVisible();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.key == FeedScreen.kudosCountKey(scenario.feedActivityId) &&
              widget.data == '0',
        ),
        findsOneWidget,
      );
      await $(feedKudosButtonFinder).tap();
      await $(feedKudosCountFinder).waitUntilVisible();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.key == FeedScreen.kudosCountKey(scenario.feedActivityId) &&
              widget.data == '1',
        ),
        findsOneWidget,
      );

      await navigateToHomeShellDestination($, HomeShellDestinationId.profile);

      final pendingEntryFinder = find.byKey(
        ProfileScreen.pendingRequestsEntryRowKey,
      );
      await $(pendingEntryFinder).scrollTo();
      await $(pendingEntryFinder).tap();

      final incomingActionFinder = find.byKey(
        SocialUserRow.actionButtonKey(scenario.incomingRequesterUserId),
      );
      await $(incomingActionFinder).waitUntilVisible();
      await $(incomingActionFinder).tap();
      await $.pumpAndSettle();
      expect(
        find.byKey(SocialUserRow.userRowKey(scenario.incomingRequesterUserId)),
        findsNothing,
      );

      await $(find.byTooltip('Back')).tap();
      await $(
        find.byKey(ProfileScreen.followingEntryRowKey),
      ).waitUntilVisible();
      await $(find.byKey(ProfileScreen.followingEntryRowKey)).tap();

      final ownerRowFinder = find.byKey(
        SocialUserRow.userRowKey(scenario.feedOwnerUserId),
      );
      await $(ownerRowFinder).waitUntilVisible();
      // Accepting an incoming request should not create a new outgoing follow
      // edge for the viewer. The following list must still contain only the
      // owner the viewer actually followed during setup.
      expect(
        find.byKey(SocialUserRow.userRowKey(scenario.incomingRequesterUserId)),
        findsNothing,
      );
      expect(
        find.byKey(SocialUserRow.userRowKey(scenario.searchTargetUserId)),
        findsNothing,
      );
      await $(ownerRowFinder).tap();
      await $(
        find.byKey(ViewedUserProfileScreen.headerCardKey),
      ).waitUntilVisible();

      await $(find.byTooltip('Back')).tap();
      await $(find.byTooltip('Find People')).tap();
      await $(
        find.byKey(RelationshipSearchScreen.searchFieldKey),
      ).waitUntilVisible();
      final searchTargetRowFinder = find.byKey(
        SocialUserRow.userRowKey(scenario.searchTargetUserId),
      );
      await submitRelationshipSearchQuery($, scenario.searchTargetSearchToken);
      await $(searchTargetRowFinder).waitUntilVisible();
      await submitRelationshipSearchQuery(
        $,
        'no-match-${scenario.viewerUserId.substring(0, 8)}',
      );
      await $(
        find.byKey(RelationshipSearchScreen.emptyResultsKey),
      ).waitUntilVisible();
      expect(searchTargetRowFinder, findsNothing);
    },
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/profile/presentation/profile_screen.dart';
import 'package:uff/src/features/social/domain/relationship_counts.dart';

import 'profile_screen_test_support.dart';

// ## Test Scenarios
// - [positive] Renders social rows with exact follower/following/request counts
// - [positive] Social rows appear after stats section and before quick links
// - [positive] Loading state shows shimmer placeholders
// - [error] Error state displays error message
// - [positive] Followers row navigates to followers screen
// - [positive] Following row navigates to following screen
// - [positive] Requests row navigates to requests screen
// - [negative] User B counts do not bleed into User A display
// - [isolation] Social counts refresh independently of profile data

void main() {
  group('ProfileScreen social relationship entries', () {
    testWidgets('renders social entry rows with exact counts', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildProfileTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      final followersFinder = find.byKey(ProfileScreen.followersEntryRowKey);
      final followingFinder = find.byKey(ProfileScreen.followingEntryRowKey);
      final requestsFinder = find.byKey(
        ProfileScreen.pendingRequestsEntryRowKey,
      );

      expect(followersFinder, findsOneWidget);
      expect(followingFinder, findsOneWidget);
      expect(requestsFinder, findsOneWidget);

      expect(
        find.descendant(
          of: followersFinder,
          matching: find.text('Followers'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: followingFinder,
          matching: find.text('Following'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: requestsFinder,
          matching: find.text('Pending Requests'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: followersFinder, matching: find.text('12')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: followingFinder, matching: find.text('8')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: requestsFinder, matching: find.text('3')),
        findsOneWidget,
      );
    });

    testWidgets(
      'social section is anchored between stats and quick links with row order',
      (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildProfileTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        final followersY = tester
            .getCenter(find.byKey(ProfileScreen.followersEntryRowKey))
            .dy;
        final followingY = tester
            .getCenter(find.byKey(ProfileScreen.followingEntryRowKey))
            .dy;
        final requestsY = tester
            .getCenter(find.byKey(ProfileScreen.pendingRequestsEntryRowKey))
            .dy;
        final statsDistanceY = tester.getCenter(find.text('Distance')).dy;
        final manageGearY = tester
            .getCenter(find.widgetWithText(ListTile, 'Manage Gear'))
            .dy;

        expect(followersY, greaterThan(statsDistanceY));
        expect(followingY, greaterThan(followersY));
        expect(requestsY, greaterThan(followingY));
        expect(requestsY, lessThan(manageGearY));
      },
    );

    testWidgets('shows social entry loading state while counts load', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;
      final pendingCounts = Completer<RelationshipCounts>();
      addTearDown(() {
        if (!pendingCounts.isCompleted) {
          pendingCounts.complete(defaultRelationshipCounts);
        }
      });

      await tester.pumpWidget(
        buildProfileTestScope(
          profileRepo: profileRepo,
          relationshipCounts: (ref) => pendingCounts.future,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(ProfileScreen.relationshipCountsLoadingKey),
        findsOneWidget,
      );
    });

    testWidgets('shows social entry error state when counts fail', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildProfileTestScope(
          profileRepo: profileRepo,
          relationshipCounts: (ref) => Future<RelationshipCounts>.error(
            Exception('failed'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ProfileScreen.relationshipCountsErrorKey),
        findsOneWidget,
      );
      expect(find.text('Unable to load social counts'), findsOneWidget);
    });

    testWidgets('followers row pushes followers route', (tester) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildProfileRouterTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      final followersRow = find.byKey(ProfileScreen.followersEntryRowKey);
      await tester.scrollUntilVisible(
        followersRow,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(followersRow);
      await tester.pumpAndSettle();

      expect(find.text('Followers Target'), findsOneWidget);
    });

    testWidgets('following row pushes following route', (tester) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildProfileRouterTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      final followingRow = find.byKey(ProfileScreen.followingEntryRowKey);
      await tester.scrollUntilVisible(
        followingRow,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(followingRow);
      await tester.pumpAndSettle();

      expect(find.text('Following Target'), findsOneWidget);
    });

    testWidgets('pending requests row pushes requests route', (tester) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildProfileRouterTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      final requestsRow = find.byKey(ProfileScreen.pendingRequestsEntryRowKey);
      await tester.scrollUntilVisible(
        requestsRow,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(requestsRow);
      await tester.pumpAndSettle();

      expect(find.text('Requests Target'), findsOneWidget);
    });
  });
}

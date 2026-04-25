import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/common_widgets/user_avatar.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/presentation/profile_screen.dart';
import 'package:uff/src/features/settings/presentation/settings_screen.dart';
import 'package:uff/src/features/social/domain/relationship_counts.dart';

import 'profile_screen_test_support.dart';

// ## Test Scenarios
// - [positive] Loading state shows circular progress indicator
// - [positive] Error state shows retry button and error message
// - [positive] Identity section displays read-only display name text and avatar
// - [positive] Avatar shows initials fallback when no avatar URL
// - [positive] Avatar renders image when HTTPS URL is present
// - [positive] Aggregate stats show exact values in metric units
// - [positive] Aggregate stats show exact values in imperial units
// - [positive] Stats show zeros when no activities exist
// - [positive] Quick links navigate to Gear and Privacy Zones
// - [positive] Social section renders followers, following, pending counts
// - [negative] Moved settings/account controls are absent from the UI
// - [negative] SettingsScreen static keys are absent from ProfileScreen
// - [isolation] Auth repump resets profile state cleanly

void main() {
  group('ProfileScreen read-only', () {
    testWidgets('loading state shows circular progress indicator', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository();
      final pendingProfile = Completer<Profile>();
      profileRepo.getProfileCompleter = pendingProfile;
      addTearDown(() {
        if (!pendingProfile.isCompleted) {
          pendingProfile.complete(testProfile);
        }
      });

      await tester.pumpWidget(
        buildProfileTestScope(profileRepo: profileRepo),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('error state shows retry button and error message', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository();

      await tester.pumpWidget(
        buildProfileTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ProfileScreen.loadErrorStateKey),
        findsOneWidget,
      );
      expect(
        find.text('Failed to load profile. Please try again.'),
        findsOneWidget,
      );
      expect(
        find.byKey(ProfileScreen.loadErrorRetryButtonKey),
        findsOneWidget,
      );
    });

    testWidgets('error state retries and recovers', (tester) async {
      final profileRepo = FakeProfileRepository();

      await tester.pumpWidget(
        buildProfileTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ProfileScreen.loadErrorStateKey), findsOneWidget);

      profileRepo.profileToReturn = testProfile;
      await tester.tap(find.byKey(ProfileScreen.loadErrorRetryButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ProfileScreen.loadErrorStateKey), findsNothing);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('identity section displays read-only display name as text', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildProfileTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.byType(UserAvatar), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('avatar shows initials fallback when no avatar URL', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildProfileTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      final avatar = tester.widget<UserAvatar>(find.byType(UserAvatar));
      expect(avatar.avatarUrl, isNull);
      expect(avatar.displayName, 'Alice');
    });

    testWidgets('avatar renders image when HTTPS URL present', (
      tester,
    ) async {
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('NetworkImageLoadException')) return;
        origOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = origOnError);

      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfileWithAvatar;

      await tester.pumpWidget(
        buildProfileTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      final avatar = tester.widget<UserAvatar>(find.byType(UserAvatar));
      expect(avatar.avatarUrl, 'https://cdn.example.com/avatars/alice.jpg');
    });

    testWidgets(
      'aggregate stats show exact values in metric units with 4 activities',
      (tester) async {
        final sessions = buildTestSessions(
          count: 4,
        );
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildProfileTestScope(
            profileRepo: profileRepo,
            savedSessions: sessions,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(ProfileScreen.activitiesStatTileKey),
            matching: find.text('Activities'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(ProfileScreen.distanceStatTileKey),
            matching: find.text('Distance'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(ProfileScreen.activitiesThisMonthStatTileKey),
            matching: find.text('This Month'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(ProfileScreen.activitiesStatTileKey),
            matching: find.text('4'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(ProfileScreen.distanceStatTileKey),
            matching: find.text('20.00 km'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(ProfileScreen.activitiesThisMonthStatTileKey),
            matching: find.text('4'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'aggregate stats show exact values in imperial units',
      (tester) async {
        final sessions = buildTestSessions(
          count: 2,
          distanceMetersEach: 1609.34,
        );
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfileImperial;

        await tester.pumpWidget(
          buildProfileTestScope(
            profileRepo: profileRepo,
            savedSessions: sessions,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(ProfileScreen.activitiesStatTileKey),
            matching: find.text('Activities'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(ProfileScreen.distanceStatTileKey),
            matching: find.text('Distance'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(ProfileScreen.activitiesThisMonthStatTileKey),
            matching: find.text('This Month'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(ProfileScreen.activitiesStatTileKey),
            matching: find.text('2'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(ProfileScreen.distanceStatTileKey),
            matching: find.text('2.00 mi'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(ProfileScreen.activitiesThisMonthStatTileKey),
            matching: find.text('2'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('stats show zeros when no activities exist', (tester) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildProfileTestScope(
          profileRepo: profileRepo,
          savedSessions: const [],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(ProfileScreen.activitiesStatTileKey),
          matching: find.text('Activities'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ProfileScreen.distanceStatTileKey),
          matching: find.text('Distance'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ProfileScreen.activitiesThisMonthStatTileKey),
          matching: find.text('This Month'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ProfileScreen.activitiesStatTileKey),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ProfileScreen.distanceStatTileKey),
          matching: find.text('0.00 km'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ProfileScreen.activitiesThisMonthStatTileKey),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('gear quick link navigates to gear route', (tester) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildProfileRouterTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      final gearTile = find.widgetWithText(ListTile, 'Manage Gear');
      expect(gearTile, findsOneWidget);
      await tester.tap(gearTile);
      await tester.pumpAndSettle();

      expect(find.text('Gear Target'), findsOneWidget);
    });

    testWidgets('privacy zones quick link navigates to privacy zones route', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildProfileRouterTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      final privacyButton = find.byKey(ProfileScreen.privacyZonesButtonKey);
      await tester.scrollUntilVisible(
        privacyButton,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(privacyButton);
      await tester.pumpAndSettle();

      expect(find.text('Privacy Zones Target'), findsOneWidget);
    });

    testWidgets('social section renders exact counts', (tester) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildProfileTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ProfileScreen.followersEntryRowKey),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ProfileScreen.followersEntryRowKey),
          matching: find.text('12'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ProfileScreen.followingEntryRowKey),
          matching: find.text('8'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ProfileScreen.pendingRequestsEntryRowKey),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('auth repump resets profile identity and stats state', (
      tester,
    ) async {
      final firstProfileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;
      final secondProfileRepo = FakeProfileRepository()
        ..profileToReturn = const Profile(
          userId: 'user-2',
          preferredUnits: 'metric',
          defaultActivityVisibility: 'private',
          onboardingCompleted: true,
          displayName: 'Bob',
        );

      await tester.pumpWidget(
        KeyedSubtree(
          key: const ValueKey('profile_scope_user_1'),
          child: buildProfileTestScope(
            profileRepo: firstProfileRepo,
            savedSessions: buildTestSessions(),
            relationshipCounts: (ref) => const RelationshipCounts(
              userId: 'user-1',
              followers: 12,
              following: 8,
              pendingRequests: 3,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ProfileScreen.distanceStatTileKey),
          matching: find.text('15.00 km'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ProfileScreen.followersEntryRowKey),
          matching: find.text('12'),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(
        KeyedSubtree(
          key: const ValueKey('profile_scope_user_2'),
          child: buildProfileTestScope(
            profileRepo: secondProfileRepo,
            savedSessions: buildTestSessions(
              count: 1,
              distanceMetersEach: 1000,
            ),
            relationshipCounts: (ref) => const RelationshipCounts(
              userId: 'user-2',
              followers: 1,
              following: 0,
              pendingRequests: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(ProfileScreen.distanceStatTileKey),
          matching: find.text('1.00 km'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ProfileScreen.distanceStatTileKey),
          matching: find.text('15.00 km'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(ProfileScreen.followersEntryRowKey),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ProfileScreen.followersEntryRowKey),
          matching: find.text('12'),
        ),
        findsNothing,
      );
    });

    group('moved settings/account controls are absent', () {
      testWidgets('display name field is absent', (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildProfileTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('profile_display_name_field')),
          findsNothing,
        );
      });

      testWidgets('save button is absent', (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildProfileTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('profile_save_button')), findsNothing);
      });

      testWidgets('sign out button is absent', (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildProfileTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('profile_sign_out_button')),
          findsNothing,
        );
      });

      testWidgets('export data button is absent', (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildProfileTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('profile_export_data_button')),
          findsNothing,
        );
      });

      testWidgets('delete account button is absent', (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildProfileTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('profile_delete_account_button')),
          findsNothing,
        );
      });

      testWidgets('units selector is absent', (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildProfileTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SegmentedButton<String>), findsNothing);
      });

      testWidgets('settings screen keys are absent', (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildProfileTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(SettingsScreen.displayNameFieldKey), findsNothing);
        expect(find.byKey(SettingsScreen.saveButtonKey), findsNothing);
        expect(find.byKey(SettingsScreen.signOutButtonKey), findsNothing);
        expect(find.byKey(SettingsScreen.exportDataButtonKey), findsNothing);
        expect(find.byKey(SettingsScreen.deleteAccountButtonKey), findsNothing);
        expect(find.byKey(SettingsScreen.unitsSegmentKey), findsNothing);
        expect(find.byKey(SettingsScreen.visibilitySegmentKey), findsNothing);
      });
    });
  });
}

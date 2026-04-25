import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/common_widgets/trusted_avatar_widget.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/domain/club_member.dart';
import 'package:uff/src/features/clubs/presentation/club_detail_screen.dart';
import 'package:uff/src/features/clubs/presentation/club_routes.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';

import '../data/fake_club_repository.dart';
import 'club_detail_test_helpers.dart';

// ## Test Scenarios
// - [positive] App bar title uses club name and member overflow shows Leave Club.
// - [positive] Admin overflow includes Edit and routes with the existing Club extra payload.
// - [positive] Creator without active membership still sees overflow Edit and no Leave Club.
// - [positive] Member rows render trusted avatars and display names from profile-backed fields.
// - [negative] Blank member display names fall back to userId and non-members see only Join.
// - [isolation] Member-row taps route to the tapped user's viewed profile path.
// - [positive] Confirmed leave routes back to Club List after the mutation succeeds.
// - [error] Failed leave keeps the user on detail and shows a retry message.
// - [positive] Non-member Join action still calls joinClub mutation once.
// - [positive] Auto-discovered unclaimed clubs show disabled claim button.
// - [negative] User-created and already-claimed auto-discovered clubs hide claim button.
void main() {
  late RecordingClubRepository repository;

  setUp(() {
    repository = RecordingClubRepository();
  });

  testWidgets(
    '[positive] app bar title and member overflow expose Leave Club',
    (tester) async {
      final club = makeClub(id: 'club-contract-1', name: 'Contract Club');
      final router = _buildClubDetailRouter(initialClubId: club.id);

      await tester.pumpWidget(
        buildClubDetailRoutedTestApp(
          repository: repository,
          club: club,
          router: router,
          members: [makeClubMember(id: 'member-1', userId: testUserId)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Contract Club'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(ClubDetailScreen.overflowMenuButtonKey),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ClubDetailScreen.overflowMenuButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ClubDetailScreen.leaveMenuItemKey), findsOneWidget);
      expect(find.byKey(ClubDetailScreen.editMenuItemKey), findsNothing);
    },
  );

  testWidgets(
    '[positive] admin overflow edit routes through ClubRoutes.clubEditPath with extra club payload',
    (tester) async {
      final club = makeClub(id: 'club-contract-2', name: 'Admin Contract Club');
      final router = _buildClubDetailRouter(initialClubId: club.id);

      await tester.pumpWidget(
        buildClubDetailRoutedTestApp(
          repository: repository,
          club: club,
          router: router,
          members: [
            makeClubMember(
              id: 'member-admin',
              userId: testUserId,
              role: ClubMemberRole.admin,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ClubDetailScreen.overflowMenuButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ClubDetailScreen.editMenuItemKey));
      await tester.pumpAndSettle();

      expect(find.text('edit-route:${club.id}'), findsOneWidget);
      expect(find.text('extra-club-id:${club.id}'), findsOneWidget);
    },
  );

  testWidgets(
    '[positive] creator without membership sees Edit overflow and no Leave Club',
    (tester) async {
      final club = makeClub(
        id: 'club-contract-creator-edit',
        creatorId: testUserId,
      );
      final router = _buildClubDetailRouter(initialClubId: club.id);

      await tester.pumpWidget(
        buildClubDetailRoutedTestApp(
          repository: repository,
          club: club,
          router: router,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ClubDetailScreen.overflowMenuButtonKey),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ClubDetailScreen.overflowMenuButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ClubDetailScreen.editMenuItemKey), findsOneWidget);
      expect(find.byKey(ClubDetailScreen.leaveMenuItemKey), findsNothing);

      await tester.tap(find.byKey(ClubDetailScreen.editMenuItemKey));
      await tester.pumpAndSettle();

      expect(find.text('edit-route:${club.id}'), findsOneWidget);
      expect(find.text('extra-club-id:${club.id}'), findsOneWidget);
    },
  );

  testWidgets(
    '[negative] non-member keeps only inline Join with no overflow actions',
    (tester) async {
      final club = makeClub(id: 'club-contract-3');
      final router = _buildClubDetailRouter(initialClubId: club.id);

      await tester.pumpWidget(
        buildClubDetailRoutedTestApp(
          repository: repository,
          club: club,
          router: router,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubDetailScreen.joinButtonKey), findsOneWidget);
      expect(find.byKey(ClubDetailScreen.overflowMenuButtonKey), findsNothing);
    },
  );

  testWidgets('[positive] non-member Join action calls joinClub once', (
    tester,
  ) async {
    final club = makeClub(id: 'club-contract-join');

    await tester.pumpWidget(
      buildClubDetailTestApp(repository: repository, club: club),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ClubDetailScreen.joinButtonKey));
    await tester.pumpAndSettle();

    expect(repository.joinClubCallCount, 1);
    expect(repository.lastJoinedClubId, club.id);
  });

  testWidgets(
    '[isolation] member rows show display-name fallback and tap routes to viewed profile',
    (tester) async {
      final club = makeClub(id: 'club-contract-4');
      final router = _buildClubDetailRouter(initialClubId: club.id);
      const firstUserId = 'member-user-1';
      const secondUserId = 'member-user-2';

      await tester.pumpWidget(
        buildClubDetailRoutedTestApp(
          repository: repository,
          club: club,
          router: router,
          members: [
            makeClubMember(
              id: 'member-row-1',
              userId: firstUserId,
              displayName: 'Avery Runner',
            ),
            makeClubMember(
              id: 'member-row-2',
              userId: secondUserId,
              displayName: '   ',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TrustedAvatarWidget), findsNWidgets(2));
      expect(find.text('Avery Runner'), findsOneWidget);
      expect(find.text(firstUserId), findsNothing);
      expect(find.text(secondUserId), findsOneWidget);

      await tester.tap(
        find.byKey(ClubDetailScreen.memberItemKey('member-row-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('profile-route:$firstUserId'), findsOneWidget);
    },
  );

  testWidgets(
    '[positive] confirmed leave navigates to ClubRoutes.clubListPath',
    (tester) async {
      final club = makeClub(id: 'club-contract-5');
      final router = _buildClubDetailRouter(initialClubId: club.id);

      await tester.pumpWidget(
        buildClubDetailRoutedTestApp(
          repository: repository,
          club: club,
          router: router,
          members: [makeClubMember(id: 'member-leave', userId: testUserId)],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ClubDetailScreen.overflowMenuButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ClubDetailScreen.leaveMenuItemKey));
      await tester.pumpAndSettle();

      final leaveInDialog = find.descendant(
        of: find.byKey(ClubDetailScreen.leaveConfirmDialogKey),
        matching: find.widgetWithText(TextButton, 'Leave'),
      );
      await tester.tap(leaveInDialog);
      await tester.pumpAndSettle();

      expect(repository.leaveClubCallCount, 1);
      expect(repository.lastLeftClubId, club.id);
      expect(find.text('club-list-screen'), findsOneWidget);
    },
  );

  testWidgets(
    '[error] failed leave stays on detail and shows an error snackbar',
    (tester) async {
      final club = makeClub(id: 'club-contract-leave-error');
      final router = _buildClubDetailRouter(initialClubId: club.id);
      repository.leaveClubError = Exception('leave failed');

      await tester.pumpWidget(
        buildClubDetailRoutedTestApp(
          repository: repository,
          club: club,
          router: router,
          members: [
            makeClubMember(id: 'member-leave-error', userId: testUserId),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ClubDetailScreen.overflowMenuButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ClubDetailScreen.leaveMenuItemKey));
      await tester.pumpAndSettle();

      final leaveInDialog = find.descendant(
        of: find.byKey(ClubDetailScreen.leaveConfirmDialogKey),
        matching: find.widgetWithText(TextButton, 'Leave'),
      );
      await tester.tap(leaveInDialog);
      await tester.pumpAndSettle();

      expect(repository.leaveClubCallCount, 1);
      expect(find.text('club-list-screen'), findsNothing);
      expect(find.byType(ClubDetailScreen), findsOneWidget);
      expect(
        find.text('Unable to leave club. Please try again.'),
        findsOneWidget,
      );
    },
  );

  group('auto-discovered claim affordance', () {
    testWidgets(
      '[positive] auto-discovered unclaimed club shows disabled claim button',
      (tester) async {
        final club = makeClub(
          id: 'club-contract-claim-1',
          source: ClubSource.autoDiscovered,
          creatorId: null,
        );

        await tester.pumpWidget(
          buildClubDetailTestApp(repository: repository, club: club),
        );
        await tester.pumpAndSettle();

        final claimButtonFinder = find.byKey(
          ClubDetailScreen.claimClubButtonKey,
        );
        expect(claimButtonFinder, findsOneWidget);
        final claimButton = tester.widget<ElevatedButton>(claimButtonFinder);
        expect(claimButton.onPressed, isNull);
      },
    );

    testWidgets('[negative] user-created club does not show claim button', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildClubDetailTestApp(
          repository: repository,
          club: makeClub(id: 'club-contract-claim-2'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubDetailScreen.claimClubButtonKey), findsNothing);
    });

    testWidgets(
      '[negative] auto-discovered claimed club does not show claim button',
      (tester) async {
        await tester.pumpWidget(
          buildClubDetailTestApp(
            repository: repository,
            club: makeClub(
              id: 'club-contract-claim-3',
              source: ClubSource.autoDiscovered,
              claimedBy: 'claimer',
              creatorId: null,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(ClubDetailScreen.claimClubButtonKey), findsNothing);
      },
    );
  });
}

GoRouter _buildClubDetailRouter({required String initialClubId}) {
  return GoRouter(
    initialLocation: ClubRoutes.clubDetailPath(initialClubId),
    routes: [
      GoRoute(
        path: ClubRoutes.clubDetailPathPattern,
        builder: (context, state) {
          final clubId = state.pathParameters['id']!;
          return ClubDetailScreen(clubId: clubId);
        },
      ),
      GoRoute(
        path: ClubRoutes.clubListPath,
        builder: (context, state) =>
            const Scaffold(body: Text('club-list-screen')),
      ),
      GoRoute(
        path: ClubRoutes.clubEditPathPattern,
        builder: (context, state) {
          final clubId = state.pathParameters['id']!;
          final extraClubId = state.extra is Club
              ? (state.extra! as Club).id
              : 'missing-extra-club';
          return Scaffold(
            body: Column(
              children: [
                Text('edit-route:$clubId'),
                Text('extra-club-id:$extraClubId'),
              ],
            ),
          );
        },
      ),
      GoRoute(
        path: SocialRoutes.viewedUserProfilePathPattern,
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          return Scaffold(body: Text('profile-route:$userId'));
        },
      ),
    ],
  );
}

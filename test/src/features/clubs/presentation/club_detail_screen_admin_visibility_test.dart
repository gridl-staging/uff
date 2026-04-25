import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/clubs/application/club_providers.dart';
import 'package:uff/src/features/clubs/domain/club_member.dart';
import 'package:uff/src/features/clubs/domain/club_run.dart';
import 'package:uff/src/features/clubs/presentation/club_detail_screen.dart';

import '../data/fake_club_repository.dart';
import 'club_detail_test_helpers.dart';

// ## Test Scenarios
// - [positive] Creator keeps Edit overflow and admin section while members are loading.
// - [error] Creator keeps Edit overflow while members fail to load.
// - [positive] Admin and organizer memberships expose admin controls.
// - [positive] Creator membership exposes admin controls without explicit member row.
// - [negative] Regular members and non-members do not see admin section.
// - [negative] User B sees overflow leave action but never admin actions.
// - [isolation] Switching clubId renders the new club name in the app bar.
void main() {
  late RecordingClubRepository repository;

  setUp(() {
    repository = RecordingClubRepository();
  });

  group('ClubDetailScreen — admin section', () {
    testWidgets(
      '[positive] creator keeps Edit overflow while members are loading',
      (tester) async {
        final membersCompleter = Completer<List<ClubMember>>();
        final club = makeClub(creatorId: testUserId);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              clubRepositoryProvider.overrideWithValue(repository),
              clubDetailProvider(
                testClubId,
              ).overrideWith((ref) => Future.value(club)),
              clubMembersProvider(
                testClubId,
              ).overrideWith((ref) => membersCompleter.future),
              upcomingClubRunsProvider(
                testClubId,
              ).overrideWith((ref) => Future.value(<ClubRun>[])),
              authenticatedUserOverride(),
            ],
            child: const MaterialApp(
              home: ClubDetailScreen(clubId: testClubId),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(ClubDetailScreen.membersLoadingIndicatorKey),
          findsOneWidget,
        );
        expect(find.byKey(ClubDetailScreen.adminSectionKey), findsOneWidget);
        expect(find.byKey(ClubDetailScreen.joinButtonKey), findsNothing);
        expect(
          find.byKey(ClubDetailScreen.overflowMenuButtonKey),
          findsOneWidget,
        );
        await tester.tap(find.byKey(ClubDetailScreen.overflowMenuButtonKey));
        await tester.pump();
        expect(find.byKey(ClubDetailScreen.editMenuItemKey), findsOneWidget);
        expect(find.byKey(ClubDetailScreen.leaveMenuItemKey), findsNothing);
      },
    );

    testWidgets(
      '[error] creator keeps Edit overflow while members fail to load',
      (tester) async {
        final club = makeClub(creatorId: testUserId);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              clubRepositoryProvider.overrideWithValue(repository),
              clubDetailProvider(
                testClubId,
              ).overrideWith((ref) => Future.value(club)),
              clubMembersProvider(testClubId).overrideWith(
                (ref) => Future<List<ClubMember>>.error('members failed'),
              ),
              upcomingClubRunsProvider(
                testClubId,
              ).overrideWith((ref) => Future.value(<ClubRun>[])),
              authenticatedUserOverride(),
            ],
            child: const MaterialApp(
              home: ClubDetailScreen(clubId: testClubId),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(ClubDetailScreen.membersRetryButtonKey),
          findsOneWidget,
        );
        expect(find.byKey(ClubDetailScreen.adminSectionKey), findsOneWidget);
        expect(find.byKey(ClubDetailScreen.joinButtonKey), findsNothing);
        expect(
          find.byKey(ClubDetailScreen.overflowMenuButtonKey),
          findsOneWidget,
        );
        await tester.tap(find.byKey(ClubDetailScreen.overflowMenuButtonKey));
        await tester.pumpAndSettle();
        expect(find.byKey(ClubDetailScreen.editMenuItemKey), findsOneWidget);
        expect(find.byKey(ClubDetailScreen.leaveMenuItemKey), findsNothing);
      },
    );

    testWidgets('[positive] admin section renders when user has admin role', (
      tester,
    ) async {
      final club = makeClub(creatorId: 'someone-else');

      await tester.pumpWidget(
        buildClubDetailTestApp(
          repository: repository,
          club: club,
          members: [
            makeClubMember(
              id: 'm1',
              userId: testUserId,
              role: ClubMemberRole.admin,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubDetailScreen.adminSectionKey), findsOneWidget);
      expect(
        find.byKey(ClubDetailScreen.overflowMenuButtonKey),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ClubDetailScreen.overflowMenuButtonKey));
      await tester.pumpAndSettle();
      expect(find.byKey(ClubDetailScreen.editMenuItemKey), findsOneWidget);
      expect(find.byKey(ClubDetailScreen.scheduleRunButtonKey), findsOneWidget);
      expect(
        find.byKey(ClubDetailScreen.manageMembersButtonKey),
        findsOneWidget,
      );
    });

    testWidgets(
      '[positive] admin section renders when user has organizer role',
      (tester) async {
        final club = makeClub(creatorId: 'someone-else');

        await tester.pumpWidget(
          buildClubDetailTestApp(
            repository: repository,
            club: club,
            members: [
              makeClubMember(
                id: 'm1',
                userId: testUserId,
                role: ClubMemberRole.organizer,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(ClubDetailScreen.adminSectionKey), findsOneWidget);
        expect(
          find.byKey(ClubDetailScreen.overflowMenuButtonKey),
          findsOneWidget,
        );
        await tester.tap(find.byKey(ClubDetailScreen.overflowMenuButtonKey));
        await tester.pumpAndSettle();
        expect(find.byKey(ClubDetailScreen.editMenuItemKey), findsOneWidget);
        expect(
          find.byKey(ClubDetailScreen.scheduleRunButtonKey),
          findsOneWidget,
        );
        expect(
          find.byKey(ClubDetailScreen.manageMembersButtonKey),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '[positive] admin section renders when user is creatorId (no explicit admin membership)',
      (tester) async {
        final club = makeClub(creatorId: testUserId);

        await tester.pumpWidget(
          buildClubDetailTestApp(repository: repository, club: club),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(ClubDetailScreen.adminSectionKey), findsOneWidget);
      },
    );

    testWidgets('[negative] admin section not shown for regular member', (
      tester,
    ) async {
      final club = makeClub(creatorId: 'someone-else');

      await tester.pumpWidget(
        buildClubDetailTestApp(
          repository: repository,
          club: club,
          members: [makeClubMember(id: 'm1', userId: testUserId)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubDetailScreen.adminSectionKey), findsNothing);
    });

    testWidgets('[negative] admin section not shown for non-member', (
      tester,
    ) async {
      final club = makeClub(creatorId: 'someone-else');

      await tester.pumpWidget(
        buildClubDetailTestApp(repository: repository, club: club),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubDetailScreen.adminSectionKey), findsNothing);
    });
  });

  group('ClubDetailScreen — cross-user isolation', () {
    testWidgets('[negative] User B sees header but not admin controls', (
      tester,
    ) async {
      final club = makeClub(creatorId: testUserId);

      await tester.pumpWidget(
        buildClubDetailTestApp(
          repository: repository,
          club: club,
          members: [
            makeClubMember(
              id: 'm1',
              userId: testUserId,
              role: ClubMemberRole.admin,
            ),
            makeClubMember(id: 'm2', userId: testUserB),
          ],
          currentUserId: testUserB,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubDetailScreen.headerKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Portland Runners'),
        ),
        findsOneWidget,
      );

      expect(find.byKey(ClubDetailScreen.adminSectionKey), findsNothing);
      expect(
        find.byKey(ClubDetailScreen.overflowMenuButtonKey),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ClubDetailScreen.overflowMenuButtonKey));
      await tester.pumpAndSettle();
      expect(find.byKey(ClubDetailScreen.leaveMenuItemKey), findsOneWidget);
      expect(find.byKey(ClubDetailScreen.editMenuItemKey), findsNothing);
      expect(find.byKey(ClubDetailScreen.scheduleRunButtonKey), findsNothing);
      expect(find.byKey(ClubDetailScreen.manageMembersButtonKey), findsNothing);
    });

    testWidgets('[isolation] switching clubId renders new club data', (
      tester,
    ) async {
      final clubA = makeClub(id: 'club-east', name: 'Club Alpha');
      final clubB = makeClub(
        id: 'club-west',
        name: 'Club Beta',
        city: 'Seattle',
      );

      await tester.pumpWidget(
        buildClubDetailSwitcherTestApp(
          repository: repository,
          initialClub: clubA,
          alternateClub: clubB,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Club Alpha'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Club Beta'),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('switch_club_button')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Club Beta'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Club Alpha'),
        ),
        findsNothing,
      );
    });
  });
}

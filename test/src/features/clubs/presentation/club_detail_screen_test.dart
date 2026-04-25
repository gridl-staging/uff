import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/clubs/application/club_providers.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/domain/club_member.dart';
import 'package:uff/src/features/clubs/domain/club_run.dart';
import 'package:uff/src/features/clubs/presentation/club_detail_screen.dart';

import '../data/fake_club_repository.dart';
import 'club_detail_test_helpers.dart';

// ## Test Scenarios
// - [positive] Header renders exact description, city, and member count.
// - [positive] Member list renders first 10 members only (seed 12).
// - [positive] Upcoming runs renders next 5 only (seed 7).
// - [positive] Non-member sees Join button and active member sees overflow.
// - [edge] Members loading state defers membership and admin visibility.
// - [edge] Runs loading state defers empty placeholder fallback.
// - [edge] Empty members and empty runs each show their placeholders.
// - [error] Error state shows retry and invalidates clubDetailProvider.
// - [error] Members and runs retry actions stay distinct by section.
// - [negative] Cross-user/admin negative coverage lives in club_detail_screen_admin_visibility_test.dart.
// - [isolation] Club switcher isolation coverage lives in club_detail_screen_admin_visibility_test.dart.
// - [positive] Join mutation coverage lives in club_detail_screen_stage2_contract_test.dart.

void main() {
  late RecordingClubRepository repository;

  setUp(() {
    repository = RecordingClubRepository();
  });

  group('ClubDetailScreen — core', () {
    testWidgets(
      '[positive] header renders exact name, description, city, member count',
      (tester) async {
        final club = makeClub();

        await tester.pumpWidget(
          buildClubDetailTestApp(
            repository: repository,
            club: club,
            members: [makeClubMember(id: 'm1', userId: 'other-user')],
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
        expect(
          find.descendant(
            of: find.byKey(ClubDetailScreen.headerKey),
            matching: find.text('Portland Runners'),
          ),
          findsOneWidget,
        );
        expect(find.text('Portland Runners'), findsNWidgets(2));
        expect(find.text('A friendly running club'), findsOneWidget);
        expect(find.text('Portland'), findsOneWidget);
        expect(find.text('42 members'), findsOneWidget);
      },
    );

    testWidgets('[positive] member list renders first 10 only (seed 12)', (
      tester,
    ) async {
      final club = makeClub();
      final members = List.generate(
        12,
        (i) => makeClubMember(id: 'm$i', userId: 'user-$i'),
      );

      await tester.pumpWidget(
        buildClubDetailTestApp(
          repository: repository,
          club: club,
          members: members,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubDetailScreen.memberListSectionKey), findsOneWidget);
      // First 10 should be visible (scrolling into view if needed)
      for (var i = 0; i < 10; i++) {
        expect(
          find.byKey(ClubDetailScreen.memberItemKey('m$i')),
          findsOneWidget,
        );
      }
      // Items 10 and 11 should NOT be rendered
      expect(find.byKey(ClubDetailScreen.memberItemKey('m10')), findsNothing);
      expect(find.byKey(ClubDetailScreen.memberItemKey('m11')), findsNothing);
    });

    testWidgets('[positive] upcoming runs renders next 5 only (seed 7)', (
      tester,
    ) async {
      final club = makeClub();
      final runs = List.generate(
        7,
        (i) => makeClubRun(id: 'r$i', title: 'Run $i'),
      );

      await tester.pumpWidget(
        buildClubDetailTestApp(repository: repository, club: club, runs: runs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubDetailScreen.runsSectionKey), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        expect(find.byKey(ClubDetailScreen.runItemKey('r$i')), findsOneWidget);
      }
      expect(find.byKey(ClubDetailScreen.runItemKey('r5')), findsNothing);
      expect(find.byKey(ClubDetailScreen.runItemKey('r6')), findsNothing);
    });

    testWidgets('[positive] non-member sees Join button', (tester) async {
      final club = makeClub();

      await tester.pumpWidget(
        buildClubDetailTestApp(
          repository: repository,
          club: club,
          members: [makeClubMember(id: 'm1', userId: 'other-user')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubDetailScreen.joinButtonKey), findsOneWidget);
      expect(find.byKey(ClubDetailScreen.overflowMenuButtonKey), findsNothing);
    });

    testWidgets('[positive] active member sees overflow menu actions', (
      tester,
    ) async {
      final club = makeClub();

      await tester.pumpWidget(
        buildClubDetailTestApp(
          repository: repository,
          club: club,
          members: [makeClubMember(id: 'm1', userId: testUserId)],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ClubDetailScreen.overflowMenuButtonKey),
        findsOneWidget,
      );
      expect(find.byKey(ClubDetailScreen.joinButtonKey), findsNothing);
    });

    testWidgets('[positive] loading state shows indicator', (tester) async {
      final loadCompleter = Completer<Club?>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clubRepositoryProvider.overrideWithValue(repository),
            clubDetailProvider(
              testClubId,
            ).overrideWith((ref) => loadCompleter.future),
            authenticatedUserOverride(),
          ],
          child: const MaterialApp(home: ClubDetailScreen(clubId: testClubId)),
        ),
      );
      await tester.pump();

      expect(find.byKey(ClubDetailScreen.loadingIndicatorKey), findsOneWidget);

      loadCompleter.complete(makeClub());
      await tester.pumpAndSettle();
    });

    testWidgets(
      '[edge] members loading state defers membership/admin visibility',
      (tester) async {
        final membersCompleter = Completer<List<ClubMember>>();
        final club = makeClub(creatorId: 'different-user');

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

        expect(find.byKey(ClubDetailScreen.headerKey), findsOneWidget);
        expect(
          find.byKey(ClubDetailScreen.membersLoadingIndicatorKey),
          findsOneWidget,
        );
        expect(find.byKey(ClubDetailScreen.joinButtonKey), findsNothing);
        expect(
          find.byKey(ClubDetailScreen.overflowMenuButtonKey),
          findsNothing,
        );
        expect(find.byKey(ClubDetailScreen.adminSectionKey), findsNothing);
        expect(find.byKey(ClubDetailScreen.emptyMembersKey), findsNothing);

        membersCompleter.complete([
          makeClubMember(
            id: 'm1',
            userId: testUserId,
            role: ClubMemberRole.admin,
          ),
        ]);
        await tester.pumpAndSettle();

        expect(
          find.byKey(ClubDetailScreen.membersLoadingIndicatorKey),
          findsNothing,
        );
        expect(
          find.byKey(ClubDetailScreen.overflowMenuButtonKey),
          findsOneWidget,
        );
        expect(find.byKey(ClubDetailScreen.adminSectionKey), findsOneWidget);
      },
    );

    testWidgets('[edge] runs loading state defers empty placeholder fallback', (
      tester,
    ) async {
      final runsCompleter = Completer<List<ClubRun>>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clubRepositoryProvider.overrideWithValue(repository),
            clubDetailProvider(
              testClubId,
            ).overrideWith((ref) => Future.value(makeClub())),
            clubMembersProvider(
              testClubId,
            ).overrideWith((ref) => Future.value(<ClubMember>[])),
            upcomingClubRunsProvider(
              testClubId,
            ).overrideWith((ref) => runsCompleter.future),
            authenticatedUserOverride(),
          ],
          child: const MaterialApp(home: ClubDetailScreen(clubId: testClubId)),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(ClubDetailScreen.runsLoadingIndicatorKey),
        findsOneWidget,
      );
      expect(find.byKey(ClubDetailScreen.emptyRunsKey), findsNothing);

      runsCompleter.complete([]);
      await tester.pumpAndSettle();

      expect(
        find.byKey(ClubDetailScreen.runsLoadingIndicatorKey),
        findsNothing,
      );
      expect(find.byKey(ClubDetailScreen.emptyRunsKey), findsOneWidget);
    });

    testWidgets('[error] error state retry invalidates clubDetailProvider', (
      tester,
    ) async {
      var loadCount = 0;
      final recoveredClub = makeClub(name: 'Recovered Club');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clubRepositoryProvider.overrideWithValue(repository),
            clubDetailProvider(testClubId).overrideWith((ref) async {
              loadCount += 1;
              if (loadCount == 1) {
                throw StateError('network error');
              }
              return recoveredClub;
            }),
            clubMembersProvider(
              testClubId,
            ).overrideWith((ref) => Future.value(<ClubMember>[])),
            upcomingClubRunsProvider(
              testClubId,
            ).overrideWith((ref) => Future.value(<ClubRun>[])),
            authenticatedUserOverride(),
          ],
          child: const MaterialApp(home: ClubDetailScreen(clubId: testClubId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubDetailScreen.errorStateKey), findsOneWidget);
      expect(find.byKey(ClubDetailScreen.retryButtonKey), findsOneWidget);

      await tester.tap(find.byKey(ClubDetailScreen.retryButtonKey));
      await tester.pumpAndSettle();

      expect(loadCount, 2);
      expect(find.byKey(ClubDetailScreen.errorStateKey), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Recovered Club'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      '[error] members and runs error sections expose distinct retry buttons',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              clubRepositoryProvider.overrideWithValue(repository),
              clubDetailProvider(
                testClubId,
              ).overrideWith((ref) => Future.value(makeClub())),
              clubMembersProvider(
                testClubId,
              ).overrideWith((ref) => Future<List<ClubMember>>.error('failed')),
              upcomingClubRunsProvider(
                testClubId,
              ).overrideWith((ref) => Future<List<ClubRun>>.error('failed')),
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
        expect(find.byKey(ClubDetailScreen.runsRetryButtonKey), findsOneWidget);
      },
    );

    testWidgets('[edge] empty members shows placeholder', (tester) async {
      await tester.pumpWidget(
        buildClubDetailTestApp(
          repository: repository,
          club: makeClub(),
          runs: [makeClubRun(id: 'r1', title: 'Morning Run')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubDetailScreen.emptyMembersKey), findsOneWidget);
    });

    testWidgets('[edge] empty runs shows placeholder', (tester) async {
      await tester.pumpWidget(
        buildClubDetailTestApp(
          repository: repository,
          club: makeClub(),
          members: [makeClubMember(id: 'm1', userId: 'other-user')],
          runs: [],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubDetailScreen.emptyRunsKey), findsOneWidget);
    });
  });
}

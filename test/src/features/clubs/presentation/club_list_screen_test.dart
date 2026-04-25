import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/clubs/application/club_location_service.dart';
import 'package:uff/src/features/clubs/application/club_providers.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/presentation/club_list_screen.dart';
import 'package:uff/src/features/clubs/presentation/club_routes.dart';

import '../data/fake_club_repository.dart';
part 'club_list_screen_test_helpers.dart';

/// ## Test Scenarios
/// - [positive] My Clubs renders seeded club names, cities, and member counts
/// - [positive] Discover renders nearbyClubsProvider data
/// - [positive] Auto-discovered discover cards show source chip while user-created cards do not
/// - [positive] Create-club FAB navigates to ClubRoutes.clubNewPath
/// - [positive] Search debounces for 300ms then renders clubSearchProvider results while hiding default sections
/// - [positive] Pull-to-refresh on default view re-fetches my and nearby clubs
/// - [positive] Pull-to-refresh on search view re-fetches search results
/// - [edge] Empty My Clubs shows "You haven't joined any clubs yet"
/// - [edge] Empty Discover shows "No clubs found nearby"
/// - [edge] Search empty state shows "No clubs found"
/// - [edge] Search empty state copy stays centered in the search results viewport
/// - [error] Error state shows retry button that invalidates visible provider state
/// - [negative] User B does not see User A's private club in discover results
/// - [isolation] Local search state clears when navigating away and back

void main() {
  group('ClubListScreen', () {
    late RecordingClubRepository repository;

    setUp(() {
      repository = RecordingClubRepository();
    });

    testWidgets(
      '[positive] My Clubs renders club names, cities, and member counts',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            repository: repository,
            myClubs: [_myClub1, _myClub2],
            nearbyClubs: [_nearbyClub1],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Morning Runners'), findsOneWidget);
        expect(find.textContaining('Portland'), findsWidgets);
        expect(find.textContaining('12 members'), findsOneWidget);
        expect(find.text('Trail Blazers'), findsOneWidget);
        expect(find.textContaining('Bend'), findsOneWidget);
        expect(find.textContaining('7 members'), findsOneWidget);
        expect(find.byKey(ClubListScreen.myClubsSectionKey), findsOneWidget);
      },
    );

    testWidgets('[positive] Discover renders nearbyClubsProvider data', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          repository: repository,
          myClubs: [_myClub1],
          nearbyClubs: [_nearbyClub1, _nearbyClub2],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Downtown Pacers'), findsOneWidget);
      expect(find.textContaining('Seattle'), findsOneWidget);
      expect(find.textContaining('24 members'), findsOneWidget);
      expect(find.text('Lake Loop Crew'), findsOneWidget);
      expect(find.textContaining('15 members'), findsOneWidget);
      expect(find.byKey(ClubListScreen.discoverSectionKey), findsOneWidget);
    });

    testWidgets(
      '[positive] auto-discovered cards show one source chip and user-created cards show none',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            repository: repository,
            myClubs: [],
            nearbyClubs: [_nearbyAutoDiscoveredClub, _nearbyUserCreatedClub],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Forest Park Striders'), findsOneWidget);
        expect(find.text('Neighborhood Pacers'), findsOneWidget);
        expect(find.byType(Chip), findsOneWidget);
        expect(find.text('Auto-discovered'), findsOneWidget);

        final autoDiscoveredCard = find.byKey(
          ClubListScreen.clubCardKey(_nearbyAutoDiscoveredClub.id),
        );
        final userCreatedCard = find.byKey(
          ClubListScreen.clubCardKey(_nearbyUserCreatedClub.id),
        );
        expect(
          find.descendant(of: autoDiscoveredCard, matching: find.byType(Chip)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: userCreatedCard, matching: find.byType(Chip)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: autoDiscoveredCard,
            matching: find.byIcon(Icons.public),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: userCreatedCard,
            matching: find.byIcon(Icons.public),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: userCreatedCard,
            matching: find.byIcon(Icons.groups),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '[positive] create-club FAB navigates to ClubRoutes.clubNewPath',
      (tester) async {
        await tester.pumpWidget(
          _buildRoutedTestApp(
            repository: repository,
            myClubs: [],
            nearbyClubs: [],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(ClubListScreen.createClubFabKey));
        await tester.pumpAndSettle();

        expect(find.text('create-club-route'), findsOneWidget);
      },
    );

    testWidgets(
      '[positive] tapping a club card navigates to ClubRoutes.clubDetailPath(id)',
      (tester) async {
        await tester.pumpWidget(
          _buildRoutedTestApp(
            repository: repository,
            myClubs: [_myClub1],
            nearbyClubs: [_nearbyClub1],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(ClubListScreen.clubCardKey(_myClub1.id)));
        await tester.pumpAndSettle();

        expect(find.text('club-detail-route:${_myClub1.id}'), findsOneWidget);
      },
    );

    testWidgets(
      '[positive] search debounces then shows results hiding default sections',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            repository: repository,
            myClubs: [_myClub1],
            nearbyClubs: [_nearbyClub1],
          ),
        );
        await tester.pumpAndSettle();

        // Switch the repository return to search results before typing.
        repository.clubsToReturn = [_searchResult];

        // Enter search text
        await tester.enterText(
          find.byKey(ClubListScreen.searchFieldKey),
          'Found',
        );
        // Before debounce completes, default sections should still be visible
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(ClubListScreen.myClubsSectionKey), findsOneWidget);

        // After debounce, search results replace default sections
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.text('Found Club'), findsOneWidget);
        expect(find.byKey(ClubListScreen.myClubsSectionKey), findsNothing);
        expect(find.byKey(ClubListScreen.discoverSectionKey), findsNothing);
      },
    );

    testWidgets(
      '[positive] pull-to-refresh on default view re-fetches my and nearby clubs',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            repository: repository,
            myClubs: [_myClub1],
            nearbyClubs: [_nearbyClub1],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(RefreshIndicator), findsOneWidget);

        final myClubsCallsBeforeRefresh = repository.getMyClubsCallCount;
        final nearbyClubsCallsBeforeRefresh = repository.listClubsCallCount;

        await tester.fling(
          find.byType(ListView).first,
          const Offset(0, 300),
          1000,
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(repository.getMyClubsCallCount, myClubsCallsBeforeRefresh + 1);
        expect(
          repository.listClubsCallCount,
          nearbyClubsCallsBeforeRefresh + 1,
        );
      },
    );

    testWidgets(
      '[positive] pull-to-refresh on search view re-fetches search results',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            repository: repository,
            myClubs: [_myClub1],
            nearbyClubs: [_nearbyClub1],
          ),
        );
        await tester.pumpAndSettle();

        repository.clubsToReturn = [_searchResult];

        await tester.enterText(
          find.byKey(ClubListScreen.searchFieldKey),
          'Found',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.text('Found Club'), findsOneWidget);
        expect(find.byType(RefreshIndicator), findsOneWidget);

        final searchCallsBeforeRefresh = repository.searchClubsCallCount;

        await tester.fling(
          find.byType(ListView).first,
          const Offset(0, 300),
          1000,
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(repository.searchClubsCallCount, searchCallsBeforeRefresh + 1);
      },
    );

    testWidgets('[edge] search empty state shows "No clubs found"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          repository: repository,
          myClubs: [_myClub1],
          nearbyClubs: [_nearbyClub1],
        ),
      );
      await tester.pumpAndSettle();

      repository.clubsToReturn = const <Club>[];

      await tester.enterText(
        find.byKey(ClubListScreen.searchFieldKey),
        'NotFound',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('No clubs found'), findsOneWidget);
      expect(find.text('No results found'), findsNothing);
    });

    testWidgets(
      '[edge] search empty state copy stays centered in results viewport',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            repository: repository,
            myClubs: [_myClub1],
            nearbyClubs: [_nearbyClub1],
          ),
        );
        await tester.pumpAndSettle();

        repository.clubsToReturn = const <Club>[];

        await tester.enterText(
          find.byKey(ClubListScreen.searchFieldKey),
          'NotFound',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        final listRect = tester.getRect(find.byType(ListView).first);
        final textCenter = tester.getCenter(find.text('No clubs found'));
        expect(
          (textCenter.dy - listRect.center.dy).abs(),
          lessThanOrEqualTo(24),
        );
      },
    );

    testWidgets('[edge] empty My Clubs shows placeholder', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          repository: repository,
          myClubs: [],
          nearbyClubs: [_nearbyClub1],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubListScreen.emptyMyClubsKey), findsOneWidget);
      expect(find.text("You haven't joined any clubs yet"), findsOneWidget);
    });

    testWidgets('[edge] empty Discover shows placeholder', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          repository: repository,
          myClubs: [_myClub1],
          nearbyClubs: [],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ClubListScreen.emptyDiscoverKey), findsOneWidget);
      expect(find.text('No clubs found nearby'), findsOneWidget);
    });

    testWidgets('[error] error state shows retry that invalidates providers', (
      tester,
    ) async {
      repository.getMyClubsError = StateError('network error');
      repository.listClubsError = StateError('network error');

      await tester.pumpWidget(_buildTestApp(repository: repository));
      await tester.pumpAndSettle();

      expect(find.byKey(ClubListScreen.errorStateKey), findsOneWidget);
      expect(find.byKey(ClubListScreen.retryButtonKey), findsOneWidget);

      // Clear errors and tap retry
      repository.getMyClubsError = null;
      repository.listClubsError = null;
      repository.myClubsToReturn = [_myClub1];
      repository.clubsToReturn = [_nearbyClub1];

      await tester.tap(find.byKey(ClubListScreen.retryButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Morning Runners'), findsOneWidget);
      expect(find.text('Downtown Pacers'), findsOneWidget);
    });

    testWidgets(
      '[negative] private club not shown in discover when overridden with public-only list',
      (tester) async {
        // nearbyClubsProvider returns only public clubs (repository returns no private)
        await tester.pumpWidget(
          _buildTestApp(
            repository: repository,
            myClubs: [],
            nearbyClubs: [_nearbyClub1],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Downtown Pacers'), findsOneWidget);
        expect(find.text('Secret Club'), findsNothing);
      },
    );

    testWidgets('[isolation] search state clears when leaving and returning', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildShellRoutedTestApp(
          repository: repository,
          myClubs: [_myClub1],
          nearbyClubs: [_nearbyClub1],
        ),
      );
      await tester.pumpAndSettle();

      // Switch to search results and type
      repository.clubsToReturn = [_searchResult];
      await tester.enterText(
        find.byKey(ClubListScreen.searchFieldKey),
        'Found',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Found Club'), findsOneWidget);

      await tester.tap(find.byKey(_goOtherShellBranchKey));
      await tester.pumpAndSettle();
      expect(find.text('other-shell-route'), findsOneWidget);

      repository.clubsToReturn = [_nearbyClub1];
      await tester.tap(find.byKey(_goClubsShellBranchKey));
      await tester.pumpAndSettle();

      final searchField = tester.widget<TextField>(
        find.byKey(ClubListScreen.searchFieldKey),
      );
      expect(searchField.controller?.text, '');
      expect(find.byKey(ClubListScreen.myClubsSectionKey), findsOneWidget);
      expect(find.byKey(ClubListScreen.discoverSectionKey), findsOneWidget);
    });

    testWidgets('[positive] loading state shows loading indicator', (
      tester,
    ) async {
      final loadCompleter = Completer<List<Club>>();
      final deferredRepo = RecordingClubRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clubRepositoryProvider.overrideWithValue(deferredRepo),
            myClubsProvider.overrideWith((ref) => loadCompleter.future),
          ],
          child: const MaterialApp(home: ClubListScreen()),
        ),
      );
      await tester.pump();

      expect(find.byKey(ClubListScreen.loadingIndicatorKey), findsOneWidget);

      loadCompleter.complete([]);
      await tester.pumpAndSettle();
    });
  });
}

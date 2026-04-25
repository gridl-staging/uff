import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/data/follow_repository.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/presentation/relationship_search_screen.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';
import 'package:uff/src/features/social/presentation/social_user_row.dart';

import 'fake_follow_repository.dart';

/// ## Test Scenarios
/// - [positive] Search UI renders user rows and follow action states for valid query results.
/// - [positive] Follow/accept actions mutate relationship state and refresh result rows.
/// - [error] Search load failures render retry UI and recover on re-read.
/// - [edge] Query submission trims whitespace and clears stale rows for trimmed-empty input.
/// - [negative] Unfollow action mutates only the selected followed search result user.
/// - [isolation] Row taps navigate to viewed-user profile for the selected result user id.
void main() {
  // -- Test data builders --------------------------------------------------

  SocialUserSummary makeUser({
    required String userId,
    String? displayName,
    FollowRelationshipStatus status = FollowRelationshipStatus.none,
    String? followId,
  }) {
    return SocialUserSummary(
      userId: userId,
      displayName: displayName ?? 'User $userId',
      avatarUrl: null,
      relationship: FollowRelationship(
        currentUserId: 'viewer-1',
        targetUserId: userId,
        status: status,
        followId: followId,
      ),
    );
  }

  // -- Helpers -------------------------------------------------------------

  /// Builds the search screen with overridden providers.
  ///
  /// [searchResults] maps a query string to the future that search returns.
  /// [followRepository] optionally records follow-action mutations.
  Widget buildSearchScreen({
    required FutureOr<List<SocialUserSummary>> Function(Ref, String)
    searchResults,
    FollowRepository? followRepository,
  }) {
    return ProviderScope(
      overrides: [
        userSearchProvider.overrideWith(
          (ref, query) => searchResults(ref, query),
        ),
        if (followRepository != null)
          followRepositoryProvider.overrideWithValue(followRepository),
      ],
      child: const MaterialApp(home: RelationshipSearchScreen()),
    );
  }

  Widget buildSearchRouterScreen({
    required FutureOr<List<SocialUserSummary>> Function(Ref, String)
    searchResults,
    FollowRepository? followRepository,
  }) {
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(
          path: '/search',
          builder: (context, state) => const RelationshipSearchScreen(),
        ),
        GoRoute(
          path: '/social/profile/:userId',
          builder: (context, state) =>
              Text('profile:${state.pathParameters['userId']}'),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        userSearchProvider.overrideWith(
          (ref, query) => searchResults(ref, query),
        ),
        if (followRepository != null)
          followRepositoryProvider.overrideWithValue(followRepository),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  group('RelationshipSearchScreen', () {
    testWidgets('shows prompt text before any search is entered', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSearchScreen(
          searchResults: (ref, query) async => const <SocialUserSummary>[],
        ),
      );
      await tester.pump();

      expect(
        find.byKey(RelationshipSearchScreen.searchFieldKey),
        findsOneWidget,
      );
      expect(
        find.byKey(RelationshipSearchScreen.promptStateKey),
        findsOneWidget,
      );
    });

    testWidgets('trims whitespace from query before searching', (
      tester,
    ) async {
      String? receivedQuery;
      await tester.pumpWidget(
        buildSearchScreen(
          searchResults: (ref, query) async {
            receivedQuery = query;
            return const <SocialUserSummary>[];
          },
        ),
      );

      // Enter a query with leading/trailing spaces.
      await tester.enterText(
        find.byKey(RelationshipSearchScreen.searchFieldKey),
        '  alice  ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      // The provider should receive the trimmed query.
      expect(receivedQuery, 'alice');
    });

    testWidgets('shows loading indicator while search is in progress', (
      tester,
    ) async {
      final pendingSearch = Completer<List<SocialUserSummary>>();
      addTearDown(() {
        if (!pendingSearch.isCompleted) {
          pendingSearch.complete(const <SocialUserSummary>[]);
        }
      });

      await tester.pumpWidget(
        buildSearchScreen(
          searchResults: (ref, query) => pendingSearch.future,
        ),
      );

      await tester.enterText(
        find.byKey(RelationshipSearchScreen.searchFieldKey),
        'alice',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(
        find.byKey(RelationshipSearchScreen.loadingIndicatorKey),
        findsOneWidget,
      );
    });

    testWidgets('shows error state with retry on search failure', (
      tester,
    ) async {
      // Use a flag (not a counter) so auto-retries keep failing until we
      // explicitly allow success — mirrors the feed_screen_test pattern.
      var allowSuccess = false;
      await tester.pumpWidget(
        buildSearchScreen(
          searchResults: (ref, query) {
            if (!allowSuccess) {
              return Future<List<SocialUserSummary>>.error(
                Exception('network error'),
              );
            }
            return Future.value(<SocialUserSummary>[
              makeUser(userId: 'u1', displayName: 'Alice'),
            ]);
          },
        ),
      );

      await tester.enterText(
        find.byKey(RelationshipSearchScreen.searchFieldKey),
        'alice',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(
        find.byKey(RelationshipSearchScreen.errorStateKey),
        findsOneWidget,
      );
      expect(
        find.byKey(RelationshipSearchScreen.retryButtonKey),
        findsOneWidget,
      );

      // Tap retry and verify results load.
      allowSuccess = true;
      await tester.tap(find.byKey(RelationshipSearchScreen.retryButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows empty results message when search returns no users', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSearchScreen(
          searchResults: (ref, query) async => const <SocialUserSummary>[],
        ),
      );

      await tester.enterText(
        find.byKey(RelationshipSearchScreen.searchFieldKey),
        'nonexistent',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(
        find.byKey(RelationshipSearchScreen.emptyResultsKey),
        findsOneWidget,
      );
    });

    testWidgets('renders SocialUserSummary rows with display names', (
      tester,
    ) async {
      final users = [
        makeUser(userId: 'u1', displayName: 'Alice Runner'),
        makeUser(userId: 'u2', displayName: 'Bob Jogger'),
      ];

      await tester.pumpWidget(
        buildSearchScreen(
          searchResults: (ref, query) async => users,
        ),
      );

      await tester.enterText(
        find.byKey(RelationshipSearchScreen.searchFieldKey),
        'a',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.byKey(SocialUserRow.userRowKey('u1')), findsOneWidget);
      expect(find.byKey(SocialUserRow.userRowKey('u2')), findsOneWidget);
      expect(find.text('Alice Runner'), findsOneWidget);
      expect(find.text('Bob Jogger'), findsOneWidget);
    });

    testWidgets(
      'tapping a social user row pushes viewed-user profile route path',
      (tester) async {
        await tester.pumpWidget(
          buildSearchRouterScreen(
            searchResults: (ref, query) async => [
              makeUser(userId: 'u1', displayName: 'Alice Runner'),
            ],
          ),
        );

        await tester.enterText(
          find.byKey(RelationshipSearchScreen.searchFieldKey),
          'alice',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(SocialUserRow.userRowKey('u1')));
        await tester.pumpAndSettle();

        expect(
          find.text(SocialRoutes.viewedUserProfilePath('u1')),
          findsNothing,
        );
        expect(find.text('profile:u1'), findsOneWidget);
      },
    );

    testWidgets(
      'shows "Follow" for none status before any mutation',
      (tester) async {
        final users = [
          makeUser(userId: 'u1', displayName: 'Alice'),
        ];

        await tester.pumpWidget(
          buildSearchScreen(
            searchResults: (ref, query) async => users,
          ),
        );

        await tester.enterText(
          find.byKey(RelationshipSearchScreen.searchFieldKey),
          'alice',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();

        // The follow action button for a 'none' relationship shows "Follow".
        final followButton = find.byKey(SocialUserRow.actionButtonKey('u1'));
        expect(followButton, findsOneWidget);
        expect(
          find.descendant(of: followButton, matching: find.text('Follow')),
          findsOneWidget,
        );
      },
    );

    testWidgets('shows "Requested" for outgoingPending relationship', (
      tester,
    ) async {
      final users = [
        makeUser(
          userId: 'u1',
          displayName: 'Alice',
          status: FollowRelationshipStatus.outgoingPending,
        ),
      ];

      await tester.pumpWidget(
        buildSearchScreen(
          searchResults: (ref, query) async => users,
        ),
      );

      await tester.enterText(
        find.byKey(RelationshipSearchScreen.searchFieldKey),
        'alice',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      final actionButton = find.byKey(SocialUserRow.actionButtonKey('u1'));
      expect(
        find.descendant(of: actionButton, matching: find.text('Requested')),
        findsOneWidget,
      );
    });

    testWidgets('shows "Following" for following relationship', (
      tester,
    ) async {
      final users = [
        makeUser(
          userId: 'u1',
          displayName: 'Alice',
          status: FollowRelationshipStatus.following,
        ),
      ];

      await tester.pumpWidget(
        buildSearchScreen(
          searchResults: (ref, query) async => users,
        ),
      );

      await tester.enterText(
        find.byKey(RelationshipSearchScreen.searchFieldKey),
        'alice',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      final actionButton = find.byKey(SocialUserRow.actionButtonKey('u1'));
      expect(
        find.descendant(of: actionButton, matching: find.text('Following')),
        findsOneWidget,
      );
    });

    testWidgets('does not search when query is only whitespace', (
      tester,
    ) async {
      var searchCalled = false;
      await tester.pumpWidget(
        buildSearchScreen(
          searchResults: (ref, query) async {
            searchCalled = true;
            return const <SocialUserSummary>[];
          },
        ),
      );

      await tester.enterText(
        find.byKey(RelationshipSearchScreen.searchFieldKey),
        '   ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      // Whitespace-only query should show prompt, not trigger search.
      expect(searchCalled, isFalse);
      expect(
        find.byKey(RelationshipSearchScreen.promptStateKey),
        findsOneWidget,
      );
    });

    testWidgets('clears stale results when a submitted query trims to empty', (
      tester,
    ) async {
      var searchCallCount = 0;
      await tester.pumpWidget(
        buildSearchScreen(
          searchResults: (ref, query) async {
            searchCallCount++;
            return [
              makeUser(userId: 'u1', displayName: 'Alice'),
            ];
          },
        ),
      );

      await tester.enterText(
        find.byKey(RelationshipSearchScreen.searchFieldKey),
        'alice',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(searchCallCount, 1);

      await tester.enterText(
        find.byKey(RelationshipSearchScreen.searchFieldKey),
        '   ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(searchCallCount, 1);
      expect(find.text('Alice'), findsNothing);
      expect(
        find.byKey(RelationshipSearchScreen.promptStateKey),
        findsOneWidget,
      );
    });

    testWidgets(
      'follow action sends request and refreshes the row to Requested',
      (tester) async {
        final followRepository = RecordingFollowRepository();

        await tester.pumpWidget(
          buildSearchScreen(
            searchResults: (ref, query) async => [
              makeUser(
                userId: 'u1',
                displayName: 'Alice',
                status: followRepository.lastSentTargetUserId == 'u1'
                    ? FollowRelationshipStatus.outgoingPending
                    : FollowRelationshipStatus.none,
              ),
            ],
            followRepository: followRepository,
          ),
        );

        await tester.enterText(
          find.byKey(RelationshipSearchScreen.searchFieldKey),
          'alice',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();

        final actionButton = find.byKey(SocialUserRow.actionButtonKey('u1'));
        expect(
          find.descendant(of: actionButton, matching: find.text('Follow')),
          findsOneWidget,
        );

        await tester.tap(actionButton);
        await tester.pumpAndSettle();

        expect(followRepository.lastSentTargetUserId, 'u1');
        expect(
          find.descendant(of: actionButton, matching: find.text('Requested')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'accept action approves an incoming request and refreshes to Following',
      (tester) async {
        final followRepository = RecordingFollowRepository();

        await tester.pumpWidget(
          buildSearchScreen(
            searchResults: (ref, query) async => [
              makeUser(
                userId: 'u1',
                displayName: 'Alice',
                status: followRepository.lastAcceptedFollowId == 'f1'
                    ? FollowRelationshipStatus.following
                    : FollowRelationshipStatus.incomingPending,
                followId: 'f1',
              ),
            ],
            followRepository: followRepository,
          ),
        );

        await tester.enterText(
          find.byKey(RelationshipSearchScreen.searchFieldKey),
          'alice',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();

        final actionButton = find.byKey(SocialUserRow.actionButtonKey('u1'));
        expect(
          find.descendant(of: actionButton, matching: find.text('Accept')),
          findsOneWidget,
        );

        await tester.tap(actionButton);
        await tester.pumpAndSettle();

        expect(followRepository.lastAcceptedFollowId, 'f1');
        expect(
          find.descendant(of: actionButton, matching: find.text('Following')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'following action unfollows only the selected search result user',
      (tester) async {
        final followRepository = RecordingFollowRepository();
        await tester.pumpWidget(
          buildSearchScreen(
            searchResults: (ref, query) async => [
              makeUser(
                userId: 'u1',
                displayName: 'Alice',
                status: FollowRelationshipStatus.following,
              ),
              makeUser(
                userId: 'u2',
                displayName: 'Bob',
                status: FollowRelationshipStatus.following,
              ),
            ],
            followRepository: followRepository,
          ),
        );

        await tester.enterText(
          find.byKey(RelationshipSearchScreen.searchFieldKey),
          'a',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(SocialUserRow.actionButtonKey('u2')));
        await tester.pumpAndSettle();

        expect(followRepository.unfollowCallCount, 1);
        expect(followRepository.lastUnfollowedTargetUserId, 'u2');
        expect(followRepository.lastSentTargetUserId, isNull);
      },
    );
  });
}

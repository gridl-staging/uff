import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/data/follow_repository.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/presentation/social_relationship_list_screen.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';
import 'package:uff/src/features/social/presentation/social_user_row.dart';

import 'fake_follow_repository.dart';

/// ## Test Scenarios
/// - [positive] Followers/following list screens render loading, empty, and populated states.
/// - [positive] Follow-back and unfollow actions mutate and refresh relationship list rows.
/// - [error] Follower/following load failures render retry affordances and recover.
/// - [isolation] Row taps navigate using the selected user id for viewed-profile routes.
/// - [edge] Followers and following list types exercise separate provider dependencies.
SocialUserSummary _user({
  required String userId,
  required String displayName,
  FollowRelationshipStatus status = FollowRelationshipStatus.following,
}) {
  return SocialUserSummary(
    userId: userId,
    displayName: displayName,
    avatarUrl: null,
    relationship: FollowRelationship(
      currentUserId: 'viewer-1',
      targetUserId: userId,
      status: status,
    ),
  );
}

Widget _buildListScreen({
  required SocialRelationshipListType listType,
  required FutureOr<List<SocialUserSummary>> Function(Ref) followersResults,
  required FutureOr<List<SocialUserSummary>> Function(Ref) followingResults,
  FollowRepository? followRepository,
}) {
  return ProviderScope(
    overrides: [
      followersProvider.overrideWith((ref) => followersResults(ref)),
      followingProvider.overrideWith((ref) => followingResults(ref)),
      if (followRepository != null)
        followRepositoryProvider.overrideWithValue(followRepository),
    ],
    child: MaterialApp(
      home: SocialRelationshipListScreen(listType: listType),
    ),
  );
}

Widget _buildListRouterScreen({
  required SocialRelationshipListType listType,
  required FutureOr<List<SocialUserSummary>> Function(Ref) followersResults,
  required FutureOr<List<SocialUserSummary>> Function(Ref) followingResults,
  FollowRepository? followRepository,
}) {
  final router = GoRouter(
    initialLocation: '/list',
    routes: [
      GoRoute(
        path: '/list',
        builder: (context, state) =>
            SocialRelationshipListScreen(listType: listType),
      ),
      GoRoute(
        path: '/social/profile/:userId',
        builder: (context, state) =>
            Text('profile:${state.pathParameters['userId']}'),
      ),
      GoRoute(
        path: SocialRoutes.searchPath,
        builder: (context, state) => const SizedBox.shrink(),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      followersProvider.overrideWith((ref) => followersResults(ref)),
      followingProvider.overrideWith((ref) => followingResults(ref)),
      if (followRepository != null)
        followRepositoryProvider.overrideWithValue(followRepository),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('SocialRelationshipListScreen followers', () {
    testWidgets('shows loading indicator while followers load', (tester) async {
      final pendingFollowers = Completer<List<SocialUserSummary>>();
      addTearDown(() {
        if (!pendingFollowers.isCompleted) {
          pendingFollowers.complete(const <SocialUserSummary>[]);
        }
      });

      await tester.pumpWidget(
        _buildListScreen(
          listType: SocialRelationshipListType.followers,
          followersResults: (ref) => pendingFollowers.future,
          followingResults: (ref) async => const <SocialUserSummary>[],
        ),
      );
      await tester.pump();

      expect(
        find.byKey(SocialRelationshipListScreen.loadingIndicatorKey),
        findsOneWidget,
      );
    });

    testWidgets('shows error state and retries followers load', (tester) async {
      var allowSuccess = false;
      await tester.pumpWidget(
        _buildListScreen(
          listType: SocialRelationshipListType.followers,
          followersResults: (ref) {
            if (!allowSuccess) {
              return Future<List<SocialUserSummary>>.error(
                Exception('network error'),
              );
            }
            return Future.value(<SocialUserSummary>[
              _user(userId: 'u1', displayName: 'Alice'),
            ]);
          },
          followingResults: (ref) async => const <SocialUserSummary>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(SocialRelationshipListScreen.errorStateKey),
        findsOneWidget,
      );
      expect(
        find.byKey(SocialRelationshipListScreen.retryButtonKey),
        findsOneWidget,
      );

      allowSuccess = true;
      await tester.tap(find.byKey(SocialRelationshipListScreen.retryButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(SocialUserRow.userRowKey('u1')), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows empty followers state', (tester) async {
      await tester.pumpWidget(
        _buildListScreen(
          listType: SocialRelationshipListType.followers,
          followersResults: (ref) async => const <SocialUserSummary>[],
          followingResults: (ref) async => const <SocialUserSummary>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(SocialRelationshipListScreen.emptyStateKey),
        findsOneWidget,
      );
      expect(find.text('No followers yet'), findsOneWidget);
    });

    testWidgets('renders populated followers list', (tester) async {
      final followers = [
        _user(userId: 'u1', displayName: 'Alice'),
        _user(userId: 'u2', displayName: 'Bob'),
      ];

      await tester.pumpWidget(
        _buildListScreen(
          listType: SocialRelationshipListType.followers,
          followersResults: (ref) async => followers,
          followingResults: (ref) async => const <SocialUserSummary>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(SocialUserRow.userRowKey('u1')), findsOneWidget);
      expect(find.byKey(SocialUserRow.userRowKey('u2')), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('tapping follower row pushes viewed-user profile route path', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildListRouterScreen(
          listType: SocialRelationshipListType.followers,
          followersResults: (ref) async => [
            _user(userId: 'u1', displayName: 'Alice'),
          ],
          followingResults: (ref) async => const <SocialUserSummary>[],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(SocialUserRow.userRowKey('u1')));
      await tester.pumpAndSettle();

      expect(find.text('profile:u1'), findsOneWidget);
    });

    testWidgets('follow back action sends request and refreshes the row', (
      tester,
    ) async {
      final followRepository = RecordingFollowRepository();

      await tester.pumpWidget(
        _buildListScreen(
          listType: SocialRelationshipListType.followers,
          followersResults: (ref) async => [
            _user(
              userId: 'u1',
              displayName: 'Alice',
              status: followRepository.lastSentTargetUserId == 'u1'
                  ? FollowRelationshipStatus.outgoingPending
                  : FollowRelationshipStatus.none,
            ),
          ],
          followingResults: (ref) async => const <SocialUserSummary>[],
          followRepository: followRepository,
        ),
      );
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
    });
  });

  group('SocialRelationshipListScreen following', () {
    testWidgets('shows loading indicator while following load', (tester) async {
      final pendingFollowing = Completer<List<SocialUserSummary>>();
      addTearDown(() {
        if (!pendingFollowing.isCompleted) {
          pendingFollowing.complete(const <SocialUserSummary>[]);
        }
      });

      await tester.pumpWidget(
        _buildListScreen(
          listType: SocialRelationshipListType.following,
          followersResults: (ref) async => const <SocialUserSummary>[],
          followingResults: (ref) => pendingFollowing.future,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(SocialRelationshipListScreen.loadingIndicatorKey),
        findsOneWidget,
      );
    });

    testWidgets('shows error state and retries following load', (tester) async {
      var allowSuccess = false;
      await tester.pumpWidget(
        _buildListScreen(
          listType: SocialRelationshipListType.following,
          followersResults: (ref) async => const <SocialUserSummary>[],
          followingResults: (ref) {
            if (!allowSuccess) {
              return Future<List<SocialUserSummary>>.error(
                Exception('network error'),
              );
            }
            return Future.value(<SocialUserSummary>[
              _user(userId: 'u3', displayName: 'Charlie'),
            ]);
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(SocialRelationshipListScreen.errorStateKey),
        findsOneWidget,
      );
      expect(
        find.byKey(SocialRelationshipListScreen.retryButtonKey),
        findsOneWidget,
      );

      allowSuccess = true;
      await tester.tap(find.byKey(SocialRelationshipListScreen.retryButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(SocialUserRow.userRowKey('u3')), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
    });

    testWidgets('shows empty following state', (tester) async {
      await tester.pumpWidget(
        _buildListScreen(
          listType: SocialRelationshipListType.following,
          followersResults: (ref) async => const <SocialUserSummary>[],
          followingResults: (ref) async => const <SocialUserSummary>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(SocialRelationshipListScreen.emptyStateKey),
        findsOneWidget,
      );
      expect(find.text('You are not following anyone yet'), findsOneWidget);
    });

    testWidgets('renders populated following list', (tester) async {
      final following = [
        _user(userId: 'u3', displayName: 'Charlie'),
        _user(userId: 'u4', displayName: 'Dana'),
      ];

      await tester.pumpWidget(
        _buildListScreen(
          listType: SocialRelationshipListType.following,
          followersResults: (ref) async => const <SocialUserSummary>[],
          followingResults: (ref) async => following,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(SocialUserRow.userRowKey('u3')), findsOneWidget);
      expect(find.byKey(SocialUserRow.userRowKey('u4')), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('Dana'), findsOneWidget);
    });

    testWidgets('following action unfollows and refreshes the list', (
      tester,
    ) async {
      final followRepository = RecordingFollowRepository();

      await tester.pumpWidget(
        _buildListScreen(
          listType: SocialRelationshipListType.following,
          followersResults: (ref) async => const <SocialUserSummary>[],
          followingResults: (ref) async =>
              followRepository.lastUnfollowedTargetUserId == 'u3'
              ? const <SocialUserSummary>[]
              : [
                  _user(
                    userId: 'u3',
                    displayName: 'Charlie',
                  ),
                ],
          followRepository: followRepository,
        ),
      );
      await tester.pumpAndSettle();

      final actionButton = find.byKey(SocialUserRow.actionButtonKey('u3'));
      expect(
        find.descendant(of: actionButton, matching: find.text('Following')),
        findsOneWidget,
      );

      await tester.tap(actionButton);
      await tester.pumpAndSettle();

      expect(followRepository.lastUnfollowedTargetUserId, 'u3');
      expect(
        find.byKey(SocialRelationshipListScreen.emptyStateKey),
        findsOneWidget,
      );
      expect(find.text('You are not following anyone yet'), findsOneWidget);
    });
  });
}

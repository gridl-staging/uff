import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/data/follow_repository.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/presentation/pending_follow_requests_screen.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';
import 'package:uff/src/features/social/presentation/social_user_row.dart';

import 'fake_follow_repository.dart';

/// ## Test Scenarios
/// - [positive] Pending-requests screen renders loading, empty, and populated request states.
/// - [positive] Accept/reject actions call follow mutations and refresh pending-list reads.
/// - [error] Load failures render retry UI and recover after provider invalidation.
/// - [negative] Action buttons remain disabled for non-incoming relationship statuses.
/// - [isolation] Row navigation pushes viewed-user profile route using the tapped pending user id.
void main() {
  // -- Test data builders --------------------------------------------------

  SocialUserSummary pendingUser({
    required String userId,
    required String followId,
    String? displayName,
    FollowRelationshipStatus status = FollowRelationshipStatus.incomingPending,
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

  Widget buildPendingScreen({
    required FutureOr<List<SocialUserSummary>> Function(Ref) pendingResults,
    FollowRepository? followRepository,
  }) {
    return ProviderScope(
      overrides: [
        pendingRequestsProvider.overrideWith(
          (ref) => pendingResults(ref),
        ),
        if (followRepository != null)
          followRepositoryProvider.overrideWithValue(followRepository),
      ],
      child: const MaterialApp(home: PendingFollowRequestsScreen()),
    );
  }

  Widget buildPendingRouterScreen({
    required FutureOr<List<SocialUserSummary>> Function(Ref) pendingResults,
    FollowRepository? followRepository,
  }) {
    final router = GoRouter(
      initialLocation: '/pending',
      routes: [
        GoRoute(
          path: '/pending',
          builder: (context, state) => const PendingFollowRequestsScreen(),
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
        pendingRequestsProvider.overrideWith(
          (ref) => pendingResults(ref),
        ),
        if (followRepository != null)
          followRepositoryProvider.overrideWithValue(followRepository),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  group('PendingFollowRequestsScreen', () {
    testWidgets('shows loading indicator while requests load', (
      tester,
    ) async {
      final pending = Completer<List<SocialUserSummary>>();
      addTearDown(() {
        if (!pending.isCompleted) {
          pending.complete(const <SocialUserSummary>[]);
        }
      });

      await tester.pumpWidget(
        buildPendingScreen(pendingResults: (ref) => pending.future),
      );
      await tester.pump();

      expect(
        find.byKey(PendingFollowRequestsScreen.loadingIndicatorKey),
        findsOneWidget,
      );
    });

    testWidgets('shows error state with retry on load failure', (
      tester,
    ) async {
      var allowSuccess = false;
      await tester.pumpWidget(
        buildPendingScreen(
          pendingResults: (ref) {
            if (!allowSuccess) {
              return Future<List<SocialUserSummary>>.error(
                Exception('network error'),
              );
            }
            return Future.value(<SocialUserSummary>[
              pendingUser(
                userId: 'u1',
                displayName: 'Alice',
                followId: 'f1',
              ),
            ]);
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(PendingFollowRequestsScreen.errorStateKey),
        findsOneWidget,
      );
      expect(
        find.byKey(PendingFollowRequestsScreen.retryButtonKey),
        findsOneWidget,
      );

      // Tap retry and verify results load.
      allowSuccess = true;
      await tester.tap(
        find.byKey(PendingFollowRequestsScreen.retryButtonKey),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows empty state when no pending requests', (tester) async {
      await tester.pumpWidget(
        buildPendingScreen(
          pendingResults: (ref) async => const <SocialUserSummary>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(PendingFollowRequestsScreen.emptyStateKey),
        findsOneWidget,
      );
    });

    testWidgets('renders incoming pending user rows', (tester) async {
      final users = [
        pendingUser(userId: 'u1', displayName: 'Alice', followId: 'f1'),
        pendingUser(userId: 'u2', displayName: 'Bob', followId: 'f2'),
      ];

      await tester.pumpWidget(
        buildPendingScreen(pendingResults: (ref) async => users),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(SocialUserRow.userRowKey('u1')), findsOneWidget);
      expect(find.byKey(SocialUserRow.userRowKey('u2')), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets(
      'tapping pending-request row pushes viewed-user profile route path',
      (tester) async {
        await tester.pumpWidget(
          buildPendingRouterScreen(
            pendingResults: (ref) async => [
              pendingUser(userId: 'u1', displayName: 'Alice', followId: 'f1'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(SocialUserRow.userRowKey('u1')));
        await tester.pumpAndSettle();

        expect(find.text('profile:u1'), findsOneWidget);
      },
    );

    testWidgets('shows Accept button for incoming pending users', (
      tester,
    ) async {
      final users = [
        pendingUser(userId: 'u1', displayName: 'Alice', followId: 'f1'),
      ];

      await tester.pumpWidget(
        buildPendingScreen(pendingResults: (ref) async => users),
      );
      await tester.pumpAndSettle();

      final actionButton = find.byKey(SocialUserRow.actionButtonKey('u1'));
      expect(actionButton, findsOneWidget);
      expect(
        find.descendant(of: actionButton, matching: find.text('Accept')),
        findsOneWidget,
      );
    });

    testWidgets(
      'disables non-incoming relationship action even when follow id exists',
      (tester) async {
        final users = [
          pendingUser(
            userId: 'u1',
            displayName: 'Alice',
            followId: 'f1',
            status: FollowRelationshipStatus.outgoingPending,
          ),
        ];

        await tester.pumpWidget(
          buildPendingScreen(pendingResults: (ref) async => users),
        );
        await tester.pumpAndSettle();

        final actionButton = find.byKey(SocialUserRow.actionButtonKey('u1'));
        expect(
          find.descendant(of: actionButton, matching: find.text('Requested')),
          findsOneWidget,
        );
        final requestedButton = tester.widget<OutlinedButton>(actionButton);
        expect(requestedButton.onPressed, isNull);
      },
    );

    testWidgets('shows reject button for incoming pending users', (
      tester,
    ) async {
      final users = [
        pendingUser(userId: 'u1', displayName: 'Alice', followId: 'f1'),
      ];

      await tester.pumpWidget(
        buildPendingScreen(pendingResults: (ref) async => users),
      );
      await tester.pumpAndSettle();

      final rejectButton = find.byKey(
        PendingFollowRequestsScreen.rejectButtonKey('u1'),
      );
      expect(rejectButton, findsOneWidget);
    });

    testWidgets(
      'disables reject action for non-incoming relationship even when follow id exists',
      (tester) async {
        final users = [
          pendingUser(
            userId: 'u1',
            displayName: 'Alice',
            followId: 'f1',
            status: FollowRelationshipStatus.outgoingPending,
          ),
        ];

        await tester.pumpWidget(
          buildPendingScreen(pendingResults: (ref) async => users),
        );
        await tester.pumpAndSettle();

        final rejectButton = find.byKey(
          PendingFollowRequestsScreen.rejectButtonKey('u1'),
        );
        expect(rejectButton, findsOneWidget);
        expect(tester.widget<IconButton>(rejectButton).onPressed, isNull);
      },
    );

    testWidgets('accepts a pending request and refreshes the list', (
      tester,
    ) async {
      final followRepository = RecordingFollowRepository();
      await tester.pumpWidget(
        buildPendingScreen(
          pendingResults: (ref) async =>
              followRepository.lastAcceptedFollowId == 'f1'
              ? const []
              : [
                  pendingUser(
                    userId: 'u1',
                    displayName: 'Alice',
                    followId: 'f1',
                  ),
                ],
          followRepository: followRepository,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(SocialUserRow.actionButtonKey('u1')));
      await tester.pumpAndSettle();

      expect(followRepository.lastAcceptedFollowId, 'f1');
      expect(
        find.byKey(PendingFollowRequestsScreen.emptyStateKey),
        findsOneWidget,
      );
    });

    testWidgets('rejects a pending request and refreshes the list', (
      tester,
    ) async {
      final followRepository = RecordingFollowRepository();
      await tester.pumpWidget(
        buildPendingScreen(
          pendingResults: (ref) async =>
              followRepository.lastRejectedFollowId == 'f1'
              ? const []
              : [
                  pendingUser(
                    userId: 'u1',
                    displayName: 'Alice',
                    followId: 'f1',
                  ),
                ],
          followRepository: followRepository,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(PendingFollowRequestsScreen.rejectButtonKey('u1')),
      );
      await tester.pumpAndSettle();

      expect(followRepository.lastRejectedFollowId, 'f1');
      expect(
        find.byKey(PendingFollowRequestsScreen.emptyStateKey),
        findsOneWidget,
      );
    });
  });
}

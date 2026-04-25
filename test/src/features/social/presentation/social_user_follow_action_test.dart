import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/presentation/social_user_follow_action.dart';

import 'fake_follow_repository.dart';

/// ## Test Scenarios
/// - [positive] None/incoming/following relationship statuses map to correct follow action callbacks.
/// - [negative] Outgoing-pending and missing-follow-id states do not expose actionable callbacks.
/// - [edge] Following state only allows unfollow when allowUnfollow is true.
/// - [isolation] Callback wiring dispatches mutation requests against the targeted user id only.
void main() {
  // -- Test data builder ----------------------------------------------------

  SocialUserSummary makeUser({
    String userId = 'u1',
    FollowRelationshipStatus status = FollowRelationshipStatus.none,
    String? followId,
  }) {
    return SocialUserSummary(
      userId: userId,
      displayName: 'User $userId',
      avatarUrl: null,
      relationship: FollowRelationship(
        currentUserId: 'viewer-1',
        targetUserId: userId,
        status: status,
        followId: followId,
      ),
    );
  }

  // -- Harness --------------------------------------------------------------

  /// Pumps a minimal Consumer that calls [buildSocialUserFollowAction] and
  /// exposes the result as a button whose onPressed is the returned callback.
  /// If the callback is null the button text reads 'null-callback'.
  Widget buildHarness({
    required RecordingFollowRepository repo,
    required SocialUserSummary user,
    bool allowUnfollow = false,
  }) {
    return ProviderScope(
      overrides: [
        followRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final callback = buildSocialUserFollowAction(
                ref: ref,
                user: user,
                allowUnfollow: allowUnfollow,
              );
              return ElevatedButton(
                onPressed: callback,
                child: Text(callback == null ? 'null-callback' : 'action'),
              );
            },
          ),
        ),
      ),
    );
  }

  // -- Tests ----------------------------------------------------------------

  group('buildSocialUserFollowAction', () {
    testWidgets('none status returns callback that calls sendFollowRequest', (
      tester,
    ) async {
      final repo = RecordingFollowRepository();
      final user = makeUser();

      await tester.pumpWidget(buildHarness(repo: repo, user: user));
      await tester.pump();

      // Callback is non-null.
      expect(find.text('action'), findsOneWidget);

      await tester.tap(find.text('action'));
      await tester.pumpAndSettle();

      expect(repo.sendFollowRequestCallCount, 1);
      expect(repo.lastSentTargetUserId, 'u1');
    });

    testWidgets('outgoingPending status returns null callback', (
      tester,
    ) async {
      final repo = RecordingFollowRepository();
      final user = makeUser(status: FollowRelationshipStatus.outgoingPending);

      await tester.pumpWidget(buildHarness(repo: repo, user: user));
      await tester.pump();

      expect(find.text('null-callback'), findsOneWidget);
    });

    testWidgets(
      'incomingPending with non-null followId returns callback that calls acceptFollowRequest',
      (tester) async {
        final repo = RecordingFollowRepository();
        final user = makeUser(
          status: FollowRelationshipStatus.incomingPending,
          followId: 'f1',
        );

        await tester.pumpWidget(buildHarness(repo: repo, user: user));
        await tester.pump();

        expect(find.text('action'), findsOneWidget);

        await tester.tap(find.text('action'));
        await tester.pumpAndSettle();

        expect(repo.acceptFollowRequestCallCount, 1);
        expect(repo.lastAcceptedFollowId, 'f1');
      },
    );

    testWidgets('incomingPending with null followId returns null callback', (
      tester,
    ) async {
      final repo = RecordingFollowRepository();
      final user = makeUser(
        status: FollowRelationshipStatus.incomingPending,
      );

      await tester.pumpWidget(buildHarness(repo: repo, user: user));
      await tester.pump();

      expect(find.text('null-callback'), findsOneWidget);
    });

    testWidgets('following with allowUnfollow false returns null callback', (
      tester,
    ) async {
      final repo = RecordingFollowRepository();
      final user = makeUser(status: FollowRelationshipStatus.following);

      await tester.pumpWidget(
        buildHarness(repo: repo, user: user),
      );
      await tester.pump();

      expect(find.text('null-callback'), findsOneWidget);
    });

    testWidgets(
      'following with allowUnfollow true returns callback that calls unfollow',
      (tester) async {
        final repo = RecordingFollowRepository();
        final user = makeUser(status: FollowRelationshipStatus.following);

        await tester.pumpWidget(
          buildHarness(repo: repo, user: user, allowUnfollow: true),
        );
        await tester.pump();

        expect(find.text('action'), findsOneWidget);

        await tester.tap(find.text('action'));
        await tester.pumpAndSettle();

        expect(repo.unfollowCallCount, 1);
        expect(repo.lastUnfollowedTargetUserId, 'u1');
      },
    );
  });
}

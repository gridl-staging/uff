import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/social/data/supabase_comments_repository.dart';
import 'package:uff/src/features/social/data/supabase_follow_repository.dart';

import 'supabase_smoke_helpers.dart';

// ## Test Scenarios
// - [positive] Public comments are visible to non-owners and followers-only
//   comments become visible to the permitted viewer after accepted follow.
// - [negative] Non-follower viewers cannot read or add comments on
//   followers-only/private activities.
// - [isolation] Permitted viewer loses followers-only comment read/write
//   access immediately after follower-side unfollow(owner.userId).
void main() {
  group('Social comments smoke test', skip: skipReason, () {
    late SmokeTestUser owner;
    late SmokeTestUser permittedViewer;
    late SmokeTestUser blockedViewer;
    late SupabaseCommentsRepository permittedViewerCommentsRepository;
    late SupabaseCommentsRepository blockedViewerCommentsRepository;
    late SupabaseFollowRepository permittedViewerFollowRepository;

    setUp(() async {
      owner = await createSignedInTestUser(displayName: 'Comments Owner');
      permittedViewer = await createSignedInTestUser(
        displayName: 'Comments Viewer',
      );
      blockedViewer = await createSignedInTestUser(
        displayName: 'Comments Blocked Viewer',
      );
      permittedViewerCommentsRepository = SupabaseCommentsRepository(
        permittedViewer.client,
      );
      blockedViewerCommentsRepository = SupabaseCommentsRepository(
        blockedViewer.client,
      );
      permittedViewerFollowRepository = SupabaseFollowRepository(
        permittedViewer.client,
      );
    });

    tearDown(() async {
      await cleanupSmokeTestUsers([owner, permittedViewer, blockedViewer]);
    });

    test(
      'proves comment visibility transitions across follow and unfollow',
      () async {
        final publicActivityId = await seedActivityForCurrentUser(
          owner.client,
          visibility: 'public',
          startedAt: DateTime.utc(2026, 3, 20, 10),
          title: 'Owner Public Run',
        );
        final followersActivityId = await seedActivityForCurrentUser(
          owner.client,
          visibility: 'followers',
          startedAt: DateTime.utc(2026, 3, 20, 11),
          title: 'Owner Followers Run',
        );
        final privateActivityId = await seedActivityForCurrentUser(
          owner.client,
          visibility: 'private',
          startedAt: DateTime.utc(2026, 3, 20, 12),
          title: 'Owner Private Run',
        );

        await owner.client.from('comments').insert({
          'activity_id': publicActivityId,
          'user_id': owner.userId,
          'body': 'Owner public baseline comment',
        });
        await owner.client.from('comments').insert({
          'activity_id': followersActivityId,
          'user_id': owner.userId,
          'body': 'Owner followers baseline comment',
        });
        await owner.client.from('comments').insert({
          'activity_id': privateActivityId,
          'user_id': owner.userId,
          'body': 'Owner private baseline comment',
        });

        final permittedPublicBeforeFollow =
            await permittedViewerCommentsRepository.loadActivityComments(
              publicActivityId,
            );
        expect(
          permittedPublicBeforeFollow.map((comment) => comment.body).toList(),
          ['Owner public baseline comment'],
        );

        final permittedFollowersBeforeFollow =
            await permittedViewerCommentsRepository.loadActivityComments(
              followersActivityId,
            );
        expect(
          permittedFollowersBeforeFollow,
          isEmpty,
          reason:
              'Followers-only comments should be hidden before accepted follow.',
        );

        await expectLater(
          permittedViewerCommentsRepository.addComment(
            activityId: followersActivityId,
            body: 'Permitted pre-follow comment attempt',
          ),
          throwsA(
            predicate(
              (Object error) => error is PostgrestException,
              'throws PostgrestException',
            ),
          ),
        );

        final blockedFollowersRead = await blockedViewerCommentsRepository
            .loadActivityComments(followersActivityId);
        expect(
          blockedFollowersRead,
          isEmpty,
          reason: 'Blocked viewer should not read followers-only comments.',
        );

        final blockedPrivateRead = await blockedViewerCommentsRepository
            .loadActivityComments(privateActivityId);
        expect(
          blockedPrivateRead,
          isEmpty,
          reason: 'Blocked viewer should not read private comments.',
        );

        await expectLater(
          blockedViewerCommentsRepository.addComment(
            activityId: followersActivityId,
            body: 'Blocked followers-only comment attempt',
          ),
          throwsA(
            predicate(
              (Object error) => error is PostgrestException,
              'throws PostgrestException',
            ),
          ),
        );
        await expectLater(
          blockedViewerCommentsRepository.addComment(
            activityId: privateActivityId,
            body: 'Blocked private comment attempt',
          ),
          throwsA(
            predicate(
              (Object error) => error is PostgrestException,
              'throws PostgrestException',
            ),
          ),
        );

        await seedAcceptedFollow(
          requesterClient: permittedViewer.client,
          targetClient: owner.client,
        );

        final permittedFollowersAfterFollow =
            await permittedViewerCommentsRepository.loadActivityComments(
              followersActivityId,
            );
        expect(
          permittedFollowersAfterFollow.map((comment) => comment.body).toList(),
          ['Owner followers baseline comment'],
        );

        final insertedByPermittedViewer =
            await permittedViewerCommentsRepository.addComment(
              activityId: followersActivityId,
              body: 'Permitted followers follow-up comment',
            );
        expect(
          insertedByPermittedViewer.body,
          'Permitted followers follow-up comment',
        );
        expect(insertedByPermittedViewer.activityId, followersActivityId);

        final permittedFollowersAfterInsert =
            await permittedViewerCommentsRepository.loadActivityComments(
              followersActivityId,
            );
        expect(
          permittedFollowersAfterInsert.map((comment) => comment.body).toList(),
          [
            'Owner followers baseline comment',
            'Permitted followers follow-up comment',
          ],
        );

        await permittedViewerCommentsRepository.deleteComment(
          insertedByPermittedViewer.commentId,
        );

        final permittedFollowersAfterDelete =
            await permittedViewerCommentsRepository.loadActivityComments(
              followersActivityId,
            );
        expect(
          permittedFollowersAfterDelete.map((comment) => comment.body).toList(),
          ['Owner followers baseline comment'],
        );

        await permittedViewerFollowRepository.unfollow(owner.userId);

        final permittedFollowersAfterUnfollow =
            await permittedViewerCommentsRepository.loadActivityComments(
              followersActivityId,
            );
        expect(
          permittedFollowersAfterUnfollow,
          isEmpty,
          reason:
              'Followers-only comments should be hidden again after unfollow.',
        );

        await expectLater(
          permittedViewerCommentsRepository.addComment(
            activityId: followersActivityId,
            body: 'Permitted post-unfollow comment attempt',
          ),
          throwsA(
            predicate(
              (Object error) => error is PostgrestException,
              'throws PostgrestException',
            ),
          ),
        );

        final permittedPublicAfterUnfollow =
            await permittedViewerCommentsRepository.loadActivityComments(
              publicActivityId,
            );
        expect(
          permittedPublicAfterUnfollow.map((comment) => comment.body).toList(),
          ['Owner public baseline comment'],
        );
      },
    );
  });
}

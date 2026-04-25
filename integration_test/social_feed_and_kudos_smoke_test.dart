import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/social/data/supabase_follow_repository.dart';
import 'package:uff/src/features/social/data/supabase_kudos_repository.dart';
import 'package:uff/src/features/social/data/supabase_social_activity_repository.dart';

import 'supabase_smoke_helpers.dart';

// ## Test Scenarios
// - [positive] Accepted follower sees owner public and followers-only
//   activities through loadFeedActivities, loadUserActivities, and
//   loadActivityDetail.
// - [negative] Stranger and non-follower are blocked from owner
//   followers-only/private detail reads while still seeing public activity.
// - [isolation] Follower-side unfollow(owner.userId) immediately revokes
//   followers-only visibility from feed, viewed-user list, and detail reads.
void main() {
  group('Social feed/detail/kudos smoke test', skip: skipReason, () {
    late SmokeTestUser owner;
    late SmokeTestUser follower;
    late SmokeTestUser stranger;
    late SupabaseSocialActivityRepository ownerActivityRepository;
    late SupabaseSocialActivityRepository followerActivityRepository;
    late SupabaseSocialActivityRepository strangerActivityRepository;
    late SupabaseFollowRepository followerFollowRepository;
    late SupabaseKudosRepository followerKudosRepository;

    setUp(() async {
      owner = await createSignedInTestUser(displayName: 'Feed Owner');
      follower = await createSignedInTestUser(displayName: 'Feed Follower');
      stranger = await createSignedInTestUser(displayName: 'Feed Stranger');
      ownerActivityRepository = SupabaseSocialActivityRepository(owner.client);
      followerActivityRepository = SupabaseSocialActivityRepository(
        follower.client,
      );
      strangerActivityRepository = SupabaseSocialActivityRepository(
        stranger.client,
      );
      followerFollowRepository = SupabaseFollowRepository(follower.client);
      followerKudosRepository = SupabaseKudosRepository(follower.client);
    });

    tearDown(() async {
      await cleanupSmokeTestUsers([owner, follower, stranger]);
    });

    test(
      'proves feed, list, and detail visibility transitions across follow and unfollow',
      () async {
        final publicActivityId = await seedActivityForCurrentUser(
          owner.client,
          visibility: 'public',
          startedAt: DateTime.utc(2026, 3, 19, 10),
          title: 'Owner Public Run',
        );
        final followersActivityId = await seedActivityForCurrentUser(
          owner.client,
          visibility: 'followers',
          startedAt: DateTime.utc(2026, 3, 19, 11),
          title: 'Owner Followers Run',
        );
        final privateActivityId = await seedActivityForCurrentUser(
          owner.client,
          visibility: 'private',
          startedAt: DateTime.utc(2026, 3, 19, 12),
          title: 'Owner Private Run',
        );
        await seedTrackPointsForActivity(
          owner.client,
          activityId: publicActivityId,
          startedAt: DateTime.utc(2026, 3, 19, 10),
        );
        await seedTrackPointsForActivity(
          owner.client,
          activityId: followersActivityId,
          startedAt: DateTime.utc(2026, 3, 19, 11),
        );

        // Create a privacy zone around seeded track points so non-owner detail
        // reads prove masked coordinates through the repository read path.
        await owner.client.from('privacy_zones').insert({
          'user_id': owner.userId,
          'label': 'Owner Home',
          'latitude': 40.7128,
          'longitude': -74.0060,
          'radius_meters': 5000,
        });

        final followerFeedBeforeFollow = await followerActivityRepository
            .loadFeedActivities(offset: 0, limit: 20);
        expect(followerFeedBeforeFollow, isEmpty);

        final strangerFeedBeforeFollow = await strangerActivityRepository
            .loadFeedActivities(offset: 0, limit: 20);
        expect(strangerFeedBeforeFollow, isEmpty);

        final ownerPublicDetail = await ownerActivityRepository
            .loadActivityDetail(
              publicActivityId,
            );
        final ownerFollowersDetail = await ownerActivityRepository
            .loadActivityDetail(followersActivityId);
        final ownerPrivateDetail = await ownerActivityRepository
            .loadActivityDetail(privateActivityId);
        expect(ownerPublicDetail?.activityId, publicActivityId);
        expect(ownerPublicDetail?.title, 'Owner Public Run');
        expect(ownerFollowersDetail?.activityId, followersActivityId);
        expect(ownerFollowersDetail?.title, 'Owner Followers Run');
        expect(ownerPrivateDetail?.activityId, privateActivityId);
        expect(ownerPrivateDetail?.title, 'Owner Private Run');

        final followerViewedListBeforeFollow = await followerActivityRepository
            .loadUserActivities(owner.userId);
        expect(
          followerViewedListBeforeFollow.map((a) => a.activityId).toList(),
          [publicActivityId],
        );
        expect(
          followerViewedListBeforeFollow.map((a) => a.title).toList(),
          ['Owner Public Run'],
        );

        final strangerViewedListBeforeFollow = await strangerActivityRepository
            .loadUserActivities(owner.userId);
        expect(
          strangerViewedListBeforeFollow.map((a) => a.activityId).toList(),
          [publicActivityId],
        );
        expect(
          strangerViewedListBeforeFollow.map((a) => a.title).toList(),
          ['Owner Public Run'],
        );

        final publicDetailBeforeFollow = await followerActivityRepository
            .loadActivityDetail(publicActivityId);
        final followersDetailBeforeFollow = await followerActivityRepository
            .loadActivityDetail(followersActivityId);
        final privateDetailBeforeFollow = await followerActivityRepository
            .loadActivityDetail(privateActivityId);
        final strangerPublicDetailBeforeFollow =
            await strangerActivityRepository.loadActivityDetail(
              publicActivityId,
            );
        final strangerFollowersDetailBeforeFollow =
            await strangerActivityRepository.loadActivityDetail(
              followersActivityId,
            );
        final strangerPrivateDetailBeforeFollow =
            await strangerActivityRepository.loadActivityDetail(
              privateActivityId,
            );
        expect(publicDetailBeforeFollow?.activityId, publicActivityId);
        expect(publicDetailBeforeFollow?.title, 'Owner Public Run');
        expect(followersDetailBeforeFollow, isNull);
        expect(privateDetailBeforeFollow, isNull);
        expect(strangerPublicDetailBeforeFollow?.activityId, publicActivityId);
        expect(strangerPublicDetailBeforeFollow?.title, 'Owner Public Run');
        expect(strangerFollowersDetailBeforeFollow, isNull);
        expect(strangerPrivateDetailBeforeFollow, isNull);

        await seedAcceptedFollow(
          requesterClient: follower.client,
          targetClient: owner.client,
        );

        final followerFeedAfterFollow = await followerActivityRepository
            .loadFeedActivities(offset: 0, limit: 20);
        expect(
          followerFeedAfterFollow.map((a) => a.activityId).toList(),
          [followersActivityId, publicActivityId],
        );
        expect(
          followerFeedAfterFollow.map((a) => a.title).toList(),
          ['Owner Followers Run', 'Owner Public Run'],
        );

        final strangerFeedAfterFollow = await strangerActivityRepository
            .loadFeedActivities(offset: 0, limit: 20);
        expect(strangerFeedAfterFollow, isEmpty);

        final strangerViewedListDuringFollow = await strangerActivityRepository
            .loadUserActivities(owner.userId);
        expect(
          strangerViewedListDuringFollow.map((a) => a.activityId).toList(),
          [publicActivityId],
        );
        expect(
          strangerViewedListDuringFollow.map((a) => a.title).toList(),
          ['Owner Public Run'],
        );

        final followerViewedListAfterFollow = await followerActivityRepository
            .loadUserActivities(owner.userId);
        expect(
          followerViewedListAfterFollow.map((a) => a.activityId).toList(),
          [followersActivityId, publicActivityId],
        );
        expect(
          followerViewedListAfterFollow.map((a) => a.title).toList(),
          ['Owner Followers Run', 'Owner Public Run'],
        );

        final followersDetailAfterFollow = await followerActivityRepository
            .loadActivityDetail(followersActivityId);
        final privateDetailDuringFollow = await followerActivityRepository
            .loadActivityDetail(privateActivityId);
        final strangerFollowersDetailDuringFollow =
            await strangerActivityRepository.loadActivityDetail(
              followersActivityId,
            );
        expect(followersDetailAfterFollow?.activityId, followersActivityId);
        expect(followersDetailAfterFollow?.title, 'Owner Followers Run');
        expect(privateDetailDuringFollow, isNull);
        expect(strangerFollowersDetailDuringFollow, isNull);

        final detailBeforeKudos = await followerActivityRepository
            .loadActivityDetail(publicActivityId);
        expect(detailBeforeKudos?.activityId, publicActivityId);
        expect(detailBeforeKudos?.title, 'Owner Public Run');
        expect(detailBeforeKudos?.viewerHasKudo, isFalse);
        expect(detailBeforeKudos?.kudosCount, 0);

        await followerKudosRepository.toggleKudos(
          activityId: publicActivityId,
          viewerHasKudo: false,
        );

        final detailAfterGivingKudos = await followerActivityRepository
            .loadActivityDetail(publicActivityId);
        expect(detailAfterGivingKudos?.activityId, publicActivityId);
        expect(detailAfterGivingKudos?.viewerHasKudo, isTrue);
        expect(detailAfterGivingKudos?.kudosCount, 1);

        await followerKudosRepository.toggleKudos(
          activityId: publicActivityId,
          viewerHasKudo: true,
        );

        final detailAfterRemovingKudos = await followerActivityRepository
            .loadActivityDetail(publicActivityId);
        expect(detailAfterRemovingKudos?.activityId, publicActivityId);
        expect(detailAfterRemovingKudos?.viewerHasKudo, isFalse);
        expect(detailAfterRemovingKudos?.kudosCount, 0);

        await followerFollowRepository.unfollow(owner.userId);

        final followerFeedAfterUnfollow = await followerActivityRepository
            .loadFeedActivities(offset: 0, limit: 20);
        expect(followerFeedAfterUnfollow, isEmpty);

        final followerViewedListAfterUnfollow = await followerActivityRepository
            .loadUserActivities(owner.userId);
        expect(
          followerViewedListAfterUnfollow.map((a) => a.activityId).toList(),
          [publicActivityId],
        );
        expect(
          followerViewedListAfterUnfollow.map((a) => a.title).toList(),
          ['Owner Public Run'],
        );

        final followerPublicDetailAfterUnfollow =
            await followerActivityRepository.loadActivityDetail(
              publicActivityId,
            );
        final followerFollowersDetailAfterUnfollow =
            await followerActivityRepository.loadActivityDetail(
              followersActivityId,
            );
        final followerPrivateDetailAfterUnfollow =
            await followerActivityRepository.loadActivityDetail(
              privateActivityId,
            );
        expect(followerPublicDetailAfterUnfollow?.activityId, publicActivityId);
        expect(followerPublicDetailAfterUnfollow?.title, 'Owner Public Run');
        expect(followerFollowersDetailAfterUnfollow, isNull);
        expect(followerPrivateDetailAfterUnfollow, isNull);

        final ownerDetail = await ownerActivityRepository.loadActivityDetail(
          publicActivityId,
        );
        final followerDetail = await followerActivityRepository
            .loadActivityDetail(publicActivityId);
        expect(ownerDetail?.activityId, publicActivityId);
        expect(followerDetail?.activityId, publicActivityId);
        expect(ownerDetail?.trackPoints.length, 2);
        expect(
          followerDetail?.trackPoints.length,
          ownerDetail?.trackPoints.length,
        );
        expect(
          ownerDetail?.trackPoints.map((point) => point.latitude).toList(),
          [40.7128, 40.7228],
        );
        expect(
          ownerDetail?.trackPoints.map((point) => point.longitude).toList(),
          [-74.006, -74.016],
        );
        expect(
          followerDetail?.trackPoints.map((point) => point.latitude).toList(),
          [null, null],
        );
        expect(
          followerDetail?.trackPoints.map((point) => point.longitude).toList(),
          [null, null],
        );
        expect(
          ownerDetail?.trackPoints.any((point) => point.latitude == null),
          isFalse,
        );
        expect(
          ownerDetail?.trackPoints.any((point) => point.longitude == null),
          isFalse,
        );
        expect(
          followerDetail?.trackPoints.any((point) => point.latitude == null),
          isTrue,
        );
      },
    );
  });
}

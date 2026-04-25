import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/social/data/supabase_follow_repository.dart';

import 'supabase_smoke_helpers.dart';

// ## Test Scenarios
// - [positive] Follow request send/accept/reject/unfollow transitions update
//   follower, following, and pending counts for both users.
// - [negative] Rejected and unfollowed relationships do not retain follower or
//   following membership.
// - [statemachine] Relationship state transitions remain coherent across
//   request -> accept -> unfollow -> request -> reject sequences.
void main() {
  group('Social relationships smoke test', skip: skipReason, () {
    late SmokeTestUser owner;
    late SmokeTestUser viewer;
    late SupabaseFollowRepository ownerRepository;
    late SupabaseFollowRepository viewerRepository;

    setUp(() async {
      owner = await createSignedInTestUser(displayName: 'Social Owner');
      viewer = await createSignedInTestUser(displayName: 'Social Viewer');
      ownerRepository = SupabaseFollowRepository(owner.client);
      viewerRepository = SupabaseFollowRepository(viewer.client);
    });

    tearDown(() async {
      await cleanupSmokeTestUsers([owner, viewer]);
    });

    test(
      'send, accept, reject, and unfollow flows update follower/following/pending counts',
      () async {
        final initialOwnerCounts = await ownerRepository
            .getRelationshipCounts();
        final initialViewerCounts = await viewerRepository
            .getRelationshipCounts();
        expect(initialOwnerCounts.followers, 0);
        expect(initialOwnerCounts.following, 0);
        expect(initialOwnerCounts.pendingRequests, 0);
        expect(initialViewerCounts.followers, 0);
        expect(initialViewerCounts.following, 0);
        expect(initialViewerCounts.pendingRequests, 0);

        await viewerRepository.sendFollowRequest(owner.userId);

        final pendingAfterRequest = await ownerRepository.getPendingRequests();
        expect(pendingAfterRequest, hasLength(1));
        expect(pendingAfterRequest.single.userId, viewer.userId);
        final pendingFollowId =
            pendingAfterRequest.single.relationship.followId;
        expect(pendingFollowId?.length, 36);

        final ownerCountsAfterRequest = await ownerRepository
            .getRelationshipCounts();
        expect(ownerCountsAfterRequest.followers, 0);
        expect(ownerCountsAfterRequest.following, 0);
        expect(ownerCountsAfterRequest.pendingRequests, 1);

        await ownerRepository.acceptFollowRequest(pendingFollowId!);

        final ownerCountsAfterAccept = await ownerRepository
            .getRelationshipCounts();
        final viewerCountsAfterAccept = await viewerRepository
            .getRelationshipCounts();
        expect(ownerCountsAfterAccept.followers, 1);
        expect(ownerCountsAfterAccept.pendingRequests, 0);
        expect(viewerCountsAfterAccept.following, 1);

        final ownerFollowers = await ownerRepository.getFollowers();
        final viewerFollowing = await viewerRepository.getFollowing();
        expect(ownerFollowers.map((u) => u.userId), contains(viewer.userId));
        expect(viewerFollowing.map((u) => u.userId), contains(owner.userId));

        await viewerRepository.unfollow(owner.userId);

        final ownerCountsAfterUnfollow = await ownerRepository
            .getRelationshipCounts();
        final viewerCountsAfterUnfollow = await viewerRepository
            .getRelationshipCounts();
        expect(ownerCountsAfterUnfollow.followers, 0);
        expect(ownerCountsAfterUnfollow.pendingRequests, 0);
        expect(viewerCountsAfterUnfollow.following, 0);

        await viewerRepository.sendFollowRequest(owner.userId);
        final pendingBeforeReject = await ownerRepository.getPendingRequests();
        expect(pendingBeforeReject, hasLength(1));
        final rejectFollowId = pendingBeforeReject.single.relationship.followId;
        expect(rejectFollowId?.length, 36);

        await ownerRepository.rejectFollowRequest(rejectFollowId!);

        final ownerCountsAfterReject = await ownerRepository
            .getRelationshipCounts();
        final viewerCountsAfterReject = await viewerRepository
            .getRelationshipCounts();
        expect(ownerCountsAfterReject.followers, 0);
        expect(ownerCountsAfterReject.pendingRequests, 0);
        expect(viewerCountsAfterReject.following, 0);
      },
    );
  });
}

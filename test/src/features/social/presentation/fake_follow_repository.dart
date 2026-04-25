import 'package:uff/src/features/social/data/follow_repository.dart';
import 'package:uff/src/features/social/domain/relationship_counts.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/domain/viewed_user_profile_header.dart';

/// Test double that records follow-mutation calls for presentation tests.
class RecordingFollowRepository implements FollowRepository {
  int sendFollowRequestCallCount = 0;
  int acceptFollowRequestCallCount = 0;
  int rejectFollowRequestCallCount = 0;
  int unfollowCallCount = 0;

  String? lastSentTargetUserId;
  String? lastAcceptedFollowId;
  String? lastRejectedFollowId;
  String? lastUnfollowedTargetUserId;

  @override
  Future<void> acceptFollowRequest(String followId) async {
    acceptFollowRequestCallCount++;
    lastAcceptedFollowId = followId;
  }

  @override
  Future<List<SocialUserSummary>> getFollowers() async => const [];

  @override
  Future<List<SocialUserSummary>> getFollowing() async => const [];

  @override
  Future<List<SocialUserSummary>> getPendingRequests() async => const [];

  @override
  Future<RelationshipCounts> getRelationshipCounts() async =>
      const RelationshipCounts(
        userId: 'viewer-1',
        followers: 0,
        following: 0,
        pendingRequests: 0,
      );

  @override
  Future<ViewedUserProfileHeader?> getViewedUserProfileHeader(
    String userId,
  ) async => null;

  @override
  Future<void> rejectFollowRequest(String followId) async {
    rejectFollowRequestCallCount++;
    lastRejectedFollowId = followId;
  }

  @override
  Future<void> sendFollowRequest(String targetUserId) async {
    sendFollowRequestCallCount++;
    lastSentTargetUserId = targetUserId;
  }

  @override
  Future<void> unfollow(String targetUserId) async {
    unfollowCallCount++;
    lastUnfollowedTargetUserId = targetUserId;
  }
}

import 'package:uff/src/features/social/domain/relationship_counts.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/domain/viewed_user_profile_header.dart';

/// Contract for follow graph mutations and relationship list reads.
abstract interface class FollowRepository {
  Future<void> sendFollowRequest(String targetUserId);

  Future<void> acceptFollowRequest(String followId);

  Future<void> rejectFollowRequest(String followId);

  Future<void> unfollow(String targetUserId);

  Future<List<SocialUserSummary>> getFollowers();

  Future<List<SocialUserSummary>> getFollowing();

  Future<List<SocialUserSummary>> getPendingRequests();

  Future<RelationshipCounts> getRelationshipCounts();

  Future<ViewedUserProfileHeader?> getViewedUserProfileHeader(String userId);
}

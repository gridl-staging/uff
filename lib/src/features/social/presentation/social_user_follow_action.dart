import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';

/// Builds the shared follow-action callback for a social user row.
///
/// The presentation layer reuses one mapping from relationship status to the
/// follow-action controller so search results and relationship lists do not
/// drift into separate mutation behavior.
VoidCallback? buildSocialUserFollowAction({
  required WidgetRef ref,
  required SocialUserSummary user,
  String? activeSearchQuery,
  bool allowUnfollow = false,
}) {
  switch (user.relationship.status) {
    case FollowRelationshipStatus.none:
      return () {
        ref
            .read(followActionControllerProvider.notifier)
            .sendFollowRequest(
              user.userId,
              activeSearchQuery: activeSearchQuery,
            );
      };
    case FollowRelationshipStatus.outgoingPending:
      return null;
    case FollowRelationshipStatus.incomingPending:
      final followId = user.relationship.followId;
      if (followId == null) {
        return null;
      }
      return () {
        ref
            .read(followActionControllerProvider.notifier)
            .acceptFollowRequest(
              followId,
              activeSearchQuery: activeSearchQuery,
            );
      };
    case FollowRelationshipStatus.following:
      if (!allowUnfollow) {
        return null;
      }
      return () {
        ref
            .read(followActionControllerProvider.notifier)
            .unfollow(
              user.userId,
              activeSearchQuery: activeSearchQuery,
            );
      };
  }
}

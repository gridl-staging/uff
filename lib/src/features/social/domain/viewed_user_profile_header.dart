import 'package:meta/meta.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';

/// Header payload for viewed-user profiles.
@immutable
class ViewedUserProfileHeader {
  const ViewedUserProfileHeader({
    required this.user,
    required this.followersCount,
    required this.followingCount,
  });

  final SocialUserSummary user;
  final int followersCount;
  final int followingCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewedUserProfileHeader &&
          runtimeType == other.runtimeType &&
          user == other.user &&
          followersCount == other.followersCount &&
          followingCount == other.followingCount;

  @override
  int get hashCode => Object.hash(user, followersCount, followingCount);
}

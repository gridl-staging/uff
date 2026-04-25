/// Shared social route definitions.
///
/// Keeping these path constants in one place prevents route drift between
/// router wiring and in-app navigation entry points.
abstract final class SocialRoutes {
  static const searchPath = '/social/search';
  static const followersPath = '/social/followers';
  static const followingPath = '/social/following';
  static const requestsPath = '/social/requests';

  static const viewedUserProfilePathPattern = '/social/profile/:userId';
  static const remoteActivityDetailPathPattern = '/social/activity/:activityId';

  static String viewedUserProfilePath(String userId) {
    return '/social/profile/${Uri.encodeComponent(userId)}';
  }

  static String remoteActivityDetailPath(String activityId) {
    return '/social/activity/${Uri.encodeComponent(activityId)}';
  }
}

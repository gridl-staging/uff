import 'package:meta/meta.dart';

/// Minimal user payload shown in activity kudos surfaces.
@immutable
class ActivityKudoUser {
  const ActivityKudoUser({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
  });

  final String userId;
  final String? displayName;
  final String? avatarUrl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityKudoUser &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          displayName == other.displayName &&
          avatarUrl == other.avatarUrl;

  @override
  int get hashCode => Object.hash(userId, displayName, avatarUrl);
}

/// Aggregate and viewer-specific kudos state for one activity id.
@immutable
class ActivityKudosSummary {
  const ActivityKudosSummary({
    required this.kudosCount,
    required this.viewerHasKudo,
    required this.users,
  });

  final int kudosCount;
  final bool viewerHasKudo;
  final List<ActivityKudoUser> users;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityKudosSummary &&
          runtimeType == other.runtimeType &&
          kudosCount == other.kudosCount &&
          viewerHasKudo == other.viewerHasKudo &&
          _listEquals(users, other.users);

  @override
  int get hashCode => Object.hash(
    kudosCount,
    viewerHasKudo,
    Object.hashAll(users),
  );
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

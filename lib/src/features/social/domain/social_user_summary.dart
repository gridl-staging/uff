import 'package:meta/meta.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';

/// Minimal user payload used by social lists and search results.
@immutable
class SocialUserSummary {
  const SocialUserSummary({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    required this.relationship,
  });

  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final FollowRelationship relationship;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SocialUserSummary &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          displayName == other.displayName &&
          avatarUrl == other.avatarUrl &&
          relationship == other.relationship;

  @override
  int get hashCode => Object.hash(
    userId,
    displayName,
    avatarUrl,
    relationship,
  );
}

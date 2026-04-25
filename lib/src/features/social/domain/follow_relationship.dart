import 'package:meta/meta.dart';

/// Represents the current user's follow relationship to a target user.
enum FollowRelationshipStatus {
  none,
  outgoingPending,
  incomingPending,
  following,
}

/// Describes the social relationship between two user ids.
@immutable
class FollowRelationship {
  const FollowRelationship({
    required this.currentUserId,
    required this.targetUserId,
    required this.status,
    this.followId,
    this.createdAt,
  });

  final String currentUserId;
  final String targetUserId;
  final FollowRelationshipStatus status;
  final String? followId;
  final DateTime? createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FollowRelationship &&
          runtimeType == other.runtimeType &&
          currentUserId == other.currentUserId &&
          targetUserId == other.targetUserId &&
          status == other.status &&
          followId == other.followId &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
    currentUserId,
    targetUserId,
    status,
    followId,
    createdAt,
  );
}

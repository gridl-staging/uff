import 'package:meta/meta.dart';

/// Aggregated follow counters for a single profile id.
@immutable
class RelationshipCounts {
  const RelationshipCounts({
    required this.userId,
    required this.followers,
    required this.following,
    required this.pendingRequests,
  });

  final String userId;
  final int followers;
  final int following;
  final int pendingRequests;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelationshipCounts &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          followers == other.followers &&
          following == other.following &&
          pendingRequests == other.pendingRequests;

  @override
  int get hashCode => Object.hash(
    userId,
    followers,
    following,
    pendingRequests,
  );
}

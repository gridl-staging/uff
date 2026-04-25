import 'package:meta/meta.dart';

/// Lightweight author payload rendered with an activity comment.
@immutable
class CommentAuthor {
  const CommentAuthor({
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
      other is CommentAuthor &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          displayName == other.displayName &&
          avatarUrl == other.avatarUrl;

  @override
  int get hashCode => Object.hash(userId, displayName, avatarUrl);
}

/// Immutable comment row projected from the Stage 2 `public.comments` table.
@immutable
class ActivityComment {
  const ActivityComment({
    required this.commentId,
    required this.activityId,
    required this.author,
    required this.body,
    required this.createdAt,
  });

  final String commentId;
  final String activityId;
  final CommentAuthor author;
  final String body;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityComment &&
          runtimeType == other.runtimeType &&
          commentId == other.commentId &&
          activityId == other.activityId &&
          author == other.author &&
          body == other.body &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
    commentId,
    activityId,
    author,
    body,
    createdAt,
  );
}

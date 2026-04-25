import 'package:uff/src/features/social/domain/activity_comment.dart';

/// Contract for activity comment reads and mutations.
abstract interface class CommentsRepository {
  Future<List<ActivityComment>> loadActivityComments(String activityId);

  Future<ActivityComment> addComment({
    required String activityId,
    required String body,
  });

  Future<void> deleteComment(String commentId);
}

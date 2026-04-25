import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/social/data/comments_repository.dart';
import 'package:uff/src/features/social/data/supabase_follow_repository.dart';
import 'package:uff/src/features/social/domain/activity_comment.dart';

const _commentsSelectColumns =
    'id,activity_id,user_id,body,created_at,profiles!comments_user_id_fkey(id,display_name,avatar_url)';

/// Supabase-backed implementation of [CommentsRepository].
class SupabaseCommentsRepository implements CommentsRepository {
  SupabaseCommentsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ActivityComment>> loadActivityComments(String activityId) async {
    _requireCurrentUserId();
    final rows = await _client
        .from('comments')
        .select(_commentsSelectColumns)
        .eq('activity_id', activityId)
        .order('created_at', ascending: true);

    return rows.map(_commentFromRow).toList(growable: false);
  }

  @override
  Future<ActivityComment> addComment({
    required String activityId,
    required String body,
  }) async {
    final viewerUserId = _requireCurrentUserId();
    final row = await _client
        .from('comments')
        .insert({
          'activity_id': activityId,
          'user_id': viewerUserId,
          'body': body,
        })
        .select(_commentsSelectColumns)
        .single();
    return _commentFromRow(row);
  }

  @override
  Future<void> deleteComment(String commentId) async {
    _requireCurrentUserId();
    final deletedRows = await _client
        .from('comments')
        .delete()
        .eq('id', commentId)
        .select('id');
    if (deletedRows.isNotEmpty) {
      return;
    }
    throw StateError(
      'Unable to delete comment because the requested comment row '
      'was not found or is no longer accessible.',
    );
  }

  ActivityComment _commentFromRow(Map<String, dynamic> row) {
    final rowMap = normalizeSupabaseRow(row);
    final profileRow = extractJoinedProfileRow(rowMap['profiles']);
    final createdAt = _parseCreatedAt(rowMap['created_at']);
    return ActivityComment(
      commentId: rowMap['id'] as String,
      activityId: rowMap['activity_id'] as String,
      author: CommentAuthor(
        userId: rowMap['user_id'] as String,
        displayName: profileRow['display_name'] as String?,
        avatarUrl: profileRow['avatar_url'] as String?,
      ),
      body: rowMap['body'] as String,
      createdAt: createdAt,
    );
  }

  String _requireCurrentUserId() {
    final viewerUserId = _client.auth.currentUser?.id;
    if (viewerUserId == null) {
      throw StateError(
        'Comment operations require an authenticated user session.',
      );
    }
    return viewerUserId;
  }
}

DateTime _parseCreatedAt(dynamic value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw StateError('Comment row is missing a valid created_at timestamp.');
}

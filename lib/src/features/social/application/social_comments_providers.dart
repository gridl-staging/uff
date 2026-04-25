import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uff/src/features/social/data/comments_repository.dart';
import 'package:uff/src/features/social/data/supabase_comments_repository.dart';
import 'package:uff/src/features/social/domain/activity_comment.dart';

part 'social_comments_providers.g.dart';

@riverpod
CommentsRepository commentsRepository(Ref ref) {
  return SupabaseCommentsRepository(Supabase.instance.client);
}

@riverpod
Future<List<ActivityComment>> activityComments(Ref ref, String activityId) {
  return ref.read(commentsRepositoryProvider).loadActivityComments(activityId);
}

/// Single mutation path for adding comments to an activity.
@riverpod
class AddCommentController extends _$AddCommentController {
  @override
  FutureOr<void> build() {}

  Future<ActivityComment> addComment({
    required String activityId,
    required String body,
  }) async {
    return _runCommentMutation(
      ref,
      stateSetter: (nextState) => state = nextState,
      activityId: activityId,
      mutate: (repository) {
        return repository.addComment(activityId: activityId, body: body);
      },
    );
  }
}

/// Single mutation path for deleting comments on an activity.
@riverpod
class DeleteCommentController extends _$DeleteCommentController {
  @override
  FutureOr<void> build() {}

  Future<void> deleteComment({
    required String activityId,
    required String commentId,
  }) async {
    await _runCommentMutation(
      ref,
      stateSetter: (nextState) => state = nextState,
      activityId: activityId,
      mutate: (repository) => repository.deleteComment(commentId),
    );
  }
}

Future<T> _runCommentMutation<T>(
  Ref ref, {
  required void Function(AsyncValue<void> state) stateSetter,
  required String activityId,
  required Future<T> Function(CommentsRepository repository) mutate,
}) async {
  final mutationKeepAlive = ref.keepAlive();
  stateSetter(const AsyncLoading<void>());
  try {
    final result = await mutate(ref.read(commentsRepositoryProvider));
    if (!ref.mounted) {
      return result;
    }
    stateSetter(const AsyncData<void>(null));
    _invalidateActivityCommentsCache(ref, activityId: activityId);
    return result;
  } on Object catch (error, stackTrace) {
    if (ref.mounted) {
      stateSetter(AsyncError<void>(error, stackTrace));
    }
    rethrow;
  } finally {
    mutationKeepAlive.close();
  }
}

void _invalidateActivityCommentsCache(Ref ref, {required String activityId}) {
  ref.invalidate(activityCommentsProvider(activityId));
}

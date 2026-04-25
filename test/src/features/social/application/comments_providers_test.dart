import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/application/social_comments_providers.dart';
import 'package:uff/src/features/social/data/comments_repository.dart';
import 'package:uff/src/features/social/data/social_activity_repository.dart';
import 'package:uff/src/features/social/domain/activity_comment.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/remote_activity_track_point.dart';
import 'package:uff/src/features/social/domain/social_activity_detail.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';

/// ## Test Scenarios
/// - [positive] activityCommentsProvider reads comment rows through the repository seam.
/// - [positive] Add/delete mutation controllers invalidate only scoped comments cache keys.
/// - [negative] Comment mutations surface repository failures without mutating unrelated activity caches.
/// - [error] Provider reads and mutations propagate repository failures as AsyncError state.
/// - [edge] Mutation controllers expose loading state and tolerate provider disposal mid-flight.
/// - [isolation] Comment mutations avoid invalidating unrelated feed/detail caches.
const _viewerId = '11111111-1111-1111-1111-111111111111';
const _ownerId = '22222222-2222-2222-2222-222222222222';
const _activityId = 'activity-1';

class _FakeSocialActivityRepository implements SocialActivityRepository {
  int loadFeedActivitiesCallCount = 0;
  int loadActivityDetailCallCount = 0;

  @override
  Future<List<SocialActivitySummary>> loadFeedActivities({
    required int offset,
    required int limit,
  }) async {
    loadFeedActivitiesCallCount++;
    return [
      SocialActivitySummary(
        activityId: _activityId,
        owner: _ownerSummary(),
        sportType: 'run',
        startedAt: DateTime.utc(2026, 3, 19, 10),
        finishedAt: DateTime.utc(2026, 3, 19, 10, 30),
        distanceMeters: 5000,
        durationSeconds: 1500,
        elevationGainMeters: 40,
        avgPaceSecondsPerKm: 300,
        title: 'Tempo',
        description: null,
        visibility: 'public',
        polylineEncoded: null,
        commentCount: 0,
        kudosCount: 0,
        viewerHasKudo: false,
      ),
    ];
  }

  @override
  Future<SocialActivityDetail?> loadActivityDetail(String activityId) async {
    loadActivityDetailCallCount++;
    return SocialActivityDetail(
      activityId: activityId,
      owner: _ownerSummary(),
      sportType: 'run',
      startedAt: DateTime.utc(2026, 3, 19, 10),
      finishedAt: DateTime.utc(2026, 3, 19, 10, 30),
      distanceMeters: 5000,
      durationSeconds: 1500,
      elevationGainMeters: 40,
      avgPaceSecondsPerKm: 300,
      title: 'Tempo',
      description: null,
      visibility: 'public',
      polylineEncoded: null,
      kudosCount: 0,
      viewerHasKudo: false,
      splits: const <SocialActivitySplit>[],
      trackPoints: const <RemoteActivityTrackPoint>[],
    );
  }

  @override
  Future<List<SocialActivitySummary>> loadUserActivities(String userId) async {
    return const <SocialActivitySummary>[];
  }
}

class _FakeCommentsRepository implements CommentsRepository {
  int loadCallCount = 0;
  int addCallCount = 0;
  int deleteCallCount = 0;

  StateError? loadError;
  StateError? addError;
  StateError? deleteError;

  final List<ActivityComment> _comments = <ActivityComment>[];
  Completer<ActivityComment>? addCompleter;
  Completer<void>? deleteCompleter;

  void seedComments(Iterable<ActivityComment> comments) {
    _comments
      ..clear()
      ..addAll(comments);
  }

  @override
  Future<List<ActivityComment>> loadActivityComments(String activityId) async {
    loadCallCount++;
    if (loadError != null) {
      throw loadError!;
    }
    return _comments
        .where((comment) => comment.activityId == activityId)
        .toList(growable: false);
  }

  @override
  Future<ActivityComment> addComment({
    required String activityId,
    required String body,
  }) async {
    addCallCount++;
    if (addError != null) {
      throw addError!;
    }
    if (addCompleter != null) {
      final inserted = await addCompleter!.future;
      _comments.add(inserted);
      return inserted;
    }

    final inserted = ActivityComment(
      commentId: 'comment-created',
      activityId: activityId,
      author: const CommentAuthor(
        userId: _viewerId,
        displayName: 'Viewer',
        avatarUrl: null,
      ),
      body: body,
      createdAt: DateTime.utc(2026, 3, 20, 12),
    );
    _comments.add(inserted);
    return inserted;
  }

  @override
  Future<void> deleteComment(String commentId) async {
    deleteCallCount++;
    if (deleteError != null) {
      throw deleteError!;
    }
    if (deleteCompleter != null) {
      await deleteCompleter!.future;
    }
    _comments.removeWhere((comment) => comment.commentId == commentId);
  }
}

SocialUserSummary _ownerSummary() {
  return const SocialUserSummary(
    userId: _ownerId,
    displayName: 'Owner',
    avatarUrl: null,
    relationship: FollowRelationship(
      currentUserId: _viewerId,
      targetUserId: _ownerId,
      status: FollowRelationshipStatus.following,
    ),
  );
}

ActivityComment _comment({
  required String commentId,
  required String body,
  required DateTime createdAt,
}) {
  return ActivityComment(
    commentId: commentId,
    activityId: _activityId,
    author: const CommentAuthor(
      userId: _ownerId,
      displayName: 'Owner',
      avatarUrl: null,
    ),
    body: body,
    createdAt: createdAt,
  );
}

void main() {
  test('activityCommentsProvider reads through repository', () async {
    final commentsRepository = _FakeCommentsRepository()
      ..seedComments([
        _comment(
          commentId: 'comment-1',
          body: 'First',
          createdAt: DateTime.utc(2026, 3, 20, 10),
        ),
      ]);
    final container = ProviderContainer(
      overrides: [
        commentsRepositoryProvider.overrideWithValue(commentsRepository),
      ],
    );
    addTearDown(container.dispose);

    final comments = await container.read(
      activityCommentsProvider(_activityId).future,
    );

    expect(commentsRepository.loadCallCount, 1);
    expect(comments.map((comment) => comment.commentId), ['comment-1']);
  });

  test('activityCommentsProvider propagates repository errors', () async {
    final commentsRepository = _FakeCommentsRepository()
      ..loadError = StateError('load failed');
    final container = ProviderContainer(
      overrides: [
        commentsRepositoryProvider.overrideWithValue(commentsRepository),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(activityCommentsProvider(_activityId).future),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('load failed'),
        ),
      ),
    );
  });

  test(
    'addComment invalidates only activityCommentsProvider(activityId)',
    () async {
      final socialRepository = _FakeSocialActivityRepository();
      final commentsRepository = _FakeCommentsRepository()
        ..seedComments([
          _comment(
            commentId: 'comment-1',
            body: 'First',
            createdAt: DateTime.utc(2026, 3, 20, 10),
          ),
        ]);
      final container = ProviderContainer(
        overrides: [
          socialActivityRepositoryProvider.overrideWithValue(socialRepository),
          commentsRepositoryProvider.overrideWithValue(commentsRepository),
          activityPhotoListProvider(
            _activityId,
          ).overrideWith((ref) async => <ActivityPhoto>[]),
        ],
      );
      addTearDown(container.dispose);

      await container.read(socialFeedProvider.future);
      await container.read(remoteActivityDetailProvider(_activityId).future);
      await container.read(activityCommentsProvider(_activityId).future);

      expect(socialRepository.loadFeedActivitiesCallCount, 1);
      expect(socialRepository.loadActivityDetailCallCount, 1);
      expect(commentsRepository.loadCallCount, 1);

      final inserted = await container
          .read(addCommentControllerProvider.notifier)
          .addComment(activityId: _activityId, body: 'Second');

      expect(inserted.commentId, 'comment-created');

      await container.read(socialFeedProvider.future);
      await container.read(remoteActivityDetailProvider(_activityId).future);
      await container.read(activityCommentsProvider(_activityId).future);

      expect(commentsRepository.addCallCount, 1);
      expect(commentsRepository.loadCallCount, 2);
      expect(socialRepository.loadFeedActivitiesCallCount, 1);
      expect(socialRepository.loadActivityDetailCallCount, 1);
    },
  );

  test('addComment exposes async error and keeps read cache stable', () async {
    final commentsRepository = _FakeCommentsRepository()
      ..seedComments([
        _comment(
          commentId: 'comment-1',
          body: 'First',
          createdAt: DateTime.utc(2026, 3, 20, 10),
        ),
      ])
      ..addError = StateError('insert failed');
    final container = ProviderContainer(
      overrides: [
        commentsRepositoryProvider.overrideWithValue(commentsRepository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(activityCommentsProvider(_activityId).future);

    await expectLater(
      container
          .read(addCommentControllerProvider.notifier)
          .addComment(activityId: _activityId, body: 'Second'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('insert failed'),
        ),
      ),
    );

    final state = container.read(addCommentControllerProvider);
    expect(state.hasError, isTrue);

    await container.read(activityCommentsProvider(_activityId).future);
    expect(commentsRepository.loadCallCount, 1);
  });

  test('addComment reports loading while mutation is in flight', () async {
    final commentsRepository = _FakeCommentsRepository()
      ..addCompleter = Completer<ActivityComment>();
    final container = ProviderContainer(
      overrides: [
        commentsRepositoryProvider.overrideWithValue(commentsRepository),
      ],
    );
    addTearDown(container.dispose);

    final addFuture = container
        .read(addCommentControllerProvider.notifier)
        .addComment(activityId: _activityId, body: 'Second');

    await container.pump();
    expect(container.read(addCommentControllerProvider).isLoading, isTrue);

    commentsRepository.addCompleter!.complete(
      ActivityComment(
        commentId: 'comment-created',
        activityId: _activityId,
        author: const CommentAuthor(
          userId: _viewerId,
          displayName: 'Viewer',
          avatarUrl: null,
        ),
        body: 'Second',
        createdAt: DateTime.utc(2026, 3, 20, 12),
      ),
    );

    await expectLater(addFuture, completes);
  });

  test('addComment does not throw when disposed mid-flight', () async {
    final commentsRepository = _FakeCommentsRepository()
      ..addCompleter = Completer<ActivityComment>();
    final container = ProviderContainer(
      overrides: [
        commentsRepositoryProvider.overrideWithValue(commentsRepository),
      ],
    );

    final addFuture = container
        .read(addCommentControllerProvider.notifier)
        .addComment(activityId: _activityId, body: 'Second');

    container.dispose();
    commentsRepository.addCompleter!.complete(
      ActivityComment(
        commentId: 'comment-created',
        activityId: _activityId,
        author: const CommentAuthor(
          userId: _viewerId,
          displayName: 'Viewer',
          avatarUrl: null,
        ),
        body: 'Second',
        createdAt: DateTime.utc(2026, 3, 20, 12),
      ),
    );

    await expectLater(addFuture, completes);
  });

  test(
    'deleteComment invalidates only activityCommentsProvider(activityId)',
    () async {
      final socialRepository = _FakeSocialActivityRepository();
      final commentsRepository = _FakeCommentsRepository()
        ..seedComments([
          _comment(
            commentId: 'comment-1',
            body: 'First',
            createdAt: DateTime.utc(2026, 3, 20, 10),
          ),
        ]);
      final container = ProviderContainer(
        overrides: [
          socialActivityRepositoryProvider.overrideWithValue(socialRepository),
          commentsRepositoryProvider.overrideWithValue(commentsRepository),
          activityPhotoListProvider(
            _activityId,
          ).overrideWith((ref) async => <ActivityPhoto>[]),
        ],
      );
      addTearDown(container.dispose);

      await container.read(socialFeedProvider.future);
      await container.read(remoteActivityDetailProvider(_activityId).future);
      await container.read(activityCommentsProvider(_activityId).future);

      await container
          .read(deleteCommentControllerProvider.notifier)
          .deleteComment(activityId: _activityId, commentId: 'comment-1');

      await container.read(socialFeedProvider.future);
      await container.read(remoteActivityDetailProvider(_activityId).future);
      final comments = await container.read(
        activityCommentsProvider(_activityId).future,
      );

      expect(commentsRepository.deleteCallCount, 1);
      expect(comments, isEmpty);
      expect(commentsRepository.loadCallCount, 2);
      expect(socialRepository.loadFeedActivitiesCallCount, 1);
      expect(socialRepository.loadActivityDetailCallCount, 1);
    },
  );

  test(
    'deleteComment exposes async error and keeps read cache stable',
    () async {
      final commentsRepository = _FakeCommentsRepository()
        ..seedComments([
          _comment(
            commentId: 'comment-1',
            body: 'First',
            createdAt: DateTime.utc(2026, 3, 20, 10),
          ),
        ])
        ..deleteError = StateError('delete failed');
      final container = ProviderContainer(
        overrides: [
          commentsRepositoryProvider.overrideWithValue(commentsRepository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(activityCommentsProvider(_activityId).future);

      await expectLater(
        container
            .read(deleteCommentControllerProvider.notifier)
            .deleteComment(activityId: _activityId, commentId: 'comment-1'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('delete failed'),
          ),
        ),
      );

      final state = container.read(deleteCommentControllerProvider);
      expect(state.hasError, isTrue);

      await container.read(activityCommentsProvider(_activityId).future);
      expect(commentsRepository.loadCallCount, 1);
    },
  );

  test('deleteComment reports loading while mutation is in flight', () async {
    final commentsRepository = _FakeCommentsRepository()
      ..seedComments([
        _comment(
          commentId: 'comment-1',
          body: 'First',
          createdAt: DateTime.utc(2026, 3, 20, 10),
        ),
      ])
      ..deleteCompleter = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        commentsRepositoryProvider.overrideWithValue(commentsRepository),
      ],
    );
    addTearDown(container.dispose);

    final deleteFuture = container
        .read(deleteCommentControllerProvider.notifier)
        .deleteComment(activityId: _activityId, commentId: 'comment-1');

    await container.pump();
    expect(container.read(deleteCommentControllerProvider).isLoading, isTrue);

    commentsRepository.deleteCompleter!.complete();
    await expectLater(deleteFuture, completes);
  });

  test('deleteComment does not throw when disposed mid-flight', () async {
    final commentsRepository = _FakeCommentsRepository()
      ..seedComments([
        _comment(
          commentId: 'comment-1',
          body: 'First',
          createdAt: DateTime.utc(2026, 3, 20, 10),
        ),
      ])
      ..deleteCompleter = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        commentsRepositoryProvider.overrideWithValue(commentsRepository),
      ],
    );

    final deleteFuture = container
        .read(deleteCommentControllerProvider.notifier)
        .deleteComment(activityId: _activityId, commentId: 'comment-1');

    container.dispose();
    commentsRepository.deleteCompleter!.complete();

    await expectLater(deleteFuture, completes);
  });
}

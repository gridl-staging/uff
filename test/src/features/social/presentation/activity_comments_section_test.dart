import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/social/application/social_comments_providers.dart';
import 'package:uff/src/features/social/data/comments_repository.dart';
import 'package:uff/src/features/social/domain/activity_comment.dart';
import 'package:uff/src/features/social/presentation/activity_comments_section.dart';

import '../../../../src/features/activity_tracking/presentation/activity_detail_screen_test_support.dart';

/// ## Test Scenarios
/// - [positive] Comment section renders empty/content states and supports add/delete flows.
/// - [positive] Pull-to-refresh re-requests the scoped activity comments provider.
/// - [error] Load, refresh, add, and delete failures surface recoverable error UI state.
/// - [edge] Submit/delete actions disable while their async mutations are in flight.
/// - [isolation] Delete actions render only for comments authored by the signed-in user.
const _activityId = 'activity-comments-test-1';
const _viewerUserId = 'viewer-user-id-1';
const _otherUserId = 'other-user-id-2';

class _RecordingCommentsRepository implements CommentsRepository {
  int loadCallCount = 0;
  int addCallCount = 0;
  int deleteCallCount = 0;

  bool throwLoadError = false;
  StateError? addError;
  StateError? deleteError;

  Completer<List<ActivityComment>>? loadCompleter;
  Completer<ActivityComment>? addCompleter;
  Completer<void>? deleteCompleter;

  List<ActivityComment> comments = <ActivityComment>[];

  @override
  Future<List<ActivityComment>> loadActivityComments(String activityId) async {
    loadCallCount++;
    if (throwLoadError) {
      throw StateError('load failed');
    }
    if (loadCompleter case final Completer<List<ActivityComment>> completer) {
      return completer.future;
    }

    return comments
        .where((comment) => comment.activityId == activityId)
        .toList(growable: false);
  }

  @override
  Future<ActivityComment> addComment({
    required String activityId,
    required String body,
  }) async {
    addCallCount++;
    if (addError case final StateError error) {
      throw error;
    }

    if (addCompleter case final Completer<ActivityComment> completer) {
      final inserted = await completer.future;
      comments = <ActivityComment>[...comments, inserted];
      return inserted;
    }

    final inserted = ActivityComment(
      commentId: 'comment-created-$addCallCount',
      activityId: activityId,
      author: const CommentAuthor(
        userId: _viewerUserId,
        displayName: 'Me',
        avatarUrl: null,
      ),
      body: body,
      createdAt: DateTime.utc(2026, 3, 20, 12),
    );
    comments = <ActivityComment>[...comments, inserted];
    return inserted;
  }

  @override
  Future<void> deleteComment(String commentId) async {
    deleteCallCount++;
    if (deleteError case final StateError error) {
      throw error;
    }
    if (deleteCompleter case final Completer<void> completer) {
      await completer.future;
    }

    comments = comments
        .where((comment) => comment.commentId != commentId)
        .toList(growable: false);
  }
}

ActivityComment _comment({
  required String commentId,
  required String authorUserId,
  required String authorName,
  required String body,
}) {
  return ActivityComment(
    commentId: commentId,
    activityId: _activityId,
    author: CommentAuthor(
      userId: authorUserId,
      displayName: authorName,
      avatarUrl: null,
    ),
    body: body,
    createdAt: DateTime.utc(2026, 3, 20, 10),
  );
}

Widget _buildTestWidget({
  required _RecordingCommentsRepository repository,
  AuthState authState = const AuthState.authenticated(
    userId: _viewerUserId,
    email: 'viewer@test.com',
  ),
}) {
  return ProviderScope(
    overrides: [
      commentsRepositoryProvider.overrideWithValue(repository),
      authProvider.overrideWith(() => FakeAuthNotifier(authState)),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: ActivityCommentsSection(activityId: _activityId),
      ),
    ),
  );
}

Future<void> _dragToRefresh(WidgetTester tester) async {
  await tester.drag(
    find.byKey(ActivityCommentsSection.refreshSurfaceKey),
    const Offset(0, 260),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('ActivityCommentsSection', () {
    test('pins static widget key contract', () {
      expect(
        ActivityCommentsSection.sectionShellKey,
        const Key('comments_section_shell'),
      );
      expect(
        ActivityCommentsSection.loadingStateKey,
        const Key('comments_section_loading'),
      );
      expect(
        ActivityCommentsSection.emptyStateKey,
        const Key('comments_section_empty'),
      );
      expect(
        ActivityCommentsSection.errorStateKey,
        const Key('comments_section_error'),
      );
      expect(
        ActivityCommentsSection.commentListKey,
        const Key('comments_section_list'),
      );
      expect(
        ActivityCommentsSection.refreshSurfaceKey,
        const Key('comments_section_refresh'),
      );
      expect(
        ActivityCommentsSection.composerFieldKey,
        const Key('comments_section_composer'),
      );
      expect(
        ActivityCommentsSection.submitActionKey,
        const Key('comments_section_submit'),
      );
      expect(
        ActivityCommentsSection.retryActionKey,
        const Key('comments_section_retry'),
      );
      expect(
        ActivityCommentsSection.commentRowKey('abc'),
        const Key('comments_section_row_abc'),
      );
      expect(
        ActivityCommentsSection.commentDeleteKey('abc'),
        const Key('comments_section_delete_abc'),
      );
    });

    testWidgets('shows loading state while comments are pending', (
      tester,
    ) async {
      final repository = _RecordingCommentsRepository()
        ..loadCompleter = Completer<List<ActivityComment>>();
      addTearDown(() {
        if (!repository.loadCompleter!.isCompleted) {
          repository.loadCompleter!.complete(<ActivityComment>[]);
        }
      });

      await tester.pumpWidget(_buildTestWidget(repository: repository));
      await tester.pump();

      expect(
        find.byKey(ActivityCommentsSection.sectionShellKey),
        findsOneWidget,
      );
      expect(
        find.byKey(ActivityCommentsSection.loadingStateKey),
        findsOneWidget,
      );
    });

    testWidgets('shows empty state and composer when no comments exist', (
      tester,
    ) async {
      final repository = _RecordingCommentsRepository();

      await tester.pumpWidget(_buildTestWidget(repository: repository));
      await tester.pumpAndSettle();

      expect(find.byKey(ActivityCommentsSection.emptyStateKey), findsOneWidget);
      expect(
        find.byKey(ActivityCommentsSection.commentListKey),
        findsOneWidget,
      );
      expect(
        find.byKey(ActivityCommentsSection.composerFieldKey),
        findsOneWidget,
      );
      expect(
        find.byKey(ActivityCommentsSection.submitActionKey),
        findsOneWidget,
      );
    });

    testWidgets('shows error state and retry recovers after failure', (
      tester,
    ) async {
      final repository = _RecordingCommentsRepository()..throwLoadError = true;

      await tester.pumpWidget(_buildTestWidget(repository: repository));
      await tester.pumpAndSettle();

      expect(find.byKey(ActivityCommentsSection.errorStateKey), findsOneWidget);
      expect(
        find.byKey(ActivityCommentsSection.retryActionKey),
        findsOneWidget,
      );
      expect(
        find.byKey(ActivityCommentsSection.refreshSurfaceKey),
        findsOneWidget,
      );

      repository
        ..throwLoadError = false
        ..comments = <ActivityComment>[
          _comment(
            commentId: 'c1',
            authorUserId: _otherUserId,
            authorName: 'Other Runner',
            body: 'Recovered',
          ),
        ];

      await tester.tap(find.byKey(ActivityCommentsSection.retryActionKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ActivityCommentsSection.errorStateKey), findsNothing);
      expect(
        find.byKey(ActivityCommentsSection.commentRowKey('c1')),
        findsOneWidget,
      );
      expect(repository.loadCallCount, greaterThan(1));
    });

    testWidgets(
      'pull-to-refresh re-requests activityCommentsProvider(activityId)',
      (
        tester,
      ) async {
        final repository = _RecordingCommentsRepository()
          ..comments = <ActivityComment>[
            _comment(
              commentId: 'c1',
              authorUserId: _otherUserId,
              authorName: 'Other Runner',
              body: 'Refresh me',
            ),
          ];

        await tester.pumpWidget(_buildTestWidget(repository: repository));
        await tester.pumpAndSettle();

        expect(repository.loadCallCount, 1);
        await _dragToRefresh(tester);
        expect(repository.loadCallCount, greaterThan(1));
      },
    );

    testWidgets('refresh failure keeps error state visible', (tester) async {
      final repository = _RecordingCommentsRepository()..throwLoadError = true;

      await tester.pumpWidget(_buildTestWidget(repository: repository));
      await tester.pumpAndSettle();

      expect(find.byKey(ActivityCommentsSection.errorStateKey), findsOneWidget);
      await _dragToRefresh(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(ActivityCommentsSection.errorStateKey), findsOneWidget);
      expect(repository.loadCallCount, greaterThan(1));
    });

    testWidgets('successful submit clears composer only after add succeeds', (
      tester,
    ) async {
      final repository = _RecordingCommentsRepository();

      await tester.pumpWidget(_buildTestWidget(repository: repository));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ActivityCommentsSection.composerFieldKey),
        'Great work',
      );
      await tester.pump();

      await tester.tap(find.byKey(ActivityCommentsSection.submitActionKey));
      await tester.pumpAndSettle();

      expect(repository.addCallCount, 1);
      final composer = tester.widget<TextField>(
        find.byKey(ActivityCommentsSection.composerFieldKey),
      );
      expect(composer.controller?.text, isEmpty);
      expect(
        find.byKey(ActivityCommentsSection.commentListKey),
        findsOneWidget,
      );
    });

    testWidgets('submit button disables during in-flight add mutation', (
      tester,
    ) async {
      final repository = _RecordingCommentsRepository()
        ..addCompleter = Completer<ActivityComment>();

      await tester.pumpWidget(_buildTestWidget(repository: repository));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ActivityCommentsSection.composerFieldKey),
        'Pending comment',
      );
      await tester.pump();

      await tester.tap(find.byKey(ActivityCommentsSection.submitActionKey));
      await tester.pump();

      final submitButton = tester.widget<IconButton>(
        find.byKey(ActivityCommentsSection.submitActionKey),
      );
      expect(submitButton.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repository.addCompleter!.complete(
        _comment(
          commentId: 'c3',
          authorUserId: _viewerUserId,
          authorName: 'Me',
          body: 'Pending comment',
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets(
      'delete button shows only for authored rows and delete succeeds',
      (
        tester,
      ) async {
        final repository = _RecordingCommentsRepository()
          ..comments = <ActivityComment>[
            _comment(
              commentId: 'c1',
              authorUserId: _viewerUserId,
              authorName: 'Me',
              body: 'My comment',
            ),
            _comment(
              commentId: 'c2',
              authorUserId: _otherUserId,
              authorName: 'Other Runner',
              body: 'Other comment',
            ),
          ];

        await tester.pumpWidget(_buildTestWidget(repository: repository));
        await tester.pumpAndSettle();

        expect(
          find.byKey(ActivityCommentsSection.commentDeleteKey('c1')),
          findsOneWidget,
        );
        expect(
          find.byKey(ActivityCommentsSection.commentDeleteKey('c2')),
          findsNothing,
        );

        await tester.tap(
          find.byKey(ActivityCommentsSection.commentDeleteKey('c1')),
        );
        await tester.pumpAndSettle();

        expect(repository.deleteCallCount, 1);
        expect(
          find.byKey(ActivityCommentsSection.commentRowKey('c1')),
          findsNothing,
        );
        expect(
          find.byKey(ActivityCommentsSection.commentRowKey('c2')),
          findsOneWidget,
        );
      },
    );

    testWidgets('delete buttons disable during in-flight delete mutation', (
      tester,
    ) async {
      final repository = _RecordingCommentsRepository()
        ..comments = <ActivityComment>[
          _comment(
            commentId: 'c1',
            authorUserId: _viewerUserId,
            authorName: 'Me',
            body: 'My comment',
          ),
        ]
        ..deleteCompleter = Completer<void>();

      await tester.pumpWidget(_buildTestWidget(repository: repository));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(ActivityCommentsSection.commentDeleteKey('c1')),
      );
      await tester.pump();

      final deleteButton = tester.widget<IconButton>(
        find.byKey(ActivityCommentsSection.commentDeleteKey('c1')),
      );
      expect(deleteButton.onPressed, isNull);

      repository.deleteCompleter!.complete();
      await tester.pumpAndSettle();
    });
  });
}

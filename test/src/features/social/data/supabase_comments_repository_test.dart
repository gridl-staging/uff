import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/social/data/supabase_comments_repository.dart';

import '../../../test_helpers/supabase_query_test_doubles.dart';

/// ## Test Scenarios
/// - [positive] Loads activity comments oldest-first and maps joined author profile rows.
/// - [positive] Inserts and deletes comments through the expected Supabase payloads.
/// - [negative] Delete fails with a StateError when no comment row is deleted.
/// - [isolation] Repository operations fail without an authenticated session.
/// - [edge] Joined profile rows can be list-or-map shaped and still deserialize.
class MockGoTrueClient extends Mock implements GoTrueClient {}

User _testUser({
  String id = '11111111-1111-1111-1111-111111111111',
  String email = 'test@example.com',
}) {
  return User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00.000Z',
    email: email,
  );
}

Map<String, dynamic> _commentRow({
  required String id,
  required String activityId,
  required String userId,
  required String body,
  required String createdAt,
  dynamic profile,
}) => {
  'id': id,
  'activity_id': activityId,
  'user_id': userId,
  'body': body,
  'created_at': createdAt,
  if (profile != null) 'profiles': profile,
};

Map<String, dynamic> _profileRow({
  required String id,
  String? displayName,
  String? avatarUrl,
}) => {
  'id': id,
  'display_name': displayName,
  'avatar_url': avatarUrl,
};

void main() {
  late MockSupabaseClient mockClient;
  late MockGoTrueClient mockAuth;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockGoTrueClient();
    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(_testUser());
  });

  group('SupabaseCommentsRepository', () {
    test(
      'loadActivityComments reads oldest-first and maps joined profile rows',
      () async {
        final commentsBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _commentRow(
              id: 'comment-1',
              activityId: 'activity-1',
              userId: 'owner-1',
              body: 'First',
              createdAt: '2026-03-20T10:00:00.000Z',
              profile: [
                _profileRow(
                  id: 'owner-1',
                  displayName: 'Owner',
                  avatarUrl: 'https://cdn.example.com/owner.png',
                ),
              ],
            ),
            _commentRow(
              id: 'comment-2',
              activityId: 'activity-1',
              userId: 'viewer-1',
              body: 'Second',
              createdAt: '2026-03-20T10:05:00.000Z',
              profile: _profileRow(
                id: 'viewer-1',
                displayName: 'Viewer',
              ),
            ),
          ],
        );
        when(
          () => mockClient.from('comments'),
        ).thenAnswer((_) => commentsBuilder);

        final repository = SupabaseCommentsRepository(mockClient);
        final comments = await repository.loadActivityComments('activity-1');

        expect(
          commentsBuilder.lastSelectColumns,
          contains('comments_user_id_fkey'),
        );
        expect(commentsBuilder.selectBuilder.lastOrderedColumn, 'created_at');
        expect(commentsBuilder.selectBuilder.lastOrderAscending, isTrue);
        expect(
          commentsBuilder.selectBuilder.eqCalls
              .map((call) => '${call.column}:${call.value}')
              .toList(growable: false),
          ['activity_id:activity-1'],
        );
        expect(comments.map((comment) => comment.commentId), [
          'comment-1',
          'comment-2',
        ]);
        expect(comments.first.author.displayName, 'Owner');
        expect(comments.first.createdAt, DateTime.utc(2026, 3, 20, 10));
      },
    );

    test(
      'addComment inserts expected payload and returns inserted row',
      () async {
        final commentsBuilder = RecordingSupabaseQueryBuilder(
          insertRows: [
            _commentRow(
              id: 'comment-created',
              activityId: 'activity-1',
              userId: '11111111-1111-1111-1111-111111111111',
              body: 'Nice effort',
              createdAt: '2026-03-20T12:00:00.000Z',
              profile: _profileRow(
                id: '11111111-1111-1111-1111-111111111111',
                displayName: 'Viewer',
              ),
            ),
          ],
        );
        when(
          () => mockClient.from('comments'),
        ).thenAnswer((_) => commentsBuilder);

        final repository = SupabaseCommentsRepository(mockClient);
        final inserted = await repository.addComment(
          activityId: 'activity-1',
          body: 'Nice effort',
        );

        expect(commentsBuilder.lastInsertPayload, <String, dynamic>{
          'activity_id': 'activity-1',
          'user_id': '11111111-1111-1111-1111-111111111111',
          'body': 'Nice effort',
        });
        expect(
          commentsBuilder.insertBuilder.lastSelectColumns,
          contains('profiles!comments_user_id_fkey'),
        );
        expect(inserted.commentId, 'comment-created');
        expect(inserted.body, 'Nice effort');
        expect(inserted.author.displayName, 'Viewer');
      },
    );

    test('deleteComment deletes by id', () async {
      final commentsBuilder = RecordingSupabaseQueryBuilder(
        deleteRows: [
          {'id': 'comment-1'},
        ],
      );
      when(
        () => mockClient.from('comments'),
      ).thenAnswer((_) => commentsBuilder);

      final repository = SupabaseCommentsRepository(mockClient);
      await repository.deleteComment('comment-1');

      expect(commentsBuilder.deleteCalled, isTrue);
      expect(commentsBuilder.deleteBuilder.lastEqColumn, 'id');
      expect(commentsBuilder.deleteBuilder.lastEqValue, 'comment-1');
    });

    test('deleteComment throws when no comment row is deleted', () async {
      final commentsBuilder = RecordingSupabaseQueryBuilder();
      when(
        () => mockClient.from('comments'),
      ).thenAnswer((_) => commentsBuilder);

      final repository = SupabaseCommentsRepository(mockClient);

      await expectLater(
        repository.deleteComment('comment-missing'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('delete comment'),
          ),
        ),
      );
    });

    test('all operations require an authenticated user session', () async {
      when(() => mockAuth.currentUser).thenReturn(null);
      final repository = SupabaseCommentsRepository(mockClient);

      await expectLater(
        repository.loadActivityComments('activity-1'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('authenticated user session'),
          ),
        ),
      );
      await expectLater(
        repository.addComment(activityId: 'activity-1', body: 'Body'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Comment operations require an authenticated user session.',
          ),
        ),
      );
      await expectLater(
        repository.deleteComment('comment-1'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Comment operations require an authenticated user session.',
          ),
        ),
      );
    });
  });
}

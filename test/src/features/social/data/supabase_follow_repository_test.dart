import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/social/data/supabase_follow_repository.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';

import '../../../test_helpers/supabase_query_test_doubles.dart';

/// ## Test Scenarios
/// - [positive] Follow mutations (send, accept, reject, unfollow) issue the expected Supabase writes.
/// - [positive] Followers/following/pending/count/header queries map relationship state correctly.
/// - [negative] Accept, reject, and unfollow throw when no relationship row is affected.
/// - [isolation] Every public follow operation requires an authenticated user session.
/// - [edge] Viewed-user profile header returns null when the profile row is missing.
class MockGoTrueClient extends Mock implements GoTrueClient {}

User _testUser({
  String id = 'user-1',
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

Map<String, dynamic> _followRow({
  String id = 'follow-1',
  String followerId = 'user-1',
  String followingId = 'user-2',
  String status = 'pending',
  String createdAt = '2026-03-19T12:00:00.000Z',
  Map<String, dynamic>? profile,
}) => {
  'id': id,
  'follower_id': followerId,
  'following_id': followingId,
  'status': status,
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

Matcher _requiresAuthenticatedSessionError() {
  return isA<StateError>().having(
    (error) => error.message,
    'message',
    'Follow operations require an authenticated user session.',
  );
}

Future<void> _expectRequiresAuthenticatedSession(
  String label,
  Future<Object?> Function() operation,
) async {
  await expectLater(
    operation(),
    throwsA(_requiresAuthenticatedSessionError()),
    reason: 'expected "$label" to require an authenticated session',
  );
}

void main() {
  late MockSupabaseClient mockClient;
  late MockGoTrueClient mockAuth;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockGoTrueClient();
    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(_testUser());
  });

  group('SupabaseFollowRepository mutations', () {
    test(
      'sendFollowRequest inserts into follows with pending status',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder();
        when(() => mockClient.from('follows')).thenAnswer((_) => fakeBuilder);

        final repository = SupabaseFollowRepository(mockClient);
        await repository.sendFollowRequest('user-2');

        expect(fakeBuilder.lastInsertPayload, <String, dynamic>{
          'follower_id': 'user-1',
          'following_id': 'user-2',
          'status': 'pending',
        });
      },
    );

    test(
      'acceptFollowRequest updates status to accepted by follow id',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          updateRows: [_followRow(id: 'follow-7', status: 'accepted')],
        );
        when(() => mockClient.from('follows')).thenAnswer((_) => fakeBuilder);

        final repository = SupabaseFollowRepository(mockClient);
        await repository.acceptFollowRequest('follow-7');

        expect(fakeBuilder.lastUpdatePayload, <String, dynamic>{
          'status': 'accepted',
        });
        expect(fakeBuilder.updateBuilder.lastEqColumn, 'id');
        expect(fakeBuilder.updateBuilder.lastEqValue, 'follow-7');
      },
    );

    test('rejectFollowRequest deletes by follow id', () async {
      final fakeBuilder = RecordingSupabaseQueryBuilder(
        deleteRows: [_followRow(id: 'follow-8')],
      );
      when(() => mockClient.from('follows')).thenAnswer((_) => fakeBuilder);

      final repository = SupabaseFollowRepository(mockClient);
      await repository.rejectFollowRequest('follow-8');

      expect(fakeBuilder.deleteCalled, isTrue);
      expect(fakeBuilder.deleteBuilder.lastEqColumn, 'id');
      expect(fakeBuilder.deleteBuilder.lastEqValue, 'follow-8');
    });

    test(
      'unfollow deletes row using current user and target user ids',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          deleteRows: [
            _followRow(
              id: 'follow-9',
              followingId: 'user-9',
            ),
          ],
        );
        when(() => mockClient.from('follows')).thenAnswer((_) => fakeBuilder);

        final repository = SupabaseFollowRepository(mockClient);
        await repository.unfollow('user-9');

        expect(fakeBuilder.deleteCalled, isTrue);
        expect(fakeBuilder.deleteBuilder.eqCalls, hasLength(2));
        expect(fakeBuilder.deleteBuilder.eqCalls[0].column, 'follower_id');
        expect(fakeBuilder.deleteBuilder.eqCalls[0].value, 'user-1');
        expect(fakeBuilder.deleteBuilder.eqCalls[1].column, 'following_id');
        expect(fakeBuilder.deleteBuilder.eqCalls[1].value, 'user-9');
      },
    );

    test(
      'acceptFollowRequest throws when no relationship row is updated',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder();
        when(() => mockClient.from('follows')).thenAnswer((_) => fakeBuilder);

        final repository = SupabaseFollowRepository(mockClient);

        await expectLater(
          repository.acceptFollowRequest('missing-follow'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('accept follow request'),
            ),
          ),
        );
      },
    );

    test(
      'rejectFollowRequest throws when no relationship row is deleted',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder();
        when(() => mockClient.from('follows')).thenAnswer((_) => fakeBuilder);

        final repository = SupabaseFollowRepository(mockClient);

        await expectLater(
          repository.rejectFollowRequest('missing-follow'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('reject follow request'),
            ),
          ),
        );
      },
    );

    test(
      'unfollow throws when no relationship row is deleted',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder();
        when(() => mockClient.from('follows')).thenAnswer((_) => fakeBuilder);

        final repository = SupabaseFollowRepository(mockClient);

        await expectLater(
          repository.unfollow('missing-target'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('unfollow user'),
            ),
          ),
        );
      },
    );

    test(
      'all follow operations require an authenticated user session',
      () async {
        when(() => mockAuth.currentUser).thenReturn(null);
        final repository = SupabaseFollowRepository(mockClient);
        final operations = <({String label, Future<Object?> Function() run})>[
          (
            label: 'sendFollowRequest',
            run: () => repository.sendFollowRequest('user-2'),
          ),
          (
            label: 'acceptFollowRequest',
            run: () => repository.acceptFollowRequest('follow-1'),
          ),
          (
            label: 'rejectFollowRequest',
            run: () => repository.rejectFollowRequest('follow-1'),
          ),
          (label: 'unfollow', run: () => repository.unfollow('user-2')),
          (label: 'getFollowers', run: repository.getFollowers),
          (label: 'getFollowing', run: repository.getFollowing),
          (label: 'getPendingRequests', run: repository.getPendingRequests),
          (
            label: 'getRelationshipCounts',
            run: repository.getRelationshipCounts,
          ),
          (
            label: 'getViewedUserProfileHeader',
            run: () => repository.getViewedUserProfileHeader('user-2'),
          ),
        ];
        const expectedOperationLabels = <String>[
          'sendFollowRequest',
          'acceptFollowRequest',
          'rejectFollowRequest',
          'unfollow',
          'getFollowers',
          'getFollowing',
          'getPendingRequests',
          'getRelationshipCounts',
          'getViewedUserProfileHeader',
        ];
        expect(
          operations.map((entry) => entry.label).toList(growable: false),
          expectedOperationLabels,
        );

        for (final operation in operations) {
          await _expectRequiresAuthenticatedSession(
            operation.label,
            operation.run,
          );
        }
        verifyNever(() => mockClient.from('follows'));
        verifyNever(() => mockClient.from('profiles'));
      },
    );
  });

  group('SupabaseFollowRepository queries', () {
    test(
      'getFollowers maps joined profile rows and outgoing relationship state',
      () async {
        final followersBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _followRow(
              id: 'incoming-1',
              followerId: 'user-2',
              followingId: 'user-1',
              status: 'accepted',
              profile: _profileRow(
                id: 'user-2',
                displayName: 'Casey Follower',
                avatarUrl: 'https://cdn.example.com/u2.png',
              ),
            ),
          ],
        );
        final outgoingBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _followRow(
              id: 'outgoing-1',
            ),
          ],
        );
        final followsBuilders = <RecordingSupabaseQueryBuilder>[
          followersBuilder,
          outgoingBuilder,
        ];
        when(
          () => mockClient.from('follows'),
        ).thenAnswer((_) => followsBuilders.removeAt(0));

        final repository = SupabaseFollowRepository(mockClient);
        final followers = await repository.getFollowers();

        expect(followers, hasLength(1));
        expect(followers.single.userId, 'user-2');
        expect(followers.single.displayName, 'Casey Follower');
        expect(
          followers.single.relationship.status,
          FollowRelationshipStatus.outgoingPending,
        );
        expect(followers.single.relationship.followId, 'outgoing-1');
        expect(followersBuilder.selectBuilder.lastOrderedColumn, 'created_at');
        expect(followersBuilder.selectBuilder.lastOrderAscending, isFalse);
      },
    );

    test(
      'getFollowing maps accepted outgoing relationship as following',
      () async {
        final followingBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _followRow(
              id: 'outgoing-accepted',
              followingId: 'user-3',
              status: 'accepted',
              profile: _profileRow(
                id: 'user-3',
                displayName: 'Taylor Following',
              ),
            ),
          ],
        );
        when(
          () => mockClient.from('follows'),
        ).thenAnswer((_) => followingBuilder);

        final repository = SupabaseFollowRepository(mockClient);
        final following = await repository.getFollowing();

        expect(following, hasLength(1));
        expect(following.single.userId, 'user-3');
        expect(
          following.single.relationship.status,
          FollowRelationshipStatus.following,
        );
        expect(following.single.relationship.followId, 'outgoing-accepted');
      },
    );

    test(
      'getPendingRequests maps incoming pending relationship and follow id',
      () async {
        final pendingBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _followRow(
              id: 'incoming-pending',
              followerId: 'user-8',
              followingId: 'user-1',
              profile: _profileRow(
                id: 'user-8',
                displayName: 'Pending Requester',
                avatarUrl: 'https://cdn.example.com/u8.png',
              ),
            ),
          ],
        );
        when(
          () => mockClient.from('follows'),
        ).thenAnswer((_) => pendingBuilder);

        final repository = SupabaseFollowRepository(mockClient);
        final requests = await repository.getPendingRequests();

        expect(requests, hasLength(1));
        expect(requests.single.userId, 'user-8');
        expect(
          requests.single.relationship.status,
          FollowRelationshipStatus.incomingPending,
        );
        expect(requests.single.relationship.followId, 'incoming-pending');
      },
    );

    test(
      'getRelationshipCounts returns follower, following, and pending totals',
      () async {
        final followsBuilders = <RecordingSupabaseQueryBuilder>[
          RecordingSupabaseQueryBuilder(selectRows: [_followRow(id: 'f1')]),
          RecordingSupabaseQueryBuilder(
            selectRows: [
              _followRow(id: 'f2'),
              _followRow(id: 'f3'),
            ],
          ),
          RecordingSupabaseQueryBuilder(selectRows: [_followRow(id: 'f4')]),
        ];
        when(
          () => mockClient.from('follows'),
        ).thenAnswer((_) => followsBuilders.removeAt(0));

        final repository = SupabaseFollowRepository(mockClient);
        final counts = await repository.getRelationshipCounts();

        expect(counts.userId, 'user-1');
        expect(counts.followers, 1);
        expect(counts.following, 2);
        expect(counts.pendingRequests, 1);
      },
    );

    test(
      'getViewedUserProfileHeader loads profile, relationship, and follower/following counts',
      () async {
        final profilesBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _profileRow(
              id: 'user-2',
              displayName: 'Viewed Runner',
              avatarUrl: 'https://cdn.example.com/u2.png',
            ),
          ],
        );
        final outgoingRelationshipBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _followRow(
              id: 'outgoing-accepted',
              status: 'accepted',
            ),
          ],
        );
        final incomingRelationshipBuilder = RecordingSupabaseQueryBuilder();
        final followerCountBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _followRow(id: 'f-1'),
            _followRow(id: 'f-2'),
          ],
        );
        final followingCountBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _followRow(id: 'f-3'),
          ],
        );
        final followsBuilders = <RecordingSupabaseQueryBuilder>[
          outgoingRelationshipBuilder,
          incomingRelationshipBuilder,
          followerCountBuilder,
          followingCountBuilder,
        ];
        when(
          () => mockClient.from('profiles'),
        ).thenAnswer((_) => profilesBuilder);
        when(
          () => mockClient.from('follows'),
        ).thenAnswer((_) => followsBuilders.removeAt(0));

        final repository = SupabaseFollowRepository(mockClient);
        final header = await repository.getViewedUserProfileHeader('user-2');

        expect(header?.user.userId, 'user-2');
        expect(header?.user.displayName, 'Viewed Runner');
        expect(header?.followersCount, 2);
        expect(header?.followingCount, 1);
        expect(
          header?.user.relationship.status,
          FollowRelationshipStatus.following,
        );
        expect(header?.user.relationship.followId, 'outgoing-accepted');
      },
    );

    test(
      'getViewedUserProfileHeader returns null when profile is missing',
      () async {
        final profilesBuilder = RecordingSupabaseQueryBuilder();
        when(
          () => mockClient.from('profiles'),
        ).thenAnswer((_) => profilesBuilder);

        final repository = SupabaseFollowRepository(mockClient);
        final header = await repository.getViewedUserProfileHeader(
          'user-missing',
        );

        expect(header, isNull);
        verifyNever(() => mockClient.from('follows'));
      },
    );
  });
}

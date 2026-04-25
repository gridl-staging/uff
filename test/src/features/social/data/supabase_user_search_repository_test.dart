import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/social/data/supabase_user_search_repository.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';

import '../../../test_helpers/supabase_query_test_doubles.dart';

/// ## Test Scenarios
/// - [positive] Search trims input and returns relationship-aware user summaries.
/// - [positive] LIKE metacharacters in query text are escaped before Supabase search.
/// - [negative] Search fails with StateError when no authenticated session exists.
/// - [isolation] Search excludes the current user and resolves incoming-vs-outgoing relationship direction.
/// - [edge] Whitespace-only queries short-circuit with no network access.
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

Map<String, dynamic> _profileRow({
  required String id,
  required String displayName,
  String? avatarUrl,
}) => {
  'id': id,
  'display_name': displayName,
  'avatar_url': avatarUrl,
};

Map<String, dynamic> _followRow({
  required String id,
  required String followerId,
  required String followingId,
  required String status,
}) => {
  'id': id,
  'follower_id': followerId,
  'following_id': followingId,
  'status': status,
  'created_at': '2026-03-19T12:00:00.000Z',
};

List<String> _recordedEqFilters(RecordingSupabaseQueryBuilder builder) {
  return builder.selectBuilder.eqCalls
      .map((call) => '${call.column}:${call.value}')
      .toList(growable: false);
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

  group('SupabaseUserSearchRepository', () {
    test(
      'returns empty list for trimmed-empty query without querying Supabase',
      () async {
        final repository = SupabaseUserSearchRepository(mockClient);

        final results = await repository.searchUsers('   ');

        expect(results, isEmpty);
        verifyNever(() => mockClient.from('profiles'));
        verifyNever(() => mockClient.from('follows'));
      },
    );

    test(
      'searches by trimmed display-name query and maps outgoing follow state',
      () async {
        final profilesBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _profileRow(
              id: 'user-2',
              displayName: 'Runner Ana',
              avatarUrl: 'https://cdn.example.com/u2.png',
            ),
            _profileRow(
              id: 'user-3',
              displayName: 'Runner Ben',
            ),
          ],
        );
        final outgoingBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _followRow(
              id: 'follow-accepted',
              followerId: 'user-1',
              followingId: 'user-2',
              status: 'accepted',
            ),
            _followRow(
              id: 'follow-pending',
              followerId: 'user-1',
              followingId: 'user-3',
              status: 'pending',
            ),
          ],
        );
        final incomingPendingBuilder = RecordingSupabaseQueryBuilder();
        final followsBuilders = <RecordingSupabaseQueryBuilder>[
          outgoingBuilder,
          incomingPendingBuilder,
        ];
        when(
          () => mockClient.from('profiles'),
        ).thenAnswer((_) => profilesBuilder);
        when(
          () => mockClient.from('follows'),
        ).thenAnswer((_) => followsBuilders.removeAt(0));

        final repository = SupabaseUserSearchRepository(mockClient);
        final results = await repository.searchUsers('  runner ');

        expect(results, hasLength(2));
        expect(followsBuilders, isEmpty);
        expect(results[0].userId, 'user-2');
        expect(
          results[0].relationship.status,
          FollowRelationshipStatus.following,
        );
        expect(results[1].userId, 'user-3');
        expect(
          results[1].relationship.status,
          FollowRelationshipStatus.outgoingPending,
        );

        expect(profilesBuilder.selectBuilder.lastIlikeColumn, 'display_name');
        expect(profilesBuilder.selectBuilder.lastIlikePattern, '%runner%');
        expect(profilesBuilder.selectBuilder.lastNeqColumn, 'id');
        expect(profilesBuilder.selectBuilder.lastNeqValue, 'user-1');
        expect(profilesBuilder.selectBuilder.lastOrderedColumn, 'display_name');
        expect(profilesBuilder.selectBuilder.lastOrderAscending, isTrue);
        expect(_recordedEqFilters(outgoingBuilder), ['follower_id:user-1']);
        expect(_recordedEqFilters(incomingPendingBuilder), [
          'following_id:user-1',
          'status:pending',
        ]);
      },
    );

    test(
      'escapes LIKE wildcards so search input is treated literally',
      () async {
        final profilesBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _profileRow(
              id: 'user-2',
              displayName: '100% Ready_Runner',
            ),
          ],
        );
        final outgoingBuilder = RecordingSupabaseQueryBuilder();
        final incomingPendingBuilder = RecordingSupabaseQueryBuilder();
        final followsBuilders = <RecordingSupabaseQueryBuilder>[
          outgoingBuilder,
          incomingPendingBuilder,
        ];
        when(
          () => mockClient.from('profiles'),
        ).thenAnswer((_) => profilesBuilder);
        when(
          () => mockClient.from('follows'),
        ).thenAnswer((_) => followsBuilders.removeAt(0));

        final repository = SupabaseUserSearchRepository(mockClient);
        await repository.searchUsers('100%_Ready');

        expect(profilesBuilder.selectBuilder.lastIlikeColumn, 'display_name');
        expect(
          profilesBuilder.selectBuilder.lastIlikePattern,
          r'%100\%\_Ready%',
        );
        expect(followsBuilders, isEmpty);
      },
    );

    test(
      'maps incoming pending follow request when current user has not followed back',
      () async {
        final profilesBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _profileRow(
              id: 'user-9',
              displayName: 'Incoming Request',
            ),
          ],
        );
        final outgoingBuilder = RecordingSupabaseQueryBuilder();
        final incomingPendingBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _followRow(
              id: 'incoming-pending-1',
              followerId: 'user-9',
              followingId: 'user-1',
              status: 'pending',
            ),
          ],
        );
        final followsBuilders = <RecordingSupabaseQueryBuilder>[
          outgoingBuilder,
          incomingPendingBuilder,
        ];
        when(
          () => mockClient.from('profiles'),
        ).thenAnswer((_) => profilesBuilder);
        when(
          () => mockClient.from('follows'),
        ).thenAnswer((_) => followsBuilders.removeAt(0));

        final repository = SupabaseUserSearchRepository(mockClient);
        final results = await repository.searchUsers('incoming');

        expect(results, hasLength(1));
        expect(followsBuilders, isEmpty);
        expect(results.single.userId, 'user-9');
        expect(
          results.single.relationship.status,
          FollowRelationshipStatus.incomingPending,
        );
        expect(results.single.relationship.followId, 'incoming-pending-1');
        expect(_recordedEqFilters(outgoingBuilder), ['follower_id:user-1']);
        expect(_recordedEqFilters(incomingPendingBuilder), [
          'following_id:user-1',
          'status:pending',
        ]);
      },
    );

    test('searchUsers requires an authenticated user session', () async {
      when(() => mockAuth.currentUser).thenReturn(null);
      final repository = SupabaseUserSearchRepository(mockClient);

      await expectLater(
        repository.searchUsers('runner'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'User search requires an authenticated user session.',
          ),
        ),
      );
      verifyNever(() => mockClient.from('profiles'));
      verifyNever(() => mockClient.from('follows'));
    });
  });
}

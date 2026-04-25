import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/social/data/supabase_kudos_repository.dart';

import '../../../test_helpers/supabase_query_test_doubles.dart';

/// ## Test Scenarios
/// - [positive] Toggle writes insert when viewer has not given kudos.
/// - [positive] Toggle removes viewer row when viewer already gave kudos.
/// - [negative] Removing a missing kudos row throws a StateError.
/// - [isolation] Kudos operations require an authenticated user session.
/// - [edge] Activity kudos summary maps both aggregate count and viewer-specific state.
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

Map<String, dynamic> _kudosRow({
  required String activityId,
  required String userId,
  Map<String, dynamic>? profile,
}) => {
  'activity_id': activityId,
  'user_id': userId,
  if (profile != null) 'profiles': profile,
};

Map<String, dynamic> _profileRow({
  required String id,
  required String displayName,
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

  group('SupabaseKudosRepository', () {
    test('toggleKudos inserts when viewer has not kudosed yet', () async {
      final kudosBuilder = RecordingSupabaseQueryBuilder();
      when(() => mockClient.from('kudos')).thenAnswer((_) => kudosBuilder);

      final repository = SupabaseKudosRepository(mockClient);
      await repository.toggleKudos(
        activityId: 'activity-1',
        viewerHasKudo: false,
      );

      expect(kudosBuilder.lastInsertPayload, <String, dynamic>{
        'activity_id': 'activity-1',
        'user_id': '11111111-1111-1111-1111-111111111111',
      });
    });

    test(
      'toggleKudos deletes viewer row when viewer already kudosed',
      () async {
        final kudosBuilder = RecordingSupabaseQueryBuilder(
          deleteRows: [
            {
              'id': 'kudos-1',
              'activity_id': 'activity-1',
              'user_id': '11111111-1111-1111-1111-111111111111',
            },
          ],
        );
        when(() => mockClient.from('kudos')).thenAnswer((_) => kudosBuilder);

        final repository = SupabaseKudosRepository(mockClient);
        await repository.toggleKudos(
          activityId: 'activity-1',
          viewerHasKudo: true,
        );

        expect(kudosBuilder.deleteCalled, isTrue);
        expect(
          kudosBuilder.deleteBuilder.eqCalls
              .map((call) => '${call.column}:${call.value}')
              .toList(growable: false),
          <String>[
            'activity_id:activity-1',
            'user_id:11111111-1111-1111-1111-111111111111',
          ],
        );
      },
    );

    test('toggleKudos throws when removing a missing kudos row', () async {
      final kudosBuilder = RecordingSupabaseQueryBuilder();
      when(() => mockClient.from('kudos')).thenAnswer((_) => kudosBuilder);

      final repository = SupabaseKudosRepository(mockClient);

      await expectLater(
        repository.toggleKudos(
          activityId: 'activity-1',
          viewerHasKudo: true,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('remove kudos'),
          ),
        ),
      );
    });

    test('loadActivityKudos maps count, viewer state, and user list', () async {
      final kudosBuilder = RecordingSupabaseQueryBuilder(
        selectRows: [
          _kudosRow(
            activityId: 'activity-1',
            userId: '11111111-1111-1111-1111-111111111111',
            profile: _profileRow(
              id: '11111111-1111-1111-1111-111111111111',
              displayName: 'Viewer',
            ),
          ),
          _kudosRow(
            activityId: 'activity-1',
            userId: '22222222-2222-2222-2222-222222222222',
            profile: _profileRow(
              id: '22222222-2222-2222-2222-222222222222',
              displayName: 'Owner',
            ),
          ),
        ],
      );
      when(() => mockClient.from('kudos')).thenAnswer((_) => kudosBuilder);

      final repository = SupabaseKudosRepository(mockClient);
      final summary = await repository.loadActivityKudos('activity-1');

      expect(summary.kudosCount, 2);
      expect(summary.viewerHasKudo, isTrue);
      expect(summary.users, hasLength(2));
      expect(
        summary.users.first.userId,
        '11111111-1111-1111-1111-111111111111',
      );
      expect(summary.users.first.displayName, 'Viewer');
      expect(summary.users[1].userId, '22222222-2222-2222-2222-222222222222');
      expect(summary.users[1].displayName, 'Owner');
    });

    test('all operations require an authenticated user session', () async {
      when(() => mockAuth.currentUser).thenReturn(null);
      final repository = SupabaseKudosRepository(mockClient);

      await expectLater(
        repository.loadActivityKudos('activity-1'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Kudos operations require an authenticated user session.',
          ),
        ),
      );
      await expectLater(
        repository.toggleKudos(
          activityId: 'activity-1',
          viewerHasKudo: false,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Kudos operations require an authenticated user session.',
          ),
        ),
      );
      verifyNever(() => mockClient.from('kudos'));
    });
  });
}

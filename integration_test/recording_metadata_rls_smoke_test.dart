import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_smoke_helpers.dart';

/// ## Test Scenarios
/// - `[positive]` Owner reads the recording-owned activity metadata by id
/// - `[negative]` Stranger reads zero rows for the owner private recording activity
/// - `[isolation]` Owner and stranger clients keep separate auth contexts while querying the same activity id
void main() {
  group('Recording metadata RLS smoke test', skip: skipReason, () {
    late SmokeTestUser owner;
    late SmokeTestUser stranger;

    setUp(() async {
      owner = await createSignedInTestUser(displayName: 'Recording Owner');
      stranger = await createSignedInTestUser(
        displayName: 'Recording Stranger',
      );
    });

    tearDown(() async {
      await cleanupSmokeTestUsers([owner, stranger]);
    });

    test(
      'owner reads private recording activity and stranger sees none',
      () async {
        final activityId = await seedActivityForCurrentUser(
          owner.client,
          visibility: 'private',
          startedAt: DateTime.utc(2026, 4, 17, 8),
          distanceMeters: 4215.7,
          durationSeconds: 1523,
          title: 'Morning Recording Run',
        );

        final ownerRows = await _loadActivityRows(owner.client, activityId);
        expect(ownerRows.length, 1);
        _expectOwnerActivityRow(
          ownerRows.first,
          expected: (
            id: activityId,
            userId: owner.userId,
            sportType: 'run',
            title: 'Morning Recording Run',
            visibility: 'private',
            distanceMeters: 4215.7,
            durationSeconds: 1523,
          ),
        );

        final strangerRows = await _loadActivityRows(
          stranger.client,
          activityId,
        );
        expect(strangerRows, isEmpty);
      },
    );

    test(
      'owner and stranger auth contexts are isolated on the same activity id',
      () async {
        final activityId = await seedActivityForCurrentUser(
          owner.client,
          visibility: 'private',
          startedAt: DateTime.utc(2026, 4, 17, 9),
          distanceMeters: 3100,
          durationSeconds: 1200,
          title: 'Isolation Check Run',
        );

        expect(owner.userId, isNot(stranger.userId));
        expect(owner.client.auth.currentUser!.id, owner.userId);
        expect(stranger.client.auth.currentUser!.id, stranger.userId);

        final ownerRows = await _loadActivityRows(owner.client, activityId);
        expect(ownerRows.length, 1);
        expect(ownerRows.first['user_id'] as String, owner.userId);

        final strangerRows = await _loadActivityRows(
          stranger.client,
          activityId,
        );
        expect(strangerRows, isEmpty);
      },
    );
  });
}

Future<List<Map<String, dynamic>>> _loadActivityRows(
  SupabaseClient client,
  String activityId,
) async {
  final rows = await client
      .from('activities')
      .select(
        'id,user_id,sport_type,title,visibility,distance_meters,duration_seconds',
      )
      .eq('id', activityId);
  return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
}

typedef _ExpectedActivityRow = ({
  String id,
  String userId,
  String sportType,
  String title,
  String visibility,
  double distanceMeters,
  int durationSeconds,
});

void _expectOwnerActivityRow(
  Map<String, dynamic> row, {
  required _ExpectedActivityRow expected,
}) {
  expect(row['id'] as String, expected.id);
  expect(row['user_id'] as String, expected.userId);
  expect(row['sport_type'] as String, expected.sportType);
  expect(row['title'] as String, expected.title);
  expect(row['visibility'] as String, expected.visibility);
  expect((row['distance_meters'] as num).toDouble(), expected.distanceMeters);
  expect((row['duration_seconds'] as num).toInt(), expected.durationSeconds);
}

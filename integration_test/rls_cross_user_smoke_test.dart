import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/utils/uuid.dart';
// 2026-03-18 merge: generateUuidV4 moved out of sync_service.dart.

import 'supabase_smoke_helpers.dart';

// ## Test Scenarios
// - [positive] Owner reads private, followers, and public rows with exact IDs.
// - [negative] Stranger sees only the public row and cannot read private or
//   followers rows.
// - [isolation] Accepted follower sees followers+public rows, while
//   owner/follower/stranger clients remain isolated by auth context.
// - [negative] [isolation] Cross-user insert/update/delete mutation attempts
//   against an owner activity row are denied and preserve owner row state.
void main() {
  group('RLS cross-user check', skip: skipReason, () {
    late SupabaseClient ownerClient;
    late SupabaseClient followerClient;
    late SupabaseClient strangerClient;

    setUp(() async {
      ownerClient = createTestClient();
      followerClient = createTestClient();
      strangerClient = createTestClient();

      await ownerClient.auth.signUp(
        email: generateTestEmail(),
        password: testPassword,
        data: {'display_name': 'Owner User'},
      );
      await followerClient.auth.signUp(
        email: generateTestEmail(),
        password: testPassword,
        data: {'display_name': 'Follower User'},
      );
      await strangerClient.auth.signUp(
        email: generateTestEmail(),
        password: testPassword,
        data: {'display_name': 'Stranger User'},
      );
    });

    tearDown(() async {
      for (final c in [ownerClient, followerClient, strangerClient]) {
        await cleanupSupabaseClient(c);
      }
    });

    test(
      'owner, follower, and stranger reads match private/followers/public matrix',
      () async {
        final ownerUserId = ownerClient.auth.currentUser!.id;
        final privateActivityId = generateUuidV4();
        final followersActivityId = generateUuidV4();
        final publicActivityId = generateUuidV4();
        final startedAtBase = DateTime.utc(2026, 3, 20, 10);

        await ownerClient.from('activities').insert([
          {
            'id': privateActivityId,
            'user_id': ownerUserId,
            'sport_type': 'run',
            'started_at': startedAtBase.toIso8601String(),
            'finished_at': startedAtBase
                .add(const Duration(minutes: 30))
                .toIso8601String(),
            'distance_meters': 4100,
            'duration_seconds': 1800,
            'visibility': 'private',
            'title': 'Matrix Private',
          },
          {
            'id': followersActivityId,
            'user_id': ownerUserId,
            'sport_type': 'run',
            'started_at': startedAtBase
                .add(const Duration(minutes: 45))
                .toIso8601String(),
            'finished_at': startedAtBase
                .add(const Duration(minutes: 75))
                .toIso8601String(),
            'distance_meters': 5200,
            'duration_seconds': 1800,
            'visibility': 'followers',
            'title': 'Matrix Followers',
          },
          {
            'id': publicActivityId,
            'user_id': ownerUserId,
            'sport_type': 'run',
            'started_at': startedAtBase
                .add(const Duration(minutes: 90))
                .toIso8601String(),
            'finished_at': startedAtBase
                .add(const Duration(minutes: 120))
                .toIso8601String(),
            'distance_meters': 6300,
            'duration_seconds': 1800,
            'visibility': 'public',
            'title': 'Matrix Public',
          },
        ]);

        await seedAcceptedFollow(
          requesterClient: followerClient,
          targetClient: ownerClient,
        );

        final ownerRows = await ownerClient
            .from('activities')
            .select('id')
            .eq('user_id', ownerUserId)
            .order('started_at', ascending: true);
        expect(ownerRows, hasLength(3));
        expect(
          ownerRows.map((row) => row['id'] as String).toList(),
          [privateActivityId, followersActivityId, publicActivityId],
          reason: 'Owner should read all seeded rows in started_at order.',
        );

        final followerRows = await followerClient
            .from('activities')
            .select('id')
            .eq('user_id', ownerUserId)
            .order('started_at', ascending: true);
        expect(followerRows, hasLength(2));
        expect(
          followerRows.map((row) => row['id'] as String).toList(),
          [followersActivityId, publicActivityId],
          reason: 'Accepted follower should read followers+public rows only.',
        );

        final strangerRows = await strangerClient
            .from('activities')
            .select('id')
            .eq('user_id', ownerUserId)
            .order('started_at', ascending: true);
        expect(strangerRows, hasLength(1));
        expect(
          strangerRows.map((row) => row['id'] as String).toList(),
          [publicActivityId],
          reason: 'Stranger should read only the public row.',
        );

        final followerPrivateRows = await followerClient
            .from('activities')
            .select('id')
            .eq('id', privateActivityId);
        expect(followerPrivateRows, isEmpty);

        final strangerPrivateRows = await strangerClient
            .from('activities')
            .select('id')
            .eq('id', privateActivityId);
        expect(strangerPrivateRows, isEmpty);

        final strangerFollowersRows = await strangerClient
            .from('activities')
            .select('id')
            .eq('id', followersActivityId);
        expect(strangerFollowersRows, isEmpty);

        final followerPublicRows = await followerClient
            .from('activities')
            .select('id')
            .eq('id', publicActivityId);
        expect(followerPublicRows, hasLength(1));
        expect(followerPublicRows.single['id'] as String, publicActivityId);

        final strangerPublicRows = await strangerClient
            .from('activities')
            .select('id')
            .eq('id', publicActivityId);
        expect(strangerPublicRows, hasLength(1));
        expect(strangerPublicRows.single['id'] as String, publicActivityId);

        final ownerFollowersRows = await ownerClient
            .from('activities')
            .select('id')
            .eq('id', followersActivityId);
        expect(ownerFollowersRows, hasLength(1));
        expect(ownerFollowersRows.single['id'] as String, followersActivityId);
      },
    );
  });

  group('RLS cross-user activity mutation check', skip: skipReason, () {
    late SmokeTestUser owner;
    late SmokeTestUser stranger;

    setUp(() async {
      owner = await createSignedInTestUser(displayName: 'Mutation Owner');
      stranger = await createSignedInTestUser(displayName: 'Mutation Stranger');
    });

    tearDown(() async {
      await cleanupSmokeTestUsers([owner, stranger]);
    });

    test(
      'cross-user activity insert update visibility and delete attempts preserve owner row',
      () async {
        final activityId = generateUuidV4();
        final spoofedActivityId = generateUuidV4();
        final startedAt = DateTime.utc(2026, 4, 14, 7, 15);
        const ownerTitle = 'Owner Seed Title';
        const ownerDescription = 'Owner seeded baseline description.';
        const ownerDistanceMeters = 9876.5;
        const ownerDurationSeconds = 2460;
        const ownerVisibility = 'public';
        const ownerUpdatedTitle = 'Owner Updated Title';

        final ownerFixture = <String, dynamic>{
          'id': activityId,
          'user_id': owner.userId,
          'sport_type': 'run',
          'started_at': startedAt.toIso8601String(),
          'finished_at': startedAt
              .add(const Duration(seconds: ownerDurationSeconds))
              .toIso8601String(),
          'distance_meters': ownerDistanceMeters,
          'duration_seconds': ownerDurationSeconds,
          'visibility': ownerVisibility,
          'title': ownerTitle,
          'description': ownerDescription,
        };

        final insertedOwnerRow = await owner.client
            .from('activities')
            .insert(ownerFixture)
            .select('id')
            .single();
        expect(insertedOwnerRow['id'], activityId);

        Future<Map<String, dynamic>> readOwnerRow() async =>
            (await owner.client
                    .from('activities')
                    .select(
                      'id,user_id,title,description,visibility,distance_meters,duration_seconds',
                    )
                    .eq('id', activityId)
                    .single())
                as Map<String, dynamic>;

        Future<void> expectOwnerRowUnchanged() async {
          final row = await readOwnerRow();
          expect(row['id'], activityId);
          expect(row['user_id'], owner.userId);
          expect(row['title'], ownerTitle);
          expect(row['description'], ownerDescription);
          expect(row['visibility'], ownerVisibility);
          expect(row['duration_seconds'], ownerDurationSeconds);
          expect(
            (row['distance_meters'] as num).toDouble(),
            closeTo(ownerDistanceMeters, 0.0001),
          );
        }

        await expectOwnerRowUnchanged();

        // activities_insert_own should deny spoofed cross-user writes.
        try {
          final spoofedInsertRows = await stranger.client
              .from('activities')
              .insert({
                'id': spoofedActivityId,
                'user_id': owner.userId,
                'sport_type': 'run',
                'started_at': startedAt
                    .add(const Duration(minutes: 45))
                    .toIso8601String(),
                'finished_at': startedAt
                    .add(
                      const Duration(
                        minutes: 45,
                        seconds: ownerDurationSeconds,
                      ),
                    )
                    .toIso8601String(),
                'distance_meters': 1111.1,
                'duration_seconds': 600,
                'visibility': 'public',
                'title': 'Spoofed Cross User Insert',
                'description': 'Stranger attempted spoofed owner row.',
              })
              .select('id,user_id');
          expect(
            spoofedInsertRows,
            isEmpty,
            reason:
                'activities_insert_own should not allow stranger spoofed rows.',
          );
        } on PostgrestException catch (_) {
          // Denial via PostgREST exception is expected for RLS failures.
        } on Object catch (_) {
          // Some environments surface non-PostgrestException wrappers.
        }

        final ownerSpoofedRows = await owner.client
            .from('activities')
            .select('id')
            .eq('id', spoofedActivityId);
        expect(ownerSpoofedRows, isEmpty);
        final strangerSpoofedRows = await stranger.client
            .from('activities')
            .select('id')
            .eq('id', spoofedActivityId);
        expect(strangerSpoofedRows, isEmpty);
        await expectOwnerRowUnchanged();

        // activities_update_own should deny title/description edits by stranger.
        try {
          final crossUserTextUpdateRows = await stranger.client
              .from('activities')
              .update({
                'title': 'Stranger Mutated Title',
                'description': 'Stranger mutated description.',
              })
              .eq('id', activityId)
              .select('id,title,description');
          expect(
            crossUserTextUpdateRows,
            isEmpty,
            reason: 'activities_update_own should deny stranger text updates.',
          );
        } on PostgrestException catch (_) {
          // Denial via PostgREST exception is expected for RLS failures.
        } on Object catch (_) {
          // Some environments surface non-PostgrestException wrappers.
        }
        await expectOwnerRowUnchanged();

        // activities_update_own should deny visibility edits by stranger.
        try {
          final crossUserVisibilityUpdateRows = await stranger.client
              .from('activities')
              .update({'visibility': 'private'})
              .eq('id', activityId)
              .select('id,visibility');
          expect(
            crossUserVisibilityUpdateRows,
            isEmpty,
            reason:
                'activities_update_own should deny stranger visibility updates.',
          );
        } on PostgrestException catch (_) {
          // Denial via PostgREST exception is expected for RLS failures.
        } on Object catch (_) {
          // Some environments surface non-PostgrestException wrappers.
        }
        await expectOwnerRowUnchanged();

        // activities_delete_own should deny cross-user deletes.
        try {
          final crossUserDeleteRows = await stranger.client
              .from('activities')
              .delete()
              .eq('id', activityId)
              .select('id');
          expect(
            crossUserDeleteRows,
            isEmpty,
            reason: 'activities_delete_own should deny stranger deletes.',
          );
        } on PostgrestException catch (_) {
          // Denial via PostgREST exception is expected for RLS failures.
        } on Object catch (_) {
          // Some environments surface non-PostgrestException wrappers.
        }
        await expectOwnerRowUnchanged();

        final ownerSuccessUpdate = await owner.client
            .from('activities')
            .update({'title': ownerUpdatedTitle})
            .eq('id', activityId)
            .select('title')
            .single();
        expect(ownerSuccessUpdate['title'], ownerUpdatedTitle);

        final ownerFinalRow = await readOwnerRow();
        expect(ownerFinalRow['id'], activityId);
        expect(ownerFinalRow['user_id'], owner.userId);
        expect(ownerFinalRow['title'], ownerUpdatedTitle);
        expect(ownerFinalRow['description'], ownerDescription);
        expect(ownerFinalRow['visibility'], ownerVisibility);
        expect(ownerFinalRow['duration_seconds'], ownerDurationSeconds);
        expect(
          (ownerFinalRow['distance_meters'] as num).toDouble(),
          closeTo(ownerDistanceMeters, 0.0001),
        );
      },
    );
  });
}

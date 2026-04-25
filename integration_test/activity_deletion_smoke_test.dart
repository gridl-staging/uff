import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart'
    as tracking_database;
import 'package:uff/src/features/activity_tracking/data/tracking_repository.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

import 'supabase_smoke_helpers.dart';

/// ## Test Scenarios
/// - `[positive]` Deleting a synced activity removes activity and track_points rows
/// - `[negative]` A second user's kudos row does not survive owner deletion
/// - `[isolation]` CASCADE delete removes comments and kudos scoped to activity id
void main() {
  group('Activity deletion CASCADE cleanup smoke test', skip: skipReason, () {
    late SupabaseClient ownerClient;
    late SmokeTestUser kudosUser;
    late tracking_database.TrackingDatabase database;
    late DriftTrackingRepository repository;
    late SupabaseSyncService syncService;
    late Directory tempDir;

    setUp(() async {
      // Owner: signs up directly on the client used for sync + deletion.
      ownerClient = createTestClient();
      await ownerClient.auth.signUp(
        email: generateTestEmail(),
        password: testPassword,
        data: {'display_name': 'Deletion Owner'},
      );

      // Second user: gives kudos to the owner's activity.
      kudosUser = await createSignedInTestUser(
        displayName: 'Deletion Kudos Giver',
      );

      tempDir = Directory.systemTemp.createTempSync('deletion_smoke_');
      database = tracking_database.TrackingDatabase.forTesting(
        NativeDatabase(File('${tempDir.path}/test.sqlite')),
      );
      repository = DriftTrackingRepository(database);

      syncService = SupabaseSyncService(
        repository: repository,
        supabaseClient: ownerClient,
        connectivityChanges: const Stream.empty(),
        checkConnectivity: () async => [ConnectivityResult.wifi],
      );
    });

    tearDown(() async {
      await syncService.dispose();
      await database.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      // Best-effort cleanup of any remaining rows + auth sessions.
      await cleanupSocialRowsForCurrentUser(ownerClient);
      await cleanupSupabaseClient(ownerClient);
      await cleanupSmokeTestUsers([kudosUser]);
    });

    test(
      'deleteRemoteActivity removes activity, track_points, kudos, and comments via CASCADE',
      () async {
        final now = DateTime.utc(2024, 6, 15, 10);

        // -- Arrange: create and sync a local activity with track points. --

        final session = TrackingSessionRecord(
          id: 0,
          status: TrackingSessionStatus.saved,
          createdAt: now,
          updatedAt: now,
          startedAt: now,
          stoppedAt: now.add(const Duration(minutes: 30)),
          sportType: 'run',
          title: 'Deletion Smoke Run',
          distanceMeters: 5000,
          movingTimeSeconds: 1800,
          elevationGainMeters: 50,
        );

        final points = [
          TrackingPoint(
            sessionId: 0,
            timestamp: now,
            coordinate: const GeoCoordinate(
              latitude: 40.7128,
              longitude: -74.006,
            ),
            elevation: 10,
            heartRateBpm: 145,
          ),
          TrackingPoint(
            sessionId: 0,
            timestamp: now.add(const Duration(minutes: 15)),
            coordinate: const GeoCoordinate(
              latitude: 40.7228,
              longitude: -74.016,
            ),
            elevation: 20,
            heartRateBpm: 155,
          ),
        ];

        final sessionId = await repository.saveImportedSession(session, points);
        await syncService.queueForSync(sessionId);

        // Capture the remote activity ID assigned by sync.
        final synced = await repository.loadSession(sessionId);
        expect(synced?.id, sessionId);
        expect(synced?.status, TrackingSessionStatus.saved);
        final remoteId = synced!.remoteId!;
        expect(
          remoteId,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            ),
          ),
          reason: 'remoteId should be a generated activity UUID',
        );

        // Verify activity and track_points exist in Supabase before deletion.
        final activitiesBefore = await ownerClient
            .from('activities')
            .select()
            .eq('id', remoteId);
        expect(activitiesBefore, hasLength(1));
        expect(activitiesBefore.first['id'], remoteId);

        final trackPointsBefore = await ownerClient
            .from('track_points')
            .select()
            .eq('activity_id', remoteId);
        expect(trackPointsBefore, hasLength(2));
        expect(trackPointsBefore.first['activity_id'], remoteId);

        // Make the activity public so the kudos user can interact with it.
        await ownerClient
            .from('activities')
            .update({'visibility': 'public'})
            .eq('id', remoteId);

        // Seed a comment (owner comments on own activity — works per social
        // comments smoke test pattern).
        final ownerId = ownerClient.auth.currentUser!.id;
        await ownerClient.from('comments').insert({
          'activity_id': remoteId,
          'user_id': ownerId,
          'body': 'Owner comment for CASCADE test',
        });

        // Seed a kudo (second user gives kudo to the activity).
        await kudosUser.client.from('kudos').insert({
          'activity_id': remoteId,
          'user_id': kudosUser.userId,
        });

        // Verify dependent rows exist before deletion.
        final commentsBefore = await ownerClient
            .from('comments')
            .select()
            .eq('activity_id', remoteId);
        expect(commentsBefore, hasLength(1), reason: 'comment should exist');

        final kudosBefore = await kudosUser.client
            .from('kudos')
            .select()
            .eq('activity_id', remoteId);
        expect(kudosBefore, hasLength(1), reason: 'kudo should exist');

        // -- Act: delete the remote activity. --
        await syncService.deleteRemoteActivity(remoteId);

        // -- Assert: all related rows are gone via CASCADE. --

        // Activity row is gone.
        final activitiesAfter = await ownerClient
            .from('activities')
            .select()
            .eq('id', remoteId);
        expect(activitiesAfter, isEmpty, reason: 'activity should be deleted');

        // Track_points rows are gone (CASCADE).
        final trackPointsAfter = await ownerClient
            .from('track_points')
            .select()
            .eq('activity_id', remoteId);
        expect(
          trackPointsAfter,
          isEmpty,
          reason: 'track_points should CASCADE delete',
        );

        // Comments rows are gone (CASCADE).
        final commentsAfter = await ownerClient
            .from('comments')
            .select()
            .eq('activity_id', remoteId);
        expect(
          commentsAfter,
          isEmpty,
          reason: 'comments should CASCADE delete',
        );

        // Kudos rows are gone (CASCADE).
        final kudosAfter = await kudosUser.client
            .from('kudos')
            .select()
            .eq('activity_id', remoteId);
        expect(kudosAfter, isEmpty, reason: 'kudos should CASCADE delete');
      },
    );
  });
}

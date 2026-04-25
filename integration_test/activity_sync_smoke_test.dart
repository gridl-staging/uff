import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart'
    as tracking_database;
import 'package:uff/src/features/activity_tracking/data/tracking_repository.dart';
import 'package:uff/src/features/activity_tracking/domain/track_metrics.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/import/application/import_pipeline.dart';

import '../test/src/features/activity_tracking/data/sync_service_test_support.dart'
    as sync_test_support;
import 'supabase_smoke_helpers.dart';

/// ## Test Scenarios
/// - `[positive]` queueForSync uploads a saved local session and points to Supabase
/// - `[positive]` Synced local session stores the same generated remote activity id
/// - `[positive]` Imported activity syncs with visibility exactly 'private'
/// - `[negative]` Stranger cannot read imported private activity after sync
/// - `[error]` Queue retry row stores translated track-point limit failures
void main() {
  group('Activity sync round-trip smoke test', skip: skipReason, () {
    late SupabaseClient client;
    late tracking_database.TrackingDatabase database;
    late DriftTrackingRepository repository;
    late SupabaseSyncService syncService;
    late Directory tempDir;

    setUp(() async {
      client = createTestClient();
      await client.auth.signUp(
        email: generateTestEmail(),
        password: testPassword,
        data: {'display_name': 'Sync Smoke Test'},
      );

      tempDir = Directory.systemTemp.createTempSync('sync_smoke_');
      database = tracking_database.TrackingDatabase.forTesting(
        NativeDatabase(File('${tempDir.path}/test.sqlite')),
      );
      repository = DriftTrackingRepository(database);

      syncService = SupabaseSyncService(
        repository: repository,
        supabaseClient: client,
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
      await cleanupSupabaseClient(client);
    });

    test(
      'local session with points → queueForSync → activity appears in Supabase',
      () async {
        final now = DateTime.utc(2024, 6, 15, 10);

        // Persist a local session + points via the repository.
        final session = TrackingSessionRecord(
          id: 0,
          status: TrackingSessionStatus.saved,
          createdAt: now,
          updatedAt: now,
          startedAt: now,
          stoppedAt: now.add(const Duration(minutes: 30)),
          sportType: 'run',
          title: 'Sync Smoke Run',
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
            timestamp: now.add(const Duration(minutes: 10)),
            coordinate: const GeoCoordinate(
              latitude: 40.7228,
              longitude: -74.016,
            ),
            elevation: 20,
            heartRateBpm: 155,
          ),
          TrackingPoint(
            sessionId: 0,
            timestamp: now.add(const Duration(minutes: 20)),
            coordinate: const GeoCoordinate(
              latitude: 40.7328,
              longitude: -74.026,
            ),
            elevation: 30,
            heartRateBpm: 165,
          ),
        ];

        final sessionId = await repository.saveImportedSession(session, points);
        final expectedRemoteDistanceMeters = calculateTrackDistanceMeters(
          points,
        );

        // Queue for sync — checkConnectivity returns wifi so it will process.
        await syncService.queueForSync(sessionId);

        // The sync should have completed by the time queueForSync returns.
        // Verify remoteId was assigned locally.
        final synced = await repository.loadSession(sessionId);
        expect(synced?.id, sessionId);
        expect(synced?.status, TrackingSessionStatus.saved);
        expect(synced?.title, 'Sync Smoke Run');
        expect(synced?.distanceMeters, 5000);
        expect(synced?.movingTimeSeconds, 1800);
        expect(
          synced?.remoteId,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            ),
          ),
          reason: 'queueForSync should persist a UUID remote id',
        );
        final remoteId = synced!.remoteId!;

        // Verify activity arrived in Supabase.
        final activities = await client
            .from('activities')
            .select()
            .eq('id', remoteId);
        expect(activities, hasLength(1));
        expect(activities.first['id'], remoteId);
        expect(activities.first['sport_type'], 'run');
        expect(activities.first['title'], 'Sync Smoke Run');
        expect(
          activities.first['distance_meters'],
          closeTo(expectedRemoteDistanceMeters, 0.01),
        );
        expect(activities.first['duration_seconds'], 1800);

        // Verify track points arrived.
        final trackPoints = await client
            .from('track_points')
            .select()
            .eq('activity_id', remoteId);
        expect(trackPoints, hasLength(3));
        expect(trackPoints.first['activity_id'], remoteId);
        expect(trackPoints.first['heart_rate'], 145);
      },
    );
  });

  group('Activity sync queue limit translation regression', () {
    late tracking_database.TrackingDatabase database;
    late DriftTrackingRepository repository;
    late SupabaseSyncService syncService;
    late Directory tempDir;
    late sync_test_support.MockSupabaseClient failingClient;
    late List<sync_test_support.RecordedOperation> operations;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('sync_limit_regression_');
      database = tracking_database.TrackingDatabase.forTesting(
        NativeDatabase(File('${tempDir.path}/test.sqlite')),
      );
      repository = DriftTrackingRepository(database);
      failingClient = sync_test_support.MockSupabaseClient();
      operations = <sync_test_support.RecordedOperation>[];
      when(() => failingClient.from('activities')).thenAnswer(
        (_) => sync_test_support.FakeSyncQueryBuilder(
          table: 'activities',
          operations: operations,
        ),
      );
      when(() => failingClient.from('track_points')).thenAnswer(
        (_) => sync_test_support.FakeSyncQueryBuilder(
          table: 'track_points',
          operations: operations,
          insertError: StateError('UFF_LIMIT_TRACK_POINTS_PER_ACTIVITY'),
        ),
      );

      syncService = SupabaseSyncService(
        repository: repository,
        supabaseClient: failingClient,
        connectivityChanges: const Stream.empty(),
        checkConnectivity: () async => [ConnectivityResult.wifi],
        currentUserIdProvider: () => 'user-1',
      );
    });

    tearDown(() async {
      await syncService.dispose();
      await database.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'queue row stores translated track-point limit message for direct sync',
      () async {
        final now = DateTime.utc(2024, 6, 15, 10);
        final session = TrackingSessionRecord(
          id: 0,
          status: TrackingSessionStatus.saved,
          createdAt: now,
          updatedAt: now,
          startedAt: now,
          stoppedAt: now.add(const Duration(minutes: 30)),
          sportType: 'run',
          title: 'Direct Sync Limit',
        );
        final points = [
          TrackingPoint(
            sessionId: 0,
            timestamp: now,
            coordinate: const GeoCoordinate(latitude: 40.7128, longitude: -74),
          ),
          TrackingPoint(
            sessionId: 0,
            timestamp: now.add(const Duration(minutes: 10)),
            coordinate: const GeoCoordinate(
              latitude: 40.7228,
              longitude: -74.01,
            ),
          ),
        ];

        final sessionId = await repository.saveImportedSession(session, points);
        await syncService.queueForSync(sessionId);

        final queueEntry = await repository.loadSyncQueueEntry(sessionId);
        expect(queueEntry?.sessionId, sessionId);
        expect(queueEntry?.status, SyncQueueEntryStatus.queued);
        expect(queueEntry?.retryCount, 1);
        expect(queueEntry?.lastError, syncQueueTrackPointsLimitErrorMessage);
      },
    );
  });

  group('Imported activity sync visibility', skip: skipReason, () {
    late SupabaseClient client;
    late tracking_database.TrackingDatabase database;
    late DriftTrackingRepository repository;
    late SupabaseSyncService syncService;
    late Directory tempDir;

    setUp(() async {
      client = createTestClient();
      await client.auth.signUp(
        email: generateTestEmail(),
        password: testPassword,
        data: {'display_name': 'Import Visibility Smoke'},
      );

      tempDir = Directory.systemTemp.createTempSync('import_vis_smoke_');
      database = tracking_database.TrackingDatabase.forTesting(
        NativeDatabase(File('${tempDir.path}/test.sqlite')),
      );
      repository = DriftTrackingRepository(database);

      syncService = SupabaseSyncService(
        repository: repository,
        supabaseClient: client,
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
      await cleanupSupabaseClient(client);
    });

    test(
      'imported activity syncs with visibility exactly private',
      () async {
        final pipeline = ImportPipeline(
          repository: repository,
          syncService: syncService,
        );

        final gpxBytes = Uint8List.fromList(utf8.encode(_importVisibilityGpx));
        final sessionId = await pipeline.run(gpxBytes, 'vis_smoke.gpx');

        // Verify sync completed — remoteId must be assigned.
        final synced = await repository.loadSession(sessionId);
        expect(
          synced?.remoteId,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            ),
          ),
          reason: 'Import sync should assign a UUID remote id',
        );
        final remoteId = synced!.remoteId!;

        // Verify remote row visibility is exactly 'private'.
        final activities = await client
            .from('activities')
            .select('id, visibility')
            .eq('id', remoteId);
        expect(activities, hasLength(1));
        expect(
          activities.first['visibility'],
          'private',
          reason:
              'Imported activity must arrive in Supabase with visibility '
              'private — not null, not public',
        );
      },
    );
  });

  group('Imported private activity cross-user isolation', skip: skipReason, () {
    late SmokeTestUser owner;
    late SmokeTestUser stranger;

    setUp(() async {
      owner = await createSignedInTestUser(displayName: 'Import Owner');
      stranger = await createSignedInTestUser(displayName: 'Import Stranger');
    });

    tearDown(() async {
      await cleanupSupabaseClient(owner.client);
      await cleanupSupabaseClient(stranger.client);
    });

    test(
      'stranger cannot read imported private activity after sync',
      () async {
        // Owner: import + sync via pipeline with real Drift DB.
        final tempDir = Directory.systemTemp.createTempSync(
          'import_crossuser_smoke_',
        );
        final database = tracking_database.TrackingDatabase.forTesting(
          NativeDatabase(File('${tempDir.path}/test.sqlite')),
        );
        final repository = DriftTrackingRepository(database);
        final syncService = SupabaseSyncService(
          repository: repository,
          supabaseClient: owner.client,
          connectivityChanges: const Stream.empty(),
          checkConnectivity: () async => [ConnectivityResult.wifi],
        );

        try {
          final pipeline = ImportPipeline(
            repository: repository,
            syncService: syncService,
          );

          final gpxBytes = Uint8List.fromList(
            utf8.encode(_importVisibilityGpx),
          );
          final sessionId = await pipeline.run(gpxBytes, 'crossuser.gpx');

          final synced = await repository.loadSession(sessionId);
          final remoteId = synced!.remoteId!;

          // Owner can see the activity.
          final ownerResult = await owner.client
              .from('activities')
              .select('id')
              .eq('id', remoteId);
          expect(ownerResult, hasLength(1));

          // Stranger must NOT see the private activity.
          final strangerResult = await stranger.client
              .from('activities')
              .select('id')
              .eq('id', remoteId);
          expect(
            strangerResult,
            isEmpty,
            reason:
                'RLS must prevent a stranger from reading a private '
                'imported activity',
          );
        } finally {
          await syncService.dispose();
          await database.close();
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      },
    );
  });
}

/// Minimal GPX fixture for import visibility smoke tests.
const _importVisibilityGpx = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="visibility-smoke-test">
  <trk>
    <name>Visibility Smoke Run</name>
    <type>Running</type>
    <trkseg>
      <trkpt lat="40.7128" lon="-74.006">
        <ele>10</ele>
        <time>2024-06-15T10:00:00Z</time>
      </trkpt>
      <trkpt lat="40.7228" lon="-74.016">
        <ele>20</ele>
        <time>2024-06-15T10:10:00Z</time>
      </trkpt>
      <trkpt lat="40.7328" lon="-74.026">
        <ele>30</ele>
        <time>2024-06-15T10:20:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

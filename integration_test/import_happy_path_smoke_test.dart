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
/// - `[positive]` GPX import persists an exact saved session record and 3 points
/// - `[positive]` Import queues a sync row with deterministic session linkage
/// - `[error]` Queue translation stores the activities-per-user limit message
void main() {
  group('Import happy-path smoke test', skip: skipReason, () {
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
        data: {'display_name': 'Import Smoke Test'},
      );

      tempDir = Directory.systemTemp.createTempSync('import_smoke_');
      database = tracking_database.TrackingDatabase.forTesting(
        NativeDatabase(File('${tempDir.path}/test.sqlite')),
      );
      repository = DriftTrackingRepository(database);

      // Offline connectivity — queue entry is created without attempting sync.
      syncService = SupabaseSyncService(
        repository: repository,
        supabaseClient: client,
        connectivityChanges: const Stream.empty(),
        checkConnectivity: () async => [ConnectivityResult.none],
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
      'GPX import → local session + points persisted → sync queue entry created',
      () async {
        final pipeline = ImportPipeline(
          repository: repository,
          syncService: syncService,
        );

        final gpxBytes = Uint8List.fromList(utf8.encode(_smokeGpx));
        final sessionId = await pipeline.run(gpxBytes, 'smoke_ride.gpx');

        // Verify local session persisted.
        final session = await repository.loadSession(sessionId);
        expect(session?.id, sessionId);
        expect(session?.status, TrackingSessionStatus.saved);
        expect(session?.sportType, 'ride');
        // Drift stores epoch millis and reconstructs as local DateTime, so
        // compare in UTC to avoid timezone-dependent failures.
        expect(session?.startedAt?.toUtc(), DateTime.utc(2024, 6, 15, 10));
        expect(session?.stoppedAt?.toUtc(), DateTime.utc(2024, 6, 15, 10, 20));
        expect(session?.movingTimeSeconds, 1200);

        // Verify points persisted.
        final points = await repository.loadPointsForSession(sessionId);
        expect(points, hasLength(3));
        expect(points.first.latitude, closeTo(40.7128, 0.000001));
        expect(points.first.longitude, closeTo(-74.006, 0.000001));
        expect(points[1].latitude, closeTo(40.7228, 0.000001));
        expect(points[1].longitude, closeTo(-74.016, 0.000001));
        expect(points.last.latitude, closeTo(40.7328, 0.000001));
        expect(points.last.longitude, closeTo(-74.026, 0.000001));
        expect(
          session?.distanceMeters,
          closeTo(calculateTrackDistanceMeters(points), 0.000001),
        );

        // Verify sync queue entry was created.
        final queueEntry = await repository.loadSyncQueueEntry(sessionId);
        expect(queueEntry?.sessionId, sessionId);
        expect(queueEntry?.status, SyncQueueEntryStatus.queued);
        expect(queueEntry?.retryCount, 0);
        expect(queueEntry?.lastError, isNull);
      },
    );
  });

  group('Import queue limit translation regression', () {
    late tracking_database.TrackingDatabase database;
    late DriftTrackingRepository repository;
    late SupabaseSyncService syncService;
    late Directory tempDir;
    late sync_test_support.MockSupabaseClient failingClient;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('import_limit_regression_');
      database = tracking_database.TrackingDatabase.forTesting(
        NativeDatabase(File('${tempDir.path}/test.sqlite')),
      );
      repository = DriftTrackingRepository(database);
      failingClient = sync_test_support.MockSupabaseClient();
      when(
        () => failingClient.from('activities'),
      ).thenThrow(StateError('UFF_LIMIT_ACTIVITIES_PER_USER'));

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
      'import-triggered sync queues translated activities-per-user limit message',
      () async {
        final pipeline = ImportPipeline(
          repository: repository,
          syncService: syncService,
        );

        final gpxBytes = Uint8List.fromList(utf8.encode(_smokeGpx));
        final sessionId = await pipeline.run(gpxBytes, 'limit_case.gpx');

        final queueEntry = await repository.loadSyncQueueEntry(sessionId);
        expect(queueEntry?.sessionId, sessionId);
        expect(queueEntry?.status, SyncQueueEntryStatus.queued);
        expect(queueEntry?.retryCount, 1);
        expect(
          queueEntry?.lastError,
          syncQueueActivitiesPerUserLimitErrorMessage,
        );
      },
    );
  });
}

/// Minimal GPX fixture with enough points for the normalizer to succeed.
const _smokeGpx = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="smoke-test">
  <trk>
    <name>Smoke Ride</name>
    <type>Biking</type>
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

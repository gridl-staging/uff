import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fit_tool/fit_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart'
    as tracking_database;
import 'package:uff/src/features/activity_tracking/data/tracking_repository.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/import/application/import_pipeline.dart';

import '../data/fit_test_helpers.dart';

/// ## Test Scenarios
/// - [positive] FIT import persists session fields, point count, and sensor values
/// - [positive] Imported session persists visibility as private before sync retry
/// - [positive] saveImportedSession auto-generates session ID
/// - [positive] Pipeline run keeps save/load/session-points/queue-entry consistent
/// - [negative] Imported session does not persist public visibility
/// - [isolation] Each import produces independent session with own DB identity

class MockSyncService extends Mock implements SyncService {}

class QueueWritingSyncServiceFake implements SyncService {
  QueueWritingSyncServiceFake({
    required DriftTrackingRepository repository,
    required DateTime queuedAt,
  }) : _repository = repository,
       _queuedAt = queuedAt;

  final DriftTrackingRepository _repository;
  final DateTime _queuedAt;
  final List<int> queuedSessionIds = <int>[];
  final List<String> deletedRemoteActivityIds = <String>[];
  final StreamController<SyncQueueStatus> _syncStatusController =
      StreamController<SyncQueueStatus>.broadcast();

  @override
  Stream<SyncQueueStatus> get syncStatus => _syncStatusController.stream;

  @override
  Future<void> queueForSync(int sessionId) async {
    queuedSessionIds.add(sessionId);
    await _repository.upsertSyncQueueEntry(
      sessionId: sessionId,
      status: SyncQueueEntryStatus.queued,
      queuedAt: _queuedAt,
    );
    _syncStatusController.add(SyncQueueStatus.queued);
  }

  @override
  Future<void> processQueue() async {}

  @override
  Future<void> deleteRemoteActivity(String remoteActivityId) async {
    deletedRemoteActivityIds.add(remoteActivityId);
  }

  Future<void> dispose() => _syncStatusController.close();
}

void main() {
  late tracking_database.TrackingDatabase database;
  late DriftTrackingRepository repository;
  late MockSyncService syncService;
  late Directory databaseDirectory;

  setUp(() {
    databaseDirectory = Directory.systemTemp.createTempSync(
      'import_persistence_test_',
    );
    database = tracking_database.TrackingDatabase.forTesting(
      NativeDatabase(File('${databaseDirectory.path}/test.sqlite')),
    );
    repository = DriftTrackingRepository(database);
    syncService = MockSyncService();
  });

  tearDown(() async {
    await database.close();
    if (databaseDirectory.existsSync()) {
      databaseDirectory.deleteSync(recursive: true);
    }
  });

  group('Import persistence round-trip', () {
    test(
      'FIT import persists session fields, point count, and sensor values',
      () async {
        when(() => syncService.queueForSync(any())).thenAnswer((_) async {});

        final fitBytes = buildFitBytes(
          records: [
            FitTestRecord(
              timestampMs: fitBaseTimestamp,
              latitude: testLatitude,
              longitude: testLongitude,
              altitude: 10,
              heartRate: 145,
              cadence: 85,
              power: 230,
            ),
            FitTestRecord(
              timestampMs: fitBaseTimestamp + 600000,
              latitude: testLatitude + 0.005,
              longitude: testLongitude + 0.005,
              altitude: 20,
              heartRate: 155,
              cadence: 90,
              power: 250,
            ),
            FitTestRecord(
              timestampMs: fitBaseTimestamp + 1200000,
              latitude: testLatitude + 0.01,
              longitude: testLongitude + 0.01,
              altitude: 30,
              heartRate: 165,
              cadence: 95,
              power: 270,
            ),
          ],
          sport: Sport.cycling,
        );

        final pipeline = ImportPipeline(
          repository: repository,
          syncService: syncService,
        );

        final sessionId = await pipeline.run(fitBytes, 'ride.fit');

        // Load session back from DB
        final session = await repository.loadSession(sessionId);
        final loadedSession = session!;
        expect(loadedSession.status, TrackingSessionStatus.saved);
        expect(loadedSession.sportType, 'ride');
        expect(
          loadedSession.startedAt?.toUtc(),
          DateTime.fromMillisecondsSinceEpoch(fitBaseTimestamp, isUtc: true),
        );
        expect(
          loadedSession.stoppedAt?.toUtc(),
          DateTime.fromMillisecondsSinceEpoch(
            fitBaseTimestamp + 1200000,
            isUtc: true,
          ),
        );
        expect(loadedSession.distanceMeters, closeTo(1395, 5.0));
        expect(loadedSession.movingTimeSeconds, equals(1200));
        expect(loadedSession.elevationGainMeters, closeTo(20, 0.1));

        // Load points back from DB
        final points = await repository.loadPointsForSession(sessionId);
        expect(points, hasLength(3));

        // Verify sensor fields persisted
        expect(points[0].heartRateBpm, 145);
        expect(points[0].cadenceRpm, 85);
        expect(points[0].powerWatts, 230);
        expect(points[1].heartRateBpm, 155);
        expect(points[2].heartRateBpm, 165);
        expect(points[2].powerWatts, 270);

        // Verify queueForSync was called
        verify(() => syncService.queueForSync(sessionId)).called(1);
      },
    );

    test('saveImportedSession auto-generates session ID', () async {
      final session = TrackingSessionRecord(
        id: 0,
        status: TrackingSessionStatus.saved,
        createdAt: DateTime(2024, 1, 1, 12),
        updatedAt: DateTime(2024, 1, 1, 12),
        startedAt: DateTime(2024, 1, 1, 12),
        stoppedAt: DateTime(2024, 1, 1, 13),
        sportType: 'run',
        title: 'Test Run',
        distanceMeters: 5000,
        movingTimeSeconds: 1800,
        elevationGainMeters: 50,
      );

      final points = [
        TrackingPoint(
          sessionId: 0,
          timestamp: DateTime(2024, 1, 1, 12),
          coordinate: const GeoCoordinate(latitude: 40, longitude: -74),
          heartRateBpm: 140,
          cadenceRpm: 80,
          powerWatts: 200,
        ),
        TrackingPoint(
          sessionId: 0,
          timestamp: DateTime(2024, 1, 1, 12, 10),
          coordinate: const GeoCoordinate(latitude: 40.01, longitude: -74.01),
          heartRateBpm: 150,
        ),
      ];

      final sessionId = await repository.saveImportedSession(session, points);

      // First auto-ID from empty Drift DB is always 1
      expect(sessionId, equals(1));

      // Session should be loadable
      final loaded = await repository.loadSession(sessionId);
      expect(loaded!.sportType, 'run');
      expect(loaded.title, 'Test Run');
      expect(loaded.distanceMeters, 5000);

      // Points should reference the real session ID
      final loadedPoints = await repository.loadPointsForSession(sessionId);
      expect(loadedPoints, hasLength(2));
      expect(loadedPoints[0].sessionId, sessionId);
      expect(loadedPoints[0].heartRateBpm, 140);
      expect(loadedPoints[1].heartRateBpm, 150);
      expect(loadedPoints[1].cadenceRpm, isNull);
    });

    test(
      'pipeline run keeps save/load/session-points/queue-entry consistent',
      () async {
        final queueQueuedAt = DateTime(2026, 3, 19, 12);
        final syncService = QueueWritingSyncServiceFake(
          repository: repository,
          queuedAt: queueQueuedAt,
        );
        addTearDown(syncService.dispose);
        final pipeline = ImportPipeline(
          repository: repository,
          syncService: syncService,
        );
        final records = buildDeterministicFitRecords(pointCount: 220);
        final fitBytes = buildFitBytes(records: records, sport: Sport.running);

        final sessionId = await pipeline.run(fitBytes, 'contract.fit');

        expect(syncService.queuedSessionIds, [sessionId]);

        final session = await repository.loadSession(sessionId);
        final points = await repository.loadPointsForSession(sessionId);
        final queueEntry = await repository.loadSyncQueueEntry(sessionId);

        expect(session!.id, sessionId);
        expect(session.status, TrackingSessionStatus.saved);
        expect(session.sportType, 'run');
        expect(session.startedAt, points.first.timestamp);
        expect(session.stoppedAt, points.last.timestamp);

        expect(points, hasLength(records.length));
        expect(points.every((point) => point.sessionId == sessionId), isTrue);
        expect(points.first.heartRateBpm, records.first.heartRate);
        expect(points.last.powerWatts, records.last.power);

        expect(queueEntry!.sessionId, sessionId);
        expect(queueEntry.status, SyncQueueEntryStatus.queued);
        expect(queueEntry.retryCount, 0);
        expect(queueEntry.lastError, isNull);
        expect(queueEntry.queuedAt, queueQueuedAt);
      },
    );

    test(
      'imported session persists visibility as private in local DB',
      () async {
        when(() => syncService.queueForSync(any())).thenAnswer((_) async {});

        final fitBytes = buildFitBytes(
          records: [
            FitTestRecord(
              timestampMs: fitBaseTimestamp,
              latitude: testLatitude,
              longitude: testLongitude,
              altitude: 10,
            ),
            FitTestRecord(
              timestampMs: fitBaseTimestamp + 600000,
              latitude: testLatitude + 0.01,
              longitude: testLongitude + 0.01,
              altitude: 20,
            ),
          ],
          sport: Sport.running,
        );

        final pipeline = ImportPipeline(
          repository: repository,
          syncService: syncService,
        );

        final sessionId = await pipeline.run(fitBytes, 'visibility.fit');

        // Reload from Drift DB — this is the row that sync retry logic reads.
        // If visibility is null here, buildActivityPayload() will omit the
        // key and the backend defaults to 'public'. That is the P0 leak.
        final session = await repository.loadSession(sessionId);
        expect(
          session!.visibility,
          privateTrackingSessionVisibility,
          reason:
              'Imported session must persist private visibility in local DB '
              'before any sync retry can read it',
        );
      },
    );
  });
}

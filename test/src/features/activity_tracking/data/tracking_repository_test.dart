import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart'
    as tracking_database;
import 'package:uff/src/features/activity_tracking/data/tracking_repository.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

void main() {
  late tracking_database.TrackingDatabase database;
  late DriftTrackingRepository repository;
  late Directory databaseDirectory;
  late String databaseFilePath;

  void openRepository() {
    database = tracking_database.TrackingDatabase.forTesting(
      NativeDatabase(File(databaseFilePath)),
    );
    repository = DriftTrackingRepository(database);
  }

  setUp(() {
    databaseDirectory = Directory.systemTemp.createTempSync(
      'tracking_repository_test_',
    );
    databaseFilePath =
        '${databaseDirectory.path}/activity_tracking_test.sqlite';
    openRepository();
  });

  tearDown(() async {
    await database.close();
    if (databaseDirectory.existsSync()) {
      databaseDirectory.deleteSync(recursive: true);
    }
  });

  group('DriftTrackingRepository', () {
    test('creates a session and appends points', () async {
      final session = await repository.createSession();
      await repository.appendPointBatch(
        [
          TrackingPoint(
            sessionId: session.id,
            timestamp: DateTime(2025, 01, 01, 12),
            coordinate: const GeoCoordinate(latitude: 40, longitude: -70),
          ),
          TrackingPoint(
            sessionId: session.id,
            timestamp: DateTime(2025, 01, 01, 12, 0, 10),
            coordinate: const GeoCoordinate(latitude: 40.1, longitude: -70.1),
            speed: 4.5,
          ),
        ],
      );

      final points = await repository.loadPointsForSession(session.id);
      expect(points, hasLength(2));
      expect(points.first.latitude, 40.0);
      expect(points.last.speed, 4.5);
    });

    test('loads a session by id', () async {
      final session = await repository.createSession();
      final loadedSession = await repository.loadSession(session.id);
      expect(loadedSession?.id, session.id);
      expect(loadedSession?.status, session.status);
    });

    test('loads saved sessions sorted by startedAt desc', () async {
      final olderSession = await repository.createSession();
      final newerSession = await repository.createSession();
      final newerStart = DateTime(2025, 01, 01, 12, 0, 2);
      final olderStart = DateTime(2025, 01, 01, 12, 0, 1);

      await repository.updateSessionStatus(
        newerSession.id,
        TrackingSessionStatus.recording,
        newerStart,
      );
      await repository.updateSessionStatus(
        olderSession.id,
        TrackingSessionStatus.recording,
        olderStart,
      );
      await repository.finalizeSession(newerSession.id);
      await repository.finalizeSession(olderSession.id);
      await repository.saveSession(
        olderSession.copyWith(
          status: TrackingSessionStatus.saved,
          updates: const TrackingSessionRecordUpdates(
            description: 'older summary',
          ),
        ),
      );

      final savedSessions = await repository.loadSavedSessions();
      expect(savedSessions, hasLength(2));
      expect(savedSessions.first.id, newerSession.id);
      expect(savedSessions.last.id, olderSession.id);
    });

    test('persists session summary metrics with saveSession', () async {
      final session = await repository.createSession();
      final updatedSession = session.copyWith(
        status: TrackingSessionStatus.saved,
        updates: const TrackingSessionRecordUpdates(
          distanceMeters: 1234.5,
          movingTimeSeconds: 456,
          elevationGainMeters: 78.9,
        ),
      );

      await repository.saveSession(updatedSession);
      final loadedSession = await repository.loadSession(session.id);

      expect(loadedSession?.distanceMeters, 1234.5);
      expect(loadedSession?.movingTimeSeconds, 456);
      expect(loadedSession?.elevationGainMeters, 78.9);
    });

    test('persists lifecycle state and restores active session', () async {
      final session = await repository.createSession();
      final startedAt = DateTime(2025, 01, 01, 12);
      await repository.updateSessionStatus(
        session.id,
        TrackingSessionStatus.recording,
        startedAt,
      );

      final active = await repository.loadActiveSession();
      expect(active?.id, session.id);
      expect(active?.status, TrackingSessionStatus.recording);
    });

    test('restores recording session after database restart', () async {
      final session = await repository.createSession();
      final startedAt = DateTime(2025, 01, 01, 12, 1);
      await repository.updateSessionStatus(
        session.id,
        TrackingSessionStatus.recording,
        startedAt,
      );
      await repository.appendPointBatch(
        [
          TrackingPoint(
            sessionId: session.id,
            timestamp: DateTime(2025, 01, 01, 12, 1, 1),
            coordinate: const GeoCoordinate(latitude: 1, longitude: 1),
          ),
        ],
      );

      await database.close();
      openRepository();
      final restartedRepository = DriftTrackingRepository(database);
      final recovered = await restartedRepository.loadActiveSession();
      final recoveredPoints = await restartedRepository.loadPointsForSession(
        session.id,
      );

      expect(recovered?.id, session.id);
      expect(recovered?.status, TrackingSessionStatus.recording);
      expect(recoveredPoints, hasLength(1));
    });

    test('keeps stopped status as stopped on recovery', () async {
      final session = await repository.createSession();
      await repository.updateSessionStatus(
        session.id,
        TrackingSessionStatus.stopped,
        DateTime(2025, 01, 01, 12, 2),
      );

      await database.close();
      openRepository();
      final restartedRepository = DriftTrackingRepository(database);
      final recovered = await restartedRepository.loadActiveSession();

      expect(recovered?.status, TrackingSessionStatus.stopped);
    });

    test('round-trips remoteId for tracking sessions', () async {
      final session = await repository.createSession();
      const remoteId = '2aeec2b5-bd67-45ab-aaca-a722156f1845';

      await repository.updateSessionRemoteId(session.id, remoteId);
      final updated = await repository.loadSession(session.id);

      expect(updated?.remoteId, remoteId);
    });

    test('preserves remoteId when saving a synced session', () async {
      final session = await repository.createSession();
      const remoteId = 'c6bc4f5c-7ba5-4a7d-bc6e-a45918ea793e';

      await repository.updateSessionRemoteId(session.id, remoteId);
      final syncedSession = await repository.loadSession(session.id);

      await repository.saveSession(
        syncedSession!.copyWith(
          status: TrackingSessionStatus.saved,
          updates: const TrackingSessionRecordUpdates(
            title: 'Morning run',
            distanceMeters: 3210,
          ),
        ),
      );

      final reloaded = await repository.loadSession(session.id);

      expect(reloaded?.remoteId, remoteId);
      expect(reloaded?.title, 'Morning run');
      expect(reloaded?.distanceMeters, 3210);
    });

    test('preserves remoteId when loading saved sessions', () async {
      final session = await repository.createSession();
      const remoteId = 'a5c27e70-50bb-4867-a38c-bce4665f3158';
      final startedAt = DateTime(2025, 1, 1, 12, 3);

      await repository.updateSessionStatus(
        session.id,
        TrackingSessionStatus.recording,
        startedAt,
      );
      await repository.finalizeSession(session.id);
      await repository.updateSessionRemoteId(session.id, remoteId);

      final savedSessions = await repository.loadSavedSessions();

      expect(savedSessions, hasLength(1));
      expect(savedSessions.single.remoteId, remoteId);
    });

    test('preserves remoteId when restoring the active session', () async {
      final session = await repository.createSession();
      const remoteId = '6b849a85-a88e-4326-abf2-563d48a28919';

      await repository.updateSessionStatus(
        session.id,
        TrackingSessionStatus.recording,
        DateTime(2025, 1, 1, 12, 4),
      );
      await repository.updateSessionRemoteId(session.id, remoteId);

      await database.close();
      openRepository();
      final restartedRepository = DriftTrackingRepository(database);
      final recovered = await restartedRepository.loadActiveSession();

      expect(recovered?.id, session.id);
      expect(recovered?.remoteId, remoteId);
    });

    test('inserts and queries pending sync queue rows', () async {
      final session = await repository.createSession();
      final queuedAt = DateTime(2026, 3, 1, 12);

      await repository.upsertSyncQueueEntry(
        sessionId: session.id,
        status: SyncQueueEntryStatus.queued,
        queuedAt: queuedAt,
      );

      final pendingEntries = await repository.loadPendingSyncQueueEntries();
      expect(pendingEntries, hasLength(1));
      expect(pendingEntries.single.sessionId, session.id);
      expect(pendingEntries.single.status, SyncQueueEntryStatus.queued);
      expect(pendingEntries.single.retryCount, 0);
      expect(pendingEntries.single.lastError, isNull);
      expect(pendingEntries.single.queuedAt, queuedAt);
    });

    group('deleteActivity', () {
      test('removes session and its tracking points', () async {
        final session = await repository.createSession();
        await repository.appendPointBatch([
          TrackingPoint(
            sessionId: session.id,
            timestamp: DateTime(2026, 3, 22, 10),
            coordinate: const GeoCoordinate(latitude: 40, longitude: -70),
          ),
          TrackingPoint(
            sessionId: session.id,
            timestamp: DateTime(2026, 3, 22, 10, 0, 5),
            coordinate: const GeoCoordinate(latitude: 40.1, longitude: -70.1),
          ),
        ]);

        await repository.deleteActivity(session.id);

        final loadedSession = await repository.loadSession(session.id);
        final loadedPoints = await repository.loadPointsForSession(session.id);
        expect(loadedSession, isNull);
        expect(loadedPoints, isEmpty);
      });

      test('removes matching sync queue entry', () async {
        final session = await repository.createSession();
        await repository.upsertSyncQueueEntry(
          sessionId: session.id,
          status: SyncQueueEntryStatus.queued,
          queuedAt: DateTime(2026, 3, 22, 10),
        );

        await repository.deleteActivity(session.id);

        final entry = await repository.loadSyncQueueEntry(session.id);
        expect(entry, isNull);
      });

      test('no-ops for a missing session id', () async {
        // Should complete without throwing for a non-existent session.
        await repository.deleteActivity(999);
      });

      test('leaves unrelated sessions and queue rows untouched', () async {
        final targetSession = await repository.createSession();
        final unrelatedSession = await repository.createSession();
        await repository.appendPointBatch([
          TrackingPoint(
            sessionId: targetSession.id,
            timestamp: DateTime(2026, 3, 22, 10),
            coordinate: const GeoCoordinate(latitude: 40, longitude: -70),
          ),
          TrackingPoint(
            sessionId: unrelatedSession.id,
            timestamp: DateTime(2026, 3, 22, 10),
            coordinate: const GeoCoordinate(latitude: 41, longitude: -71),
          ),
        ]);
        await repository.upsertSyncQueueEntry(
          sessionId: targetSession.id,
          status: SyncQueueEntryStatus.queued,
          queuedAt: DateTime(2026, 3, 22, 10),
        );
        await repository.upsertSyncQueueEntry(
          sessionId: unrelatedSession.id,
          status: SyncQueueEntryStatus.queued,
          queuedAt: DateTime(2026, 3, 22, 10),
        );

        await repository.deleteActivity(targetSession.id);

        // Unrelated session and its data must survive.
        final survivingSession = await repository.loadSession(
          unrelatedSession.id,
        );
        final survivingPoints = await repository.loadPointsForSession(
          unrelatedSession.id,
        );
        final survivingEntry = await repository.loadSyncQueueEntry(
          unrelatedSession.id,
        );

        expect(survivingSession?.status, TrackingSessionStatus.idle);
        expect(survivingPoints, hasLength(1));
        expect(survivingEntry?.status, SyncQueueEntryStatus.queued);

        // Target session must be fully gone.
        final deletedSession = await repository.loadSession(targetSession.id);
        final deletedPoints = await repository.loadPointsForSession(
          targetSession.id,
        );
        final deletedEntry = await repository.loadSyncQueueEntry(
          targetSession.id,
        );

        expect(deletedSession, isNull);
        expect(deletedPoints, isEmpty);
        expect(deletedEntry, isNull);
      });
    });

    test('updates sync queue status with retry count and error', () async {
      final session = await repository.createSession();

      await repository.upsertSyncQueueEntry(
        sessionId: session.id,
        status: SyncQueueEntryStatus.queued,
        queuedAt: DateTime(2026, 3, 1, 12),
      );

      await repository.updateSyncQueueEntryStatus(
        sessionId: session.id,
        status: SyncQueueEntryStatus.processing,
        retryCount: 2,
        lastError: 'network timeout',
      );

      final entry = await repository.loadSyncQueueEntry(session.id);
      expect(entry?.status, SyncQueueEntryStatus.processing);
      expect(entry?.retryCount, 2);
      expect(entry?.lastError, 'network timeout');
    });
  });
}

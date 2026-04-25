import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart'
    as db;
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_repository.dart';

/// NOTE(stuart): Document DriftTrackingRepository.
class DriftTrackingRepository implements TrackingRepository {
  DriftTrackingRepository(this.database);

  final db.TrackingDatabase database;

  @override
  Future<TrackingSessionRecord> createSession() async {
    final now = DateTime.now();
    final insertedId = await database.insertSession(
      db.TrackingSessionsCompanion(
        status: const Value(TrackingSessionStatus.idle),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    final session = await database.loadSession(insertedId);
    if (session == null) {
      throw StateError('Failed to load newly created tracking session.');
    }
    return session;
  }

  @override
  Future<TrackingSessionRecord?> loadSession(int sessionId) {
    return database.loadSession(sessionId);
  }

  @override
  Future<void> appendPointBatch(List<TrackingPoint> points) async {
    if (points.isEmpty) {
      return;
    }

    await database.batch((batch) {
      for (final point in points) {
        batch.insert(
          database.trackingPoints,
          _buildPointCompanion(point.sessionId, point),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  @override
  Future<List<TrackingPoint>> loadPointsForSession(int sessionId) async {
    return database.loadPoints(sessionId);
  }

  @override
  Future<List<TrackingSessionRecord>> loadSavedSessions() {
    return database.loadSavedSessions();
  }

  @override
  Future<void> saveSession(TrackingSessionRecord session) {
    return database.saveSession(session.toCompanion());
  }

  @override
  Future<TrackingSessionRecord?> loadActiveSession() {
    return database.loadActiveSession();
  }

  @override
  Future<void> updateSessionStatus(
    int sessionId,
    TrackingSessionStatus status,
    DateTime at,
  ) async {
    final existingSession = await database.loadSession(sessionId);
    if (existingSession == null) {
      return;
    }

    await (database.update(
      database.trackingSessions,
    )..where((table) => table.id.equals(sessionId))).write(
      db.TrackingSessionsCompanion(
        status: Value(status),
        updatedAt: Value(at),
        startedAt:
            status == TrackingSessionStatus.recording &&
                existingSession.startedAt == null
            ? Value(at)
            : const Value.absent(),
        stoppedAt: status == TrackingSessionStatus.stopped
            ? Value(at)
            : const Value.absent(),
      ),
    );
  }

  @override
  Future<void> finalizeSession(int sessionId) async {
    await (database.update(
      database.trackingSessions,
    )..where((table) => table.id.equals(sessionId))).write(
      db.TrackingSessionsCompanion(
        status: const Value(TrackingSessionStatus.saved),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> discardSession(int sessionId) async {
    await (database.update(
      database.trackingSessions,
    )..where((table) => table.id.equals(sessionId))).write(
      db.TrackingSessionsCompanion(
        status: const Value(TrackingSessionStatus.discarded),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> updateSessionRemoteId(int sessionId, String remoteId) async {
    await database.customStatement(
      '''
      UPDATE tracking_sessions
      SET remote_id = ?2
      WHERE id = ?1
      ''',
      [sessionId, remoteId],
    );
  }

  @override
  Future<void> deleteActivity(int sessionId) {
    // Delete order: sync_queue → tracking_points → tracking_sessions.
    // FK enforcement is off by default in SQLite, so we manually delete
    // children before the parent to keep the database consistent.
    return database.transaction(() async {
      await database.customStatement(
        'DELETE FROM sync_queue WHERE session_id = ?1',
        [sessionId],
      );
      await database.customStatement(
        'DELETE FROM tracking_points WHERE session_id = ?1',
        [sessionId],
      );
      await database.customStatement(
        'DELETE FROM tracking_sessions WHERE id = ?1',
        [sessionId],
      );
    });
  }

  @override
  Future<int> saveImportedSession(
    TrackingSessionRecord session,
    List<TrackingPoint> points,
  ) async {
    return database.transaction(() async {
      final sessionId = await database.insertSession(
        db.TrackingSessionsCompanion(
          status: Value(session.status),
          createdAt: Value(session.createdAt),
          updatedAt: Value(session.updatedAt),
          startedAt: Value(session.startedAt),
          stoppedAt: Value(session.stoppedAt),
          title: Value(session.title),
          description: Value(session.description),
          distanceMeters: Value(session.distanceMeters),
          movingTimeSeconds: Value(session.movingTimeSeconds),
          elevationGainMeters: Value(session.elevationGainMeters),
          sportType: Value(session.sportType),
          visibility: Value(session.visibility),
        ),
      );

      if (points.isNotEmpty) {
        await database.batch((batch) {
          for (final point in points) {
            batch.insert(
              database.trackingPoints,
              _buildPointCompanion(sessionId, point),
            );
          }
        });
      }

      return sessionId;
    });
  }

  @override
  Future<void> upsertSyncQueueEntry({
    required int sessionId,
    required SyncQueueEntryStatus status,
    required DateTime queuedAt,
    int retryCount = 0,
    String? lastError,
  }) {
    return database.upsertSyncQueueEntryRaw(
      sessionId: sessionId,
      status: status,
      queuedAt: queuedAt,
      retryCount: retryCount,
      lastError: lastError,
    );
  }

  @override
  Future<List<SyncQueueEntry>> loadPendingSyncQueueEntries() {
    return database.loadSyncQueueEntriesByStatus(SyncQueueEntryStatus.queued);
  }

  @override
  Future<SyncQueueEntry?> loadSyncQueueEntry(int sessionId) {
    return database.loadSyncQueueEntry(sessionId);
  }

  @override
  Future<void> updateSyncQueueEntryStatus({
    required int sessionId,
    required SyncQueueEntryStatus status,
    int? retryCount,
    String? lastError,
  }) async {
    await database.updateSyncQueueEntryStatusRaw(
      sessionId: sessionId,
      status: status,
      retryCount: retryCount,
      lastError: lastError,
    );
  }

  static db.TrackingPointsCompanion _buildPointCompanion(
    int sessionId,
    TrackingPoint point,
  ) {
    return db.TrackingPointsCompanion.insert(
      sessionId: sessionId,
      timestamp: point.timestamp,
      latitude: point.latitude,
      longitude: point.longitude,
      elevation: Value(point.elevation),
      accuracy: Value(point.accuracy),
      speed: Value(point.speed),
      heartRateBpm: Value(point.heartRateBpm),
      cadenceRpm: Value(point.cadenceRpm),
      powerWatts: Value(point.powerWatts),
    );
  }
}

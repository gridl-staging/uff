import 'dart:async';

import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

abstract interface class TrackingRepository {
  FutureOr<TrackingSessionRecord?> loadSession(int sessionId);

  FutureOr<TrackingSessionRecord?> loadActiveSession();

  FutureOr<TrackingSessionRecord> createSession();

  Future<void> appendPointBatch(List<TrackingPoint> points);

  Future<List<TrackingSessionRecord>> loadSavedSessions();

  Future<List<TrackingPoint>> loadPointsForSession(int sessionId);

  Future<void> saveSession(TrackingSessionRecord session);

  Future<void> updateSessionStatus(
    int sessionId,
    TrackingSessionStatus status,
    DateTime at,
  );

  Future<void> finalizeSession(int sessionId);

  Future<void> discardSession(int sessionId);

  /// Deletes all local data for the given session: sync queue entry, tracking
  /// points, and the session row itself. No-ops if the session does not exist.
  Future<void> deleteActivity(int sessionId);

  Future<void> updateSessionRemoteId(int sessionId, String remoteId);

  /// Persists an imported session and its points in a single transaction.
  ///
  /// The [session] ID is ignored — the database auto-generates a new one.
  /// Point session IDs are replaced with the real auto-generated session ID.
  /// Returns the auto-generated session ID.
  Future<int> saveImportedSession(
    TrackingSessionRecord session,
    List<TrackingPoint> points,
  );

  Future<void> upsertSyncQueueEntry({
    required int sessionId,
    required SyncQueueEntryStatus status,
    required DateTime queuedAt,
    int retryCount,
    String? lastError,
  });

  Future<List<SyncQueueEntry>> loadPendingSyncQueueEntries();

  Future<SyncQueueEntry?> loadSyncQueueEntry(int sessionId);

  Future<void> updateSyncQueueEntryStatus({
    required int sessionId,
    required SyncQueueEntryStatus status,
    int? retryCount,
    String? lastError,
  });
}

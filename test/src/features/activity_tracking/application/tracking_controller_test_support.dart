import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_controller.dart';
import 'package:uff/src/features/activity_tracking/data/permission_service.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_engine.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_repository.dart';

/// NOTE(stuart): Document FakeTrackingEngine.
class FakeTrackingEngine implements TrackingEngine {
  FakeTrackingEngine({
    this.throwOnStart = false,
    this.recoveredSamples = const [],
    this.sampleDuringRecovery,
  });

  bool disposeCalled = false;
  bool startCalled = false;
  bool pauseCalled = false;
  bool resumeCalled = false;
  bool stopCalled = false;
  int? startedSessionId;
  int? activeSessionId;
  int? recoveredSessionId;
  final bool throwOnStart;
  final List<TrackingPoint> recoveredSamples;
  final TrackingPoint? sampleDuringRecovery;
  bool _didEmitRecoverySample = false;

  final _sampleController = StreamController<TrackingPoint>.broadcast();
  final _statusController = StreamController<TrackingEngineStatus>.broadcast();

  @override
  Stream<TrackingPoint> get sampleStream => _sampleController.stream;

  @override
  Stream<TrackingEngineStatus> get statusStream => _statusController.stream;

  void emitSample(TrackingPoint point) {
    final currentSessionId = activeSessionId;
    if (currentSessionId == null || point.sessionId != currentSessionId) {
      return;
    }
    _sampleController.add(point);
  }

  @override
  Future<void> start(int sessionId) async {
    if (throwOnStart) {
      throw StateError('Failed to start tracking engine.');
    }

    startCalled = true;
    startedSessionId = sessionId;
    activeSessionId = sessionId;
    _statusController.add(TrackingEngineStatus.running);
  }

  @override
  Future<void> pause() async {
    pauseCalled = true;
    _statusController.add(TrackingEngineStatus.paused);
  }

  @override
  Future<void> resume() async {
    resumeCalled = true;
    _statusController.add(TrackingEngineStatus.running);
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
    activeSessionId = null;
    _statusController.add(TrackingEngineStatus.stopped);
  }

  @override
  Future<List<TrackingPoint>> recoverPersistedSamples(
    int sessionId, {
    DateTime? afterTimestamp,
  }) async {
    recoveredSessionId = sessionId;
    activeSessionId = sessionId;
    final liveRecoverySample = sampleDuringRecovery;
    if (!_didEmitRecoverySample && liveRecoverySample != null) {
      _didEmitRecoverySample = true;
      emitSample(liveRecoverySample);
    }
    if (afterTimestamp == null) {
      return recoveredSamples;
    }

    return recoveredSamples
        .where((point) => point.timestamp.isAfter(afterTimestamp))
        .toList(growable: false);
  }

  @override
  Future<void> dispose() async {
    disposeCalled = true;
    await _sampleController.close();
    await _statusController.close();
  }
}

/// NOTE(stuart): Document FakePermissionService.
class FakePermissionService extends TrackingPermissionService {
  FakePermissionService(this.decisions);

  final List<TrackingPermissionDecision> decisions;
  int _index = 0;

  @override
  Future<TrackingPermissionDecision> ensureForegroundPermission() async {
    return _nextDecision();
  }

  @override
  Future<TrackingPermissionDecision> ensureBackgroundPermission() async {
    return _nextDecision();
  }

  Future<TrackingPermissionDecision> _nextDecision() async {
    if (_index >= decisions.length) {
      return TrackingPermissionDecision.denied;
    }

    final decision = decisions[_index];
    _index += 1;
    return decision;
  }
}

/// NOTE(stuart): Document FakeTrackingRepository.
class FakeTrackingRepository implements TrackingRepository {
  FakeTrackingRepository({
    this.throwOnDiscard = false,
    this.throwOnFinalize = false,
    this.throwOnAppendPoints = false,
    this.throwOnLoadPoints = false,
    this.throwOnSaveSession = false,
  });

  int _nextSessionId = 1;
  TrackingSessionRecord? activeSession;
  final Map<int, TrackingSessionRecord> sessionsById = {};
  final List<TrackingPoint> points = [];
  final bool throwOnDiscard;
  final bool throwOnFinalize;
  final bool throwOnAppendPoints;
  final bool throwOnLoadPoints;
  final bool throwOnSaveSession;
  final List<TrackingSessionStatus> sessionStatusUpdates = [];
  int saveSessionCallCount = 0;
  final List<TrackingSessionRecord> savedSessions = [];
  final Map<int, SyncQueueEntry> syncQueueBySessionId = {};

  @override
  Future<TrackingSessionRecord> createSession() async {
    final now = DateTime(2025, 1, 1, 12);
    final session = TrackingSessionRecord(
      id: _nextSessionId,
      status: TrackingSessionStatus.idle,
      createdAt: now,
      updatedAt: now,
    );
    _nextSessionId += 1;
    activeSession = session;
    sessionsById[session.id] = session;
    return session;
  }

  @override
  FutureOr<TrackingSessionRecord?> loadSession(int sessionId) {
    return sessionsById[sessionId];
  }

  @override
  Future<List<TrackingSessionRecord>> loadSavedSessions() async {
    return sessionsById.values
        .where((session) => session.status == TrackingSessionStatus.saved)
        .toList(growable: false)
      ..sort(
        (left, right) {
          final leftSort = left.startedAt ?? left.updatedAt;
          final rightSort = right.startedAt ?? right.updatedAt;
          return rightSort.compareTo(leftSort);
        },
      );
  }

  @override
  Future<void> appendPointBatch(List<TrackingPoint> pointsToAppend) async {
    if (throwOnAppendPoints) {
      throw StateError('Failed to persist tracking points.');
    }
    points.addAll(pointsToAppend);
  }

  @override
  Future<void> saveSession(TrackingSessionRecord session) async {
    if (throwOnSaveSession) {
      throw StateError('Failed to persist session summary.');
    }

    saveSessionCallCount += 1;
    sessionsById[session.id] = session;
    activeSession = session;
    if (session.status == TrackingSessionStatus.saved) {
      savedSessions.add(session);
    }
  }

  @override
  Future<List<TrackingPoint>> loadPointsForSession(int sessionId) async {
    if (throwOnLoadPoints) {
      throw StateError('Failed to load points for session.');
    }
    return points.where((point) => point.sessionId == sessionId).toList();
  }

  @override
  Future<TrackingSessionRecord?> loadActiveSession() async {
    return activeSession;
  }

  @override
  Future<void> updateSessionStatus(
    int sessionId,
    TrackingSessionStatus status,
    DateTime at,
  ) async {
    sessionStatusUpdates.add(status);
    final currentSession = sessionsById[sessionId];
    if (currentSession == null) {
      return;
    }

    final updatedSession = currentSession.copyWith(
      status: status,
      updatedAt: at,
      startedAt:
          status == TrackingSessionStatus.recording &&
              currentSession.startedAt == null
          ? at
          : currentSession.startedAt,
      stoppedAt: status == TrackingSessionStatus.stopped
          ? at
          : currentSession.stoppedAt,
    );
    sessionsById[sessionId] = updatedSession;
    if (activeSession?.id == sessionId) {
      activeSession = updatedSession;
    }
  }

  @override
  Future<void> finalizeSession(int sessionId) async {
    if (throwOnFinalize) {
      throw StateError('Failed to finalize tracking session.');
    }

    final currentSession = sessionsById[sessionId];
    if (currentSession == null) {
      return;
    }

    activeSession = currentSession.copyWith(
      status: TrackingSessionStatus.saved,
      updatedAt: DateTime.now(),
    );
    sessionsById[sessionId] = activeSession!;
  }

  @override
  Future<void> discardSession(int sessionId) async {
    if (throwOnDiscard) {
      throw StateError('Failed to discard draft session.');
    }

    final currentSession = sessionsById[sessionId];
    if (currentSession == null) {
      return;
    }

    activeSession = currentSession.copyWith(
      status: TrackingSessionStatus.discarded,
      updatedAt: DateTime.now(),
    );
    sessionsById[sessionId] = activeSession!;
  }

  @override
  Future<void> updateSessionRemoteId(int sessionId, String remoteId) async {
    final session = sessionsById[sessionId];
    if (session == null) {
      return;
    }

    final updatedSession = session.copyWith(remoteId: remoteId);
    sessionsById[sessionId] = updatedSession;
    if (activeSession?.id == sessionId) {
      activeSession = updatedSession;
    }
  }

  @override
  Future<void> upsertSyncQueueEntry({
    required int sessionId,
    required SyncQueueEntryStatus status,
    required DateTime queuedAt,
    int retryCount = 0,
    String? lastError,
  }) async {
    syncQueueBySessionId[sessionId] = SyncQueueEntry(
      sessionId: sessionId,
      status: status,
      retryCount: retryCount,
      lastError: lastError,
      queuedAt: queuedAt,
    );
  }

  @override
  Future<List<SyncQueueEntry>> loadPendingSyncQueueEntries() async {
    return syncQueueBySessionId.values
        .where((entry) => entry.status == SyncQueueEntryStatus.queued)
        .toList(growable: false);
  }

  @override
  Future<SyncQueueEntry?> loadSyncQueueEntry(int sessionId) async {
    return syncQueueBySessionId[sessionId];
  }

  @override
  Future<void> updateSyncQueueEntryStatus({
    required int sessionId,
    required SyncQueueEntryStatus status,
    int? retryCount,
    String? lastError,
  }) async {
    final existingEntry = syncQueueBySessionId[sessionId];
    if (existingEntry == null) {
      return;
    }
    syncQueueBySessionId[sessionId] = SyncQueueEntry(
      sessionId: existingEntry.sessionId,
      status: status,
      retryCount: retryCount ?? existingEntry.retryCount,
      lastError: lastError,
      queuedAt: existingEntry.queuedAt,
    );
  }

  @override
  Future<void> deleteActivity(int sessionId) async {
    syncQueueBySessionId.remove(sessionId);
    points.removeWhere((p) => p.sessionId == sessionId);
    final removed = sessionsById.remove(sessionId);
    if (activeSession?.id == sessionId) {
      activeSession = null;
    }
    if (removed != null) {
      savedSessions.removeWhere((s) => s.id == sessionId);
    }
  }

  @override
  Future<int> saveImportedSession(
    TrackingSessionRecord session,
    List<TrackingPoint> points,
  ) async {
    throw UnsupportedError('saveImportedSession not used in this test');
  }
}

/// NOTE(stuart): Document FakeSyncService.
class FakeSyncService implements SyncService {
  FakeSyncService({Stream<SyncQueueStatus>? syncStatusStream})
    : _syncStatusStream = syncStatusStream;

  final List<int> queuedSessionIds = [];
  final List<String> deletedRemoteActivityIds = [];
  final Stream<SyncQueueStatus>? _syncStatusStream;

  @override
  Stream<SyncQueueStatus> get syncStatus =>
      _syncStatusStream ?? const Stream.empty();

  @override
  Future<void> queueForSync(int sessionId) async {
    queuedSessionIds.add(sessionId);
  }

  @override
  Future<void> processQueue() async {}

  @override
  Future<void> deleteRemoteActivity(String remoteActivityId) async {
    deletedRemoteActivityIds.add(remoteActivityId);
  }
}

ProviderContainer createControllerContainer({
  required FakeTrackingRepository repository,
  required FakeTrackingEngine engine,
  required FakePermissionService permissions,
  FakeSyncService? syncService,
}) {
  return ProviderContainer(
    overrides: [
      trackingRepositoryProvider.overrideWithValue(repository),
      trackingEngineProvider.overrideWithValue(engine),
      trackingPermissionServiceProvider.overrideWithValue(permissions),
      syncServiceProvider.overrideWithValue(syncService ?? FakeSyncService()),
    ],
  );
}

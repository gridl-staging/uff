part of 'tracking_controller.dart';

/// TODO: Document SessionRestorer.
class SessionRestorer {
  SessionRestorer({
    required TrackingRepository repository,
    required TrackingEngine trackingEngine,
    DateTime Function() clock = DateTime.now,
  }) : _repository = repository,
       _trackingEngine = trackingEngine,
       _clock = clock;

  final TrackingRepository _repository;
  final TrackingEngine _trackingEngine;
  final DateTime Function() _clock;

  Future<void> restore({
    required RecordingErrorState currentErrorState,
    required void Function(RecordingControllerState) applyState,
  }) async {
    final session = await _repository.loadActiveSession();
    if (session == null) {
      return;
    }

    final persistedPoints = await _repository.loadPointsForSession(session.id);
    applyState(
      _applyRestoredSessionState(
        session: session,
        points: persistedPoints,
        now: _clock(),
        currentErrorState: currentErrorState,
      ),
    );

    final recoveredPoints = await _loadRecoveredPoints(
      session,
      persistedPoints: persistedPoints,
    );
    if (recoveredPoints == null) {
      return;
    }

    final mergedPoints = await _repository.loadPointsForSession(session.id);
    applyState(
      _applyRestoredSessionState(
        session: session,
        points: mergedPoints,
        now: _clock(),
        currentErrorState: currentErrorState,
      ),
    );
  }

  RecordingControllerState _applyRestoredSessionState({
    required tracking_domain.TrackingSessionRecord session,
    required List<tracking_domain.TrackingPoint> points,
    required DateTime now,
    required RecordingErrorState currentErrorState,
  }) {
    final isRecording =
        session.status == tracking_domain.TrackingSessionStatus.recording;
    final initialDuration = isRecording && session.startedAt != null
        ? now.difference(session.startedAt!)
        : Duration.zero;
    final lastFixTimestamp = points.isNotEmpty ? points.last.timestamp : null;
    // Restored quality is recomputed from persisted points, not persisted separately.
    final lastAccuracy = points.isNotEmpty ? points.last.accuracy : null;

    return RecordingControllerState(
      status: session.status,
      session: session,
      points: points,
      timeline: RecordingTimeline(
        activeDuration: isRecording ? initialDuration : Duration.zero,
        segmentStartTimestamp: isRecording ? now : null,
        lastFixTimestamp: lastFixTimestamp,
        lastAccuracy: lastAccuracy,
      ),
      errorState: currentErrorState,
    );
  }

  Future<List<tracking_domain.TrackingPoint>?> _loadRecoveredPoints(
    tracking_domain.TrackingSessionRecord session, {
    required List<tracking_domain.TrackingPoint> persistedPoints,
  }) async {
    if (!_shouldRecoverPersistedEngineSamples(session.status)) {
      return null;
    }

    final lastTimestamp = persistedPoints.isEmpty
        ? session.startedAt ?? session.createdAt
        : persistedPoints.last.timestamp;
    final recoveredPoints = await _trackingEngine.recoverPersistedSamples(
      session.id,
      afterTimestamp: lastTimestamp,
    );
    if (recoveredPoints.isEmpty) {
      return null;
    }

    await _repository.appendPointBatch(recoveredPoints);
    return recoveredPoints;
  }

  bool _shouldRecoverPersistedEngineSamples(
    tracking_domain.TrackingSessionStatus status,
  ) {
    return status == tracking_domain.TrackingSessionStatus.recording ||
        status == tracking_domain.TrackingSessionStatus.paused;
  }
}

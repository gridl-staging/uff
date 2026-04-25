import 'dart:async';

import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_engine.dart';

/// A [TrackingEngine] that replays a pre-recorded list of [TrackingPoint]s
/// at a configurable interval. Designed for deterministic E2E and unit testing
/// without real GPS hardware.
class ReplayTrackingEngine implements TrackingEngine {
  ReplayTrackingEngine({
    required List<TrackingPoint> points,
    this.emissionInterval = const Duration(milliseconds: 200),
  }) : _points = points;

  final List<TrackingPoint> _points;
  final Duration emissionInterval;

  final _sampleController = StreamController<TrackingPoint>.broadcast();
  final _statusController = StreamController<TrackingEngineStatus>.broadcast();

  bool _isDisposed = false;
  int? _activeSessionId;
  int _nextPointIndex = 0;
  Timer? _emissionTimer;
  final List<TrackingPoint> _emittedPoints = [];

  @override
  Stream<TrackingPoint> get sampleStream => _sampleController.stream;

  @override
  Stream<TrackingEngineStatus> get statusStream => _statusController.stream;

  @override
  Future<void> start(int sessionId) async {
    _ensureNotDisposed('start');
    _activeSessionId = sessionId;
    _nextPointIndex = 0;
    _emittedPoints.clear();
    _statusController.add(TrackingEngineStatus.running);
    _startEmissionTimer();
  }

  @override
  Future<void> pause() async {
    _ensureNotDisposed('pause');
    _cancelEmissionTimer();
    _statusController.add(TrackingEngineStatus.paused);
  }

  @override
  Future<void> resume() async {
    _ensureNotDisposed('resume');
    if (_activeSessionId == null) {
      return;
    }
    _statusController.add(TrackingEngineStatus.running);
    _startEmissionTimer();
  }

  @override
  Future<void> stop() async {
    _ensureNotDisposed('stop');
    _cancelEmissionTimer();
    _activeSessionId = null;
    _statusController.add(TrackingEngineStatus.stopped);
  }

  @override
  Future<List<TrackingPoint>> recoverPersistedSamples(
    int sessionId, {
    DateTime? afterTimestamp,
  }) async {
    _ensureNotDisposed('recoverPersistedSamples');
    final matchingSessionPoints = _emittedPoints.where(
      (point) => point.sessionId == sessionId,
    );
    if (afterTimestamp == null) {
      return List.unmodifiable(matchingSessionPoints.toList(growable: false));
    }
    return matchingSessionPoints
        .where((point) => point.timestamp.isAfter(afterTimestamp))
        .toList(growable: false);
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _cancelEmissionTimer();
    await Future.wait([
      _sampleController.close(),
      _statusController.close(),
    ]);
  }

  void _startEmissionTimer() {
    _cancelEmissionTimer();
    if (_activeSessionId == null || _nextPointIndex >= _points.length) {
      return;
    }
    _emissionTimer = Timer.periodic(emissionInterval, (_) {
      _emitNextPoint();
    });
  }

  void _cancelEmissionTimer() {
    _emissionTimer?.cancel();
    _emissionTimer = null;
  }

  void _emitNextPoint() {
    if (_nextPointIndex >= _points.length) {
      _cancelEmissionTimer();
      return;
    }

    final sessionId = _activeSessionId;
    if (sessionId == null) return;

    final source = _points[_nextPointIndex];
    final point = TrackingPoint(
      sessionId: sessionId,
      timestamp: source.timestamp,
      coordinate: source.coordinate,
      elevation: source.elevation,
      accuracy: source.accuracy,
      speed: source.speed,
      heartRateBpm: source.heartRateBpm,
      cadenceRpm: source.cadenceRpm,
      powerWatts: source.powerWatts,
    );

    _sampleController.add(point);
    _emittedPoints.add(point);
    _nextPointIndex++;
  }

  void _ensureNotDisposed(String operation) {
    if (_isDisposed) {
      throw StateError('Cannot $operation replay engine after disposal.');
    }
  }
}

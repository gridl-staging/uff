import 'dart:async';

import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

enum TrackingEngineStatus {
  idle,
  running,
  paused,
  stopped,
  error,
}

/// NOTE(stuart): Document TrackingEngine.
abstract interface class TrackingEngine {
  Stream<TrackingPoint> get sampleStream;

  Stream<TrackingEngineStatus> get statusStream;

  Future<void> start(int sessionId);

  Future<void> pause();

  Future<void> resume();

  Future<void> stop();

  Future<List<TrackingPoint>> recoverPersistedSamples(
    int sessionId, {
    DateTime? afterTimestamp,
  });

  Future<void> dispose();
}

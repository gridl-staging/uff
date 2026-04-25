import 'dart:async';

import 'package:meta/meta.dart';
import 'package:tracelet/tracelet.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_engine.dart';

// TODO(stuart): Document TraceletSamplingGate.
/// TODO: Document TraceletSamplingGate.
@immutable
class TraceletSamplingGate {
  const TraceletSamplingGate({
    this.minLocationInterval = defaultMinLocationInterval,
    this.minDistanceMeters = defaultMinDistanceMeters,
  });

  // Favor denser live route updates while avoiding 1 Hz battery churn.
  static const Duration defaultMinLocationInterval = Duration(seconds: 2);
  static const double defaultMinDistanceMeters = 5;

  final Duration minLocationInterval;
  final double minDistanceMeters;

  GeoConfig toGeoConfig() {
    return GeoConfig(
      distanceFilter: minDistanceMeters,
      locationUpdateInterval: minLocationInterval.inMilliseconds,
    );
  }
}

@visibleForTesting
TrackingPoint? normalizeTraceletLocation(
  Location location, {
  required int sessionId,
}) {
  final timestamp = _parseTraceletTimestamp(location.timestamp);
  if (timestamp == null) {
    return null;
  }

  return TrackingPoint(
    sessionId: sessionId,
    timestamp: timestamp,
    coordinate: GeoCoordinate(
      latitude: location.coords.latitude,
      longitude: location.coords.longitude,
    ),
    elevation: location.coords.altitude,
    accuracy: location.coords.accuracy,
    speed: location.coords.speed,
  );
}

@visibleForTesting
List<TrackingPoint> normalizeTraceletLocations({
  required List<Location> locations,
  required int sessionId,
  DateTime? afterTimestamp,
}) {
  return locations
      .map(
        (location) => normalizeTraceletLocation(location, sessionId: sessionId),
      )
      .whereType<TrackingPoint>()
      .where((point) {
        if (afterTimestamp == null) {
          return true;
        }
        return point.timestamp.isAfter(afterTimestamp);
      })
      .toList(growable: false);
}

DateTime? _parseTraceletTimestamp(String rawTimestamp) {
  final parsedTimestamp = DateTime.tryParse(rawTimestamp);
  if (parsedTimestamp == null) {
    return null;
  }
  return parsedTimestamp.toUtc();
}

// TODO(uff): Document TraceletTrackingEngine.
/// TODO: Document TraceletTrackingEngine.
class TraceletTrackingEngine implements TrackingEngine {
  TraceletTrackingEngine({
    Duration minLocationInterval =
        TraceletSamplingGate.defaultMinLocationInterval,
    double minDistanceMeters = TraceletSamplingGate.defaultMinDistanceMeters,
  }) : _samplingGate = TraceletSamplingGate(
         minLocationInterval: minLocationInterval,
         minDistanceMeters: minDistanceMeters,
       );

  final TraceletSamplingGate _samplingGate;

  final _sampleController = StreamController<TrackingPoint>.broadcast();
  final _statusController = StreamController<TrackingEngineStatus>.broadcast();

  StreamSubscription<Location>? _locationSubscription;
  bool _isDisposed = false;
  bool _isReady = false;
  int? _activeSessionId;

  @override
  Stream<TrackingPoint> get sampleStream => _sampleController.stream;

  @override
  Stream<TrackingEngineStatus> get statusStream => _statusController.stream;

  @visibleForTesting
  TraceletSamplingGate get samplingGate => _samplingGate;

  @override
  Future<void> start(int sessionId) async {
    _throwIfDisposed('start');

    _activeSessionId = sessionId;
    await _ensureReady();

    await Tracelet.start();
    _statusController.add(TrackingEngineStatus.running);
  }

  @override
  Future<void> pause() async {
    _throwIfDisposed('pause');

    await Tracelet.changePace(false);
    _statusController.add(TrackingEngineStatus.paused);
  }

  @override
  Future<void> resume() async {
    _throwIfDisposed('resume');

    await Tracelet.changePace(true);
    _statusController.add(TrackingEngineStatus.running);
  }

  @override
  Future<void> stop() async {
    _throwIfDisposed('stop');

    await Tracelet.stop();
    _activeSessionId = null;
    _statusController.add(TrackingEngineStatus.stopped);
  }

  @override
  Future<List<TrackingPoint>> recoverPersistedSamples(
    int sessionId, {
    DateTime? afterTimestamp,
  }) async {
    _throwIfDisposed('recover persisted samples');

    _activeSessionId = sessionId;
    await _ensureReady();
    final persistedLocations = await Tracelet.getLocations(
      SQLQuery(
        start: afterTimestamp?.toUtc(),
      ),
    );

    return normalizeTraceletLocations(
      locations: persistedLocations,
      sessionId: sessionId,
      afterTimestamp: afterTimestamp,
    );
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;

    await _locationSubscription?.cancel();

    if (_isReady) {
      await Tracelet.stop();
    }

    await Future.wait([
      _sampleController.close(),
      _statusController.close(),
    ]);
  }

  Future<void> _initializeTracelet() async {
    await Tracelet.ready(
      Config(
        geo: _samplingGate.toGeoConfig(),
        app: const AppConfig(
          stopOnTerminate: false,
          foregroundService: ForegroundServiceConfig(
            notificationTitle: 'Uff tracking active',
            notificationText: 'Recording continues while your phone is locked.',
          ),
        ),
      ),
    );

    _statusController.add(TrackingEngineStatus.idle);
  }

  Future<void> _ensureReady() async {
    if (_isReady) {
      return;
    }

    await _initializeTracelet();
    _isReady = true;
    _listenForLocationEvents();
  }

  void _throwIfDisposed(String action) {
    if (_isDisposed) {
      throw StateError('Cannot $action tracking engine after disposal.');
    }
  }

  void _listenForLocationEvents() {
    _locationSubscription = Tracelet.onLocation(_normalizeAndEmitLocation);
  }

  void _normalizeAndEmitLocation(Location location) {
    final sessionId = _activeSessionId;
    if (sessionId == null) {
      return;
    }

    final trackedPoint = normalizeTraceletLocation(
      location,
      sessionId: sessionId,
    );
    if (trackedPoint == null) {
      return;
    }
    _sampleController.add(trackedPoint);
  }
}

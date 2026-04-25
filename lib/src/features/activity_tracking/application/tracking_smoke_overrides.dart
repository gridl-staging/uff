import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:uff/src/features/activity_tracking/data/permission_service.dart';
import 'package:uff/src/features/activity_tracking/data/replay_tracking_engine.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';

const _e2eReplayTracking = bool.fromEnvironment('E2E_REPLAY_TRACKING');
const _e2eReplayEmissionIntervalMs = int.fromEnvironment(
  'E2E_REPLAY_EMISSION_INTERVAL_MS',
  defaultValue: 50,
);

/// Smoke builds can override the initial GPS gate when they inject a replay
/// engine instead of waiting on simulator geolocation.
final allowRecordingStartWithoutGpsFixProvider = Provider<bool>((_) => false);

List<Override> buildTrackingSmokeOverrides() {
  if (!_e2eReplayTracking) {
    return const <Override>[];
  }

  return <Override>[
    trackingEngineProvider.overrideWithValue(
      ReplayTrackingEngine(
        points: _buildSmokeReplayPoints(),
        emissionInterval: Duration(
          milliseconds: _normalizedReplayEmissionIntervalMs(),
        ),
      ),
    ),
    trackingPermissionServiceProvider.overrideWithValue(
      _SmokeTrackingPermissionService(),
    ),
    allowRecordingStartWithoutGpsFixProvider.overrideWithValue(true),
  ];
}

int _normalizedReplayEmissionIntervalMs() {
  if (_e2eReplayEmissionIntervalMs > 0) {
    return _e2eReplayEmissionIntervalMs;
  }
  return 50;
}

List<TrackingPoint> _buildSmokeReplayPoints() {
  const startLatitude = 40.7128;
  const startLongitude = -74.0060;
  const latitudeStep = 0.00003;
  const longitudeStep = 0.00002;
  final startTime = DateTime.utc(2026, 4, 20, 12);

  return List<TrackingPoint>.generate(240, (index) {
    return TrackingPoint(
      sessionId: 0,
      timestamp: startTime.add(Duration(seconds: index)),
      coordinate: GeoCoordinate(
        latitude: startLatitude + (latitudeStep * index),
        longitude: startLongitude + (longitudeStep * index),
      ),
      elevation: 12 + ((index % 6) * 0.4),
      accuracy: 5,
      speed: 3.2,
    );
  }, growable: false);
}

class _SmokeTrackingPermissionService extends TrackingPermissionService {
  @override
  Future<TrackingPermissionDecision> ensureForegroundPermission() async {
    return TrackingPermissionDecision.granted;
  }

  @override
  Future<TrackingPermissionDecision> ensureBackgroundPermission() async {
    return TrackingPermissionDecision.granted;
  }
}

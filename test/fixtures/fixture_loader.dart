import 'dart:convert';
import 'dart:io';

import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/analytics/domain/analytics_point.dart';

import '../src/test_helpers/fixture_point_parser.dart';

/// Shared fixture registry used by unit, import, and e2e-oriented tests.
const Map<String, String> fixturePathsByName = <String, String>{
  '5k_run': 'e2e_test/test_data/5k_run.json',
  'interval_workout': 'e2e_test/test_data/generated/interval_workout.json',
  'hilly_10k': 'e2e_test/test_data/generated/hilly_10k.json',
  'auto_pause_test': 'e2e_test/test_data/generated/auto_pause_test.json',
  'long_easy_run': 'e2e_test/test_data/generated/long_easy_run.json',
};

const String expectedMetricsPath = 'e2e_test/test_data/expected_metrics.json';
const int _fixtureSessionId = 1;

Future<List<TrackingPoint>> loadFixtureTrackingPoints(
  String fixtureName,
) async {
  final fixtureJson = await File(_fixturePathFor(fixtureName)).readAsString();
  return parseFixturePointsFromJson(
    fixtureJson,
    sessionId: _fixtureSessionId,
  );
}

Map<String, dynamic> loadExpectedMetrics() {
  final manifestJson = File(expectedMetricsPath).readAsStringSync();
  return jsonDecode(manifestJson) as Map<String, dynamic>;
}

Map<String, dynamic> loadExpectedFixture(String fixtureName) {
  final fixtureMetrics = loadExpectedMetrics()[fixtureName];
  if (fixtureMetrics is! Map<String, dynamic>) {
    throw StateError('Missing expected metrics for fixture: $fixtureName');
  }

  return fixtureMetrics;
}

Future<List<AnalyticsPoint>> loadFixtureAnalyticsPoints(
  String fixtureName,
) async {
  return toAnalyticsPoints(await loadFixtureTrackingPoints(fixtureName));
}

double averagePaceSecondsPerKmFromExpectedMetrics(
  Map<String, dynamic> expectedMetrics,
) {
  final movingSeconds = (expectedMetrics['movingSeconds'] as num).toDouble();
  final plannedDistanceMeters =
      (expectedMetrics['plannedDistanceMeters'] as num).toDouble();
  return movingSeconds / (plannedDistanceMeters / 1000);
}

List<AnalyticsPoint> toAnalyticsPoints(List<TrackingPoint> trackingPoints) {
  return trackingPoints
      .map(
        (trackingPoint) => AnalyticsPoint(
          timestamp: trackingPoint.timestamp,
          latitude: trackingPoint.coordinate.latitude,
          longitude: trackingPoint.coordinate.longitude,
          elevationMeters: trackingPoint.elevation,
          speedMs: trackingPoint.speed,
          heartRateBpm: trackingPoint.heartRateBpm,
          cadenceRpm: trackingPoint.cadenceRpm?.toInt(),
          powerWatts: trackingPoint.powerWatts,
        ),
      )
      .toList(growable: false);
}

String _fixturePathFor(String fixtureName) {
  final fixturePath = fixturePathsByName[fixtureName];
  if (fixturePath != null) {
    return fixturePath;
  }

  throw ArgumentError.value(
    fixtureName,
    'fixtureName',
    'Unknown fixture. Expected one of: ${fixturePathsByName.keys.join(', ')}',
  );
}

import 'dart:convert';

import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

/// Parses a JSON string of fixture points into [TrackingPoint] objects.
///
/// This is the single source of truth for fixture JSON → TrackingPoint
/// conversion, used by both the e2e replay loader and unit-test helpers.
/// Sensor fields (`heartRateBpm`, `cadenceRpm`, `powerWatts`) are optional
/// and default to null when absent — backward-compatible with pre-sensor
/// fixtures like `5k_run.json`.
List<TrackingPoint> parseFixturePointsFromJson(
  String jsonString, {
  required int sessionId,
}) {
  final entries = jsonDecode(jsonString) as List<dynamic>;
  return entries
      .map((entry) {
        final map = entry as Map<String, dynamic>;
        return TrackingPoint(
          sessionId: sessionId,
          timestamp: DateTime.parse(map['timestamp'] as String),
          coordinate: GeoCoordinate(
            latitude: (map['latitude'] as num).toDouble(),
            longitude: (map['longitude'] as num).toDouble(),
          ),
          elevation: (map['elevation'] as num?)?.toDouble(),
          accuracy: (map['accuracy'] as num?)?.toDouble(),
          speed: (map['speed'] as num?)?.toDouble(),
          heartRateBpm: (map['heartRateBpm'] as num?)?.toInt(),
          cadenceRpm: (map['cadenceRpm'] as num?)?.toDouble(),
          powerWatts: (map['powerWatts'] as num?)?.toInt(),
        );
      })
      .toList(growable: false);
}

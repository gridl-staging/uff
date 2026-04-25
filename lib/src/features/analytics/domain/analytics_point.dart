import 'package:meta/meta.dart';

/// Immutable analytics sample extracted from a recorded activity stream.
@immutable
class AnalyticsPoint {
  const AnalyticsPoint({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.elevationMeters,
    this.speedMs,
    this.heartRateBpm,
    this.cadenceRpm,
    this.powerWatts,
    this.cumulativeDistanceMeters,
  });

  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? elevationMeters;
  final double? speedMs;
  final int? heartRateBpm;
  final int? cadenceRpm;
  final int? powerWatts;
  final double? cumulativeDistanceMeters;
}

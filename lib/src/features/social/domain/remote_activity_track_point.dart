import 'package:meta/meta.dart';

/// Remote track point row returned from `read_activity_track_points`.
///
/// Latitude and longitude can be null when privacy-zone masking applies.
@immutable
class RemoteActivityTrackPoint {
  const RemoteActivityTrackPoint({
    required this.id,
    required this.activityId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.elevation,
    this.heartRate,
    this.cadence,
    this.power,
    this.speed,
    this.distance,
    this.temperature,
  });

  final int id;
  final String activityId;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final double? elevation;
  final int? heartRate;
  final int? cadence;
  final int? power;
  final double? speed;
  final double? distance;
  final int? temperature;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteActivityTrackPoint &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          activityId == other.activityId &&
          timestamp == other.timestamp &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          elevation == other.elevation &&
          heartRate == other.heartRate &&
          cadence == other.cadence &&
          power == other.power &&
          speed == other.speed &&
          distance == other.distance &&
          temperature == other.temperature;

  @override
  int get hashCode => Object.hash(
    id,
    activityId,
    timestamp,
    latitude,
    longitude,
    elevation,
    heartRate,
    cadence,
    power,
    speed,
    distance,
    temperature,
  );
}

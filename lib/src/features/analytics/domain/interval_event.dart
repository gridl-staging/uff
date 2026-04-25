import 'package:meta/meta.dart';

enum IntervalIntensity {
  hard,
  easy,
}

/// Detected interval segment with summary metrics over its duration.
@immutable
class IntervalEvent {
  const IntervalEvent({
    required this.intensity,
    required this.startTimestamp,
    required this.endTimestamp,
    required this.distanceMeters,
    required this.avgPaceSecsPerKm,
    this.avgHeartRateBpm,
  });

  final IntervalIntensity intensity;
  final DateTime startTimestamp;
  final DateTime endTimestamp;
  final double distanceMeters;
  final double avgPaceSecsPerKm;
  final double? avgHeartRateBpm;

  Duration get duration => endTimestamp.difference(startTimestamp);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is IntervalEvent &&
        other.intensity == intensity &&
        other.startTimestamp == startTimestamp &&
        other.endTimestamp == endTimestamp &&
        other.distanceMeters == distanceMeters &&
        other.avgPaceSecsPerKm == avgPaceSecsPerKm &&
        other.avgHeartRateBpm == avgHeartRateBpm;
  }

  @override
  int get hashCode => Object.hash(
    intensity,
    startTimestamp,
    endTimestamp,
    distanceMeters,
    avgPaceSecsPerKm,
    avgHeartRateBpm,
  );
}

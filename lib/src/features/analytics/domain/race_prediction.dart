import 'package:meta/meta.dart';

/// Completed race used as the baseline for prediction calculations.
@immutable
class RaceResult {
  const RaceResult({
    required this.distanceMeters,
    required this.duration,
  });

  final double distanceMeters;
  final Duration duration;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is RaceResult &&
        other.distanceMeters == distanceMeters &&
        other.duration == duration;
  }

  @override
  int get hashCode => Object.hash(distanceMeters, duration);
}

@immutable
class RacePrediction {
  const RacePrediction({
    required this.label,
    required this.distanceMeters,
    required this.predictedTime,
    required this.intensityFactor,
  });

  final String label;
  final double distanceMeters;
  final Duration predictedTime;
  final double intensityFactor;
}

abstract final class StandardRaces {
  static const List<({String label, double distanceMeters})> all = [
    (label: '5 km', distanceMeters: 5000.0),
    (label: '10 km', distanceMeters: 10000.0),
    (label: '15 km', distanceMeters: 15000.0),
    (label: 'Half Marathon', distanceMeters: 21097.5),
    (label: '30 km', distanceMeters: 30000.0),
    (label: 'Marathon', distanceMeters: 42195.0),
  ];
}

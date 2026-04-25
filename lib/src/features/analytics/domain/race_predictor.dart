import 'dart:math';

import 'package:uff/src/features/analytics/domain/race_prediction.dart';

/// Predicts race times using the Riegel formula and generates predictions
/// for standard race distances.
abstract final class RacePredictor {
  /// Predicts the time to complete [targetDistanceMeters] based on a
  /// [reference] race result using the Riegel formula:
  /// `T2 = T1 × (D2/D1)^exponent`.
  ///
  /// Throws [ArgumentError] if any distance is not positive or reference
  /// duration is zero.
  static Duration predictTime(
    RaceResult reference,
    double targetDistanceMeters, {
    double exponent = 1.06,
  }) {
    if (reference.distanceMeters <= 0) {
      throw ArgumentError.value(
        reference.distanceMeters,
        'reference.distanceMeters',
        'must be positive',
      );
    }
    if (reference.duration == Duration.zero) {
      throw ArgumentError.value(
        reference.duration,
        'reference.duration',
        'must be non-zero',
      );
    }
    if (targetDistanceMeters <= 0) {
      throw ArgumentError.value(
        targetDistanceMeters,
        'targetDistanceMeters',
        'must be positive',
      );
    }

    final distanceRatio = targetDistanceMeters / reference.distanceMeters;
    final timeMultiplier = pow(distanceRatio, exponent);
    final predictedMicroseconds =
        reference.duration.inMicroseconds * timeMultiplier;

    return Duration(microseconds: predictedMicroseconds.round());
  }

  /// Returns predictions for all [StandardRaces] distances strictly greater
  /// than the reference distance.
  ///
  /// Shorter distances are excluded because Riegel extrapolation to shorter
  /// races is unreliable — the fatigue model only applies in one direction.
  static List<RacePrediction> predictStandardRaces(
    RaceResult reference, {
    double exponent = 1.06,
  }) {
    final referenceSpeed =
        reference.distanceMeters / reference.duration.inMicroseconds;

    final predictions = <RacePrediction>[];
    for (final race in StandardRaces.all) {
      if (race.distanceMeters <= reference.distanceMeters) continue;

      final predicted = predictTime(
        reference,
        race.distanceMeters,
        exponent: exponent,
      );
      final predictedSpeed = race.distanceMeters / predicted.inMicroseconds;

      predictions.add(
        RacePrediction(
          label: race.label,
          distanceMeters: race.distanceMeters,
          predictedTime: predicted,
          intensityFactor: predictedSpeed / referenceSpeed,
        ),
      );
    }
    return predictions;
  }
}

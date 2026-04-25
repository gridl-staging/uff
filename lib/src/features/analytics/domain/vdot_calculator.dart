import 'dart:math';

import 'package:uff/src/features/analytics/domain/race_prediction.dart';

/// Estimates VDOT (Daniels-Gilbert VO2max approximation) from a race result.
///
/// The Daniels-Gilbert regression computes oxygen cost from velocity, then
/// divides by the sustainable fraction of VO2max for the given duration.
/// VDOT approximates VO2max in ml/kg/min but is not identical to a lab test.
abstract final class VdotCalculator {
  // VO2 regression coefficients (oxygen cost from velocity in m/min).
  static const _vo2Intercept = -4.60;
  static const _vo2LinearCoeff = 0.182258;
  static const _vo2QuadraticCoeff = 0.000104;

  // Drop-off coefficients (fraction of VO2max sustainable for duration t min).
  static const _dropOffBase = 0.8;
  static const _dropOffCoeff1 = 0.1894393;
  static const _dropOffDecay1 = -0.012778;
  static const _dropOffCoeff2 = 0.2989558;
  static const _dropOffDecay2 = -0.1932605;

  /// Returns the estimated VDOT for a [result].
  ///
  /// Throws [ArgumentError] if distance is not positive or duration is zero.
  static double estimate(RaceResult result) {
    if (result.distanceMeters <= 0) {
      throw ArgumentError.value(
        result.distanceMeters,
        'result.distanceMeters',
        'must be positive',
      );
    }
    if (result.duration == Duration.zero) {
      throw ArgumentError.value(
        result.duration,
        'result.duration',
        'must be non-zero',
      );
    }

    final durationMinutes = result.duration.inSeconds / 60.0;
    final velocity = result.distanceMeters / durationMinutes;

    final vo2 = _oxygenCost(velocity);
    final pctVO2max = _sustainableFraction(durationMinutes);

    return vo2 / pctVO2max;
  }

  /// Oxygen cost at a given velocity (m/min).
  static double _oxygenCost(double velocity) =>
      _vo2Intercept +
      _vo2LinearCoeff * velocity +
      _vo2QuadraticCoeff * velocity * velocity;

  /// Fraction of VO2max sustainable for [minutes] of effort.
  static double _sustainableFraction(double minutes) =>
      _dropOffBase +
      _dropOffCoeff1 * exp(_dropOffDecay1 * minutes) +
      _dropOffCoeff2 * exp(_dropOffDecay2 * minutes);
}

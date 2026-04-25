import 'dart:math' as math;

import 'package:uff/src/features/analytics/domain/analytics_point.dart';
import 'package:uff/src/features/analytics/domain/training_stress.dart';

/// Calculates run and cycling Training Stress Score variants.
abstract final class TssCalculator {
  static TrainingStressResult? simpleTss({
    required int durationSeconds,
    required double avgPaceSecsPerKm,
    required double? thresholdPaceSecsPerKm,
  }) {
    if (thresholdPaceSecsPerKm == null || thresholdPaceSecsPerKm <= 0) {
      return null;
    }
    if (avgPaceSecsPerKm <= 0) {
      return null;
    }

    final intensityFactor = thresholdPaceSecsPerKm / avgPaceSecsPerKm;
    return _tssFromIntensityFactor(
      durationSeconds,
      intensityFactor,
      TssMethod.simpleTSS,
    );
  }

  static TrainingStressResult? rTss({
    required List<AnalyticsPoint> points,
    required double? thresholdPaceSecsPerKm,
  }) {
    if (thresholdPaceSecsPerKm == null || thresholdPaceSecsPerKm <= 0) {
      return null;
    }
    if (points.isEmpty) {
      return null;
    }

    final durationSeconds = _sumPositiveTimestampDeltas(points);
    if (durationSeconds <= 0) {
      return null;
    }

    final adjustedPaces = <_TimedNormalizationSample>[];
    for (var index = 1; index < points.length; index++) {
      final previousPoint = points[index - 1];
      final currentPoint = points[index];
      final deltaSeconds = currentPoint.timestamp
          .difference(previousPoint.timestamp)
          .inSeconds;
      if (deltaSeconds <= 0) {
        continue;
      }

      final speedMs = currentPoint.speedMs;
      if (speedMs == null || speedMs <= 0) {
        continue;
      }

      final horizontalDistanceMeters = _horizontalDistanceMeters(
        previousPoint: previousPoint,
        currentPoint: currentPoint,
        deltaSeconds: deltaSeconds,
        speedMs: speedMs,
      );
      if (horizontalDistanceMeters <= 0) {
        continue;
      }

      final rawPaceSecsPerKm = 1000 / speedMs;
      final elevationDeltaMeters = _elevationDeltaMeters(
        previousPoint,
        currentPoint,
      );
      final grade = elevationDeltaMeters / horizontalDistanceMeters;

      // Minetti approximation applied to convert raw pace to grade-adjusted effort.
      final gradeAdjustmentFactor = 1 + (3.3 * grade) + (5.4 * grade * grade);
      final gradeAdjustedPaceSecsPerKm =
          rawPaceSecsPerKm * gradeAdjustmentFactor;
      if (gradeAdjustedPaceSecsPerKm > 0 &&
          gradeAdjustedPaceSecsPerKm.isFinite) {
        adjustedPaces.add(
          _TimedNormalizationSample(
            value: gradeAdjustedPaceSecsPerKm,
            durationSeconds: deltaSeconds,
          ),
        );
      }
    }

    if (adjustedPaces.isEmpty) {
      return null;
    }

    final normalizedPaceSecsPerKm = _fourthPowerNormalize(adjustedPaces);
    final intensityFactor = thresholdPaceSecsPerKm / normalizedPaceSecsPerKm;

    return _tssFromIntensityFactor(
      durationSeconds,
      intensityFactor,
      TssMethod.rTSS,
      normalizedEffortSecsPerKm: normalizedPaceSecsPerKm,
    );
  }

  static TrainingStressResult? cTss({
    required List<AnalyticsPoint> points,
    required int? ftpWatts,
  }) {
    if (ftpWatts == null || ftpWatts <= 0) {
      return null;
    }
    if (points.isEmpty) {
      return null;
    }

    final durationSeconds = _sumPositiveTimestampDeltas(points);
    if (durationSeconds <= 0) {
      return null;
    }

    final powerSamples = <_TimedNormalizationSample>[];
    for (var index = 1; index < points.length; index++) {
      final previousPoint = points[index - 1];
      final currentPoint = points[index];
      final deltaSeconds = currentPoint.timestamp
          .difference(previousPoint.timestamp)
          .inSeconds;
      if (deltaSeconds <= 0) {
        continue;
      }

      final powerWatts = currentPoint.powerWatts;
      if (powerWatts == null || powerWatts < 0) {
        continue;
      }

      powerSamples.add(
        _TimedNormalizationSample(
          value: powerWatts.toDouble(),
          durationSeconds: deltaSeconds,
        ),
      );
    }

    if (powerSamples.isEmpty) {
      return null;
    }

    final normalizedPowerWatts = _fourthPowerNormalize(powerSamples);
    final intensityFactor = normalizedPowerWatts / ftpWatts;

    return _tssFromIntensityFactor(
      durationSeconds,
      intensityFactor,
      TssMethod.cTSS,
    );
  }

  static TrainingStressResult _tssFromIntensityFactor(
    int durationSeconds,
    double intensityFactor,
    TssMethod method, {
    double? normalizedEffortSecsPerKm,
  }) {
    final nonNegativeDurationSeconds = math.max(0, durationSeconds);
    final trainingHours = nonNegativeDurationSeconds / 3600;
    final tss = trainingHours * intensityFactor * intensityFactor * 100;

    return TrainingStressResult(
      tss: tss,
      intensityFactor: intensityFactor,
      method: method,
      normalizedEffortSecsPerKm: normalizedEffortSecsPerKm,
    );
  }

  static int _sumPositiveTimestampDeltas(List<AnalyticsPoint> points) {
    var durationSeconds = 0;
    for (var index = 1; index < points.length; index++) {
      final deltaSeconds = points[index].timestamp
          .difference(points[index - 1].timestamp)
          .inSeconds;
      if (deltaSeconds > 0) {
        durationSeconds += deltaSeconds;
      }
    }
    return durationSeconds;
  }

  static double _horizontalDistanceMeters({
    required AnalyticsPoint previousPoint,
    required AnalyticsPoint currentPoint,
    required int deltaSeconds,
    required double speedMs,
  }) {
    // Prefer cumulative-distance deltas as the single source of truth when present.
    // If those deltas are non-positive, treat the segment as invalid instead of
    // inventing a second distance value from speed.
    final previousDistanceMeters = previousPoint.cumulativeDistanceMeters;
    final currentDistanceMeters = currentPoint.cumulativeDistanceMeters;
    if (previousDistanceMeters != null && currentDistanceMeters != null) {
      final cumulativeDeltaMeters =
          currentDistanceMeters - previousDistanceMeters;
      if (cumulativeDeltaMeters > 0) {
        return cumulativeDeltaMeters;
      }

      return 0;
    }

    final fallbackDistanceMeters = speedMs * deltaSeconds;
    if (fallbackDistanceMeters > 0) {
      return fallbackDistanceMeters;
    }

    return 0;
  }

  static double _elevationDeltaMeters(
    AnalyticsPoint previousPoint,
    AnalyticsPoint currentPoint,
  ) {
    final previousElevationMeters = previousPoint.elevationMeters;
    final currentElevationMeters = currentPoint.elevationMeters;
    if (previousElevationMeters == null || currentElevationMeters == null) {
      return 0;
    }

    return currentElevationMeters - previousElevationMeters;
  }

  static double _fourthPowerNormalize(
    List<_TimedNormalizationSample> values, {
    int windowSize = 30,
  }) {
    if (values.isEmpty) {
      throw ArgumentError.value(values, 'values', 'must not be empty');
    }

    final boundedWindowSize = math.max(1, windowSize);
    final rollingWindowValues = List<double>.filled(boundedWindowSize, 0);
    final rollingWindowFourthPowers = <double>[];
    var rollingSum = 0.0;
    var rollingWindowCount = 0;
    var nextWindowIndex = 0;

    for (final value in values) {
      for (var second = 0; second < value.durationSeconds; second++) {
        if (rollingWindowCount == boundedWindowSize) {
          rollingSum -= rollingWindowValues[nextWindowIndex];
        } else {
          rollingWindowCount++;
        }

        rollingWindowValues[nextWindowIndex] = value.value;
        rollingSum += value.value;
        nextWindowIndex = (nextWindowIndex + 1) % boundedWindowSize;

        final rollingMean = rollingSum / rollingWindowCount;
        rollingWindowFourthPowers.add(math.pow(rollingMean, 4).toDouble());
      }
    }

    if (rollingWindowFourthPowers.isEmpty) {
      throw ArgumentError.value(
        values,
        'values',
        'must include positive-duration samples',
      );
    }

    final fourthPowerMean =
        rollingWindowFourthPowers.reduce((left, right) => left + right) /
        rollingWindowFourthPowers.length;

    return math.pow(fourthPowerMean, 0.25).toDouble();
  }
}

final class _TimedNormalizationSample {
  const _TimedNormalizationSample({
    required this.value,
    required this.durationSeconds,
  });

  final double value;
  final int durationSeconds;
}

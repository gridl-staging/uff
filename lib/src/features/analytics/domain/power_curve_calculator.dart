import 'package:uff/src/features/analytics/domain/analytics_point.dart';
import 'package:uff/src/features/analytics/domain/power_curve_point.dart';

/// Computes best-average-power at standard durations from a point stream.
///
/// For each standard duration, slides a two-pointer window across the
/// power-bearing points to find the window with the highest time-weighted
/// average power. O(n×k) where n = points and k = standard durations.
abstract final class PowerCurveCalculator {
  static const _standardDurations = [
    5,
    10,
    30,
    60,
    120,
    300,
    600,
    1200,
    1800,
    3600,
  ];

  /// Returns the best average power for each standard duration that fits
  /// within the recording, sorted by ascending duration.
  static List<PowerCurvePoint> calculate({
    required List<AnalyticsPoint> points,
  }) {
    final powerPoints = _filterAndSort(points);
    if (powerPoints.length < 2) return const [];

    final totalElapsed = powerPoints.last.timestamp
        .difference(powerPoints.first.timestamp)
        .inSeconds;

    final results = <PowerCurvePoint>[];

    for (final durationSecs in _standardDurations) {
      if (durationSecs > totalElapsed) continue;

      final bestAvg = _bestAverageForDuration(powerPoints, durationSecs);
      if (bestAvg != null) {
        results.add(
          PowerCurvePoint(
            duration: Duration(seconds: durationSecs),
            avgWatts: bestAvg,
          ),
        );
      }
    }

    return results;
  }

  static List<AnalyticsPoint> _filterAndSort(List<AnalyticsPoint> points) {
    final filtered = [
      for (final p in points)
        if (p.powerWatts != null) p,
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return filtered;
  }

  /// Slides a two-pointer window to find the maximum time-weighted average
  /// power for windows with elapsed time ≥ [durationSecs].
  static double? _bestAverageForDuration(
    List<AnalyticsPoint> points,
    int durationSecs,
  ) {
    double? bestAvg;
    var windowPowerSum = 0.0; // Σ(power × dt) for intervals in window
    var windowTimeSecs = 0.0;
    var end = 1;

    // Seed the first interval [0,1].
    windowPowerSum += _intervalPowerTime(points, 0);
    windowTimeSecs += _intervalDuration(points, 0);

    for (var start = 0; start < points.length - 1; start++) {
      // Extend the end pointer until window covers the required duration.
      while (end < points.length - 1 && windowTimeSecs < durationSecs) {
        windowPowerSum += _intervalPowerTime(points, end);
        windowTimeSecs += _intervalDuration(points, end);
        end++;
      }

      if (windowTimeSecs >= durationSecs) {
        final avg = windowPowerSum / windowTimeSecs;
        if (bestAvg == null || avg > bestAvg) {
          bestAvg = avg;
        }
      }

      // Shrink window from the left by removing interval [start, start+1].
      windowPowerSum -= _intervalPowerTime(points, start);
      windowTimeSecs -= _intervalDuration(points, start);
    }

    return bestAvg;
  }

  /// Power × time contribution for the interval from points[i] to points[i+1].
  /// Uses the leading point's power (previous-sample convention).
  static double _intervalPowerTime(List<AnalyticsPoint> points, int i) {
    final dt = _intervalDuration(points, i);
    if (dt <= 0) return 0;
    return points[i].powerWatts!.toDouble() * dt;
  }

  /// Duration in seconds from points[i] to points[i+1].
  static double _intervalDuration(List<AnalyticsPoint> points, int i) {
    return points[i + 1].timestamp
            .difference(points[i].timestamp)
            .inMilliseconds /
        1000.0;
  }
}

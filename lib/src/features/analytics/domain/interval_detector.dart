import 'dart:math' as math;

import 'package:uff/src/features/analytics/domain/analytics_point.dart';
import 'package:uff/src/features/analytics/domain/interval_event.dart';

/// Detects interval workout segments from a stream of analytics points.
///
/// Uses a pace-based pipeline: extract pace → smooth → label → group →
/// filter short segments → merge adjacent same-label → validate ≥3 segments.
abstract final class IntervalDetector {
  /// Detects interval segments from [points].
  ///
  /// Returns an empty list if fewer than 3 alternating segments are found
  /// after noise filtering.
  static List<IntervalEvent> detect({
    required List<AnalyticsPoint> points,
    int smoothingWindow = 5,
    int minSegmentSeconds = 30,
    double? thresholdPaceSecsPerKm,
  }) {
    // (1) Extract pace-bearing points.
    final pacePoints = _extractPacePoints(points);
    if (pacePoints.length < 2) return const [];

    // (2) Smooth pace values with centered rolling mean.
    final smoothedPaces = _smoothPaces(pacePoints, smoothingWindow);

    // (3) Determine threshold and label each point.
    final threshold = thresholdPaceSecsPerKm ?? _meanPace(smoothedPaces);
    final labels = _labelPoints(smoothedPaces, threshold);

    // (4) Group consecutive same-label points into segments.
    var segments = _groupSegments(pacePoints, labels);

    // (5) Filter short segments.
    segments = _filterShortSegments(segments, minSegmentSeconds);

    // (6) Merge adjacent same-label segments.
    segments = _mergeAdjacentSegments(segments);

    // (7) Validate ≥3 segments.
    if (segments.length < 3) return const [];

    // (8) Build IntervalEvent for each segment.
    return segments.map(_buildEvent).toList();
  }

  // ---------------------------------------------------------------------------
  // Pipeline helpers
  // ---------------------------------------------------------------------------

  static List<_PacePoint> _extractPacePoints(List<AnalyticsPoint> points) {
    final result = <_PacePoint>[];
    for (final point in points) {
      final speed = point.speedMs;
      if (speed == null || speed <= 0) continue;
      result.add(
        _PacePoint(
          timestamp: point.timestamp,
          rawPace: 1000 / speed,
          speedMs: speed,
          heartRateBpm: point.heartRateBpm,
          cumulativeDistanceMeters: point.cumulativeDistanceMeters,
        ),
      );
    }
    return result;
  }

  static List<double> _smoothPaces(
    List<_PacePoint> points,
    int windowSize,
  ) {
    final halfWindow = math.max(0, windowSize ~/ 2);
    final result = List<double>.filled(points.length, 0);

    for (var i = 0; i < points.length; i++) {
      final start = math.max(0, i - halfWindow);
      final end = math.min(points.length - 1, i + halfWindow);
      var sum = 0.0;
      var count = 0;
      for (var j = start; j <= end; j++) {
        sum += points[j].rawPace;
        count++;
      }
      result[i] = sum / count;
    }

    return result;
  }

  static double _meanPace(List<double> paces) {
    var sum = 0.0;
    for (final p in paces) {
      sum += p;
    }
    return sum / paces.length;
  }

  static List<IntervalIntensity> _labelPoints(
    List<double> smoothedPaces,
    double threshold,
  ) {
    return [
      for (final pace in smoothedPaces)
        pace < threshold ? IntervalIntensity.hard : IntervalIntensity.easy,
    ];
  }

  static List<_Segment> _groupSegments(
    List<_PacePoint> points,
    List<IntervalIntensity> labels,
  ) {
    if (points.isEmpty) return const [];

    final segments = <_Segment>[];
    var segStart = 0;

    for (var i = 1; i < points.length; i++) {
      if (labels[i] != labels[segStart]) {
        segments.add(
          _Segment(
            label: labels[segStart],
            startIndex: segStart,
            endIndex: i - 1,
            points: points,
          ),
        );
        segStart = i;
      }
    }

    // Final segment.
    segments.add(
      _Segment(
        label: labels[segStart],
        startIndex: segStart,
        endIndex: points.length - 1,
        points: points,
      ),
    );

    return segments;
  }

  static List<_Segment> _filterShortSegments(
    List<_Segment> segments,
    int minSeconds,
  ) {
    if (minSeconds <= 0) return segments;
    return [
      for (final seg in segments)
        if (seg.durationSeconds >= minSeconds) seg,
    ];
  }

  static List<_Segment> _mergeAdjacentSegments(List<_Segment> segments) {
    if (segments.isEmpty) return const [];

    final merged = <_Segment>[segments.first];

    for (var i = 1; i < segments.length; i++) {
      final current = segments[i];
      final previous = merged.last;
      if (current.label == previous.label) {
        // Replace the last entry with the merged version.
        merged[merged.length - 1] = _Segment(
          label: previous.label,
          startIndex: previous.startIndex,
          endIndex: current.endIndex,
          points: previous.points,
        );
      } else {
        merged.add(current);
      }
    }

    return merged;
  }

  static IntervalEvent _buildEvent(_Segment segment) {
    final points = segment.points;
    final startPoint = points[segment.startIndex];
    final endPoint = points[segment.endIndex];

    // Distance: prefer cumulative distance delta, fallback to speed × time.
    final distanceMeters = _segmentDistance(segment);

    // Average pace: mean of raw paces in segment.
    var paceSum = 0.0;
    for (var i = segment.startIndex; i <= segment.endIndex; i++) {
      paceSum += points[i].rawPace;
    }
    final pointCount = segment.endIndex - segment.startIndex + 1;
    final avgPace = paceSum / pointCount;

    // Average HR: mean of non-null values, or null if all null.
    final avgHr = _segmentAvgHr(segment);

    return IntervalEvent(
      intensity: segment.label,
      startTimestamp: startPoint.timestamp,
      endTimestamp: endPoint.timestamp,
      distanceMeters: distanceMeters,
      avgPaceSecsPerKm: avgPace,
      avgHeartRateBpm: avgHr,
    );
  }

  static double _segmentDistance(_Segment segment) {
    final points = segment.points;
    final startCumDist = points[segment.startIndex].cumulativeDistanceMeters;
    final endCumDist = points[segment.endIndex].cumulativeDistanceMeters;

    if (startCumDist != null && endCumDist != null) {
      final delta = endCumDist - startCumDist;
      if (delta > 0) return delta;
    }

    // Fallback: sum speed × timeDelta for each consecutive pair.
    var distance = 0.0;
    for (var i = segment.startIndex; i < segment.endIndex; i++) {
      final dt = points[i + 1].timestamp
          .difference(points[i].timestamp)
          .inSeconds;
      if (dt > 0) {
        distance += points[i].speedMs * dt;
      }
    }
    return distance;
  }

  static double? _segmentAvgHr(_Segment segment) {
    var hrSum = 0.0;
    var hrCount = 0;
    for (var i = segment.startIndex; i <= segment.endIndex; i++) {
      final hr = segment.points[i].heartRateBpm;
      if (hr != null) {
        hrSum += hr;
        hrCount++;
      }
    }
    return hrCount > 0 ? hrSum / hrCount : null;
  }
}

// ---------------------------------------------------------------------------
// Internal data types
// ---------------------------------------------------------------------------

final class _PacePoint {
  const _PacePoint({
    required this.timestamp,
    required this.rawPace,
    required this.speedMs,
    required this.heartRateBpm,
    required this.cumulativeDistanceMeters,
  });

  final DateTime timestamp;
  final double rawPace;
  final double speedMs;
  final int? heartRateBpm;
  final double? cumulativeDistanceMeters;
}

/// Consecutive points that share one interval-intensity label.
final class _Segment {
  const _Segment({
    required this.label,
    required this.startIndex,
    required this.endIndex,
    required this.points,
  });

  final IntervalIntensity label;
  final int startIndex;
  final int endIndex;
  final List<_PacePoint> points;

  int get durationSeconds {
    final start = points[startIndex].timestamp;
    final end = points[endIndex].timestamp;
    return end.difference(start).inSeconds;
  }
}

import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/distance_calculator.dart';
import 'package:uff/src/features/activity_tracking/domain/track_metrics.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

const double _splitBoundaryEpsilonMeters = 1e-3;

List<ActivitySplit> generateSplits({
  required List<TrackingPoint> cleanedPoints,
  required SplitUnit splitUnit,
}) {
  if (cleanedPoints.length < 2) {
    return const [];
  }

  final createdSplits = <ActivitySplit>[];
  final unitDistanceMeters = splitUnit.unitDistanceMeters;

  var cumulativeDistanceMeters = 0.0;
  var nextBoundaryDistanceMeters = unitDistanceMeters;
  var previousSplitCumulativeDuration = Duration.zero;
  final activityStartTimestamp = cleanedPoints.first.timestamp;

  for (var index = 1; index < cleanedPoints.length; index += 1) {
    final segmentStart = cleanedPoints[index - 1];
    final segmentEnd = cleanedPoints[index];
    final segmentDuration = segmentEnd.timestamp.difference(
      segmentStart.timestamp,
    );

    if (segmentDuration <= Duration.zero) {
      continue;
    }

    final segmentDistanceMeters = calculateGeodesicDistanceMeters(
      segmentStart.coordinate,
      segmentEnd.coordinate,
    );
    if (segmentDistanceMeters <= 0) {
      continue;
    }

    while (nextBoundaryDistanceMeters <=
        cumulativeDistanceMeters +
            segmentDistanceMeters +
            _splitBoundaryEpsilonMeters) {
      final distanceFromSegmentStartToBoundary =
          nextBoundaryDistanceMeters - cumulativeDistanceMeters;
      final segmentProgressRatio =
          (distanceFromSegmentStartToBoundary / segmentDistanceMeters)
              .clamp(0, 1)
              .toDouble();

      final boundaryTimestamp = _interpolateTimestamp(
        start: segmentStart.timestamp,
        duration: segmentDuration,
        progressRatio: segmentProgressRatio,
      );
      final boundaryCumulativeDuration = boundaryTimestamp.difference(
        activityStartTimestamp,
      );
      final splitDuration =
          boundaryCumulativeDuration - previousSplitCumulativeDuration;

      createdSplits.add(
        ActivitySplit(
          index: createdSplits.length + 1,
          unit: splitUnit,
          splitDuration: splitDuration,
          cumulativeDuration: boundaryCumulativeDuration,
          cumulativeDistanceMeters: nextBoundaryDistanceMeters,
          pace: calculatePaceForUnit(
            distanceMeters: unitDistanceMeters,
            elapsedTime: splitDuration,
            splitUnit: splitUnit,
          ),
        ),
      );

      previousSplitCumulativeDuration = boundaryCumulativeDuration;
      nextBoundaryDistanceMeters += unitDistanceMeters;
    }

    cumulativeDistanceMeters += segmentDistanceMeters;
  }

  return List<ActivitySplit>.unmodifiable(createdSplits);
}

DateTime _interpolateTimestamp({
  required DateTime start,
  required Duration duration,
  required double progressRatio,
}) {
  final elapsedMilliseconds = (duration.inMilliseconds * progressRatio).round();
  return start.add(Duration(milliseconds: elapsedMilliseconds));
}

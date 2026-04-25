import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/distance_calculator.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

PointCleanupResult cleanTrackingPoints(List<TrackingPoint> rawPoints) {
  if (rawPoints.isEmpty) {
    return const PointCleanupResult(
      cleanedPoints: [],
      droppedDuplicateCount: 0,
      droppedOutlierCount: 0,
    );
  }

  final indexedPoints = <({int originalIndex, TrackingPoint point})>[];
  for (var index = 0; index < rawPoints.length; index += 1) {
    indexedPoints.add((originalIndex: index, point: rawPoints[index]));
  }

  indexedPoints.sort((left, right) {
    final timestampComparison = left.point.timestamp.compareTo(
      right.point.timestamp,
    );
    if (timestampComparison != 0) {
      return timestampComparison;
    }

    return left.originalIndex.compareTo(right.originalIndex);
  });

  final normalizedPoints = <TrackingPoint>[];
  var droppedDuplicateCount = 0;

  for (final indexedPoint in indexedPoints) {
    final point = indexedPoint.point;
    final previousPoint = normalizedPoints.isEmpty
        ? null
        : normalizedPoints.last;
    if (_isDuplicateSample(previousPoint, point)) {
      droppedDuplicateCount += 1;
      continue;
    }

    normalizedPoints.add(point);
  }

  if (normalizedPoints.length < 2) {
    return PointCleanupResult(
      cleanedPoints: List<TrackingPoint>.unmodifiable(normalizedPoints),
      droppedDuplicateCount: droppedDuplicateCount,
      droppedOutlierCount: 0,
    );
  }

  final cleanedPoints = <TrackingPoint>[normalizedPoints.first];
  var droppedOutlierCount = 0;

  for (final candidatePoint in normalizedPoints.skip(1)) {
    final previousCleanPoint = cleanedPoints.last;
    final speedMetersPerSecond = _calculatePointToPointSpeed(
      previousCleanPoint,
      candidatePoint,
    );

    if (speedMetersPerSecond == null ||
        speedMetersPerSecond > maximumPlausibleSpeedMetersPerSecond) {
      droppedOutlierCount += 1;
      continue;
    }

    cleanedPoints.add(candidatePoint);
  }

  return PointCleanupResult(
    cleanedPoints: List<TrackingPoint>.unmodifiable(cleanedPoints),
    droppedDuplicateCount: droppedDuplicateCount,
    droppedOutlierCount: droppedOutlierCount,
  );
}

bool _isDuplicateSample(TrackingPoint? previous, TrackingPoint current) {
  if (previous == null) {
    return false;
  }

  return current.timestamp.isAtSameMomentAs(previous.timestamp);
}

double? _calculatePointToPointSpeed(
  TrackingPoint start,
  TrackingPoint end,
) {
  final elapsedMilliseconds = end.timestamp
      .difference(start.timestamp)
      .inMilliseconds;
  if (elapsedMilliseconds <= 0) {
    return null;
  }

  final distanceMeters = calculateGeodesicDistanceMeters(
    start.coordinate,
    end.coordinate,
  );

  return distanceMeters /
      (elapsedMilliseconds / Duration.millisecondsPerSecond);
}

import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/distance_calculator.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

double calculateTrackDistanceMeters(List<TrackingPoint> cleanedPoints) {
  if (cleanedPoints.length < 2) {
    return 0;
  }

  var cumulativeDistanceMeters = 0.0;
  for (var index = 1; index < cleanedPoints.length; index += 1) {
    cumulativeDistanceMeters += calculateGeodesicDistanceMeters(
      cleanedPoints[index - 1].coordinate,
      cleanedPoints[index].coordinate,
    );
  }

  return cumulativeDistanceMeters;
}

Duration calculateElapsedTime(List<TrackingPoint> orderedPoints) {
  if (orderedPoints.length < 2) {
    return Duration.zero;
  }

  for (var index = 1; index < orderedPoints.length; index += 1) {
    final previousTimestamp = orderedPoints[index - 1].timestamp;
    final currentTimestamp = orderedPoints[index].timestamp;
    if (!currentTimestamp.isAfter(previousTimestamp)) {
      return Duration.zero;
    }
  }

  return orderedPoints.last.timestamp.difference(orderedPoints.first.timestamp);
}

Duration? calculatePacePerKilometer({
  required double distanceMeters,
  required Duration elapsedTime,
}) {
  return calculatePaceForUnit(
    distanceMeters: distanceMeters,
    elapsedTime: elapsedTime,
    splitUnit: SplitUnit.kilometer,
  );
}

Duration? calculatePacePerMile({
  required double distanceMeters,
  required Duration elapsedTime,
}) {
  return calculatePaceForUnit(
    distanceMeters: distanceMeters,
    elapsedTime: elapsedTime,
    splitUnit: SplitUnit.mile,
  );
}

Duration? calculatePaceForUnit({
  required double distanceMeters,
  required Duration elapsedTime,
  required SplitUnit splitUnit,
}) {
  if (distanceMeters <= 0 || elapsedTime <= Duration.zero) {
    return null;
  }

  final coveredUnits = distanceMeters / splitUnit.unitDistanceMeters;
  if (coveredUnits <= 0) {
    return null;
  }

  final secondsPerUnit = elapsedTime.inSeconds / coveredUnits;
  if (!secondsPerUnit.isFinite || secondsPerUnit <= 0) {
    return null;
  }

  return Duration(seconds: secondsPerUnit.floor());
}

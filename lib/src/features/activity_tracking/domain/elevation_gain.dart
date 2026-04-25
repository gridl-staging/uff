import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

double calculateElevationGainMeters(List<TrackingPoint> orderedPoints) {
  if (orderedPoints.isEmpty) {
    return 0;
  }

  double? previousKnownElevation;
  var totalGainMeters = 0.0;

  for (final point in orderedPoints) {
    final elevation = point.elevation;
    if (elevation == null) {
      continue;
    }

    if (previousKnownElevation != null) {
      final elevationDelta = elevation - previousKnownElevation;
      if (elevationDelta >= minimumElevationGainDeltaMeters) {
        totalGainMeters += elevationDelta;
      }
    }

    previousKnownElevation = elevation;
  }

  return totalGainMeters;
}

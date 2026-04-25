import 'package:meta/meta.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

const double earthRadiusMeters = 6371000;
const double maximumPlausibleSpeedMetersPerSecond = 18;
const double minimumElevationGainDeltaMeters = 1;
const double autoPauseStopSpeedThresholdMetersPerSecond = 0.5;
const double autoPauseResumeSpeedThresholdMetersPerSecond = 1;
const Duration minimumAutoPauseDuration = Duration(seconds: 60);

const double metersPerKilometer = 1000;
const double metersPerMile = 1609.344;

enum SplitUnit {
  kilometer,
  mile,
}

extension SplitUnitDistance on SplitUnit {
  double get unitDistanceMeters {
    return switch (this) {
      SplitUnit.kilometer => metersPerKilometer,
      SplitUnit.mile => metersPerMile,
    };
  }
}

@immutable
class PointCleanupResult {
  const PointCleanupResult({
    required this.cleanedPoints,
    required this.droppedDuplicateCount,
    required this.droppedOutlierCount,
  });

  final List<TrackingPoint> cleanedPoints;
  final int droppedDuplicateCount;
  final int droppedOutlierCount;
}

@immutable
class ActivityPace {
  const ActivityPace({
    required this.perKilometer,
    required this.perMile,
  });

  final Duration? perKilometer;
  final Duration? perMile;
}

/// NOTE(stuart): Document ActivitySplit.
@immutable
class ActivitySplit {
  const ActivitySplit({
    required this.index,
    required this.unit,
    required this.splitDuration,
    required this.cumulativeDuration,
    required this.cumulativeDistanceMeters,
    required this.pace,
  });

  final int index;
  final SplitUnit unit;
  final Duration splitDuration;
  final Duration cumulativeDuration;
  final double cumulativeDistanceMeters;
  final Duration? pace;

  double get unitDistanceMeters => unit.unitDistanceMeters;
}

enum AutoPauseState {
  moving,
  stopped,
}

@immutable
class AutoPauseWindow {
  const AutoPauseWindow({
    required this.state,
    required this.startedAt,
    required this.endedAt,
  });

  final AutoPauseState state;
  final DateTime startedAt;
  final DateTime endedAt;

  Duration get duration => endedAt.difference(startedAt);
}

@immutable
class AutoPauseResult {
  const AutoPauseResult({
    required this.windows,
    required this.totalMovingDuration,
  });

  final List<AutoPauseWindow> windows;
  final Duration totalMovingDuration;
}

@immutable
class TrackSummary {
  const TrackSummary({
    required this.distanceMeters,
    required this.movingTime,
    required this.averagePace,
    required this.elevationGainMeters,
  });

  final double distanceMeters;
  final Duration movingTime;
  final ActivityPace averagePace;
  final double elevationGainMeters;
}

@immutable
class ProcessedActivityMetrics {
  const ProcessedActivityMetrics({
    required this.session,
    required this.trackSummary,
    required this.splits,
    required this.autoPause,
  });

  final TrackingSessionRecord session;
  final TrackSummary trackSummary;
  final List<ActivitySplit> splits;
  final AutoPauseResult autoPause;
}

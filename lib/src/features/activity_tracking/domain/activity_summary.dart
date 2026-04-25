import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/auto_pause.dart';
import 'package:uff/src/features/activity_tracking/domain/elevation_gain.dart';
import 'package:uff/src/features/activity_tracking/domain/split_generation.dart';
import 'package:uff/src/features/activity_tracking/domain/track_metrics.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

Duration calculatePersistedActivityDuration({
  required TrackingSessionRecord session,
  required Duration processedMovingTime,
}) {
  final sessionElapsed = calculateSessionElapsedDuration(session);
  return sessionElapsed > processedMovingTime
      ? sessionElapsed
      : processedMovingTime;
}

Duration calculateSessionElapsedDuration(TrackingSessionRecord session) {
  final startedAt = session.startedAt;
  final stoppedAt = session.stoppedAt;
  if (startedAt == null || stoppedAt == null || !stoppedAt.isAfter(startedAt)) {
    return Duration.zero;
  }
  return stoppedAt.difference(startedAt);
}

ProcessedActivityMetrics calculateProcessedActivityMetrics({
  required TrackingSessionRecord session,
  required List<TrackingPoint> cleanedPoints,
  SplitUnit splitUnit = SplitUnit.kilometer,
}) {
  final cleanedDistanceMeters = calculateTrackDistanceMeters(cleanedPoints);
  final autoPause = classifyAutoPauseWindows(cleanedPoints);
  final elapsedTime = calculateElapsedTime(cleanedPoints);
  final movingTime = autoPause.windows.isEmpty
      ? elapsedTime
      : autoPause.totalMovingDuration;

  return ProcessedActivityMetrics(
    session: session,
    trackSummary: TrackSummary(
      distanceMeters: cleanedDistanceMeters,
      movingTime: movingTime,
      averagePace: ActivityPace(
        perKilometer: calculatePacePerKilometer(
          distanceMeters: cleanedDistanceMeters,
          elapsedTime: movingTime,
        ),
        perMile: calculatePacePerMile(
          distanceMeters: cleanedDistanceMeters,
          elapsedTime: movingTime,
        ),
      ),
      elevationGainMeters: calculateElevationGainMeters(cleanedPoints),
    ),
    splits: generateSplits(
      cleanedPoints: cleanedPoints,
      splitUnit: splitUnit,
    ),
    autoPause: autoPause,
  );
}

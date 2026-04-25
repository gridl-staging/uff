import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_summary.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

Map<String, dynamic> buildActivityPayload({
  required TrackingSessionRecord session,
  required ProcessedActivityMetrics metrics,
  required List<TrackingPoint> cleanedPoints,
  required String remoteId,
  required String userId,
}) {
  final startedAt = resolveStartedAt(session, cleanedPoints);
  final finishedAt = resolveFinishedAt(session, cleanedPoints, startedAt);
  final visibility = supportedTrackingSessionVisibilityOrNull(
    session.visibility,
  );
  final persistedDuration = calculatePersistedActivityDuration(
    session: session,
    processedMovingTime: metrics.trackSummary.movingTime,
  );
  final pacePerKilometerSeconds =
      metrics.trackSummary.averagePace.perKilometer?.inMilliseconds == null
      ? null
      : metrics.trackSummary.averagePace.perKilometer!.inMilliseconds / 1000;

  return <String, dynamic>{
    'id': remoteId,
    'user_id': userId,
    'sport_type': session.sportType ?? 'workout',
    'started_at': startedAt.toUtc().toIso8601String(),
    'finished_at': finishedAt.toUtc().toIso8601String(),
    'distance_meters': metrics.trackSummary.distanceMeters,
    'duration_seconds': persistedDuration.inSeconds,
    'elevation_gain_meters': metrics.trackSummary.elevationGainMeters,
    'avg_pace_seconds_per_km': pacePerKilometerSeconds,
    'title': session.title,
    'description': session.description,
    if (visibility != null) 'visibility': visibility,
  };
}

DateTime resolveStartedAt(
  TrackingSessionRecord session,
  List<TrackingPoint> cleanedPoints,
) {
  final startedAt = session.startedAt;
  if (startedAt != null) {
    return startedAt;
  }
  if (cleanedPoints.isNotEmpty) {
    return cleanedPoints.first.timestamp;
  }
  return session.createdAt;
}

DateTime resolveFinishedAt(
  TrackingSessionRecord session,
  List<TrackingPoint> cleanedPoints,
  DateTime startedAt,
) {
  final stoppedAt = session.stoppedAt;
  if (stoppedAt != null) {
    return stoppedAt;
  }
  if (cleanedPoints.isNotEmpty) {
    return cleanedPoints.last.timestamp;
  }
  return startedAt;
}

List<Map<String, dynamic>> buildTrackPointRows({
  required String remoteId,
  required List<TrackingPoint> cleanedPoints,
}) {
  return cleanedPoints
      .map((point) {
        return <String, dynamic>{
          'activity_id': remoteId,
          'timestamp': point.timestamp.toUtc().toIso8601String(),
          'latitude': point.latitude,
          'longitude': point.longitude,
          'elevation': point.elevation,
          'speed': point.speed,
          'heart_rate': point.heartRateBpm,
          // Remote track_points.cadence is a smallint, while imported
          // cadence can carry fractional precision locally.
          'cadence': normalizeCadenceForSync(point.cadenceRpm),
          'power': point.powerWatts,
        };
      })
      .toList(growable: false);
}

int? normalizeCadenceForSync(double? cadenceRpm) {
  return cadenceRpm?.round();
}

List<Map<String, dynamic>> buildSplitRows({
  required String remoteId,
  required ProcessedActivityMetrics processedMetrics,
}) {
  return processedMetrics.splits
      .map((split) {
        return <String, dynamic>{
          'activity_id': remoteId,
          'split_number': split.index,
          'distance_meters': split.unitDistanceMeters,
          'duration_seconds': split.splitDuration.inSeconds,
          'avg_pace_seconds_per_km': split.pace?.inMilliseconds == null
              ? null
              : split.pace!.inMilliseconds / 1000,
          'elevation_change_meters': null,
        };
      })
      .toList(growable: false);
}

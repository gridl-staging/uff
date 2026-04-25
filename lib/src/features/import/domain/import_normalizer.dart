import 'package:uff/src/features/activity_tracking/domain/activity_summary.dart';
import 'package:uff/src/features/activity_tracking/domain/point_cleanup.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/import/domain/imported_activity.dart';

/// Converts raw [ParsedActivityData] from any format-specific parser into a
/// normalized [ImportedActivity] using the shared activity-tracking pipeline.
///
/// This is the sole entry point for imported data into the domain pipeline,
/// ensuring one source of truth for cleaned points, summary metrics, and splits
/// across both import formats and live recording.
ImportedActivity normalizeImportedActivity(ParsedActivityData parsed) {
  if (parsed.points.isEmpty) {
    throw const FormatException(
      'Cannot normalize activity: no GPS points in parsed data',
    );
  }

  final rawTrackingPoints = _convertToTrackingPoints(parsed.points);
  final cleanupResult = cleanTrackingPoints(rawTrackingPoints);
  final cleanedPoints = cleanupResult.cleanedPoints;

  if (cleanedPoints.isEmpty) {
    throw const FormatException(
      'Cannot normalize activity: all points were dropped during cleanup',
    );
  }

  final parsedTimeBounds = _resolveParsedTimeBounds(parsed.points);
  final startedAt = parsed.startedAt ?? parsedTimeBounds.startedAt;
  final finishedAt = parsed.finishedAt ?? parsedTimeBounds.finishedAt;

  final session = TrackingSessionRecord(
    id: 0,
    status: TrackingSessionStatus.stopped,
    createdAt: startedAt,
    updatedAt: startedAt,
    startedAt: startedAt,
    stoppedAt: finishedAt,
  );

  final metrics = calculateProcessedActivityMetrics(
    session: session,
    cleanedPoints: cleanedPoints,
  );

  return ImportedActivity(
    sportType: parsed.sportType,
    title: parsed.title,
    startedAt: startedAt,
    finishedAt: finishedAt,
    cleanedPoints: cleanedPoints,
    metrics: metrics,
  );
}

List<TrackingPoint> _convertToTrackingPoints(List<ImportedPoint> imported) {
  return imported
      .map(
        (point) => TrackingPoint(
          sessionId: 0,
          timestamp: point.timestamp,
          coordinate: GeoCoordinate(
            latitude: point.latitude,
            longitude: point.longitude,
          ),
          elevation: point.elevation,
          speed: point.speed,
          heartRateBpm: point.heartRateBpm,
          cadenceRpm: point.cadenceRpm,
          powerWatts: point.powerWatts,
        ),
      )
      .toList(growable: false);
}

({DateTime startedAt, DateTime finishedAt}) _resolveParsedTimeBounds(
  List<ImportedPoint> points,
) {
  var startedAt = points.first.timestamp;
  var finishedAt = points.first.timestamp;

  for (final point in points.skip(1)) {
    if (point.timestamp.isBefore(startedAt)) {
      startedAt = point.timestamp;
    }
    if (point.timestamp.isAfter(finishedAt)) {
      finishedAt = point.timestamp;
    }
  }

  return (startedAt: startedAt, finishedAt: finishedAt);
}

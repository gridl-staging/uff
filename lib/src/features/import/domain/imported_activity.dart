import 'package:meta/meta.dart';

import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

/// Raw point extracted by a format-specific parser (FIT or GPX).
///
/// Exists only at the parser boundary — it is not the persisted or normalized
/// activity point model. The shared normalizer converts these into
/// [TrackingPoint] for pipeline processing.
@immutable
class ImportedPoint {
  const ImportedPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.elevation,
    this.speed,
    this.heartRateBpm,
    this.cadenceRpm,
    this.powerWatts,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? elevation;
  final double? speed;
  final int? heartRateBpm;
  final double? cadenceRpm;
  final int? powerWatts;
}

/// Raw parser output — sport type, optional metadata, and raw imported points.
/// No computed metrics. Both FIT and GPX parsers produce this type.
@immutable
class ParsedActivityData {
  const ParsedActivityData({
    required this.sportType,
    required this.points,
    this.title,
    this.startedAt,
    this.finishedAt,
  });

  final String sportType;
  final List<ImportedPoint> points;
  final String? title;
  final DateTime? startedAt;
  final DateTime? finishedAt;
}

/// Normalized output from the shared normalizer. Contains the cleaned
/// [TrackingPoint] list that Stage 6 will persist, plus pre-computed
/// [ProcessedActivityMetrics] from the shared pipeline.
@immutable
class ImportedActivity {
  const ImportedActivity({
    required this.sportType,
    required this.startedAt,
    required this.finishedAt,
    required this.cleanedPoints,
    required this.metrics,
    this.title,
  });

  final String sportType;
  final DateTime startedAt;
  final DateTime finishedAt;
  final List<TrackingPoint> cleanedPoints;
  final ProcessedActivityMetrics metrics;
  final String? title;
}

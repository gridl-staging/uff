import 'package:meta/meta.dart';
import 'package:uff/src/features/social/domain/remote_activity_track_point.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';

/// Remote split row from `public.splits` for activity detail rendering.
@immutable
class SocialActivitySplit {
  const SocialActivitySplit({
    required this.splitNumber,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.avgPaceSecondsPerKm,
    required this.avgHeartRate,
    required this.elevationChangeMeters,
  });

  final int splitNumber;
  final double distanceMeters;
  final int durationSeconds;
  final double? avgPaceSecondsPerKm;
  final int? avgHeartRate;
  final double? elevationChangeMeters;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SocialActivitySplit &&
          runtimeType == other.runtimeType &&
          splitNumber == other.splitNumber &&
          distanceMeters == other.distanceMeters &&
          durationSeconds == other.durationSeconds &&
          avgPaceSecondsPerKm == other.avgPaceSecondsPerKm &&
          avgHeartRate == other.avgHeartRate &&
          elevationChangeMeters == other.elevationChangeMeters;

  @override
  int get hashCode => Object.hash(
    splitNumber,
    distanceMeters,
    durationSeconds,
    avgPaceSecondsPerKm,
    avgHeartRate,
    elevationChangeMeters,
  );
}

/// Detailed remote activity payload for social detail screens.
@immutable
class SocialActivityDetail {
  const SocialActivityDetail({
    required this.activityId,
    required this.owner,
    required this.sportType,
    required this.startedAt,
    required this.finishedAt,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.elevationGainMeters,
    required this.avgPaceSecondsPerKm,
    required this.title,
    required this.description,
    required this.visibility,
    required this.polylineEncoded,
    required this.kudosCount,
    required this.viewerHasKudo,
    required this.splits,
    required this.trackPoints,
  });

  final String activityId;
  final SocialUserSummary owner;
  final String sportType;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final double distanceMeters;
  final int durationSeconds;
  final double? elevationGainMeters;
  final double? avgPaceSecondsPerKm;
  final String? title;
  final String? description;
  final String visibility;
  final String? polylineEncoded;
  final int kudosCount;
  final bool viewerHasKudo;
  final List<SocialActivitySplit> splits;
  final List<RemoteActivityTrackPoint> trackPoints;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SocialActivityDetail &&
          runtimeType == other.runtimeType &&
          activityId == other.activityId &&
          owner == other.owner &&
          sportType == other.sportType &&
          startedAt == other.startedAt &&
          finishedAt == other.finishedAt &&
          distanceMeters == other.distanceMeters &&
          durationSeconds == other.durationSeconds &&
          elevationGainMeters == other.elevationGainMeters &&
          avgPaceSecondsPerKm == other.avgPaceSecondsPerKm &&
          title == other.title &&
          description == other.description &&
          visibility == other.visibility &&
          polylineEncoded == other.polylineEncoded &&
          kudosCount == other.kudosCount &&
          viewerHasKudo == other.viewerHasKudo &&
          _listEquals(splits, other.splits) &&
          _listEquals(trackPoints, other.trackPoints);

  @override
  int get hashCode => Object.hash(
    activityId,
    owner,
    sportType,
    startedAt,
    finishedAt,
    distanceMeters,
    durationSeconds,
    elevationGainMeters,
    avgPaceSecondsPerKm,
    title,
    description,
    visibility,
    polylineEncoded,
    kudosCount,
    viewerHasKudo,
    Object.hashAll(splits),
    Object.hashAll(trackPoints),
  );
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

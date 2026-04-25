import 'package:meta/meta.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';

/// Read model for social feed and profile activity list rows.
@immutable
class SocialActivitySummary {
  SocialActivitySummary({
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
    required this.commentCount,
    required this.kudosCount,
    required this.viewerHasKudo,
    List<RoutePoint>? routePoints,
  }) : _routePoints = routePoints == null
           ? null
           : List<RoutePoint>.unmodifiable(routePoints);

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
  // Owners keep their stored summary polyline for feed/profile previews.
  final String? polylineEncoded;
  // Non-owners use backend-masked route points from read_activity_track_points.
  final List<RoutePoint>? _routePoints;
  List<RoutePoint>? get routePoints => _routePoints;
  final int commentCount;
  final int kudosCount;
  final bool viewerHasKudo;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SocialActivitySummary &&
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
          _listEquals(_routePoints, other._routePoints) &&
          commentCount == other.commentCount &&
          kudosCount == other.kudosCount &&
          viewerHasKudo == other.viewerHasKudo;

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
    Object.hashAll(_routePoints ?? const <RoutePoint>[]),
    commentCount,
    kudosCount,
    viewerHasKudo,
  );
}

bool _listEquals<T>(List<T>? left, List<T>? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

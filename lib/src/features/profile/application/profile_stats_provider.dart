import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

/// TODO: Document ProfileStats.
@immutable
class ProfileStats {
  const ProfileStats({
    required this.totalDistanceMeters,
    required this.activityCount,
    required this.activitiesThisMonth,
  });

  static const empty = ProfileStats(
    totalDistanceMeters: 0,
    activityCount: 0,
    activitiesThisMonth: 0,
  );

  final double totalDistanceMeters;
  final int activityCount;
  final int activitiesThisMonth;

  @override
  bool operator ==(Object other) {
    return other is ProfileStats &&
        other.totalDistanceMeters == totalDistanceMeters &&
        other.activityCount == activityCount &&
        other.activitiesThisMonth == activitiesThisMonth;
  }

  @override
  int get hashCode =>
      Object.hash(totalDistanceMeters, activityCount, activitiesThisMonth);
}

final FutureProvider<ProfileStats> profileStatsProvider =
    FutureProvider.autoDispose<ProfileStats>((ref) async {
      final sessions = await ref.watch(savedActivitiesProvider.future);
      return _computeStats(sessions);
    });

ProfileStats _computeStats(List<TrackingSessionRecord> sessions) {
  final saved = sessions
      .where((s) => s.status == TrackingSessionStatus.saved)
      .toList();
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month);
  var totalDistance = 0.0;
  var thisMonth = 0;
  for (final session in saved) {
    totalDistance += session.distanceMeters ?? 0;
    if (session.stoppedAt != null && !session.stoppedAt!.isBefore(monthStart)) {
      thisMonth++;
    }
  }
  return ProfileStats(
    totalDistanceMeters: totalDistance,
    activityCount: saved.length,
    activitiesThisMonth: thisMonth,
  );
}

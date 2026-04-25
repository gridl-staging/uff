import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_repository.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart'
    show generateDefaultActivityTitle;

/// Finalizes a stopped draft session into a saved activity and queues it for
/// sync using the same summary-calculation contract as the recording screen.
Future<int> finalizeDraftActivity({
  required TrackingRepository repository,
  required SyncService syncService,
  required TrackingSessionRecord session,
  required List<TrackingPoint> cleanedPoints,
}) async {
  final processedMetrics = calculateProcessedActivityMetrics(
    session: session,
    cleanedPoints: cleanedPoints,
  );
  final persistedDuration = calculatePersistedActivityDuration(
    session: session,
    processedMovingTime: processedMetrics.trackSummary.movingTime,
  );
  final autoTitle = session.title == null || session.title!.trim().isEmpty
      ? generateDefaultActivityTitle(
          startedAt: session.startedAt ?? session.createdAt,
          sportType: session.sportType,
        )
      : null;
  final summaryUpdates = TrackingSessionRecordUpdates(
    distanceMeters: processedMetrics.trackSummary.distanceMeters,
    movingTimeSeconds: persistedDuration.inSeconds,
    elevationGainMeters: processedMetrics.trackSummary.elevationGainMeters,
    title: autoTitle,
  );
  final sessionWithSummary = session.copyWith(
    status: TrackingSessionStatus.saving,
    updates: summaryUpdates,
    updatedAt: DateTime.now(),
  );

  await repository.saveSession(sessionWithSummary);
  await repository.finalizeSession(session.id);
  await syncService.queueForSync(session.id);
  return session.id;
}

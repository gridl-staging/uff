import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:meta/meta.dart';
import 'package:uff/src/core/units/preferred_units.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/gear/application/gear_providers.dart';
import 'package:uff/src/features/gear/domain/gear_item.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';

@immutable
class ActivityDetailData {
  const ActivityDetailData({
    required this.session,
    required this.cleanedPoints,
    required this.processedMetrics,
  });

  final TrackingSessionRecord session;
  final List<TrackingPoint> cleanedPoints;
  final ProcessedActivityMetrics processedMetrics;
}

/// TODO: Document ActivityDetailGearState.
@immutable
class ActivityDetailGearState {
  const ActivityDetailGearState._({
    required this.isEditable,
    required this.selectableGear,
    required this.selectedGearId,
    required this.hasStaleAssignedGear,
    this.remoteActivityId,
    this.nonEditableMessage,
  });

  const ActivityDetailGearState.editable({
    required String remoteActivityId,
    required List<GearItem> selectableGear,
    required String? selectedGearId,
    required bool hasStaleAssignedGear,
  }) : this._(
         isEditable: true,
         remoteActivityId: remoteActivityId,
         selectableGear: selectableGear,
         selectedGearId: selectedGearId,
         hasStaleAssignedGear: hasStaleAssignedGear,
       );

  const ActivityDetailGearState.nonEditable({
    required String message,
    required List<GearItem> selectableGear,
  }) : this._(
         isEditable: false,
         nonEditableMessage: message,
         selectableGear: selectableGear,
         selectedGearId: null,
         hasStaleAssignedGear: false,
       );

  final bool isEditable;
  final String? remoteActivityId;
  final String? nonEditableMessage;
  final List<GearItem> selectableGear;
  final String? selectedGearId;
  final bool hasStaleAssignedGear;

  // Default returned when the provider is disposed or the activity is missing.
  static const notFound = ActivityDetailGearState.nonEditable(
    message: 'Activity not found.',
    selectableGear: <GearItem>[],
  );
}

final FutureProvider<List<TrackingSessionRecord>> savedActivitiesProvider =
    FutureProvider.autoDispose<List<TrackingSessionRecord>>((ref) async {
      final repository = ref.read(trackingRepositoryProvider);
      return repository.loadSavedSessions();
    });

final FutureProviderFamily<ActivityDetailData?, int> activityDetailProvider =
    FutureProvider.autoDispose.family<ActivityDetailData?, int>(
      (ref, int sessionId) async {
        final repository = ref.read(trackingRepositoryProvider);
        final session = await repository.loadSession(sessionId);
        if (session == null) {
          return null;
        }

        final profile = await ref.watch(profileProvider.future);
        final rawPoints = await repository.loadPointsForSession(sessionId);
        final cleanedPoints = cleanTrackingPoints(rawPoints).cleanedPoints;
        final processedMetrics = calculateProcessedActivityMetrics(
          session: session,
          cleanedPoints: cleanedPoints,
          splitUnit: splitUnitForPreferredUnits(profile?.preferredUnits),
        );

        return ActivityDetailData(
          session: session,
          cleanedPoints: cleanedPoints,
          processedMetrics: processedMetrics,
        );
      },
    );

final FutureProviderFamily<SyncQueueEntry?, int> activitySyncEntryProvider =
    FutureProvider.autoDispose.family<SyncQueueEntry?, int>((
      ref,
      int sessionId,
    ) async {
      final repository = ref.read(trackingRepositoryProvider);
      return repository.loadSyncQueueEntry(sessionId);
    });

final FutureProviderFamily<ActivityDetailGearState, int>
activityDetailGearProvider = FutureProvider.autoDispose
    .family<ActivityDetailGearState, int>((ref, int sessionId) async {
      final detail = await ref.watch(activityDetailProvider(sessionId).future);
      if (!ref.mounted || detail == null) {
        return ActivityDetailGearState.notFound;
      }

      final selectableGear = _filterSelectableGear(
        await ref.watch(gearListProvider.future),
      );
      if (!ref.mounted) {
        return ActivityDetailGearState.notFound;
      }
      final remoteActivityId = detail.session.remoteId;
      if (remoteActivityId == null) {
        return ActivityDetailGearState.nonEditable(
          message: 'Gear can be assigned after this activity syncs.',
          selectableGear: selectableGear,
        );
      }

      final assignmentRepository = ref.read(
        activityGearAssignmentRepositoryProvider,
      );
      final assignedGearId = await assignmentRepository.loadAssignedGearId(
        remoteActivityId,
      );
      String? selectedGearId;
      for (final item in selectableGear) {
        if (item.id == assignedGearId) {
          selectedGearId = item.id;
          break;
        }
      }

      return ActivityDetailGearState.editable(
        remoteActivityId: remoteActivityId,
        selectableGear: selectableGear,
        selectedGearId: selectedGearId,
        hasStaleAssignedGear: assignedGearId != null && selectedGearId == null,
      );
    });

List<GearItem> _filterSelectableGear(List<GearItem> gearItems) {
  return gearItems
      .where(
        (item) =>
            !item.retired &&
            (item.gearType == GearType.shoe || item.gearType == GearType.bike),
      )
      .toList(growable: false);
}

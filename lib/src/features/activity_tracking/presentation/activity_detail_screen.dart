import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/core/presentation/discard_changes_dialog.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_unresolved_views.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_deletion_helper.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_analytics_section.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_metadata_card.dart';
import 'package:uff/src/features/gear/application/gear_providers.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';
import 'package:uff/src/features/maps/presentation/map_view.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart';
import 'package:uff/src/features/photos/data/photo_picker_service.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';
import 'package:uff/src/features/photos/presentation/activity_photo_gallery_section.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/social/application/social_kudos_providers.dart';
import 'package:uff/src/features/social/presentation/activity_comments_section.dart';

part 'activity_detail_screen_gear.dart';
part 'activity_detail_screen_photos.dart';

// NOTE(stuart): Document ActivityDetailScreen.
/// TODO: Document ActivityDetailScreen.
class ActivityDetailScreen extends ConsumerStatefulWidget {
  const ActivityDetailScreen({required this.activityId, super.key});

  static const Key titleFieldKey = ActivityMetadataCard.titleFieldKey;
  static const Key descriptionFieldKey =
      ActivityMetadataCard.descriptionFieldKey;
  static const Key saveButtonKey = ActivityMetadataCard.saveButtonKey;
  static const distanceValueTextKey = Key('detail_distance_value_text');
  static const durationValueTextKey = Key('detail_duration_value_text');
  static const paceValueTextKey = Key('detail_pace_value_text');
  static const elevationValueTextKey = Key('detail_elevation_value_text');
  static const splitsTableKey = Key('detail_splits_table');
  static const Key detailRetryButtonKey = activityDetailRetryButtonKey;
  static const Key detailErrorMessageKey = activityDetailErrorMessageKey;
  static const gearDropdownKey = Key('detail_gear_dropdown');
  static const gearRetryButtonKey = Key('detail_gear_retry_button');
  static const Key visibilitySegmentedButtonKey =
      ActivityMetadataCard.visibilitySegmentedButtonKey;
  static const photoSectionKey = Key('detail_photo_section');
  static const photoUnsyncedMessageKey = Key('detail_photo_unsynced_message');
  static const photoEmptyStateKey = Key('detail_photo_empty_state');
  static const photoAddButtonKey = Key('detail_photo_add_button');
  static const photoSourceSheetKey = Key('detail_photo_source_sheet');
  static const photoSourceGalleryOptionKey = Key(
    'detail_photo_source_gallery_option',
  );
  static const photoSourceCameraOptionKey = Key(
    'detail_photo_source_camera_option',
  );
  static const photoViewerKey = Key('detail_photo_viewer');
  static const photoViewerUnavailableKey = Key(
    'detail_photo_viewer_unavailable',
  );
  static const photoViewerDeleteButtonKey = Key('detail_photo_delete_button');
  static const photoViewerShareButtonKey = Key('detail_photo_share_button');
  static const photoViewerShareLoadingKey = Key('detail_photo_share_loading');
  static const photoDeleteConfirmKey = Key('detail_photo_delete_confirm');
  static const ownerKudosSectionKey = Key('detail_owner_kudos_section');
  static const ownerKudosCountTextKey = Key('detail_owner_kudos_count_text');
  static const ownerKudosToggleButtonKey = Key(
    'detail_owner_kudos_toggle_button',
  );
  // Keep the legacy draft-save key available while the e2e suite finishes
  // migrating to ActivityReviewScreen-specific constants.
  static const Key draftSaveButtonKey = ActivityMetadataCard.saveButtonKey;
  static const overflowMenuButtonKey = Key('detail_overflow_button');
  static const editButtonKey = Key('detail_edit_button');
  static const deleteButtonKey = Key('detail_delete_button');
  static const cancelButtonKey = Key('detail_cancel_button');
  static const deleteConfirmDialogKey = Key('detail_delete_confirm_dialog');
  static const deleteConfirmButtonKey = Key('detail_delete_confirm_button');
  static const deleteCancelButtonKey = Key('detail_delete_cancel_button');
  static const deleteProgressIndicatorKey = Key(
    'detail_delete_progress_indicator',
  );
  static const routeMapBoundaryKey = Key('detail_route_map_boundary');
  static const visibilityBadgeKey = Key('detail_visibility_badge');
  static const notesSectionKey = Key('detail_notes_section');

  static Key photoThumbnailKey(String photoId) {
    return Key('detail_photo_thumbnail_$photoId');
  }

  static Key photoUploadMutationTileKey(String uploadMutationId) {
    return Key('detail_photo_upload_$uploadMutationId');
  }

  static Key photoUploadMutationErrorKey(String uploadMutationId) {
    return Key('detail_photo_upload_error_$uploadMutationId');
  }

  static Key photoDeleteMutationErrorKey(String photoId) {
    return Key('detail_photo_delete_error_$photoId');
  }

  static Key photoViewerImageKey(String photoId) {
    return Key('detail_photo_viewer_image_$photoId');
  }

  final int activityId;

  @override
  ConsumerState<ActivityDetailScreen> createState() =>
      _ActivityDetailScreenState();
}

// NOTE(stuart): Document _ActivityDetailScreenState.
/// TODO: Document _ActivityDetailScreenState.
class _ActivityDetailScreenState extends ConsumerState<ActivityDetailScreen> {
  final GlobalKey<ActivityMetadataCardState> _metadataCardKey =
      GlobalKey<ActivityMetadataCardState>();
  bool _isEditingDetails = false;
  bool _isSavingGearAssignment = false;
  bool _isDeletingActivity = false;

  ActivityMetadataCardState? get _metadataCardState =>
      _metadataCardKey.currentState;

  bool get _isSavingMetadata => _metadataCardState?.isSaving ?? false;

  bool get _hasBlockingMutation =>
      _isSavingGearAssignment || _isDeletingActivity;

  bool get _canPop =>
      !_isEditingDetails && !_isSavingMetadata && !_hasBlockingMutation;

  @override
  Widget build(BuildContext context) {
    final detailState = ref.watch<AsyncValue<ActivityDetailData?>>(
      activityDetailProvider(widget.activityId),
    );
    final detail = detailState.asData?.value;

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: _handlePopInvoked,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_appBarTitle(detail)),
          actions: detail == null || _isEditingDetails
              ? null
              : <Widget>[_buildOverflowMenu()],
        ),
        body: Stack(
          children: [
            detailState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => ActivityDetailRetryableMessage(
                message: 'Unable to load activity detail. Please try again.',
                onRetry: _reloadDetail,
              ),
              data: (ActivityDetailData? detail) {
                if (detail == null) {
                  return _buildActivityNotFoundState(context);
                }

                final gearState = ref.watch(
                  activityDetailGearProvider(widget.activityId),
                );
                return _buildActivityContent(context, detail, gearState);
              },
            ),
            if (_isDeletingActivity)
              const Positioned.fill(
                child: AbsorbPointer(
                  child: ColoredBox(
                    color: Colors.black26,
                    child: Center(
                      child: SizedBox(
                        key: ActivityDetailScreen.deleteProgressIndicatorKey,
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityContent(
    BuildContext context,
    ActivityDetailData detail,
    AsyncValue<ActivityDetailGearState> gearState,
  ) {
    final preferredUnits = ref
        .watch(profileProvider)
        .asData
        ?.value
        ?.preferredUnits;
    final metricRows = _buildMetricRows(
      detail.processedMetrics,
      preferredUnits: preferredUnits,
    );
    final splitRows = _buildSplitRows(detail.processedMetrics.splits);

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final photoResult = _resolveSortedSyncedPhotos(detail);
    final markerTapHandler = _buildPhotoMarkerTapHandler(context, photoResult);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      children: [
        _buildRouteMap(
          detail.cleanedPoints,
          photoMarkers: _photoMarkersFromResult(photoResult),
          onPhotoMarkerTapped: markerTapHandler,
        ),
        const SizedBox(height: 12),
        _buildSummaryCard(context, metricRows),
        const SizedBox(height: 12),
        _buildMetadataSection(detail),
        if (_shouldRenderPhotoSection(photoResult)) ...[
          const SizedBox(height: 12),
          _buildPhotoGallerySection(context, photoResult),
        ],
        const SizedBox(height: 12),
        _buildSplitsCard(context, splitRows),
        const SizedBox(height: 12),
        ActivityAnalyticsSection(activityId: widget.activityId),
        if (_shouldRenderGearSection(gearState)) ...[
          const SizedBox(height: 12),
          _buildGearAssignmentCard(context, gearState),
        ],
        const SizedBox(height: 12),
        _buildOwnerKudosSection(detail.session.remoteId),
        if (detail.session.remoteId case final String remoteId) ...[
          const SizedBox(height: 12),
          ActivityCommentsSection(activityId: remoteId),
        ],
        if (_isEditingDetails) ...[
          const SizedBox(height: 12),
          _buildEditActions(),
        ],
      ],
    );
  }

  ValueChanged<String>? _buildPhotoMarkerTapHandler(
    BuildContext context,
    _SortedSyncedPhotosResult photoResult,
  ) {
    if (!photoResult.isSynced) {
      return null;
    }

    return (String photoId) {
      final photo = photoResult.sortedPhotos
          ?.where((candidate) => candidate.id == photoId)
          .firstOrNull;
      if (photo == null) {
        return;
      }
      _openPhotoViewer(
        context,
        photoResult.remoteActivityId,
        photo,
        allowDelete: _isEditingDetails,
      );
    };
  }

  String _appBarTitle(ActivityDetailData? detail) =>
      _normalizedMetadataText(detail?.session.title) ?? 'Activity Detail';

  Widget _buildOverflowMenu() {
    return PopupMenuButton<_ActivityDetailMenuAction>(
      key: ActivityDetailScreen.overflowMenuButtonKey,
      onSelected: (action) {
        switch (action) {
          case _ActivityDetailMenuAction.edit:
            _enterEditMode();
            return;
          case _ActivityDetailMenuAction.delete:
            _showDeleteConfirmation();
            return;
        }
      },
      itemBuilder: (context) =>
          const <PopupMenuEntry<_ActivityDetailMenuAction>>[
            PopupMenuItem<_ActivityDetailMenuAction>(
              key: ActivityDetailScreen.editButtonKey,
              value: _ActivityDetailMenuAction.edit,
              child: Text('Edit'),
            ),
            PopupMenuItem<_ActivityDetailMenuAction>(
              key: ActivityDetailScreen.deleteButtonKey,
              value: _ActivityDetailMenuAction.delete,
              child: Text('Delete'),
            ),
          ],
      icon: const Icon(Icons.more_vert),
    );
  }

  Widget _buildSummaryCard(BuildContext context, List<Widget> metricRows) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...metricRows,
          ],
        ),
      ),
    );
  }

  Widget _buildSplitsCard(BuildContext context, List<DataRow> splitRows) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Splits', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (splitRows.isEmpty)
              Text(
                'Not enough distance to compute splits.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  key: ActivityDetailScreen.splitsTableKey,
                  columns: const [
                    DataColumn(label: Text('Split')),
                    DataColumn(label: Text('Time')),
                    DataColumn(label: Text('Pace')),
                  ],
                  rows: splitRows,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataSection(ActivityDetailData detail) {
    if (_isEditingDetails) {
      return ActivityMetadataCard(
        key: _metadataCardKey,
        detail: detail,
        showInlineSaveButton: false,
        onSaved: () {
          _showSnackBarMessage('Activity notes updated.');
        },
        onPendingChangesChanged: _handleMetadataPendingChangesChanged,
      );
    }

    return _buildReadOnlyMetadataCard(detail);
  }

  Widget _buildReadOnlyMetadataCard(ActivityDetailData detail) {
    final description = _normalizedMetadataText(detail.session.description);
    final visibilityLabel = _visibilityLabel(detail.session.visibility);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  visibilityLabel,
                  key: ActivityDetailScreen.visibilityBadgeKey,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: 12),
              Text('Notes', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                description,
                key: ActivityDetailScreen.notesSectionKey,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEditActions() {
    final metadataCardState = _metadataCardState;
    final canSaveMetadata =
        (metadataCardState?.canSave ?? false) && !_hasBlockingMutation;
    final canCancelEditing = !_isSavingMetadata && !_hasBlockingMutation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          key: ActivityDetailScreen.saveButtonKey,
          onPressed: canSaveMetadata ? _saveMetadataChanges : null,
          child: _isSavingMetadata
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save changes'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: ActivityDetailScreen.cancelButtonKey,
          onPressed: canCancelEditing ? _cancelEditing : null,
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildOwnerKudosSection(String? remoteActivityId) {
    if (remoteActivityId == null) {
      return const SizedBox.shrink();
    }

    final kudosAsync = ref.watch(activityKudosProvider(remoteActivityId));
    return Card(
      key: ActivityDetailScreen.ownerKudosSectionKey,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: kudosAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Unable to load kudos.'),
          data: (kudos) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.favorite_border, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '${kudos.kudosCount}',
                      key: ActivityDetailScreen.ownerKudosCountTextKey,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (kudos.users.isEmpty)
                  const Text('No kudos yet.')
                else
                  ...kudos.users.map(
                    (user) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(user.displayName ?? user.userId),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRouteMap(
    List<TrackingPoint> points, {
    List<PhotoMarkerInput> photoMarkers = const [],
    ValueChanged<String>? onPhotoMarkerTapped,
  }) {
    return SizedBox(
      key: ActivityDetailScreen.routeMapBoundaryKey,
      height: 260,
      child: MapView(
        routePoints: toRoutePoints(points),
        photoMarkers: photoMarkers,
        onPhotoMarkerTapped: onPhotoMarkerTapped,
        // Keep map-started drags owned by the platform view.
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
      ),
    );
  }

  List<Widget> _buildMetricRows(
    ProcessedActivityMetrics metrics, {
    required String? preferredUnits,
  }) {
    return [
      metricDetailRow(
        'Distance',
        formatDistance(
          metrics.trackSummary.distanceMeters,
          preferredUnits: preferredUnits,
        ),
        valueKey: ActivityDetailScreen.distanceValueTextKey,
      ),
      metricDetailRow(
        'Duration',
        formatDuration(metrics.trackSummary.movingTime),
        valueKey: ActivityDetailScreen.durationValueTextKey,
      ),
      metricDetailRow(
        'Avg pace',
        formatPaceForPreferredUnits(
          pacePerKilometer: metrics.trackSummary.averagePace.perKilometer,
          pacePerMile: metrics.trackSummary.averagePace.perMile,
          preferredUnits: preferredUnits,
        ),
        valueKey: ActivityDetailScreen.paceValueTextKey,
      ),
      metricDetailRow(
        'Elevation gain',
        formatElevation(
          metrics.trackSummary.elevationGainMeters,
          preferredUnits: preferredUnits,
        ),
        valueKey: ActivityDetailScreen.elevationValueTextKey,
      ),
    ];
  }

  List<DataRow> _buildSplitRows(List<ActivitySplit> splits) {
    return splits
        .map(
          (split) => DataRow(
            cells: [
              DataCell(Text(split.index.toString())),
              DataCell(Text(formatDuration(split.splitDuration))),
              DataCell(Text(formatPaceForUnit(split.pace, split.unit))),
            ],
          ),
        )
        .toList(growable: false);
  }

  Future<void> _handlePopInvoked(bool didPop, Object? result) async {
    if (didPop) {
      return;
    }
    final metadataCardState = _metadataCardState;
    if (!_isEditingDetails || _isSavingMetadata || _hasBlockingMutation) {
      return;
    }

    final hasPendingMetadataChanges =
        metadataCardState?.hasPendingChanges ?? false;
    if (hasPendingMetadataChanges) {
      final shouldDiscard = await showDiscardChangesDialog(context);
      if (!shouldDiscard || !mounted) {
        return;
      }
    }

    _exitEditMode();
  }

  void _handleMetadataPendingChangesChanged(bool _) {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showDeleteConfirmation() async {
    if (_isDeletingActivity) {
      return;
    }

    final confirmed = await confirmActivityDeletion(
      context,
      dialogKey: ActivityDetailScreen.deleteConfirmDialogKey,
      cancelButtonKey: ActivityDetailScreen.deleteCancelButtonKey,
      confirmButtonKey: ActivityDetailScreen.deleteConfirmButtonKey,
    );
    if (!confirmed) {
      return;
    }

    await _deleteActivity();
  }

  Future<void> _deleteActivity() async {
    if (_isDeletingActivity) {
      return;
    }

    setState(() {
      _isDeletingActivity = true;
    });

    // Read detail before deletion so we know the remoteId.
    final detail = ref.read(activityDetailProvider(widget.activityId)).value;
    final sessionForDeletion =
        detail?.session ??
        TrackingSessionRecord(
          id: widget.activityId,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
    final didDelete = await performActivityDeletion(ref, sessionForDeletion);
    if (!mounted) {
      return;
    }

    if (didDelete) {
      _leaveDetailScreen();
    } else {
      setState(() {
        _isDeletingActivity = false;
      });
      showActivityDeletionFailureSnackBar(context);
    }
  }

  void _enterEditMode() {
    if (mounted) {
      setState(() {
        _isEditingDetails = true;
      });
    }
  }

  Future<void> _saveMetadataChanges() async {
    final metadataCardState = _metadataCardState;
    if (metadataCardState == null || !metadataCardState.canSave) {
      return;
    }

    final didSave = await metadataCardState.saveMetadata();
    if (!mounted || !didSave) {
      return;
    }

    _exitEditMode();
  }

  void _exitEditMode() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isEditingDetails = false;
    });
  }

  void _cancelEditing() {
    if (_isSavingMetadata) {
      return;
    }
    _exitEditMode();
  }

  bool _shouldRenderPhotoSection(_SortedSyncedPhotosResult photoResult) {
    if (_isEditingDetails) {
      return true;
    }
    if (!photoResult.isSynced) {
      return true;
    }
    return photoResult.isLoading ||
        photoResult.loadingError != null ||
        (photoResult.sortedPhotos?.isNotEmpty ?? false) ||
        photoResult.controllerState.uploadMutationsByLocalId.isNotEmpty;
  }

  bool _shouldRenderGearSection(AsyncValue<ActivityDetailGearState> gearState) {
    if (_isEditingDetails || gearState.isLoading || gearState.hasError) {
      return true;
    }
    final resolvedGearState = gearState.asData?.value;
    if (resolvedGearState == null) {
      return false;
    }
    if (!resolvedGearState.isEditable) {
      return resolvedGearState.nonEditableMessage != null;
    }
    return resolvedGearState.selectedGearId != null ||
        resolvedGearState.hasStaleAssignedGear;
  }

  void _showSnackBarMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildActivityNotFoundState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Activity not found.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Go back to the previous screen or try again if the activity was just restored.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _retryMissingActivityLookup,
              child: const Text('Try again'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _navigateBackFromMissingActivity,
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateBackFromMissingActivity() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    final router = GoRouter.maybeOf(context);
    router?.go('/home/activity');
  }

  void _retryMissingActivityLookup() {
    _reloadDetail();
  }

  void _reloadDetail() {
    ref.invalidate(activityDetailProvider(widget.activityId));
  }

  void _leaveDetailScreen() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go('/home/activity');
      return;
    }

    Navigator.of(context).pop();
  }
}

enum _ActivityDetailMenuAction { edit, delete }

String? _normalizedMetadataText(String? value) {
  final trimmedValue = value?.trim();
  if (trimmedValue == null || trimmedValue.isEmpty) {
    return null;
  }
  return trimmedValue;
}

String _visibilityLabel(String? visibility) {
  return switch (normalizeTrackingSessionVisibility(visibility)) {
    publicTrackingSessionVisibility => 'Public',
    followersTrackingSessionVisibility => 'Followers',
    privateTrackingSessionVisibility => 'Private',
    _ => 'Public',
  };
}

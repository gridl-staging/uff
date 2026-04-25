import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/draft_activity_actions.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_controller.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_metadata_card.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';
import 'package:uff/src/features/maps/presentation/map_view.dart';
import 'package:uff/src/features/photos/application/pending_photo_providers.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';

/// TODO: Document ActivityReviewScreen.
class ActivityReviewScreen extends ConsumerStatefulWidget {
  const ActivityReviewScreen({required this.detail, super.key});

  static const Key draftSaveButtonKey = ActivityMetadataCard.saveButtonKey;
  static const draftSaveButtonSemanticsId = 'review_save_run_button';
  static const discardDraftButtonKey = Key('detail_discard_button');
  static const draftReviewNoteKey = Key('detail_draft_review_note');
  static const distanceValueTextKey = Key('review_distance_value_text');
  static const durationValueTextKey = Key('review_duration_value_text');
  static const paceValueTextKey = Key('review_pace_value_text');
  static const elevationValueTextKey = Key('review_elevation_value_text');

  final ActivityDetailData detail;

  @override
  ConsumerState<ActivityReviewScreen> createState() =>
      _ActivityReviewScreenState();
}

/// TODO: Document _ActivityReviewScreenState.
class _ActivityReviewScreenState extends ConsumerState<ActivityReviewScreen> {
  final GlobalKey<ActivityMetadataCardState> _metadataCardKey =
      GlobalKey<ActivityMetadataCardState>();

  int? _lastMetadataSessionIdFromCard;
  int? _latestDetailSessionId;
  bool _isSavingDraftActivity = false;
  bool _isDiscardingDraftActivity = false;
  bool _allowNextPop = false;

  @override
  Widget build(BuildContext context) {
    _latestDetailSessionId = widget.detail.session.id;
    final detail = widget.detail;

    return PopScope(
      canPop: _allowNextPop,
      onPopInvokedWithResult: _handlePopInvoked,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Review Run'),
          automaticallyImplyLeading: false,
        ),
        body: _buildReviewContent(context, detail),
      ),
    );
  }

  Widget _buildReviewContent(BuildContext context, ActivityDetailData detail) {
    final preferredUnits = ref
        .watch(profileProvider)
        .asData
        ?.value
        ?.preferredUnits;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          height: 260,
          child: MapView(routePoints: toRoutePoints(detail.cleanedPoints)),
        ),
        const SizedBox(height: 12),
        ActivityMetadataCard(
          key: _metadataCardKey,
          detail: detail,
          showInlineSaveButton: false,
          onSaved: () {
            _showSnackBarMessage('Activity notes updated.');
          },
          onPendingChangesChanged: _handleMetadataPendingChangesChanged,
        ),
        const SizedBox(height: 12),
        _buildSummaryMetrics(context, detail, preferredUnits),
        const SizedBox(height: 12),
        _buildDraftReviewActions(detail),
      ],
    );
  }

  Widget _buildDraftReviewActions(ActivityDetailData detail) {
    final isPersistedSavingState =
        detail.session.status == TrackingSessionStatus.saving;
    // Both Save and Discard share this guard: disabled during any
    // in-flight save, discard, or metadata-card persistence operation.
    final canMutateDraft =
        !isPersistedSavingState &&
        !_isSavingDraftActivity &&
        !_isDiscardingDraftActivity &&
        !(_metadataCardKey.currentState?.isSaving ?? false);
    final saveDraftAction = canMutateDraft
        ? () => _saveDraftActivity(detail)
        : null;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Finish review',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose the title, notes, and visibility first. Saving here publishes this run with those settings.',
                key: ActivityReviewScreen.draftReviewNoteKey,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              // CTA hierarchy: Save is the primary action at full width and
              // Discard is secondary below it. Keep this card in the review
              // scroll content so users reach Save/Discard at the bottom of
              // the same surface as the summary metrics.
              Semantics(
                // Expose one explicit accessibility node so release-lane smoke
                // can find the final Save action deterministically even though
                // the CTA lives deep in a long review surface.
                container: true,
                button: true,
                enabled: canMutateDraft,
                identifier: ActivityReviewScreen.draftSaveButtonSemanticsId,
                label: 'Save Run',
                onTap: saveDraftAction,
                child: ExcludeSemantics(
                  child: ElevatedButton(
                    key: ActivityReviewScreen.draftSaveButtonKey,
                    onPressed: saveDraftAction,
                    child: _isSavingDraftActivity
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save Run'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: ActivityReviewScreen.discardDraftButtonKey,
                onPressed: canMutateDraft
                    ? () => _discardDraftActivity(detail)
                    : null,
                child: _isDiscardingDraftActivity
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Discard'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryMetrics(
    BuildContext context,
    ActivityDetailData detail,
    String? preferredUnits,
  ) {
    final metrics = detail.processedMetrics;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _detailRow(
              'Distance',
              formatDistance(
                metrics.trackSummary.distanceMeters,
                preferredUnits: preferredUnits,
              ),
              valueKey: ActivityReviewScreen.distanceValueTextKey,
            ),
            _detailRow(
              'Duration',
              formatDuration(metrics.trackSummary.movingTime),
              valueKey: ActivityReviewScreen.durationValueTextKey,
            ),
            _detailRow(
              'Avg pace',
              formatPaceForPreferredUnits(
                pacePerKilometer: metrics.trackSummary.averagePace.perKilometer,
                pacePerMile: metrics.trackSummary.averagePace.perMile,
                preferredUnits: preferredUnits,
              ),
              valueKey: ActivityReviewScreen.paceValueTextKey,
            ),
            _detailRow(
              'Elevation gain',
              formatElevation(
                metrics.trackSummary.elevationGainMeters,
                preferredUnits: preferredUnits,
              ),
              valueKey: ActivityReviewScreen.elevationValueTextKey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {Key? valueKey}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, key: valueKey),
        ],
      ),
    );
  }

  Future<void> _saveDraftActivity(ActivityDetailData detail) async {
    if (_isSavingDraftActivity || _isDiscardingDraftActivity) {
      return;
    }

    setState(() {
      _isSavingDraftActivity = true;
    });

    try {
      final metadataCardState = _metadataCardKey.currentState;
      final didSaveMetadata =
          !(metadataCardState?.hasPendingChanges ?? false) ||
          await (metadataCardState?.saveMetadata() ?? Future.value(true));
      if (!didSaveMetadata) {
        return;
      }

      final repository = ref.read(trackingRepositoryProvider);
      final syncService = ref.read(syncServiceProvider);
      final refreshedSession = await repository.loadSession(detail.session.id);
      if (refreshedSession == null) {
        // If the draft disappeared between review and save, refresh the route
        // state so the entry wrapper can surface the existing not-found UI.
        ref.invalidate(activityDetailProvider(detail.session.id));
        if (mounted) {
          _showSnackBarMessage('Activity not found.');
        }
        return;
      }
      if (!mounted) {
        return;
      }

      await finalizeDraftActivity(
        repository: repository,
        syncService: syncService,
        session: refreshedSession,
        cleanedPoints: detail.cleanedPoints,
      );
      ref
        ..invalidate(savedActivitiesProvider)
        ..invalidate(activityDetailProvider(detail.session.id))
        ..invalidate(recordingControllerProvider);
      _showSnackBarMessage('Activity saved.');
    } on Object {
      if (!mounted) {
        return;
      }
      _showSnackBarMessage('Unable to save. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSavingDraftActivity = false;
        });
      }
    }
  }

  Future<void> _discardDraftActivity(ActivityDetailData detail) async {
    if (_isSavingDraftActivity || _isDiscardingDraftActivity) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this run?'),
        content: const Text('The recorded data will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) != true || !mounted) {
      return;
    }

    setState(() {
      _isDiscardingDraftActivity = true;
    });

    try {
      final repository = ref.read(trackingRepositoryProvider);
      await repository.discardSession(detail.session.id);
      try {
        final pendingPhotoService = await ref.read(
          pendingPhotoServiceProvider.future,
        );
        await pendingPhotoService.discardPendingPhotos(detail.session.id);
      } on Object {
        if (mounted) {
          _showSnackBarMessage(
            'Run discarded, but pending photos could not be cleared.',
          );
        }
      }
      ref
        ..invalidate(savedActivitiesProvider)
        ..invalidate(activityDetailProvider(detail.session.id))
        ..invalidate(recordingControllerProvider);
      if (!mounted) {
        return;
      }
      setState(() {
        _allowNextPop = true;
      });
      final router = GoRouter.maybeOf(context);
      if (router != null) {
        router.go('/home/activity');
      } else {
        await Navigator.of(context).maybePop();
      }
    } on Object {
      if (!mounted) {
        return;
      }
      _showSnackBarMessage('Unable to discard activity. Please try again.');
      setState(() {
        _isDiscardingDraftActivity = false;
      });
    }
  }

  Future<void> _handlePopInvoked(bool didPop, Object? result) async {
    if (didPop) {
      return;
    }
    await _discardDraftActivity(widget.detail);
  }

  void _handleMetadataPendingChangesChanged(bool _) {
    final detailSessionId = _latestDetailSessionId;
    final didLoadNewSession =
        detailSessionId != null &&
        detailSessionId != _lastMetadataSessionIdFromCard;

    if (!mounted) {
      return;
    }

    setState(() {
      if (didLoadNewSession) {
        _lastMetadataSessionIdFromCard = detailSessionId;
        _allowNextPop = false;
      }
    });
  }

  void _showSnackBarMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

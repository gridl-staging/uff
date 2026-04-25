import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_unresolved_views.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_review_screen.dart';

/// TODO: Document ActivityEntryScreen.
class ActivityEntryScreen extends ConsumerWidget {
  const ActivityEntryScreen({required this.activityId, super.key});

  static const Key reviewBranchKey = Key('activity_entry_review_branch');
  static const Key detailBranchKey = Key('activity_entry_detail_branch');

  final int activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailState = ref.watch<AsyncValue<ActivityDetailData?>>(
      activityDetailProvider(activityId),
    );

    return detailState.when(
      loading: () => const ActivityDetailRouteScaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => ActivityDetailRouteScaffold(
        body: ActivityDetailRetryableMessage(
          message: 'Unable to load activity detail. Please try again.',
          onRetry: () {
            ref.invalidate(activityDetailProvider(activityId));
          },
        ),
      ),
      data: (ActivityDetailData? detail) {
        if (detail == null) {
          return ActivityDetailRouteScaffold(
            body: ActivityDetailRetryableMessage(
              message: 'Activity not found.',
              onRetry: () {
                ref.invalidate(activityDetailProvider(activityId));
              },
            ),
          );
        }

        // Runtime finalization follows stopped -> saving -> saved, driven by
        // draft_activity_actions.dart and tracking_repository.dart::finalizeSession.
        // The static transition validator in tracking_domain.dart currently
        // lists saving -> idle, but finalizeSession writes saved directly and
        // bypasses TrackingStateTransition.isAllowed. The wrapper keeps review
        // mounted for both draft statuses so the in-flight save UI is stable.
        final status = detail.session.status;
        switch (status) {
          case TrackingSessionStatus.stopped:
          case TrackingSessionStatus.saving:
            return KeyedSubtree(
              key: reviewBranchKey,
              child: ActivityReviewScreen(detail: detail),
            );
          case TrackingSessionStatus.saved:
            return KeyedSubtree(
              key: detailBranchKey,
              child: ActivityDetailScreen(activityId: activityId),
            );
          case TrackingSessionStatus.idle:
            // `idle` means there is no usable session behind `/activity/:id`.
            // Treat it like not-found instead of bouncing to another tab.
            return ActivityDetailRouteScaffold(
              body: ActivityDetailRetryableMessage(
                message: 'Activity not found.',
                onRetry: () {
                  ref.invalidate(activityDetailProvider(activityId));
                },
              ),
            );
          case TrackingSessionStatus.recording:
          case TrackingSessionStatus.paused:
            // Active sessions belong on the recorder surface. Redirect before
            // mounting detail/review UI because those screens assume recording
            // has already stopped.
            return const _ActivityEntryRedirectScreen(
              targetPath: '/home/record',
            );
          case TrackingSessionStatus.discarded:
            // Discarded drafts no longer have an activity surface to show, so
            // the user goes back to the activity tab instead of seeing a dead
            // `/activity/:id` route.
            return const _ActivityEntryRedirectScreen(
              targetPath: '/home/activity',
            );
        }
      },
    );
  }
}

class _ActivityEntryRedirectScreen extends StatefulWidget {
  const _ActivityEntryRedirectScreen({required this.targetPath});

  final String targetPath;

  @override
  State<_ActivityEntryRedirectScreen> createState() =>
      _ActivityEntryRedirectScreenState();
}

/// TODO: Document _ActivityEntryRedirectScreenState.
class _ActivityEntryRedirectScreenState
    extends State<_ActivityEntryRedirectScreen> {
  bool _hasScheduledRedirect = false;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (!_hasScheduledRedirect && router != null) {
      _hasScheduledRedirect = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        router.go(widget.targetPath);
      });
    }

    return const ActivityDetailRouteScaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

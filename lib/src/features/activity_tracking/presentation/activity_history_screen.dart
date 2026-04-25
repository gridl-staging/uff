import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/common_widgets/sport_type_icon.dart';
import 'package:uff/src/core/presentation/copyable_error_text.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/domain/track_metrics.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_deletion_helper.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_routes.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';

// TODO(uff): Document ActivityHistoryScreen.
/// TODO: Document ActivityHistoryScreen.
class ActivityHistoryScreen extends ConsumerWidget {
  const ActivityHistoryScreen({super.key});

  static const loadingStateKey = Key('activity_history_loading_state');
  static const loadingIndicatorKey = Key('activity_history_loading_indicator');
  static const emptyStateKey = Key('activity_history_empty_state');
  static const errorStateKey = Key('activity_history_error_state');
  static const retryButtonKey = Key('activity_history_retry_button');
  static const errorMessageKey = Key('activity_history_error_message');

  static Key activityCardKey(int sessionId) => Key('activity_card_$sessionId');
  static Key activityDismissibleKey(int sessionId) =>
      ValueKey<String>('activity_dismissible_$sessionId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedActivities = ref.watch(savedActivitiesProvider);
    final preferredUnits = ref
        .watch(profileProvider)
        .asData
        ?.value
        ?.preferredUnits;

    Future<void> refreshActivities() => _refreshActivities(ref);

    // No Scaffold here — the HomeShellScreen provides the outer Scaffold
    // with AppBar (title: "Activities") and BottomNavigationBar. Wrapping
    // in another Scaffold caused a double-AppBar bug.
    return savedActivities.when(
      skipError: true,
      loading: () => const Center(
        key: loadingStateKey,
        child: CircularProgressIndicator(key: loadingIndicatorKey),
      ),
      error: (_, __) => _buildRefreshableContent(
        onRefresh: refreshActivities,
        child: Column(
          key: errorStateKey,
          mainAxisSize: MainAxisSize.min,
          children: [
            const CopyableErrorText(
              'Unable to load activity history. Please try again.',
              key: errorMessageKey,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              key: retryButtonKey,
              onPressed: () => ref.invalidate(savedActivitiesProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (sessions) => sessions.isEmpty
          ? _buildRefreshableContent(
              onRefresh: refreshActivities,
              child: Column(
                key: emptyStateKey,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No saved activities yet.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.go('/home/record'),
                    icon: const Icon(Icons.fiber_manual_record),
                    label: const Text('Start Recording'),
                  ),
                ],
              ),
            )
          : _buildSessionList(
              ref: ref,
              sessions: sessions,
              preferredUnits: preferredUnits,
              onRefresh: refreshActivities,
            ),
    );
  }

  Future<void> _refreshActivities(WidgetRef ref) async {
    try {
      final _ = await ref.refresh(savedActivitiesProvider.future);
    } on Object {
      // Keep the visible error state when refresh fails.
    }
  }

  Widget _buildRefreshableContent({
    required Future<void> Function() onRefresh,
    required Widget child,
  }) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: child),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList({
    required WidgetRef ref,
    required List<TrackingSessionRecord> sessions,
    required String? preferredUnits,
    required Future<void> Function() onRefresh,
  }) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: sessions.length,
        itemBuilder: (context, index) {
          final session = sessions[index];
          final startedAt = session.startedAt ?? session.updatedAt;
          final hasCustomTitle =
              session.title != null && session.title!.trim().isNotEmpty;
          final displayTitle = hasCustomTitle
              ? session.title!
              : generateDefaultActivityTitle(
                  startedAt: session.startedAt ?? session.createdAt,
                  sportType: session.sportType,
                );
          final distanceLabel = formatDistance(
            session.distanceMeters,
            preferredUnits: preferredUnits,
          );
          final duration = session.movingTimeSeconds == null
              ? null
              : Duration(seconds: session.movingTimeSeconds!);
          final pace = formatPaceForPreferredUnits(
            pacePerKilometer: calculatePacePerKilometer(
              distanceMeters: session.distanceMeters ?? 0,
              elapsedTime: duration ?? Duration.zero,
            ),
            pacePerMile: calculatePacePerMile(
              distanceMeters: session.distanceMeters ?? 0,
              elapsedTime: duration ?? Duration.zero,
            ),
            preferredUnits: preferredUnits,
          );

          return Dismissible(
            key: activityDismissibleKey(session.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) =>
                _confirmDeletionAndDeleteActivity(context, ref, session),
            background: Container(
              alignment: Alignment.centerRight,
              color: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            child: Card(
              margin: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              child: ListTile(
                key: activityCardKey(session.id),
                onTap: () =>
                    context.push(ActivityRoutes.activityDetailPath(session.id)),
                // Keep history rows aligned with the shared activity title and
                // sport icon contracts used across the app.
                leading: SportTypeIcon(sportType: session.sportType),
                title: Text(displayTitle),
                subtitle: Text(formatDateLabel(startedAt)),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(distanceLabel),
                    Text(formatDuration(duration)),
                    Text(
                      'Avg pace: $pace',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _confirmDeletionAndDeleteActivity(
    BuildContext context,
    WidgetRef ref,
    TrackingSessionRecord session,
  ) async {
    final confirmed = await confirmActivityDeletion(context);
    if (!confirmed) {
      return false;
    }

    final didDelete = await performActivityDeletion(ref, session);
    if (didDelete) {
      return true;
    }

    if (context.mounted) {
      showActivityDeletionFailureSnackBar(context);
    }
    return false;
  }
}

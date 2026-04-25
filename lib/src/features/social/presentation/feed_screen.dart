import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/common_widgets/feed_skeleton_card.dart';
import 'package:uff/src/common_widgets/static_route_preview.dart';
import 'package:uff/src/common_widgets/trusted_avatar_widget.dart';
import 'package:uff/src/features/activity_tracking/domain/track_metrics.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/application/social_kudos_providers.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';

/// TODO: Document FeedScreen.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  static const loadingIndicatorKey = Key('feed_loading_indicator');
  static const errorStateKey = Key('feed_error_state');
  static const retryButtonKey = Key('feed_retry_button');
  static const emptyStateKey = Key('feed_empty_state');
  static const emptyFollowingNobodyKey = Key('feed_empty_following_nobody');
  static const emptyNoRecentActivityKey = Key('feed_empty_no_recent_activity');
  static const searchCtaButtonKey = Key('feed_search_cta_button');
  static const loadMoreProgressKey = Key('feed_load_more_progress');
  static const loadMoreErrorKey = Key('feed_load_more_error');
  static const loadMoreRetryButtonKey = Key('feed_load_more_retry_button');
  static const terminalStateKey = Key('feed_terminal_state');

  static Key feedCardKey(String activityId) => Key('feed_card_$activityId');
  static Key ownerTapTargetKey(String activityId) =>
      Key('feed_owner_tap_target_$activityId');
  static Key activityTapTargetKey(String activityId) =>
      Key('feed_activity_tap_target_$activityId');
  static Key kudosButtonKey(String activityId) =>
      Key('feed_kudos_button_$activityId');
  static Key kudosCountKey(String activityId) =>
      Key('feed_kudos_count_$activityId');
  static Key commentIconKey(String activityId) =>
      Key('feed_comment_icon_$activityId');
  static Key commentCountKey(String activityId) =>
      Key('feed_comment_count_$activityId');

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

/// TODO: Document _FeedScreenState.
class _FeedScreenState extends ConsumerState<FeedScreen> {
  static const double _loadMoreThresholdPixels = 240;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _refreshFeed() {
    return ref.read(socialFeedProvider.notifier).refresh();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final feedState = ref.read(socialFeedProvider).value;
    if (feedState == null ||
        feedState.isRefreshing ||
        feedState.isLoadingMore ||
        feedState.hasReachedEnd ||
        feedState.loadMoreError != null) {
      return;
    }

    final scrollPosition = _scrollController.position;
    final remainingPixels =
        scrollPosition.maxScrollExtent - scrollPosition.pixels;
    if (remainingPixels <= _loadMoreThresholdPixels) {
      ref.read(socialFeedProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(socialFeedProvider);

    return feedAsync.when(
      loading: () =>
          const FeedSkeletonList(key: FeedScreen.loadingIndicatorKey),
      error: (_, __) => _FeedErrorState(
        onRefresh: _refreshFeed,
        onRetry: () {
          ref.read(socialFeedProvider.notifier).refresh();
        },
      ),
      data: (feedState) {
        if (feedState.activities.isEmpty) {
          final followsPeople = ref
              .watch(followingProvider)
              .when(
                data: (following) => following.isNotEmpty,
                loading: () => false,
                error: (_, __) => false,
              );

          return _FeedEmptyState(
            followsPeople: followsPeople,
            onRefresh: _refreshFeed,
          );
        }

        return _FeedActivityList(
          feedState: feedState,
          scrollController: _scrollController,
          onRefresh: _refreshFeed,
          onRetryLoadMore: () {
            ref.read(socialFeedProvider.notifier).loadMore();
          },
        );
      },
    );
  }
}

/// TODO: Document _FeedErrorState.
class _FeedErrorState extends StatelessWidget {
  const _FeedErrorState({
    required this.onRefresh,
    required this.onRetry,
  });

  final RefreshCallback onRefresh;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              key: FeedScreen.errorStateKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Unable to load feed. Please try again.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    key: FeedScreen.retryButtonKey,
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// TODO: Document _FeedEmptyState.
class _FeedEmptyState extends StatelessWidget {
  const _FeedEmptyState({
    required this.followsPeople,
    required this.onRefresh,
  });

  final bool followsPeople;
  final RefreshCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final emptyStateKeyForVariant = followsPeople
        ? FeedScreen.emptyNoRecentActivityKey
        : FeedScreen.emptyFollowingNobodyKey;
    final emptyStateCopy = followsPeople
        ? 'No recent activities from people you follow'
        : 'Follow other runners to see their activities here.';

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            key: FeedScreen.emptyStateKey,
            hasScrollBody: false,
            child: Center(
              key: emptyStateKeyForVariant,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.dynamic_feed,
                    size: 48,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    emptyStateCopy,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (!followsPeople) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      key: FeedScreen.searchCtaButtonKey,
                      onPressed: () => context.push(SocialRoutes.searchPath),
                      child: const Text('Find People'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// TODO: Document _FeedActivityList.
class _FeedActivityList extends StatelessWidget {
  const _FeedActivityList({
    required this.feedState,
    required this.scrollController,
    required this.onRefresh,
    required this.onRetryLoadMore,
  });

  final SocialFeedState feedState;
  final ScrollController scrollController;
  final RefreshCallback onRefresh;
  final VoidCallback onRetryLoadMore;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: feedState.activities.length + 1,
        itemBuilder: (context, index) {
          if (index < feedState.activities.length) {
            return _FeedCard(activity: feedState.activities[index]);
          }
          if (feedState.isLoadingMore) {
            return const Padding(
              key: FeedScreen.loadMoreProgressKey,
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (feedState.loadMoreError != null) {
            return Padding(
              key: FeedScreen.loadMoreErrorKey,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Unable to load more activities.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: FeedScreen.loadMoreRetryButtonKey,
                    onPressed: onRetryLoadMore,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          if (feedState.hasReachedEnd) {
            return Padding(
              key: FeedScreen.terminalStateKey,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'You are all caught up.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

/// TODO: Document _FeedCard.
class _FeedCard extends ConsumerWidget {
  const _FeedCard({required this.activity});

  final SocialActivitySummary activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inFlightByActivity = ref.watch(kudosToggleInFlightByActivityProvider);
    final optimisticByActivity = ref.watch(optimisticKudosByActivityProvider);
    final preferredUnits = ref
        .watch(profileProvider)
        .asData
        ?.value
        ?.preferredUnits;
    final ownerName = activity.owner.displayName ?? 'Unknown Runner';
    final distanceLabel = formatDistance(
      activity.distanceMeters,
      preferredUnits: preferredUnits,
    );
    final durationLabel = formatDuration(
      Duration(seconds: activity.durationSeconds),
    );
    final pacePerKilometer = activity.avgPaceSecondsPerKm == null
        ? null
        : Duration(seconds: activity.avgPaceSecondsPerKm!.round());
    final paceLabel = formatPaceForPreferredUnits(
      pacePerKilometer: pacePerKilometer,
      pacePerMile: pacePerKilometer == null
          ? null
          : calculatePacePerMile(
              distanceMeters: 1000,
              elapsedTime: pacePerKilometer,
            ),
      preferredUnits: preferredUnits,
    );
    final projectedKudosState = projectKudosState(
      sourceKudosCount: activity.kudosCount,
      sourceViewerHasKudo: activity.viewerHasKudo,
      optimisticViewerHasKudo: optimisticByActivity[activity.activityId],
    );

    return Card(
      key: FeedScreen.feedCardKey(activity.activityId),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        key: FeedScreen.activityTapTargetKey(activity.activityId),
        onTap: () {
          context.push(
            SocialRoutes.remoteActivityDetailPath(activity.activityId),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OwnerRow(activity: activity, ownerName: ownerName),
              const SizedBox(height: 8),
              if (activity.title != null)
                Text(
                  activity.title!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              if (activity.polylineEncoded != null ||
                  activity.routePoints != null) ...[
                const SizedBox(height: 8),
                StaticRoutePreview(
                  polylineEncoded: activity.polylineEncoded,
                  routePoints: activity.routePoints,
                ),
              ],
              const SizedBox(height: 8),
              _MetricsRow(
                distanceLabel: distanceLabel,
                durationLabel: durationLabel,
                paceLabel: paceLabel,
              ),
              const SizedBox(height: 4),
              _SocialRow(
                activity: activity,
                projectedKudosState: projectedKudosState,
                kudosInFlight: inFlightByActivity[activity.activityId] ?? false,
                onToggleKudos: () {
                  ref
                      .read(kudosToggleControllerProvider.notifier)
                      .toggleKudos(
                        activityId: activity.activityId,
                        viewerHasKudo: projectedKudosState.viewerHasKudo,
                      );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// TODO: Document _OwnerRow.
class _OwnerRow extends StatelessWidget {
  const _OwnerRow({required this.activity, required this.ownerName});

  final SocialActivitySummary activity;
  final String ownerName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TrustedAvatarWidget(
          avatarUrl: activity.owner.avatarUrl,
          displayName: ownerName,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            key: FeedScreen.ownerTapTargetKey(activity.activityId),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              context.push(
                SocialRoutes.viewedUserProfilePath(activity.owner.userId),
              );
            },
            child: Text(
              ownerName,
              style: Theme.of(context).textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Text(
          formatDateLabel(activity.startedAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// TODO: Document _MetricsRow.
class _MetricsRow extends StatelessWidget {
  const _MetricsRow({
    required this.distanceLabel,
    required this.durationLabel,
    required this.paceLabel,
  });

  final String distanceLabel;
  final String durationLabel;
  final String paceLabel;

  @override
  Widget build(BuildContext context) {
    final metricStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w500,
    );
    final iconColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.straighten, size: 16, color: iconColor),
        const SizedBox(width: 4),
        Text(distanceLabel, style: metricStyle),
        const SizedBox(width: 16),
        Icon(Icons.timer_outlined, size: 16, color: iconColor),
        const SizedBox(width: 4),
        Text(durationLabel, style: metricStyle),
        const SizedBox(width: 16),
        Icon(Icons.speed_outlined, size: 16, color: iconColor),
        const SizedBox(width: 4),
        Text(paceLabel, style: metricStyle),
      ],
    );
  }
}

/// TODO: Document _SocialRow.
class _SocialRow extends StatelessWidget {
  const _SocialRow({
    required this.activity,
    required this.projectedKudosState,
    required this.kudosInFlight,
    required this.onToggleKudos,
  });

  final SocialActivitySummary activity;
  final ProjectedKudosState projectedKudosState;
  final bool kudosInFlight;
  final VoidCallback onToggleKudos;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: FeedScreen.kudosButtonKey(activity.activityId),
          onPressed: kudosInFlight ? null : onToggleKudos,
          icon: Icon(
            projectedKudosState.viewerHasKudo
                ? Icons.favorite
                : Icons.favorite_border,
            size: 20,
            color: projectedKudosState.viewerHasKudo
                ? Colors.red
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          '${projectedKudosState.kudosCount}',
          key: FeedScreen.kudosCountKey(activity.activityId),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(width: 12),
        Icon(
          Icons.chat_bubble_outline,
          key: FeedScreen.commentIconKey(activity.activityId),
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          '${activity.commentCount}',
          key: FeedScreen.commentCountKey(activity.activityId),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

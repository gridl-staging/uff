import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/common_widgets/static_route_preview.dart';
import 'package:uff/src/common_widgets/trusted_avatar_widget.dart';
import 'package:uff/src/features/activity_tracking/domain/track_metrics.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/application/social_kudos_providers.dart';
import 'package:uff/src/features/social/domain/social_activity_detail.dart';
import 'package:uff/src/features/social/presentation/activity_comments_section.dart';
import 'package:uff/src/features/social/presentation/social_route_recovery_scaffold.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';

/// TODO: Document RemoteActivityDetailScreen.
class RemoteActivityDetailScreen extends ConsumerWidget {
  const RemoteActivityDetailScreen({required this.activityId, super.key});

  static const loadingStateKey = Key('remote_activity_detail_loading');
  static const errorStateKey = Key('remote_activity_detail_error');
  static const notFoundStateKey = Key('remote_activity_detail_not_found');
  static const contentStateKey = Key('remote_activity_detail_content');
  static const kudosCountTextKey = Key('remote_activity_detail_kudos_count');
  static const kudosButtonKey = Key('remote_activity_detail_kudos_button');
  static const ownerTapTargetKey = Key('remote_activity_detail_owner_tap');
  static const metricsRowKey = Key('remote_activity_detail_metrics_row');
  static const routePreviewKey = Key('remote_activity_detail_route_preview');
  static const photoStripKey = Key('remote_activity_detail_photo_strip');

  final String activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(remoteActivityDetailProvider(activityId));

    return detailAsync.when(
      loading: () => const SocialRouteRecoveryScaffold(
        stateKey: loadingStateKey,
        message: 'Loading activity detail...',
        showLoadingIndicator: true,
      ),
      error: (_, __) => SocialRouteRecoveryScaffold(
        stateKey: errorStateKey,
        message: 'Unable to load activity detail.',
        onRetry: () => ref.invalidate(remoteActivityDetailProvider(activityId)),
      ),
      data: (data) {
        if (data == null) {
          return SocialRouteRecoveryScaffold(
            stateKey: notFoundStateKey,
            message: 'Activity not found.',
            onRetry: () =>
                ref.invalidate(remoteActivityDetailProvider(activityId)),
          );
        }
        return _RemoteActivityDetailContent(data: data);
      },
    );
  }
}

/// TODO: Document _RemoteActivityDetailContent.
class _RemoteActivityDetailContent extends ConsumerWidget {
  const _RemoteActivityDetailContent({required this.data});

  final RemoteActivityDetailData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = data.detail;
    final projectedKudosState = projectKudosState(
      sourceKudosCount: detail.kudosCount,
      sourceViewerHasKudo: detail.viewerHasKudo,
      optimisticViewerHasKudo: ref.watch(
        optimisticKudosByActivityProvider,
      )[detail.activityId],
    );
    final kudosInFlight =
        ref.watch(kudosToggleInFlightByActivityProvider)[detail.activityId] ??
        false;
    final ownerName = detail.owner.displayName ?? detail.owner.userId;
    final photosWithPreview = data.photos
        .where((photo) => (photo.previewUrl ?? '').isNotEmpty)
        .toList(growable: false);
    final metricsLabels = _RemoteMetricsLabels.fromDetail(
      detail: detail,
      preferredUnits: ref.watch(profileProvider).asData?.value?.preferredUnits,
    );
    final visibleRoutePoints = detail.trackPoints
        .where((point) => point.latitude != null && point.longitude != null)
        .map(
          (point) => RoutePoint(
            latitude: point.latitude!,
            longitude: point.longitude!,
          ),
        )
        .toList(growable: false);

    // Keep content clear of the iPhone home indicator on this pushed route.
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: ListView(
        key: RemoteActivityDetailScreen.contentStateKey,
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
        children: [
          _RemoteOwnerRow(detail: detail, ownerName: ownerName),
          if (detail.title != null) ...[
            const SizedBox(height: 4),
            Text(
              detail.title!,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
          if (visibleRoutePoints.length >= 2) ...[
            const SizedBox(height: 12),
            _RemoteRoutePreview(routePoints: visibleRoutePoints),
          ],
          if (photosWithPreview.isNotEmpty) ...[
            const SizedBox(height: 12),
            _RemotePhotoStrip(photos: photosWithPreview),
          ],
          const SizedBox(height: 12),
          _RemoteMetricsRow(labels: metricsLabels),
          const SizedBox(height: 12),
          _RemoteKudosCard(
            detail: detail,
            projectedKudosState: projectedKudosState,
            kudosInFlight: kudosInFlight,
          ),
          const SizedBox(height: 12),
          ActivityCommentsSection(activityId: detail.activityId),
        ],
      ),
    );
  }
}

/// TODO: Document _RemoteOwnerRow.
class _RemoteOwnerRow extends StatelessWidget {
  const _RemoteOwnerRow({required this.detail, required this.ownerName});

  final SocialActivityDetail detail;
  final String ownerName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TrustedAvatarWidget(
          avatarUrl: detail.owner.avatarUrl,
          displayName: ownerName,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            key: RemoteActivityDetailScreen.ownerTapTargetKey,
            behavior: HitTestBehavior.opaque,
            onTap: () {
              context.push(
                SocialRoutes.viewedUserProfilePath(detail.owner.userId),
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
          formatDateLabel(detail.startedAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// TODO: Document _RemoteRoutePreview.
class _RemoteRoutePreview extends StatelessWidget {
  const _RemoteRoutePreview({required this.routePoints});

  final List<RoutePoint> routePoints;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: RemoteActivityDetailScreen.routePreviewKey,
      child: StaticRoutePreview(
        routePoints: routePoints,
        preset: StaticRoutePreviewSizePreset.detail,
      ),
    );
  }
}

/// TODO: Document _RemotePhotoStrip.
class _RemotePhotoStrip extends StatelessWidget {
  const _RemotePhotoStrip({required this.photos});

  final List<ActivityPhoto> photos;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: RemoteActivityDetailScreen.photoStripKey,
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) =>
            _RemotePhotoThumbnail(previewUrl: photos[index].previewUrl!),
      ),
    );
  }
}

/// TODO: Document _RemotePhotoThumbnail.
class _RemotePhotoThumbnail extends StatelessWidget {
  const _RemotePhotoThumbnail({required this.previewUrl});

  final String previewUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 1,
        child: Image.network(
          previewUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFE0E0E0),
            ),
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// TODO: Document _RemoteMetricsLabels.
class _RemoteMetricsLabels {
  const _RemoteMetricsLabels({
    required this.distance,
    required this.duration,
    required this.pace,
  });

  factory _RemoteMetricsLabels.fromDetail({
    required SocialActivityDetail detail,
    required String? preferredUnits,
  }) {
    final pacePerKilometer = detail.avgPaceSecondsPerKm == null
        ? null
        : Duration(seconds: detail.avgPaceSecondsPerKm!.round());
    return _RemoteMetricsLabels(
      distance: formatDistance(
        detail.distanceMeters,
        preferredUnits: preferredUnits,
      ),
      duration: formatDuration(Duration(seconds: detail.durationSeconds)),
      pace: formatPaceForPreferredUnits(
        pacePerKilometer: pacePerKilometer,
        pacePerMile: pacePerKilometer == null
            ? null
            : calculatePacePerMile(
                distanceMeters: 1000,
                elapsedTime: pacePerKilometer,
              ),
        preferredUnits: preferredUnits,
      ),
    );
  }

  final String distance;
  final String duration;
  final String pace;
}

/// TODO: Document _RemoteMetricsRow.
class _RemoteMetricsRow extends StatelessWidget {
  const _RemoteMetricsRow({required this.labels});

  final _RemoteMetricsLabels labels;

  @override
  Widget build(BuildContext context) {
    final metricStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w500,
    );
    final iconColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      key: RemoteActivityDetailScreen.metricsRowKey,
      children: [
        Icon(Icons.straighten, size: 16, color: iconColor),
        const SizedBox(width: 4),
        Text(labels.distance, style: metricStyle),
        const SizedBox(width: 16),
        Icon(Icons.timer_outlined, size: 16, color: iconColor),
        const SizedBox(width: 4),
        Text(labels.duration, style: metricStyle),
        const SizedBox(width: 16),
        Icon(Icons.speed_outlined, size: 16, color: iconColor),
        const SizedBox(width: 4),
        Text(labels.pace, style: metricStyle),
      ],
    );
  }
}

/// TODO: Document _RemoteKudosCard.
class _RemoteKudosCard extends ConsumerWidget {
  const _RemoteKudosCard({
    required this.detail,
    required this.projectedKudosState,
    required this.kudosInFlight,
  });

  final SocialActivityDetail detail;
  final ProjectedKudosState projectedKudosState;
  final bool kudosInFlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: IconButton(
          key: RemoteActivityDetailScreen.kudosButtonKey,
          onPressed: kudosInFlight
              ? null
              : () {
                  ref
                      .read(kudosToggleControllerProvider.notifier)
                      .toggleKudos(
                        activityId: detail.activityId,
                        viewerHasKudo: projectedKudosState.viewerHasKudo,
                      );
                },
          icon: Icon(
            projectedKudosState.viewerHasKudo
                ? Icons.favorite
                : Icons.favorite_border,
          ),
        ),
        title: const Text('Kudos'),
        trailing: Text(
          '${projectedKudosState.kudosCount}',
          key: RemoteActivityDetailScreen.kudosCountTextKey,
        ),
      ),
    );
  }
}

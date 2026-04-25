import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/common_widgets/static_route_preview.dart';
import 'package:uff/src/common_widgets/user_avatar.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';
import 'package:uff/src/features/social/domain/viewed_user_profile_header.dart';
import 'package:uff/src/features/social/presentation/social_user_follow_action.dart';
import 'package:uff/src/features/social/presentation/social_route_recovery_scaffold.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';
import 'package:uff/src/features/social/presentation/social_user_display_name.dart';
import 'package:uff/src/features/social/presentation/social_user_row.dart';

/// TODO: Document ViewedUserProfileScreen.
class ViewedUserProfileScreen extends ConsumerWidget {
  const ViewedUserProfileScreen({required this.userId, super.key});

  static const loadingStateKey = Key('viewed_user_profile_loading');
  static const errorStateKey = Key('viewed_user_profile_error');
  static const notFoundStateKey = Key('viewed_user_profile_not_found');
  static const headerCardKey = Key('viewed_user_profile_header_card');
  static const emptyStateKey = Key('viewed_user_profile_empty');

  static Key activityRowKey(String activityId) =>
      Key('viewed_user_activity_row_$activityId');

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headerAsync = ref.watch(viewedUserProfileHeaderProvider(userId));
    final activitiesAsync = ref.watch(viewedUserActivityListProvider(userId));
    void retry() => _invalidateViewedUserProfile(ref, userId);

    if (headerAsync.isLoading || activitiesAsync.isLoading) {
      return const _ViewedUserProfileRecoveryState(
        stateKey: loadingStateKey,
        message: 'Loading profile...',
        showLoadingIndicator: true,
      );
    }

    if (_hasBlockingLoadError(headerAsync) ||
        _hasBlockingLoadError(activitiesAsync)) {
      return _ViewedUserProfileRecoveryState(
        stateKey: errorStateKey,
        message: 'Unable to load this profile right now.',
        onRetry: retry,
      );
    }

    final header = headerAsync.value;
    if (header == null) {
      return _ViewedUserProfileRecoveryState(
        stateKey: notFoundStateKey,
        message: 'Profile not found.',
        onRetry: retry,
      );
    }

    final activities = activitiesAsync.value ?? const <SocialActivitySummary>[];
    final displayName = socialUserDisplayNameOrId(
      userId: header.user.userId,
      displayName: header.user.displayName,
    );
    final preferredUnits = ref
        .watch(profileProvider)
        .asData
        ?.value
        ?.preferredUnits;

    return Scaffold(
      appBar: AppBar(title: Text(displayName)),
      body: ListView(
        padding: _viewedUserProfilePadding(context),
        children: [
          _ViewedUserProfileHeaderCard(
            key: headerCardKey,
            header: header,
            displayName: displayName,
            onFollowAction: buildSocialUserFollowAction(
              ref: ref,
              user: header.user,
              allowUnfollow: true,
            ),
          ),
          const SizedBox(height: 12),
          ..._buildViewedUserActivityRows(
            activities: activities,
            preferredUnits: preferredUnits,
          ),
        ],
      ),
    );
  }
}

bool _hasBlockingLoadError(AsyncValue<Object?> value) {
  return value.hasError && !value.hasValue;
}

EdgeInsets _viewedUserProfilePadding(BuildContext context) {
  // This route is pushed above the bottom navigation, so include the safe area
  // to keep the last item clear of the home indicator.
  final bottomInset = MediaQuery.of(context).padding.bottom;
  return EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset);
}

List<Widget> _buildViewedUserActivityRows({
  required List<SocialActivitySummary> activities,
  required String? preferredUnits,
}) {
  if (activities.isEmpty) {
    return const <Widget>[
      Center(
        key: ViewedUserProfileScreen.emptyStateKey,
        child: Text('No activities yet.'),
      ),
    ];
  }

  return activities
      .map(
        (activity) => _ViewedUserActivityRow(
          activity: activity,
          preferredUnits: preferredUnits,
        ),
      )
      .toList(growable: false);
}

void _invalidateViewedUserProfile(WidgetRef ref, String userId) {
  ref
    ..invalidate(viewedUserProfileHeaderProvider(userId))
    ..invalidate(viewedUserActivityListProvider(userId));
}

/// TODO: Document _ViewedUserProfileRecoveryState.
class _ViewedUserProfileRecoveryState extends StatelessWidget {
  const _ViewedUserProfileRecoveryState({
    required this.stateKey,
    required this.message,
    this.onRetry,
    this.showLoadingIndicator = false,
  });

  final Key stateKey;
  final String message;
  final VoidCallback? onRetry;
  final bool showLoadingIndicator;

  @override
  Widget build(BuildContext context) {
    return SocialRouteRecoveryScaffold(
      stateKey: stateKey,
      message: message,
      onRetry: onRetry,
      showLoadingIndicator: showLoadingIndicator,
    );
  }
}

/// TODO: Document _ViewedUserProfileHeaderCard.
class _ViewedUserProfileHeaderCard extends StatelessWidget {
  const _ViewedUserProfileHeaderCard({
    required this.header,
    required this.displayName,
    required this.onFollowAction,
    super.key,
  });

  final ViewedUserProfileHeader header;
  final String displayName;
  final VoidCallback? onFollowAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: UserAvatar(
          avatarUrl: header.user.avatarUrl,
          displayName: displayName,
          radius: 16,
        ),
        title: Text(displayName),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(header.user.userId),
            const SizedBox(height: 4),
            Text('${header.followersCount} followers'),
            Text('${header.followingCount} following'),
          ],
        ),
        trailing: SocialUserFollowActionButton(
          buttonKey: SocialUserRow.actionButtonKey(header.user.userId),
          status: header.user.relationship.status,
          onPressed: onFollowAction,
        ),
      ),
    );
  }
}

/// TODO: Document _ViewedUserActivityRow.
class _ViewedUserActivityRow extends StatelessWidget {
  const _ViewedUserActivityRow({
    required this.activity,
    required this.preferredUnits,
  });

  final SocialActivitySummary activity;
  final String? preferredUnits;

  @override
  Widget build(BuildContext context) {
    // Use the viewer's preferred units for distance display.
    final distanceLabel = formatDistance(
      activity.distanceMeters,
      preferredUnits: preferredUnits,
    );
    final durationLabel = formatDuration(
      Duration(seconds: activity.durationSeconds),
    );
    final dateLabel = formatDateLabel(activity.startedAt);

    return ListTile(
      key: ViewedUserProfileScreen.activityRowKey(activity.activityId),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: activity.polylineEncoded != null || activity.routePoints != null
          ? StaticRoutePreview(
              polylineEncoded: activity.polylineEncoded,
              routePoints: activity.routePoints,
              preset: StaticRoutePreviewSizePreset.compact,
            )
          : null,
      title: Text(activity.title ?? dateLabel),
      subtitle: Text('$distanceLabel • $durationLabel'),
      trailing: Text(dateLabel),
      onTap: () {
        context.push(
          SocialRoutes.remoteActivityDetailPath(activity.activityId),
        );
      },
    );
  }
}

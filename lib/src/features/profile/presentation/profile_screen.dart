import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/common_widgets/user_avatar.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart';
import 'package:uff/src/features/photos/data/photo_picker_service.dart';
import 'package:uff/src/features/gear/presentation/gear_routes.dart';
import 'package:uff/src/features/profile/application/profile_stats_provider.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/profile/presentation/profile_routes.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/domain/relationship_counts.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';

/// TODO: Document ProfileScreen.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const privacyZonesButtonKey = Key('profile_privacy_zones_button');
  static const relationshipCountsLoadingKey = Key(
    'profile_relationship_counts_loading',
  );
  static const relationshipCountsErrorKey = Key(
    'profile_relationship_counts_error',
  );
  static const loadErrorStateKey = Key('profile_load_error_state');
  static const loadErrorRetryButtonKey = Key('profile_load_error_retry_button');
  static const followersEntryRowKey = Key('profile_followers_entry_row');
  static const followingEntryRowKey = Key('profile_following_entry_row');
  static const pendingRequestsEntryRowKey = Key(
    'profile_pending_requests_entry_row',
  );
  static const activitiesStatTileKey = Key('profile_activities_stat_tile');
  static const distanceStatTileKey = Key('profile_distance_stat_tile');
  static const activitiesThisMonthStatTileKey = Key(
    'profile_activities_this_month_stat_tile',
  );
  static const avatarTapTargetKey = Key('profile_avatar_tap_target');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          key: loadErrorStateKey,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Failed to load profile. Please try again.'),
            const SizedBox(height: 12),
            FilledButton(
              key: loadErrorRetryButtonKey,
              onPressed: () => ref.invalidate(profileProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (profile) {
        if (profile == null) {
          return const Center(child: Text('No profile'));
        }
        return _ProfileBody(profile: profile);
      },
    );
  }
}

/// TODO: Document _ProfileBody.
class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relationshipCounts = ref.watch(relationshipCountsProvider);
    final statsAsync = ref.watch(profileStatsProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          _buildIdentitySection(context, ref),
          const SizedBox(height: 24),
          _buildStatsSection(statsAsync),
          const SizedBox(height: 16),
          const Divider(),
          _buildRelationshipEntrySection(context, relationshipCounts),
          const SizedBox(height: 16),
          const Divider(),
          _buildQuickLinksSection(context),
        ],
      ),
    );
  }

  Widget _buildIdentitySection(BuildContext context, WidgetRef ref) {
    final authRepository = ref.watch(authRepositoryProvider);
    final memberSinceLabel = _memberSinceLabel(authRepository.memberSince());

    return Column(
      children: [
        GestureDetector(
          key: ProfileScreen.avatarTapTargetKey,
          onTap: () => _handleAvatarTap(context, ref),
          child: UserAvatar(
            avatarUrl: profile.avatarUrl,
            displayName: profile.displayName,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          profile.displayName ?? '',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        if (memberSinceLabel != null) ...[
          const SizedBox(height: 4),
          Text(
            memberSinceLabel,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  String? _memberSinceLabel(DateTime? memberSince) {
    if (memberSince == null) {
      return null;
    }
    return 'Member since ${_formatMonthYearLabel(memberSince)}';
  }

  String _formatMonthYearLabel(DateTime value) {
    const monthNames = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${monthNames[value.month - 1]} ${value.year}';
  }

  Future<void> _handleAvatarTap(BuildContext context, WidgetRef ref) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final photoPicker = ref.read(photoPickerServiceProvider);

    List<PickedPhoto> pickedPhotos;
    try {
      pickedPhotos = await photoPicker.pickPhotos(
        source: PhotoPickSource.gallery,
        maxSelection: 1,
      );
    } on Exception {
      scaffoldMessenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to select photo. Please try again.'),
          ),
        );
      return;
    }

    if (pickedPhotos.isEmpty) {
      return;
    }

    final selectedPhoto = pickedPhotos.first;
    try {
      final uploadedAvatarUrl = await ref
          .read(profileRepositoryProvider)
          .uploadAvatar(
            profile.userId,
            selectedPhoto.bytes,
            selectedPhoto.fileName,
          );
      await ref
          .read(profileProvider.notifier)
          .updateProfile(profile.copyWith(avatarUrl: uploadedAvatarUrl));
    } on Exception {
      scaffoldMessenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to update avatar. Please try again.'),
          ),
        );
    }
  }

  Widget _buildStatsSection(AsyncValue<ProfileStats> statsAsync) {
    final stats = statsAsync.value ?? ProfileStats.empty;
    final preferredUnits = profile.preferredUnits;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _StatTile(
          key: ProfileScreen.activitiesStatTileKey,
          label: 'Activities',
          value: '${stats.activityCount}',
        ),
        _StatTile(
          key: ProfileScreen.distanceStatTileKey,
          label: 'Distance',
          value: formatDistance(
            stats.totalDistanceMeters,
            preferredUnits: preferredUnits,
          ),
        ),
        _StatTile(
          key: ProfileScreen.activitiesThisMonthStatTileKey,
          label: 'This Month',
          value: '${stats.activitiesThisMonth}',
        ),
      ],
    );
  }

  Widget _buildRelationshipEntrySection(
    BuildContext context,
    AsyncValue<RelationshipCounts> relationshipCounts,
  ) {
    if (relationshipCounts.isLoading) {
      return const Center(
        key: ProfileScreen.relationshipCountsLoadingKey,
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (relationshipCounts.hasError && !relationshipCounts.hasValue) {
      return const Text(
        'Unable to load social counts',
        key: ProfileScreen.relationshipCountsErrorKey,
      );
    }

    final counts = relationshipCounts.value;
    if (counts == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        _buildRelationshipEntryRow(
          context: context,
          rowKey: ProfileScreen.followersEntryRowKey,
          label: 'Followers',
          count: counts.followers,
          onTap: () => context.push(SocialRoutes.followersPath),
        ),
        _buildRelationshipEntryRow(
          context: context,
          rowKey: ProfileScreen.followingEntryRowKey,
          label: 'Following',
          count: counts.following,
          onTap: () => context.push(SocialRoutes.followingPath),
        ),
        _buildRelationshipEntryRow(
          context: context,
          rowKey: ProfileScreen.pendingRequestsEntryRowKey,
          label: 'Pending Requests',
          count: counts.pendingRequests,
          onTap: () => context.push(SocialRoutes.requestsPath),
        ),
      ],
    );
  }

  Widget _buildRelationshipEntryRow({
    required BuildContext context,
    required Key rowKey,
    required String label,
    required int count,
    required VoidCallback onTap,
  }) {
    return ListTile(
      key: rowKey,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count'),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildQuickLinksSection(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.directions_run),
          title: const Text('Manage Gear'),
          subtitle: const Text('Track shoe mileage, bikes, and components'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(GearRoutes.gearPath),
        ),
        ListTile(
          key: ProfileScreen.privacyZonesButtonKey,
          leading: const Icon(Icons.shield),
          title: const Text('Privacy Zones'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(ProfileRoutes.privacyZonesPath),
        ),
      ],
    );
  }
}

/// TODO: Document _StatTile.
class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

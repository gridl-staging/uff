import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/activity_tracking/application/sync_status_provider.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_history_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/recording_screen.dart';
import 'package:uff/src/features/analytics/presentation/analytics_screen.dart';
import 'package:uff/src/features/profile/presentation/profile_screen.dart';
import 'package:uff/src/features/clubs/presentation/club_list_screen.dart';
import 'package:uff/src/features/clubs/presentation/club_routes.dart';
import 'package:uff/src/features/settings/presentation/settings_routes.dart';
import 'package:uff/src/features/social/presentation/feed_screen.dart';

enum HomeShellDestinationId {
  feed,
  activity,
  record,
  analytics,
  clubs,
  profile,
}

class HomeShellDestination {
  const HomeShellDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.path,
    required this.navigationKey,
  });

  final HomeShellDestinationId id;
  final String label;
  final IconData icon;
  final String path;
  final Key navigationKey;
}

const _feedTabKey = Key('home_nav_feed');
const _activityTabKey = Key('home_nav_activity');
const _recordTabKey = Key('home_nav_record');
const _analyticsTabKey = Key('home_nav_analytics');
const _clubsTabKey = Key('home_nav_clubs');
const _profileTabKey = Key('home_nav_profile');

const _feedDestination = HomeShellDestination(
  id: HomeShellDestinationId.feed,
  label: 'Feed',
  icon: Icons.dynamic_feed,
  path: '/home',
  navigationKey: _feedTabKey,
);

const _activityDestination = HomeShellDestination(
  id: HomeShellDestinationId.activity,
  label: 'Activity',
  icon: Icons.list_alt,
  path: '/home/activity',
  navigationKey: _activityTabKey,
);

const homeRecordDestination = HomeShellDestination(
  id: HomeShellDestinationId.record,
  label: 'Record',
  icon: Icons.fiber_manual_record,
  path: '/home/record',
  navigationKey: _recordTabKey,
);

const _analyticsDestination = HomeShellDestination(
  id: HomeShellDestinationId.analytics,
  label: 'Analytics',
  icon: Icons.show_chart,
  path: '/home/analytics',
  navigationKey: _analyticsTabKey,
);

const _clubsDestination = HomeShellDestination(
  id: HomeShellDestinationId.clubs,
  label: 'Clubs',
  icon: Icons.groups,
  path: ClubRoutes.clubListPath,
  navigationKey: _clubsTabKey,
);

const _profileDestination = HomeShellDestination(
  id: HomeShellDestinationId.profile,
  label: 'Profile',
  icon: Icons.person,
  path: '/home/profile',
  navigationKey: _profileTabKey,
);

const homeShellDestinations = <HomeShellDestination>[
  _feedDestination,
  _activityDestination,
  homeRecordDestination,
  _analyticsDestination,
  _clubsDestination,
  _profileDestination,
];

Widget buildHomeShellBranchContent(HomeShellDestinationId destinationId) {
  switch (destinationId) {
    case HomeShellDestinationId.feed:
      return const FeedScreen();
    case HomeShellDestinationId.activity:
      return const ActivityHistoryScreen();
    case HomeShellDestinationId.record:
      return const RecordingScreen();
    case HomeShellDestinationId.analytics:
      return const AnalyticsScreen();
    case HomeShellDestinationId.clubs:
      return const ClubListScreen();
    case HomeShellDestinationId.profile:
      return const ProfileScreen();
  }
}

/// TODO: Document HomeShellScreen.
class HomeShellScreen extends ConsumerWidget {
  const HomeShellScreen({required this.navigationShell, super.key});

  static const _syncIndicatorPadding = EdgeInsetsDirectional.only(end: 8);
  static const notificationButtonKey = Key('home_open_notification_button');
  static const openSettingsButtonKey = Key('home_open_settings_button');
  static const openImportButtonKey = Key('home_open_import_button');
  static const syncIndicatorQueuedKey = Key('home_sync_indicator_queued');
  static const syncIndicatorUploadingKey = Key('home_sync_indicator_uploading');
  static const syncIndicatorFailedKey = Key('home_sync_indicator_failed');
  static const bottomNavigationBarKey = Key('home_bottom_navigation_bar');
  static const Key feedTabKey = _feedTabKey;
  static const Key activityTabKey = _activityTabKey;
  static const Key recordTabKey = _recordTabKey;
  static const Key analyticsTabKey = _analyticsTabKey;
  static const Key clubsTabKey = _clubsTabKey;
  static const Key profileTabKey = _profileTabKey;

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatusValue = ref.watch(syncStatusProvider);
    final syncStatusIndicator = _buildSyncStatusIndicator(
      context: context,
      syncStatusValue: syncStatusValue,
    );
    // Hide the AppBar on the Record tab so the recording screen can be
    // full-bleed (map fills edge-to-edge). All other tabs get a shell-provided
    // AppBar with the tab-specific title. This eliminates the double-AppBar
    // bug where inner screens (Analytics, Activity History) previously had
    // their own Scaffold+AppBar stacked under the shell's "Home" AppBar.
    final currentDestination =
        homeShellDestinations[navigationShell.currentIndex];
    final isRecordTab = currentDestination.id == HomeShellDestinationId.record;
    final appBarTitle = _shellAppBarTitle(currentDestination.id);

    return Scaffold(
      appBar: isRecordTab
          ? null
          : AppBar(
              title: Text(appBarTitle),
              actions: [
                if (syncStatusIndicator != null) syncStatusIndicator,
                IconButton(
                  key: notificationButtonKey,
                  onPressed: () => _showNotificationPlaceholder(context),
                  icon: const Icon(Icons.notifications_none),
                  tooltip: 'Notifications',
                ),
                IconButton(
                  key: openImportButtonKey,
                  onPressed: () => context.push('/import'),
                  icon: const Icon(Icons.file_upload),
                  tooltip: 'Import',
                ),
                IconButton(
                  key: openSettingsButtonKey,
                  onPressed: () => context.push(SettingsRoutes.settingsPath),
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings',
                ),
              ],
            ),
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        key: bottomNavigationBarKey,
        type: BottomNavigationBarType.fixed,
        currentIndex: navigationShell.currentIndex,
        onTap: _goToBranch,
        items: [
          for (final destination in homeShellDestinations)
            BottomNavigationBarItem(
              icon: Icon(destination.icon, key: destination.navigationKey),
              label: destination.label,
            ),
        ],
      ),
    );
  }

  void _showNotificationPlaceholder(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notifications coming soon.'),
      ),
    );
  }

  void _goToBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  Widget? _buildSyncStatusIndicator({
    required BuildContext context,
    required AsyncValue<SyncQueueStatus> syncStatusValue,
  }) {
    return syncStatusValue.when(
      data: (status) {
        switch (status) {
          case SyncQueueStatus.queued:
            return _buildSyncStatusIcon(
              icon: Icons.cloud_upload_outlined,
              key: syncIndicatorQueuedKey,
              color: Colors.grey,
            );
          case SyncQueueStatus.processing:
            return const Padding(
              padding: _syncIndicatorPadding,
              child: SizedBox(
                key: syncIndicatorUploadingKey,
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          case SyncQueueStatus.failed:
            return _buildSyncStatusIcon(
              icon: Icons.cloud_off_outlined,
              key: syncIndicatorFailedKey,
              color: Theme.of(context).colorScheme.error,
            );
          case SyncQueueStatus.idle:
          case SyncQueueStatus.successful:
            return null;
        }
      },
      loading: () => null,
      error: (_, __) => null,
    );
  }

  Widget _buildSyncStatusIcon({
    required IconData icon,
    required Key key,
    Color? color,
  }) {
    return Padding(
      padding: _syncIndicatorPadding,
      child: Icon(icon, key: key, color: color),
    );
  }
}

/// Maps each tab destination to the title shown in the shell's AppBar.
/// "Activity" nav label maps to "Activities" title (matching the former
/// ActivityHistoryScreen AppBar). Record tab returns empty string but the
/// AppBar is hidden for that tab, so it's never displayed.
String _shellAppBarTitle(HomeShellDestinationId id) {
  return switch (id) {
    HomeShellDestinationId.feed => 'Feed',
    HomeShellDestinationId.activity => 'Activities',
    HomeShellDestinationId.record => '',
    HomeShellDestinationId.analytics => 'Analytics',
    HomeShellDestinationId.clubs => 'Clubs',
    HomeShellDestinationId.profile => 'Profile',
  };
}

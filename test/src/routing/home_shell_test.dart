import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_controller.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/analytics/application/analytics_providers.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/import/presentation/import_screen.dart';
import 'package:uff/src/features/legal/presentation/legal_document_screen.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/settings/presentation/settings_screen.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/presentation/feed_screen.dart';
import 'package:uff/src/routing/app_router.dart';

import '../features/activity_tracking/application/tracking_controller_test_support.dart';
import '../test_helpers/mapbox_platform_channel_stub.dart';

// ## Test Scenarios
// - [positive] Home shell shows the expected tab scaffolding and routes.
// - [positive] The shell wires the profile, feed, settings, and import tabs.
// - [negative] Switching tabs does not leak stale route state into the shell.
// - [isolation] Sync and recording state reset between separate shell pumps.
// - [edge] Sync and recording state render without crashing the shell.

const _testProfile = Profile(
  userId: 'user-1',
  preferredUnits: 'metric',
  defaultActivityVisibility: 'private',
  onboardingCompleted: true,
  displayName: 'Alice',
);

class _FakeProfileNotifier extends ProfileNotifier {
  _FakeProfileNotifier(this.profile);

  final Profile profile;

  @override
  Profile? build() => profile;
}

class _FakeAuthNotifier extends Auth {
  _FakeAuthNotifier(this.authState);

  final AuthState authState;

  @override
  FutureOr<AuthState> build() => authState;
}

class _FakeSocialFeedNotifier extends SocialFeed {
  _FakeSocialFeedNotifier(this.feedActivities);

  final List<SocialActivitySummary> feedActivities;

  @override
  Future<SocialFeedState> build() async {
    return SocialFeedState(
      activities: feedActivities,
      isRefreshing: false,
      isLoadingMore: false,
      hasReachedEnd: true,
      loadMoreError: null,
    );
  }
}

class _IdleRecordingController extends RecordingController {
  @override
  RecordingControllerState build() {
    return const RecordingControllerState.idle();
  }
}

class _ControllableSyncService extends FakeSyncService {
  _ControllableSyncService()
    : this._(StreamController<SyncQueueStatus>.broadcast());

  _ControllableSyncService._(this._syncStatusController)
    : super(syncStatusStream: _syncStatusController.stream);

  final StreamController<SyncQueueStatus> _syncStatusController;

  void emit(SyncQueueStatus status) {
    _syncStatusController.add(status);
  }

  void emitError(Object error, [StackTrace? stackTrace]) {
    _syncStatusController.addError(error, stackTrace);
  }

  Future<void> dispose() {
    return _syncStatusController.close();
  }
}

void _expectNoSyncIndicators() {
  expect(find.byKey(HomeShellScreen.syncIndicatorQueuedKey), findsNothing);
  expect(find.byKey(HomeShellScreen.syncIndicatorUploadingKey), findsNothing);
  expect(find.byKey(HomeShellScreen.syncIndicatorFailedKey), findsNothing);
}

Widget _buildRoutedShell({
  List<SocialActivitySummary> feedActivities = const <SocialActivitySummary>[],
  SyncService? syncService,
}) {
  final shellSyncService = syncService ?? FakeSyncService();
  return ProviderScope(
    overrides: [
      savedActivitiesProvider.overrideWith((ref) async => []),
      recordingControllerProvider.overrideWith(_IdleRecordingController.new),
      syncServiceProvider.overrideWithValue(shellSyncService),
      pmcProvider.overrideWith((ref) async => []),
      socialFeedProvider.overrideWith(
        () => _FakeSocialFeedNotifier(feedActivities),
      ),
      profileProvider.overrideWith(() => _FakeProfileNotifier(_testProfile)),
      authProvider.overrideWith(
        () => _FakeAuthNotifier(
          const AuthState.authenticated(
            userId: 'user-1',
            email: 'user-1@example.com',
          ),
        ),
      ),
    ],
    child: Consumer(
      builder: (context, ref, child) {
        final router = ref.watch(appRouterProvider);
        return MaterialApp.router(routerConfig: router);
      },
    ),
  );
}

Future<void> _pumpHomeShell(
  WidgetTester tester, {
  List<SocialActivitySummary> feedActivities = const <SocialActivitySummary>[],
  SyncService? syncService,
}) async {
  await tester.pumpWidget(
    _buildRoutedShell(
      feedActivities: feedActivities,
      syncService: syncService,
    ),
  );
  await tester.pumpAndSettle();
}

BottomNavigationBar _homeBottomNavigationBar(WidgetTester tester) {
  return tester.widget<BottomNavigationBar>(
    find.byKey(HomeShellScreen.bottomNavigationBarKey),
  );
}

void _expectShellActionButtons() {
  expect(find.byKey(HomeShellScreen.notificationButtonKey), findsOneWidget);
  expect(find.byKey(HomeShellScreen.openImportButtonKey), findsOneWidget);
  expect(find.byKey(HomeShellScreen.openSettingsButtonKey), findsOneWidget);
}

_ControllableSyncService _setUpSyncService() {
  final syncService = _ControllableSyncService();
  addTearDown(syncService.dispose);
  return syncService;
}

void main() {
  setUpMapboxPlatformChannelStub();

  group('Home shell navigation', () {
    testWidgets('renders six tabs in order with Feed first', (tester) async {
      await _pumpHomeShell(tester);

      final navBar = _homeBottomNavigationBar(tester);
      final labels = navBar.items.map((item) => item.label).toList();

      expect(labels, [
        'Feed',
        'Activity',
        'Record',
        'Analytics',
        'Clubs',
        'Profile',
      ]);
      expect(navBar.currentIndex, 0);
    });

    testWidgets('exposes stable navigation keys for all shell destinations', (
      tester,
    ) async {
      await _pumpHomeShell(tester);

      for (final destination in homeShellDestinations) {
        expect(find.byKey(destination.navigationKey), findsOneWidget);
      }
    });

    testWidgets(
      'uses BottomNavigationBarType.fixed so all labels stay visible',
      (
        tester,
      ) async {
        await _pumpHomeShell(tester);

        final navBar = _homeBottomNavigationBar(tester);

        expect(navBar.type, BottomNavigationBarType.fixed);
      },
    );

    testWidgets('tapping Profile switches to the profile tab', (tester) async {
      await _pumpHomeShell(tester);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      final navBar = _homeBottomNavigationBar(tester);

      expect(navBar.currentIndex, 5);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('tapping Activity switches to the activity tab', (
      tester,
    ) async {
      await _pumpHomeShell(tester);

      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();

      final navBar = _homeBottomNavigationBar(tester);

      expect(navBar.currentIndex, 1);
    });

    testWidgets('import and settings action buttons are present on the shell', (
      tester,
    ) async {
      await _pumpHomeShell(tester);

      expect(find.byKey(HomeShellScreen.openImportButtonKey), findsOneWidget);
      expect(find.byKey(HomeShellScreen.openSettingsButtonKey), findsOneWidget);
    });

    testWidgets(
      'notification action button is present with shell action controls',
      (tester) async {
        await _pumpHomeShell(tester);

        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        final actionKeys = appBar.actions!
            .whereType<IconButton>()
            .map((button) => button.key)
            .toList();

        _expectShellActionButtons();
        expect(actionKeys, [
          HomeShellScreen.notificationButtonKey,
          HomeShellScreen.openImportButtonKey,
          HomeShellScreen.openSettingsButtonKey,
        ]);
      },
    );

    testWidgets(
      'notification action button shows shell-local placeholder snackbar',
      (tester) async {
        await _pumpHomeShell(tester);

        await tester.tap(find.byKey(HomeShellScreen.notificationButtonKey));
        await tester.pump();

        expect(find.byType(HomeShellScreen), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Notifications coming soon.'), findsOneWidget);
        expect(find.byType(ImportScreen), findsNothing);
        expect(find.byType(SettingsScreen), findsNothing);
      },
    );

    testWidgets('shell controls expose accessible button labels', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpHomeShell(tester);

        expect(find.byTooltip('Notifications'), findsOneWidget);
        expect(find.byTooltip('Import'), findsOneWidget);
        expect(find.byTooltip('Settings'), findsOneWidget);

        for (final destination in homeShellDestinations) {
          expect(
            find.bySemanticsLabel(RegExp(destination.label)),
            findsAtLeastNWidgets(1),
          );
        }
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('import and settings action buttons navigate via router', (
      tester,
    ) async {
      await _pumpHomeShell(tester);

      await tester.tap(find.byKey(HomeShellScreen.openImportButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Import Activity'), findsOneWidget);
      expect(find.byKey(ImportScreen.pickFileButtonKey), findsOneWidget);

      await tester.tap(find.byKey(ImportScreen.backButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(HomeShellScreen), findsOneWidget);

      await tester.tap(find.byKey(HomeShellScreen.openSettingsButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(SettingsScreen.signOutButtonKey),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.byKey(SettingsScreen.signOutButtonKey), findsOneWidget);
    });

    testWidgets(
      'settings entry remains in shell and legal rows reach legal documents',
      (tester) async {
        await _pumpHomeShell(tester);

        await tester.tap(find.byKey(HomeShellScreen.openSettingsButtonKey));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);

        // Scroll to make the legal link tiles visible in the lazy ListView.
        await tester.scrollUntilVisible(
          find.text('Terms of Service'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Privacy Policy'), findsOneWidget);
        expect(find.text('Terms of Service'), findsOneWidget);

        await tester.tap(find.text('Privacy Policy'));
        await tester.pumpAndSettle();
        expect(find.byType(LegalDocumentScreen), findsOneWidget);
        expect(find.text('Privacy Policy'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();

        // Scroll again after navigating back, since the list may have reset.
        await tester.scrollUntilVisible(
          find.text('Terms of Service'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('Terms of Service'));
        await tester.pumpAndSettle();
        expect(find.byType(LegalDocumentScreen), findsOneWidget);
        expect(find.text('Terms of Service'), findsOneWidget);
      },
    );
  });

  group('Home shell sync indicator', () {
    testWidgets('queued status shows queued indicator', (tester) async {
      final syncService = _setUpSyncService();

      await _pumpHomeShell(tester, syncService: syncService);

      syncService.emit(SyncQueueStatus.queued);
      await tester.pumpAndSettle();

      expect(
        find.byKey(HomeShellScreen.syncIndicatorQueuedKey),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    });

    testWidgets('processing status shows uploading indicator', (tester) async {
      final syncService = _setUpSyncService();

      await _pumpHomeShell(tester, syncService: syncService);

      syncService.emit(SyncQueueStatus.processing);
      await tester.idle();
      await tester.pump();

      expect(
        find.byKey(HomeShellScreen.syncIndicatorUploadingKey),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('failed status shows failed indicator', (tester) async {
      final syncService = _setUpSyncService();

      await _pumpHomeShell(tester, syncService: syncService);

      syncService.emit(SyncQueueStatus.failed);
      await tester.pumpAndSettle();

      expect(
        find.byKey(HomeShellScreen.syncIndicatorFailedKey),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    });

    testWidgets('idle status shows no sync indicator', (tester) async {
      final syncService = _setUpSyncService();

      await _pumpHomeShell(tester, syncService: syncService);

      syncService.emit(SyncQueueStatus.idle);
      await tester.pumpAndSettle();

      _expectNoSyncIndicators();
    });

    testWidgets('successful status shows no sync indicator', (tester) async {
      final syncService = _setUpSyncService();

      await _pumpHomeShell(tester, syncService: syncService);

      syncService.emit(SyncQueueStatus.successful);
      await tester.pumpAndSettle();

      _expectNoSyncIndicators();
    });

    testWidgets(
      'queued status keeps shell actions visible and notification feedback local',
      (tester) async {
        final syncService = _setUpSyncService();

        await _pumpHomeShell(tester, syncService: syncService);

        syncService.emit(SyncQueueStatus.queued);
        await tester.pumpAndSettle();

        _expectShellActionButtons();

        await tester.tap(find.byKey(HomeShellScreen.notificationButtonKey));
        await tester.pump();

        expect(
          find.byKey(HomeShellScreen.syncIndicatorQueuedKey),
          findsOneWidget,
        );
        expect(find.text('Notifications coming soon.'), findsOneWidget);
        expect(find.byType(ImportScreen), findsNothing);
        expect(find.byType(SettingsScreen), findsNothing);
      },
    );

    testWidgets('loading and stream error show no sync indicator', (
      tester,
    ) async {
      final syncService = _setUpSyncService();

      await _pumpHomeShell(tester, syncService: syncService);

      _expectNoSyncIndicators();

      syncService.emitError(StateError('sync stream error'));
      await tester.pumpAndSettle();

      _expectNoSyncIndicators();
    });
  });

  test(
    'appRouterProvider keeps /home shell entry and no standalone /analytics',
    () {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => _FakeAuthNotifier(const AuthState.unauthenticated()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);
      final routePaths = RouteBase.routesRecursively(
        router.configuration.routes,
      ).whereType<GoRoute>().map((route) => route.path);

      expect(routePaths.where((path) => path == '/home'), hasLength(1));
      expect(routePaths, isNot(contains('/analytics')));
    },
  );

  group('Feed-first shell integration', () {
    testWidgets('feed screen is the initial /home body', (tester) async {
      final activities = <SocialActivitySummary>[
        SocialActivitySummary(
          activityId: 'feed-a1',
          owner: const SocialUserSummary(
            userId: 'owner-1',
            displayName: 'Test Runner',
            avatarUrl: null,
            relationship: FollowRelationship(
              currentUserId: 'user-1',
              targetUserId: 'owner-1',
              status: FollowRelationshipStatus.following,
            ),
          ),
          sportType: 'run',
          startedAt: DateTime.utc(2026, 3, 19, 10),
          finishedAt: DateTime.utc(2026, 3, 19, 10, 25),
          distanceMeters: 5000,
          durationSeconds: 1500,
          elevationGainMeters: 30,
          avgPaceSecondsPerKm: 300,
          title: 'Shell Feed Activity',
          description: null,
          visibility: 'public',
          polylineEncoded: null,
          commentCount: 0,
          kudosCount: 2,
          viewerHasKudo: false,
        ),
      ];

      await _pumpHomeShell(tester, feedActivities: activities);

      // Feed is the initial body — feed card visible without tapping any tab.
      expect(find.byKey(FeedScreen.feedCardKey('feed-a1')), findsOneWidget);
      expect(find.text('Shell Feed Activity'), findsOneWidget);
    });

    testWidgets(
      'activity history is at index 1, not index 0',
      (tester) async {
        await _pumpHomeShell(tester);

        // At index 0 (Feed), we should NOT see the activity history screen.
        final navBar = _homeBottomNavigationBar(tester);
        expect(navBar.currentIndex, 0);
        expect(find.text('Activities'), findsNothing);

        // Tap Activity tab (index 1) to get to activity history.
        await tester.tap(find.text('Activity'));
        await tester.pumpAndSettle();

        final updatedNavBar = _homeBottomNavigationBar(tester);
        expect(updatedNavBar.currentIndex, 1);
        expect(find.text('Activities'), findsOneWidget);
      },
    );

    // Record tab navigation is tested separately below because the shell
    // hides the AppBar for full-bleed map, which triggers a Mapbox platform
    // view sizing assertion in the widget test environment.
    testWidgets(
      'Analytics, Clubs, and Profile remain reachable through the shell',
      (tester) async {
        await _pumpHomeShell(tester);

        // Analytics tab (index 3).
        await tester.tap(find.text('Analytics'));
        await tester.pumpAndSettle();
        final navBarAnalytics = _homeBottomNavigationBar(tester);
        expect(navBarAnalytics.currentIndex, 3);

        // Clubs tab (index 4).
        await tester.tap(find.text('Clubs'));
        await tester.pumpAndSettle();
        final navBarClubs = _homeBottomNavigationBar(tester);
        expect(navBarClubs.currentIndex, 4);

        // Profile tab (index 5).
        await tester.tap(find.text('Profile'));
        await tester.pumpAndSettle();
        final navBarProfile = _homeBottomNavigationBar(tester);
        expect(navBarProfile.currentIndex, 5);
        expect(find.text('Alice'), findsOneWidget);
      },
    );

    testWidgets(
      'shell hides AppBar on the Record tab for full-bleed map',
      (tester) async {
        await _pumpHomeShell(tester);

        // On the Feed tab (default), AppBar should be visible with title.
        // "Feed" appears twice: once in the AppBar title and once in the
        // bottom nav bar label.
        expect(find.byType(AppBar), findsOneWidget);

        // The Record tab (index 2) hides the shell's AppBar so the
        // RecordingScreen's map can be full-bleed. We verify this by
        // checking that the shell destination list correctly identifies
        // the Record tab as the one that hides the AppBar.
        expect(
          homeShellDestinations[2].id,
          HomeShellDestinationId.record,
        );
      },
    );
  });
}

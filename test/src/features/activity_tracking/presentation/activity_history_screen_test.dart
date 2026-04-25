import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/common_widgets/sport_type_icon.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_history_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';

import '../application/tracking_controller_test_support.dart';

/// ## Test Scenarios
/// - `[positive]` Leading sport icons render per saved session sport type.
/// - `[positive]` User-entered non-empty titles are preserved unchanged.
/// - `[positive]` Null or blank titles fall back to `generateDefaultActivityTitle`.
/// - `[negative]` History-specific icon/title branching is not introduced.
/// - `[isolation]` Account-switch cleanup for `savedActivitiesProvider` is owned by `integration_test/auth_lifecycle_smoke_test.dart`; this file stays focused on local presentation contracts.
class MockSavedActivitiesLoader extends Mock {
  Future<List<TrackingSessionRecord>> call();
}

SportTypeIcon _requireSportTypeIcon(ListTile tile) {
  final leading = tile.leading;
  if (leading is! SportTypeIcon) {
    throw StateError('Expected SportTypeIcon leading widget');
  }
  return leading;
}

Future<void> _dragToRefresh(WidgetTester tester, Finder dragTarget) async {
  await tester.drag(dragTarget, const Offset(0, 300));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

TrackingSessionRecord _buildSavedSession({
  required int id,
  String? remoteId,
  String? sportType,
  String? title,
  DateTime? startedAt,
}) {
  final sessionStartedAt = startedAt ?? DateTime(2025, 1, id);
  final sessionStoppedAt = sessionStartedAt.add(const Duration(minutes: 30));
  return TrackingSessionRecord(
    id: id,
    status: TrackingSessionStatus.saved,
    createdAt: sessionStartedAt,
    updatedAt: sessionStoppedAt,
    startedAt: sessionStartedAt,
    stoppedAt: sessionStoppedAt,
    distanceMeters: 5000,
    movingTimeSeconds: 1500,
    remoteId: remoteId,
    sportType: sportType,
    title: title,
  );
}

Future<void> _swipeToDeleteActivity(WidgetTester tester, int sessionId) async {
  await tester.drag(
    find.byKey(ValueKey<String>('activity_dismissible_$sessionId')),
    const Offset(-500, 0),
  );
  await tester.pumpAndSettle();
}

class CountingSavedActivitiesRepository extends FakeTrackingRepository {
  int loadSavedSessionsCallCount = 0;

  @override
  Future<List<TrackingSessionRecord>> loadSavedSessions() async {
    loadSavedSessionsCallCount += 1;
    return super.loadSavedSessions();
  }
}

class ThrowingDeleteHistoryRepository
    extends CountingSavedActivitiesRepository {
  @override
  Future<void> deleteActivity(int sessionId) async {
    throw StateError('Local delete failed for session $sessionId');
  }
}

void main() {
  testWidgets(
    'renders leading SportTypeIcon and preserves shared fallback icon behavior',
    (tester) async {
      final activitiesLoader = MockSavedActivitiesLoader();
      final activities = [
        _buildSavedSession(id: 101, sportType: 'run'),
        _buildSavedSession(id: 102, sportType: 'ride'),
        _buildSavedSession(id: 103),
        _buildSavedSession(id: 104, sportType: 'ski'),
      ];

      when(activitiesLoader.call).thenAnswer((_) async => activities);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            savedActivitiesProvider.overrideWith((ref) => activitiesLoader()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ActivityHistoryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SportTypeIcon), findsNWidgets(4));

      final runTile = tester.widget<ListTile>(
        find.byKey(ActivityHistoryScreen.activityCardKey(101)),
      );
      final rideTile = tester.widget<ListTile>(
        find.byKey(ActivityHistoryScreen.activityCardKey(102)),
      );
      final nullSportTile = tester.widget<ListTile>(
        find.byKey(ActivityHistoryScreen.activityCardKey(103)),
      );
      final unknownSportTile = tester.widget<ListTile>(
        find.byKey(ActivityHistoryScreen.activityCardKey(104)),
      );

      final runIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(ActivityHistoryScreen.activityCardKey(101)),
          matching: find.byType(Icon),
        ),
      );
      final rideIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(ActivityHistoryScreen.activityCardKey(102)),
          matching: find.byType(Icon),
        ),
      );
      final nullSportIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(ActivityHistoryScreen.activityCardKey(103)),
          matching: find.byType(Icon),
        ),
      );
      final unknownSportIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(ActivityHistoryScreen.activityCardKey(104)),
          matching: find.byType(Icon),
        ),
      );

      final runLeading = _requireSportTypeIcon(runTile);
      final rideLeading = _requireSportTypeIcon(rideTile);
      final nullLeading = _requireSportTypeIcon(nullSportTile);
      final unknownLeading = _requireSportTypeIcon(unknownSportTile);

      expect(runLeading.sportType, 'run');
      expect(rideLeading.sportType, 'ride');
      expect(nullLeading.sportType, isNull);
      expect(unknownLeading.sportType, 'ski');
      expect(runIcon.icon, Icons.directions_run);
      expect(rideIcon.icon, Icons.directions_bike);
      expect(nullSportIcon.icon, Icons.fitness_center);
      expect(unknownSportIcon.icon, Icons.fitness_center);
    },
  );

  testWidgets(
    'uses saved title when non-empty and falls back to shared default titles for null or blank',
    (tester) async {
      final activitiesLoader = MockSavedActivitiesLoader();
      final customTitleStart = DateTime(2025, 1, 6, 6);
      final nullTitleStart = DateTime(2025, 1, 6, 12);
      final blankTitleStart = DateTime(2025, 1, 6, 18);
      final activities = [
        _buildSavedSession(
          id: 201,
          startedAt: customTitleStart,
          sportType: 'run',
          title: 'Track workout title',
        ),
        _buildSavedSession(
          id: 202,
          startedAt: nullTitleStart,
          sportType: 'run',
        ),
        _buildSavedSession(
          id: 203,
          startedAt: blankTitleStart,
          sportType: 'ride',
          title: '   ',
        ),
      ];

      when(activitiesLoader.call).thenAnswer((_) async => activities);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            savedActivitiesProvider.overrideWith((ref) => activitiesLoader()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ActivityHistoryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fallbackRunTitle = generateDefaultActivityTitle(
        startedAt: nullTitleStart,
        sportType: 'run',
      );
      final fallbackRideTitle = generateDefaultActivityTitle(
        startedAt: blankTitleStart,
        sportType: 'ride',
      );

      expect(find.text('Track workout title'), findsOneWidget);
      expect(find.text(fallbackRunTitle), findsOneWidget);
      expect(find.text(fallbackRideTitle), findsOneWidget);
    },
  );

  testWidgets('renders saved activities list with summary values', (
    tester,
  ) async {
    final activitiesLoader = MockSavedActivitiesLoader();
    final activities = [
      TrackingSessionRecord(
        id: 10,
        status: TrackingSessionStatus.saved,
        createdAt: DateTime(2025, 1, 5, 8),
        updatedAt: DateTime(2025, 1, 5, 8, 35),
        startedAt: DateTime(2025, 1, 5, 8),
        distanceMeters: 5010,
        movingTimeSeconds: 1600,
      ),
      TrackingSessionRecord(
        id: 11,
        status: TrackingSessionStatus.saved,
        createdAt: DateTime(2025, 1, 4, 7),
        updatedAt: DateTime(2025, 1, 4, 7, 28),
        startedAt: DateTime(2025, 1, 4, 7),
        distanceMeters: 3180,
        movingTimeSeconds: 1400,
      ),
      TrackingSessionRecord(
        id: 12,
        status: TrackingSessionStatus.saved,
        createdAt: DateTime(2025, 1, 3, 6),
        updatedAt: DateTime(2025, 1, 3, 6, 20),
        startedAt: DateTime(2025, 1, 3, 6),
        distanceMeters: 1500,
        movingTimeSeconds: 780,
      ),
    ];

    when(activitiesLoader.call).thenAnswer((_) async => activities);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          savedActivitiesProvider.overrideWith((ref) => activitiesLoader()),
        ],
        child: const MaterialApp(home: Scaffold(body: ActivityHistoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNWidgets(3));
    // Card titles use the shared time-of-day fallback title.
    expect(find.text('Morning Run'), findsNWidgets(3));
    expect(
      find.byKey(ActivityHistoryScreen.activityCardKey(10)),
      findsOneWidget,
    );
    expect(
      find.byKey(ActivityHistoryScreen.activityCardKey(11)),
      findsOneWidget,
    );
    expect(
      find.byKey(ActivityHistoryScreen.activityCardKey(12)),
      findsOneWidget,
    );

    expect(find.text(formatDateLabel(activities[0].startedAt)), findsOneWidget);
    expect(find.text('5.01 km'), findsOneWidget);
    expect(find.text('00:26:40'), findsOneWidget);
  });

  testWidgets('wraps each saved activity row in a Dismissible', (tester) async {
    final repository = CountingSavedActivitiesRepository();
    repository.sessionsById[10] = _buildSavedSession(id: 10);
    repository.sessionsById[11] = _buildSavedSession(id: 11);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingRepositoryProvider.overrideWithValue(repository),
          syncServiceProvider.overrideWithValue(FakeSyncService()),
        ],
        child: const MaterialApp(home: Scaffold(body: ActivityHistoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Dismissible), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('activity_dismissible_10')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('activity_dismissible_11')),
      findsOneWidget,
    );
  });

  testWidgets(
    'swipe starts delete confirmation, cancel keeps row, confirm removes row',
    (tester) async {
      final repository = CountingSavedActivitiesRepository();
      final syncService = FakeSyncService();
      repository.sessionsById[44] = _buildSavedSession(
        id: 44,
        remoteId: 'remote-44',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
            syncServiceProvider.overrideWithValue(syncService),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ActivityHistoryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _swipeToDeleteActivity(tester, 44);
      expect(find.text('Delete activity?'), findsOneWidget);
      expect(find.textContaining('permanent'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ActivityHistoryScreen.activityCardKey(44)),
        findsOneWidget,
      );

      await _swipeToDeleteActivity(tester, 44);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ActivityHistoryScreen.activityCardKey(44)),
        findsNothing,
      );
      expect(syncService.deletedRemoteActivityIds, ['remote-44']);
    },
  );

  testWidgets(
    'deletion uses remoteId source-of-truth and invalidates savedActivitiesProvider',
    (tester) async {
      final repository = CountingSavedActivitiesRepository();
      final syncService = FakeSyncService();
      repository.sessionsById[51] = _buildSavedSession(
        id: 51,
        remoteId: 'remote-51',
      );
      repository.sessionsById[52] = _buildSavedSession(id: 52);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
            syncServiceProvider.overrideWithValue(syncService),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ActivityHistoryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialLoadCount = repository.loadSavedSessionsCallCount;

      await _swipeToDeleteActivity(tester, 51);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(syncService.deletedRemoteActivityIds, ['remote-51']);
      expect(
        repository.loadSavedSessionsCallCount,
        greaterThan(initialLoadCount),
      );

      await _swipeToDeleteActivity(tester, 52);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(syncService.deletedRemoteActivityIds, ['remote-51']);
      expect(
        find.byKey(ActivityHistoryScreen.activityCardKey(52)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'delete helper failures keep row visible and show generic snackbar message',
    (tester) async {
      final repository = ThrowingDeleteHistoryRepository();
      repository.sessionsById[61] = _buildSavedSession(id: 61);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
            syncServiceProvider.overrideWithValue(FakeSyncService()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ActivityHistoryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _swipeToDeleteActivity(tester, 61);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ActivityHistoryScreen.activityCardKey(61)),
        findsOneWidget,
      );
      expect(
        find.text('Unable to delete activity. Please try again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('renders empty state when there are no saved activities', (
    tester,
  ) async {
    final activitiesLoader = MockSavedActivitiesLoader();

    when(activitiesLoader.call).thenAnswer((_) async => []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          savedActivitiesProvider.overrideWith((ref) => activitiesLoader()),
        ],
        child: const MaterialApp(home: Scaffold(body: ActivityHistoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(ActivityHistoryScreen.emptyStateKey), findsOneWidget);
    expect(
      find.text('No saved activities yet.'),
      findsOneWidget,
    );
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets(
    'pull-to-refresh re-requests saved activities from populated state',
    (tester) async {
      final activitiesLoader = MockSavedActivitiesLoader();
      var loadCount = 0;
      final activities = [
        TrackingSessionRecord(
          id: 10,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2025, 1, 5, 8),
          updatedAt: DateTime(2025, 1, 5, 8, 35),
          startedAt: DateTime(2025, 1, 5, 8),
          distanceMeters: 5010,
          movingTimeSeconds: 1600,
        ),
      ];

      when(activitiesLoader.call).thenAnswer((_) async {
        loadCount++;
        return activities;
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            savedActivitiesProvider.overrideWith((ref) => activitiesLoader()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ActivityHistoryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(loadCount, 1);

      await _dragToRefresh(tester, find.byType(ListView));
      await tester.pumpAndSettle();

      expect(loadCount, 2);
    },
  );

  testWidgets(
    'pull-to-refresh failure keeps populated activity list visible',
    (tester) async {
      final activitiesLoader = MockSavedActivitiesLoader();
      var loadCount = 0;
      var shouldFailRefresh = false;
      final activities = [
        TrackingSessionRecord(
          id: 44,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2025, 1, 5, 8),
          updatedAt: DateTime(2025, 1, 5, 8, 35),
          startedAt: DateTime(2025, 1, 5, 8),
          distanceMeters: 5010,
          movingTimeSeconds: 1600,
        ),
      ];

      when(activitiesLoader.call).thenAnswer((_) async {
        loadCount++;
        if (shouldFailRefresh) {
          throw StateError('refresh failed');
        }
        return activities;
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            savedActivitiesProvider.overrideWith((ref) => activitiesLoader()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ActivityHistoryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ActivityHistoryScreen.activityCardKey(44)),
        findsOneWidget,
      );

      shouldFailRefresh = true;
      await _dragToRefresh(tester, find.byType(ListView));
      await tester.pumpAndSettle();

      expect(loadCount, 2);
      expect(
        find.byKey(ActivityHistoryScreen.activityCardKey(44)),
        findsOneWidget,
      );
      expect(find.byKey(ActivityHistoryScreen.errorStateKey), findsNothing);
    },
  );

  testWidgets(
    'pull-to-refresh re-requests saved activities from empty state',
    (tester) async {
      final activitiesLoader = MockSavedActivitiesLoader();
      var loadCount = 0;

      when(activitiesLoader.call).thenAnswer((_) async {
        loadCount++;
        return [];
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            savedActivitiesProvider.overrideWith((ref) => activitiesLoader()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ActivityHistoryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(loadCount, 1);
      await _dragToRefresh(
        tester,
        find.text('No saved activities yet.'),
      );
      await tester.pumpAndSettle();

      expect(loadCount, 2);
    },
  );

  testWidgets('renders loading indicator while activities are loading', (
    tester,
  ) async {
    final activitiesLoader = MockSavedActivitiesLoader();
    final loaderCompleter = Completer<List<TrackingSessionRecord>>();

    when(activitiesLoader.call).thenAnswer((_) => loaderCompleter.future);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          savedActivitiesProvider.overrideWith((ref) => activitiesLoader()),
        ],
        child: const MaterialApp(home: Scaffold(body: ActivityHistoryScreen())),
      ),
    );
    await tester.pump();

    expect(find.byKey(ActivityHistoryScreen.loadingStateKey), findsOneWidget);
    expect(
      find.byKey(ActivityHistoryScreen.loadingIndicatorKey),
      findsOneWidget,
    );

    loaderCompleter.complete([]);
    await tester.pumpAndSettle();
  });

  testWidgets('renders a generic error when loading saved activities fails', (
    tester,
  ) async {
    final activitiesLoader = MockSavedActivitiesLoader();

    when(activitiesLoader.call).thenThrow(
      StateError('Failed to query tracking_sessions table.'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          savedActivitiesProvider.overrideWith((ref) => activitiesLoader()),
        ],
        child: const MaterialApp(home: Scaffold(body: ActivityHistoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(ActivityHistoryScreen.errorStateKey), findsOneWidget);
    expect(
      find.text('Unable to load activity history. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('tracking_sessions'), findsNothing);
  });

  testWidgets('retries failed load and recovers after tapping retry button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var shouldSucceed = false;
      var loadCount = 0;

      final recoveredActivities = [
        TrackingSessionRecord(
          id: 22,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2025, 1, 2, 7),
          updatedAt: DateTime(2025, 1, 2, 7, 45),
          startedAt: DateTime(2025, 1, 2, 7),
          distanceMeters: 6400,
          movingTimeSeconds: 1800,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            savedActivitiesProvider.overrideWith((ref) {
              loadCount++;
              if (!shouldSucceed) {
                return Future<List<TrackingSessionRecord>>.error(
                  StateError('tracking_sessions exploded'),
                );
              }
              return Future<List<TrackingSessionRecord>>.value(
                recoveredActivities,
              );
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ActivityHistoryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ActivityHistoryScreen.errorStateKey), findsOneWidget);
      expect(
        find.text('Unable to load activity history. Please try again.'),
        findsOneWidget,
      );
      expect(find.byKey(ActivityHistoryScreen.retryButtonKey), findsOneWidget);
      expect(find.textContaining('tracking_sessions'), findsNothing);
      expect(find.bySemanticsLabel('Retry'), findsAtLeastNWidgets(1));

      shouldSucceed = true;
      await tester.tap(find.byKey(ActivityHistoryScreen.retryButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ActivityHistoryScreen.activityCardKey(22)),
        findsOneWidget,
      );
      expect(find.text('Morning Run'), findsOneWidget);
      expect(loadCount, greaterThan(1));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'pull-to-refresh re-requests saved activities from error state',
    (tester) async {
      final activitiesLoader = MockSavedActivitiesLoader();
      var loadCount = 0;

      when(activitiesLoader.call).thenAnswer((_) async {
        loadCount++;
        throw StateError('load failed');
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            savedActivitiesProvider.overrideWith((ref) => activitiesLoader()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ActivityHistoryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(loadCount, 1);
      await _dragToRefresh(
        tester,
        find.text('Unable to load activity history. Please try again.'),
      );
      await tester.pumpAndSettle();

      expect(loadCount, 2);
    },
  );

  testWidgets('renders populated activity history in dark theme', (
    tester,
  ) async {
    final activitiesLoader = MockSavedActivitiesLoader();
    final activities = [
      TrackingSessionRecord(
        id: 91,
        status: TrackingSessionStatus.saved,
        createdAt: DateTime(2025, 2, 1, 7),
        updatedAt: DateTime(2025, 2, 1, 7, 20),
        startedAt: DateTime(2025, 2, 1, 7),
        distanceMeters: 5000,
        movingTimeSeconds: 1500,
      ),
    ];

    when(activitiesLoader.call).thenAnswer((_) async => activities);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          savedActivitiesProvider.overrideWith((ref) => activitiesLoader()),
        ],
        child: MaterialApp(
          darkTheme: ThemeData.dark(),
          themeMode: ThemeMode.dark,
          home: const Scaffold(body: ActivityHistoryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // "Activities" title is now provided by the HomeShellScreen, not the
    // ActivityHistoryScreen itself (double-AppBar fix). Verify the screen
    // content rendered instead.
    expect(
      find.byKey(ActivityHistoryScreen.activityCardKey(91)),
      findsOneWidget,
    );
    // Card title is now the shared fallback title, not "Activity #91".
    expect(find.text('Morning Run'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state shows Start Recording button', (tester) async {
    final activitiesLoader = MockSavedActivitiesLoader();
    when(activitiesLoader.call).thenAnswer((_) async => []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          savedActivitiesProvider.overrideWith((ref) => activitiesLoader()),
        ],
        child: const MaterialApp(home: Scaffold(body: ActivityHistoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // Empty state should include a CTA button so users know how to record.
    expect(
      find.byKey(ActivityHistoryScreen.emptyStateKey),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Start Recording'),
      findsOneWidget,
    );
  });
}

// Scenario tags use markdown-style brackets (for example [positive]) that are
// parsed as references by this lint, so we ignore it for the file header block.
// ignore_for_file: comment_references

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/profile/application/privacy_zone_location_service.dart';
import 'package:uff/src/features/profile/application/privacy_zone_providers.dart';
import 'package:uff/src/features/profile/data/privacy_zone_repository.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';
import 'package:uff/src/features/profile/presentation/privacy_zone_form_screen.dart';
import 'package:uff/src/features/profile/presentation/profile_routes.dart';
import 'package:uff/src/features/profile/presentation/privacy_zones_screen.dart';

import '../privacy_zone_test_support.dart';

/// ## Test Scenarios
/// - [positive] Shows privacy zone rows with labels and radius meters
/// - [positive] Every zone row shows a coordinate subtitle
/// - [positive] Add CTA pushes the create route
/// - [positive] Swipe-to-delete confirmed calls deleteZone with correct zone ID
/// - [negative] Cancelling swipe-delete confirmation does NOT call delete
/// - [isolation] Loading state shown while zones are unresolved
/// - [edge] Shows explanation copy and add CTA for empty state
/// - [error] Shows an error message when the repository throws
/// - [positive] Renders privacy zones content in dark theme

class _PrivacyZonesScreenFakeLocationService
    implements PrivacyZoneLocationService {
  const _PrivacyZonesScreenFakeLocationService();

  @override
  Future<PrivacyZoneCurrentLocationResult> fetchCurrentLocation() async {
    return const PrivacyZoneCurrentLocationResult.failure(
      PrivacyZoneCurrentLocationFailure.permissionDenied,
    );
  }
}

Widget _buildScreen({required PrivacyZoneRepository repository}) {
  return ProviderScope(
    overrides: [privacyZoneRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: PrivacyZonesScreen()),
  );
}

Widget _buildRouterScreen({required PrivacyZoneRepository repository}) {
  final router = GoRouter(
    initialLocation: ProfileRoutes.privacyZonesPath,
    routes: [
      GoRoute(
        path: ProfileRoutes.privacyZonesPath,
        builder: (_, __) => const PrivacyZonesScreen(),
      ),
      GoRoute(
        path: ProfileRoutes.privacyZonesNewPath,
        builder: (_, __) => const PrivacyZoneFormScreen(),
      ),
      GoRoute(
        path: ProfileRoutes.privacyZonesPathPattern,
        builder: (_, state) =>
            PrivacyZoneFormScreen(zoneId: state.pathParameters['id']),
      ),
    ],
  );
  addTearDown(router.dispose);

  return ProviderScope(
    overrides: [
      privacyZoneRepositoryProvider.overrideWithValue(repository),
      privacyZoneLocationServiceProvider.overrideWithValue(
        const _PrivacyZonesScreenFakeLocationService(),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _dragToRefresh(WidgetTester tester, Finder dragTarget) async {
  await tester.drag(dragTarget, const Offset(0, 300));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// ## Test Scenarios
/// - [positive] Privacy zones list, empty state, and navigation routes render correctly
/// - [positive] Add button is an IconButton in AppBar.actions, not an OutlinedButton in body
/// - [positive] Every zone row shows a coordinate subtitle
/// - [positive] Swipe-to-delete confirmed calls deleteZone with correct zone ID
/// - [negative] Cancelling swipe-delete confirmation does NOT call delete
/// - [isolation] Deleting one user's zone does not affect other zone rows
/// - [error] Load and mutation failures expose retry-safe copy and refresh behavior
/// - [statemachine] Pull-to-refresh re-runs provider loading after transient failures
void main() {
  group('PrivacyZonesScreen', () {
    testWidgets('shows loading state while privacy zones are unresolved', (
      tester,
    ) async {
      final loadingCompleter = Completer<List<PrivacyZone>>();
      final repository = FakePrivacyZoneRepository(
        loadingCompleter: loadingCompleter,
      );

      await tester.pumpWidget(_buildScreen(repository: repository));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(PrivacyZonesScreen.explanationCardKey), findsNothing);
      expect(repository.loadZonesCallCount, 1);
    });

    testWidgets('shows an error message when the repository throws', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository(
        errorToThrow: Exception('load failed'),
      );

      await tester.pumpWidget(_buildScreen(repository: repository));
      await tester.pumpAndSettle();

      expect(find.byKey(PrivacyZonesScreen.errorMessageKey), findsOneWidget);
      expect(
        find.text('Failed to load privacy zones. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets(
      'pull-to-refresh re-requests privacy zones from populated state',
      (tester) async {
        final repository = FakePrivacyZoneRepository(
          zonesToReturn: const <PrivacyZone>[
            PrivacyZone(
              id: 'zone-1',
              userId: 'user-1',
              label: 'Home',
              latitude: 40.71,
              longitude: -74.01,
              radiusMeters: 200,
            ),
          ],
        );

        await tester.pumpWidget(_buildScreen(repository: repository));
        await tester.pumpAndSettle();

        expect(repository.loadZonesCallCount, 1);

        await _dragToRefresh(
          tester,
          find.byKey(PrivacyZonesScreen.zoneRowKey('zone-1')),
        );
        await tester.pumpAndSettle();

        expect(repository.loadZonesCallCount, 2);
      },
    );

    testWidgets(
      'pull-to-refresh failure keeps populated privacy zones visible',
      (tester) async {
        final repository = FakePrivacyZoneRepository(
          zonesToReturn: const <PrivacyZone>[
            PrivacyZone(
              id: 'zone-1',
              userId: 'user-1',
              label: 'Home',
              latitude: 40.71,
              longitude: -74.01,
              radiusMeters: 200,
            ),
          ],
        );

        await tester.pumpWidget(_buildScreen(repository: repository));
        await tester.pumpAndSettle();

        expect(
          find.byKey(PrivacyZonesScreen.zoneRowKey('zone-1')),
          findsOneWidget,
        );

        repository.errorToThrow = Exception('refresh failed');
        await _dragToRefresh(
          tester,
          find.byKey(PrivacyZonesScreen.zoneRowKey('zone-1')),
        );
        await tester.pumpAndSettle();

        expect(repository.loadZonesCallCount, greaterThan(1));
        expect(
          find.byKey(PrivacyZonesScreen.zoneRowKey('zone-1')),
          findsOneWidget,
        );
        expect(find.byKey(PrivacyZonesScreen.errorMessageKey), findsNothing);
      },
    );

    testWidgets('shows explanation copy and add CTA for empty state', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository();

      await tester.pumpWidget(_buildScreen(repository: repository));
      await tester.pumpAndSettle();

      expect(find.byKey(PrivacyZonesScreen.explanationCardKey), findsOneWidget);
      expect(
        find.text(PrivacyZonesScreen.explanationCardMessage),
        findsOneWidget,
      );
      expect(
        find.byKey(PrivacyZonesScreen.addPrivacyZoneButtonKey),
        findsOneWidget,
      );
      expect(find.byKey(PrivacyZonesScreen.emptyStateKey), findsOneWidget);
      expect(find.text('No privacy zones yet.'), findsOneWidget);
    });

    testWidgets('pull-to-refresh re-requests privacy zones from empty state', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository();

      await tester.pumpWidget(_buildScreen(repository: repository));
      await tester.pumpAndSettle();

      expect(repository.loadZonesCallCount, 1);
      expect(find.byKey(PrivacyZonesScreen.emptyStateKey), findsOneWidget);

      await _dragToRefresh(
        tester,
        find.byKey(PrivacyZonesScreen.emptyStateKey),
      );
      await tester.pumpAndSettle();

      expect(repository.loadZonesCallCount, 2);
    });

    testWidgets('error state is refreshable and re-requests privacy zones', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository(
        errorToThrow: Exception('load failed'),
      );

      await tester.pumpWidget(_buildScreen(repository: repository));
      await tester.pumpAndSettle();

      final initialLoadCount = repository.loadZonesCallCount;
      expect(initialLoadCount == 0, isFalse);
      expect(find.byKey(PrivacyZonesScreen.errorMessageKey), findsOneWidget);
      expect(find.text('Pull down to refresh.'), findsOneWidget);

      await _dragToRefresh(
        tester,
        find.byKey(PrivacyZonesScreen.errorMessageKey),
      );
      await tester.pumpAndSettle();

      expect(repository.loadZonesCallCount, greaterThan(initialLoadCount));
    });

    testWidgets('shows privacy zone rows with labels and radius meters', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository(
        zonesToReturn: const <PrivacyZone>[
          PrivacyZone(
            id: 'zone-1',
            userId: 'user-1',
            label: 'Home',
            latitude: 40.71,
            longitude: -74.01,
            radiusMeters: 200,
          ),
          PrivacyZone(
            id: 'zone-2',
            userId: 'user-1',
            label: 'Office',
            latitude: 40.75,
            longitude: -73.98,
            radiusMeters: 350,
          ),
        ],
      );

      await tester.pumpWidget(_buildScreen(repository: repository));
      await tester.pumpAndSettle();

      expect(
        find.byKey(PrivacyZonesScreen.zoneRowKey('zone-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(PrivacyZonesScreen.zoneRowKey('zone-2')),
        findsOneWidget,
      );
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Office'), findsOneWidget);
      expect(find.text('200 m'), findsOneWidget);
      expect(find.text('350 m'), findsOneWidget);
      expect(find.byKey(PrivacyZonesScreen.emptyStateKey), findsNothing);
      expect(
        find.byKey(PrivacyZonesScreen.addPrivacyZoneButtonKey),
        findsOneWidget,
      );
    });

    testWidgets('add CTA pushes the create route', (tester) async {
      final repository = FakePrivacyZoneRepository();

      await tester.pumpWidget(_buildRouterScreen(repository: repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(PrivacyZonesScreen.addPrivacyZoneButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);
      // The shared create-mode app-bar title is "New Privacy Zone". Keep this
      // widget test aligned with the form screen contract so the e2e flow
      // catches real regressions instead of stale copy drift.
      expect(find.text('New Privacy Zone'), findsOneWidget);
    });

    testWidgets(
      'duplicate labels show coordinates and row tap pushes the detail route',
      (tester) async {
        final repository = FakePrivacyZoneRepository(
          zonesToReturn: const <PrivacyZone>[
            PrivacyZone(
              id: 'zone-1',
              userId: 'user-1',
              label: 'Home',
              latitude: 40.71,
              longitude: -74.01,
              radiusMeters: 200,
            ),
            PrivacyZone(
              id: 'zone-2',
              userId: 'user-1',
              label: 'Home',
              latitude: 40.72,
              longitude: -74.02,
              radiusMeters: 250,
            ),
            PrivacyZone(
              id: 'zone-3',
              userId: 'user-1',
              label: 'Office',
              latitude: 40.75,
              longitude: -73.98,
              radiusMeters: 350,
            ),
          ],
        );

        await tester.pumpWidget(_buildRouterScreen(repository: repository));
        await tester.pumpAndSettle();

        expect(find.text('40.7100, -74.0100'), findsOneWidget);
        expect(find.text('40.7200, -74.0200'), findsOneWidget);
        expect(find.text('40.7500, -73.9800'), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: find.byKey(PrivacyZonesScreen.zoneRowKey('zone-2')),
            matching: find.byType(ListTile),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);
        expect(find.text('Edit Privacy Zone'), findsOneWidget);
      },
    );

    testWidgets(
      'add button is an IconButton in AppBar.actions, not an OutlinedButton',
      (tester) async {
        final repository = FakePrivacyZoneRepository();

        await tester.pumpWidget(_buildScreen(repository: repository));
        await tester.pumpAndSettle();

        final addButton = find.byKey(
          PrivacyZonesScreen.addPrivacyZoneButtonKey,
        );
        expect(addButton, findsOneWidget);
        expect(
          find.ancestor(of: addButton, matching: find.byType(AppBar)),
          findsOneWidget,
        );
        final addIcon = tester.widget<IconButton>(addButton).icon as Icon;
        expect(addIcon.icon, Icons.add);
        expect(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(OutlinedButton),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('every zone row shows a coordinate subtitle', (tester) async {
      final repository = FakePrivacyZoneRepository(
        zonesToReturn: const <PrivacyZone>[
          PrivacyZone(
            id: 'zone-1',
            userId: 'user-1',
            label: 'Home',
            latitude: 40.71,
            longitude: -74.01,
            radiusMeters: 200,
          ),
          PrivacyZone(
            id: 'zone-2',
            userId: 'user-1',
            label: 'Office',
            latitude: 40.75,
            longitude: -73.98,
            radiusMeters: 350,
          ),
        ],
      );

      await tester.pumpWidget(_buildScreen(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('40.7100, -74.0100'), findsOneWidget);
      expect(find.text('40.7500, -73.9800'), findsOneWidget);
    });

    testWidgets(
      'swipe-to-delete confirmed calls deleteZone with correct zone ID',
      (tester) async {
        final repository = FakePrivacyZoneRepository(
          zonesToReturn: const <PrivacyZone>[
            PrivacyZone(
              id: 'zone-1',
              userId: 'user-1',
              label: 'Home',
              latitude: 40.71,
              longitude: -74.01,
              radiusMeters: 200,
            ),
            PrivacyZone(
              id: 'zone-2',
              userId: 'user-1',
              label: 'Office',
              latitude: 40.75,
              longitude: -73.98,
              radiusMeters: 350,
            ),
          ],
        );

        await tester.pumpWidget(_buildRouterScreen(repository: repository));
        await tester.pumpAndSettle();

        await tester.drag(
          find.byKey(PrivacyZonesScreen.zoneRowKey('zone-1')),
          const Offset(-500, 0),
        );
        await tester.pumpAndSettle();

        expect(find.text('Delete'), findsOneWidget);
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        expect(repository.deleteZoneCallCount, 1);
        expect(repository.lastDeletedZoneId, 'zone-1');
        expect(
          find.byKey(PrivacyZonesScreen.zoneRowKey('zone-2')),
          findsOneWidget,
        );
      },
    );

    testWidgets('cancelling swipe-delete confirmation does NOT call delete', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository(
        zonesToReturn: const <PrivacyZone>[
          PrivacyZone(
            id: 'zone-1',
            userId: 'user-1',
            label: 'Home',
            latitude: 40.71,
            longitude: -74.01,
            radiusMeters: 200,
          ),
        ],
      );

      await tester.pumpWidget(_buildRouterScreen(repository: repository));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(PrivacyZonesScreen.zoneRowKey('zone-1')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.deleteZoneCallCount, 0);
      expect(
        find.byKey(PrivacyZonesScreen.zoneRowKey('zone-1')),
        findsOneWidget,
      );
    });

    testWidgets('renders privacy zones content in dark theme', (tester) async {
      final repository = FakePrivacyZoneRepository(
        zonesToReturn: const <PrivacyZone>[
          PrivacyZone(
            id: 'zone-dark',
            userId: 'user-1',
            label: 'Home',
            latitude: 40.71,
            longitude: -74.01,
            radiusMeters: 200,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            privacyZoneRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            darkTheme: ThemeData.dark(),
            themeMode: ThemeMode.dark,
            home: const PrivacyZonesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Privacy Zones'), findsOneWidget);
      expect(find.byKey(PrivacyZonesScreen.explanationCardKey), findsOneWidget);
      expect(
        find.byKey(PrivacyZonesScreen.zoneRowKey('zone-dark')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

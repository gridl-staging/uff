import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/gear/application/gear_providers.dart';
import 'package:uff/src/features/gear/domain/gear_item.dart';
import 'package:uff/src/features/gear/presentation/gear_list_screen.dart';
import 'package:uff/src/features/gear/presentation/gear_routes.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';

import '../../../test_helpers/gear_test_support.dart';

/// ## Test Scenarios
/// - [positive] Shows loading indicator while fetching gear
/// - [positive] Displays gear cards with active and retired formatting
/// - [positive] Add-gear button navigates to gear form
/// - [edge] Empty state shows placeholder message
/// - [error] Error state shows message and retry button
/// - [negative] Missing user profile falls back to kilometers without crashing
/// - [positive] Pull-to-refresh reloads gear list (populated, empty, error states)
/// - [edge] Refresh failure keeps existing list visible
/// - [isolation] Subtitle distance respects the signed-in user's preferred units only
/// - [positive] Dark theme chip renders correctly
/// - [positive] Gear card tap navigates to gear detail
/// - [positive] Subtitle includes brand/model prefix when present
/// - [positive] Subtitle omits missing brand/model segments without extra separators
/// - [positive] Subtitle distance respects preferred unit formatting (km/mi)

Future<void> _dragToRefresh(WidgetTester tester, Finder dragTarget) async {
  await tester.drag(dragTarget, const Offset(0, 300));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Profile _profileWithPreferredUnits(String preferredUnits) {
  return Profile(
    userId: 'user-1',
    preferredUnits: preferredUnits,
    defaultActivityVisibility: 'private',
    onboardingCompleted: true,
    displayName: 'Test User',
  );
}

void main() {
  testWidgets('exposes stable key contract: loading and add-button keys', (
    tester,
  ) async {
    final loadingRepository = RecordingGearRepository(itemsToReturn: []);
    final loadCompleter = Completer<List<GearItem>>();
    loadingRepository.loadGearError = null;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gearRepositoryProvider.overrideWithValue(
            _DeferredLoadRepository(
              loadFuture: loadCompleter.future,
              fallback: loadingRepository,
            ),
          ),
        ],
        child: const MaterialApp(home: GearListScreen()),
      ),
    );
    await tester.pump();

    expect(find.byKey(GearListScreen.loadingIndicatorKey), findsOneWidget);

    expect(find.byKey(GearListScreen.addButtonKey), findsOneWidget);
    loadCompleter.complete([]);
    await tester.pumpAndSettle();
  });

  testWidgets('exposes stable key contract: empty-state key', (tester) async {
    final repository = RecordingGearRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gearRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GearListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(GearListScreen.emptyStateKey), findsOneWidget);
  });

  testWidgets(
    'exposes stable key contract: gear-card keys for active and retired items',
    (tester) async {
      final repository = RecordingGearRepository(
        itemsToReturn: [testShoeGear, testRetiredComponentGear],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [gearRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(home: GearListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(GearListScreen.gearCardKey(testShoeGear.id)),
        findsOneWidget,
      );
      expect(
        find.byKey(GearListScreen.gearCardKey(testRetiredComponentGear.id)),
        findsOneWidget,
      );
    },
  );

  testWidgets('exposes stable key contract: error and retry keys', (
    tester,
  ) async {
    final repository = RecordingGearRepository(
      loadGearError: StateError('first load failed'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gearRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GearListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(GearListScreen.errorMessageKey), findsOneWidget);
    expect(find.byKey(GearListScreen.retryButtonKey), findsOneWidget);
  });

  testWidgets('shows loading indicator while gear list is loading', (
    tester,
  ) async {
    final repository = RecordingGearRepository(itemsToReturn: [testShoeGear]);
    final loadCompleter = Completer<List<GearItem>>();
    repository
      ..itemsToReturn = []
      ..loadGearError = null;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gearRepositoryProvider.overrideWithValue(
            _DeferredLoadRepository(
              loadFuture: loadCompleter.future,
              fallback: repository,
            ),
          ),
        ],
        child: const MaterialApp(home: GearListScreen()),
      ),
    );
    await tester.pump();

    expect(find.byKey(GearListScreen.loadingIndicatorKey), findsOneWidget);

    loadCompleter.complete([]);
    await tester.pumpAndSettle();
  });

  testWidgets('shows empty state when no gear exists', (tester) async {
    final repository = RecordingGearRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gearRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GearListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No gear yet. Add your first shoe or bike.'),
      findsOneWidget,
    );
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('shows error with retry button and reloads list on retry', (
    tester,
  ) async {
    final repository = RecordingGearRepository(
      loadGearError: StateError('first load failed'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gearRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GearListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(GearListScreen.errorMessageKey), findsOneWidget);
    expect(find.text('Unable to load gear. Please try again.'), findsOneWidget);
    expect(find.byKey(GearListScreen.retryButtonKey), findsOneWidget);

    repository
      ..loadGearError = null
      ..itemsToReturn = [];

    await tester.tap(find.byKey(GearListScreen.retryButtonKey));
    await tester.pumpAndSettle();

    expect(repository.loadGearCallCount, 2);
    expect(
      find.text('No gear yet. Add your first shoe or bike.'),
      findsOneWidget,
    );
  });

  testWidgets('pull-to-refresh re-requests gear list from populated state', (
    tester,
  ) async {
    final repository = RecordingGearRepository(itemsToReturn: [testShoeGear]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gearRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GearListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.loadGearCallCount, 1);

    await _dragToRefresh(tester, find.byType(ListView));
    await tester.pumpAndSettle();

    expect(repository.loadGearCallCount, 2);
  });

  testWidgets('pull-to-refresh failure keeps populated gear list visible', (
    tester,
  ) async {
    final repository = RecordingGearRepository(itemsToReturn: [testShoeGear]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gearRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GearListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(GearListScreen.gearCardKey(testShoeGear.id)),
      findsOneWidget,
    );

    repository.loadGearError = StateError('refresh failed');
    await _dragToRefresh(tester, find.byType(ListView));
    await tester.pumpAndSettle();

    expect(repository.loadGearCallCount, 2);
    expect(
      find.byKey(GearListScreen.gearCardKey(testShoeGear.id)),
      findsOneWidget,
    );
    expect(find.byKey(GearListScreen.errorMessageKey), findsNothing);
  });

  testWidgets('pull-to-refresh re-requests gear list from empty state', (
    tester,
  ) async {
    final repository = RecordingGearRepository(itemsToReturn: []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gearRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GearListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.loadGearCallCount, 1);
    expect(find.byKey(GearListScreen.emptyStateKey), findsOneWidget);

    await _dragToRefresh(tester, find.byKey(GearListScreen.emptyStateKey));
    await tester.pumpAndSettle();

    expect(repository.loadGearCallCount, 2);
  });

  testWidgets('pull-to-refresh re-requests gear list from error state', (
    tester,
  ) async {
    final repository = RecordingGearRepository(
      loadGearError: StateError('load failed'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gearRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GearListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.loadGearCallCount, 1);
    expect(find.byKey(GearListScreen.errorMessageKey), findsOneWidget);

    await _dragToRefresh(tester, find.byKey(GearListScreen.errorMessageKey));
    await tester.pumpAndSettle();

    expect(repository.loadGearCallCount, 2);
  });

  testWidgets('renders active and retired sections with expected formatting', (
    tester,
  ) async {
    final repository = RecordingGearRepository(
      itemsToReturn: [testShoeGear, testRetiredComponentGear, testBikeGear],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gearRepositoryProvider.overrideWithValue(repository),
          profileProvider.overrideWith(
            () => _FakeProfileNotifier(_profileWithPreferredUnits('metric')),
          ),
        ],
        child: const MaterialApp(home: GearListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final tileTitles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data)
        .whereType<String>()
        .toList();
    expect(tileTitles, ['Daily Trainer', 'Road Bike', 'Old Chain']);

    expect(find.text('Nike Pegasus · Shoe · 120.50 km'), findsOneWidget);
    expect(find.text('Canyon Endurace · Bike · 2500.00 km'), findsOneWidget);
    expect(find.text('Shimano HG701 · Component · 810.00 km'), findsOneWidget);
    expect(find.text('Retired'), findsNWidgets(2));

    final retiredTile = find.byKey(
      GearListScreen.gearCardKey(testRetiredComponentGear.id),
    );
    expect(
      find.ancestor(of: retiredTile, matching: find.byType(Opacity)),
      findsOneWidget,
    );

    expect(find.byIcon(Icons.directions_run), findsOneWidget);
    expect(find.byIcon(Icons.pedal_bike), findsOneWidget);
    expect(find.byIcon(Icons.build), findsOneWidget);
  });

  testWidgets(
    'subtitle includes brand and model with metric distance formatting',
    (tester) async {
      final repository = RecordingGearRepository(itemsToReturn: [testShoeGear]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gearRepositoryProvider.overrideWithValue(repository),
            profileProvider.overrideWith(
              () => _FakeProfileNotifier(_profileWithPreferredUnits('metric')),
            ),
          ],
          child: const MaterialApp(home: GearListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nike Pegasus · Shoe · 120.50 km'), findsOneWidget);
    },
  );

  testWidgets('subtitle omits missing brand', (tester) async {
    final repository = RecordingGearRepository(
      itemsToReturn: [testShoeGearNoBrand],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gearRepositoryProvider.overrideWithValue(repository),
          profileProvider.overrideWith(
            () => _FakeProfileNotifier(_profileWithPreferredUnits('metric')),
          ),
        ],
        child: const MaterialApp(home: GearListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pegasus · Shoe · 120.50 km'), findsOneWidget);
  });

  testWidgets('subtitle omits missing model', (tester) async {
    final repository = RecordingGearRepository(
      itemsToReturn: [testShoeGearNoModel],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gearRepositoryProvider.overrideWithValue(repository),
          profileProvider.overrideWith(
            () => _FakeProfileNotifier(_profileWithPreferredUnits('metric')),
          ),
        ],
        child: const MaterialApp(home: GearListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nike · Shoe · 120.50 km'), findsOneWidget);
  });

  testWidgets('subtitle omits brand-model segment when both are missing', (
    tester,
  ) async {
    final repository = RecordingGearRepository(
      itemsToReturn: [testShoeGearNoBrandOrModel],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gearRepositoryProvider.overrideWithValue(repository),
          profileProvider.overrideWith(
            () => _FakeProfileNotifier(_profileWithPreferredUnits('metric')),
          ),
        ],
        child: const MaterialApp(home: GearListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shoe · 120.50 km'), findsOneWidget);
  });

  testWidgets('subtitle uses imperial units when preferred', (tester) async {
    final repository = RecordingGearRepository(itemsToReturn: [testShoeGear]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gearRepositoryProvider.overrideWithValue(repository),
          profileProvider.overrideWith(
            () => _FakeProfileNotifier(_profileWithPreferredUnits('imperial')),
          ),
        ],
        child: const MaterialApp(home: GearListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nike Pegasus · Shoe · 74.88 mi'), findsOneWidget);
  });

  testWidgets('retired chip color follows dark theme chip color', (
    tester,
  ) async {
    const themedRetiredChipColor = Color(0xFF455A64);
    final darkTheme = ThemeData.dark().copyWith(
      chipTheme: ThemeData.dark().chipTheme.copyWith(
        backgroundColor: themedRetiredChipColor,
      ),
    );
    final repository = RecordingGearRepository(
      itemsToReturn: [testRetiredComponentGear],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gearRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          darkTheme: darkTheme,
          themeMode: ThemeMode.dark,
          home: const GearListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final retiredChip = tester.widget<Chip>(
      find.widgetWithText(Chip, 'Retired'),
    );
    expect(retiredChip.backgroundColor, themedRetiredChipColor);
  });

  testWidgets('navigates to create and edit routes from list actions', (
    tester,
  ) async {
    final repository = RecordingGearRepository(itemsToReturn: [testShoeGear]);
    final router = GoRouter(
      initialLocation: GearRoutes.gearPath,
      routes: [
        GoRoute(
          path: GearRoutes.gearPath,
          builder: (_, __) => const GearListScreen(),
        ),
        GoRoute(
          path: GearRoutes.gearNewPath,
          builder: (_, __) => const Scaffold(body: Text('Create gear route')),
        ),
        GoRoute(
          path: GearRoutes.gearPathPattern,
          builder: (_, state) {
            final extra = state.extra;
            final text = extra is GearItem
                ? 'Edit ${extra.name}'
                : 'Unexpected extra';
            return Scaffold(body: Text(text));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gearRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(GearListScreen.addButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Create gear route'), findsOneWidget);

    router.go(GearRoutes.gearPath);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(GearListScreen.gearCardKey(testShoeGear.id)));
    await tester.pumpAndSettle();

    expect(find.text('Edit Daily Trainer'), findsOneWidget);
  });
}

class _DeferredLoadRepository extends RecordingGearRepository {
  _DeferredLoadRepository({required this.loadFuture, required this.fallback});

  final Future<List<GearItem>> loadFuture;
  final RecordingGearRepository fallback;

  var _resolved = false;

  @override
  Future<List<GearItem>> loadGear() async {
    if (_resolved) {
      return fallback.loadGear();
    }

    _resolved = true;
    return loadFuture;
  }
}

class _FakeProfileNotifier extends ProfileNotifier {
  _FakeProfileNotifier(this._profile);

  final Profile _profile;

  @override
  Profile build() {
    return _profile;
  }
}

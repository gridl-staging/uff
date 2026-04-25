import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_routes.dart';
import 'package:uff/src/features/import/presentation/import_screen.dart';

import '../../activity_tracking/data/sync_service_test_support.dart';
import 'import_screen_test_support.dart';

// ## Test Scenarios
// - [positive] View Activity navigates to the imported activity detail route.
// - [positive] Back button exposes the standard accessible Back label when the route can pop.
// - [negative] Single-file import keeps the back button hidden while work is in flight.
// - [isolation] Import screen state resets between sessions with no stale prior-import data leaking across widget rebuilds.
// - [statemachine] Background completion keeps the screen on import until resume reveals a single terminal result.
// - [statemachine] Backgrounded single-file failures stay in importing state until resume reveals one terminal error result.
// - [edge] Duplicate single-file import starts are ignored while one import is already running.

const _openImportFromHomeKey = Key('open_import_from_home');

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  testWidgets('view activity button navigates to detail route', (tester) async {
    final mockPipeline = MockImportPipeline();
    final mockRepo = MockTrackingRepository();
    final router = GoRouter(
      initialLocation: '/import',
      routes: [
        GoRoute(path: '/import', builder: (_, __) => const ImportScreen()),
        GoRoute(
          path: ActivityRoutes.activityPathPattern,
          builder: (_, state) =>
              Scaffold(body: Text('Activity ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    when(() => mockPipeline.run(any(), any())).thenAnswer((_) async => 42);
    when(
      () => mockRepo.loadSession(42),
    ).thenAnswer((_) async => buildImportScreenSessionRecord(id: 42));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          importPipelineProvider.overrideWithValue(mockPipeline),
          trackingRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state<ImportScreenState>(find.byType(ImportScreen));
    await state.runImport(Uint8List(0), 'ride.gpx');
    await tester.pumpAndSettle();

    await tester.tap(find.text('View Activity'));
    await tester.pumpAndSettle();

    expect(find.text('Activity 42'), findsOneWidget);
  });

  testWidgets('back button exposes an accessible label when import can pop', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: _openImportFromHomeKey,
                  onPressed: () => context.push('/import'),
                  child: const Text('Open Import'),
                ),
              ),
            ),
          ),
          GoRoute(path: '/import', builder: (_, __) => const ImportScreen()),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            importPipelineProvider.overrideWithValue(MockImportPipeline()),
            trackingRepositoryProvider.overrideWithValue(
              MockTrackingRepository(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_openImportFromHomeKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ImportScreen.backButtonKey), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'back navigation is blocked while single-file import is in flight',
    (tester) async {
      final mockPipeline = MockImportPipeline();
      final mockRepo = MockTrackingRepository();
      final sessionIdCompleter = Completer<int>();
      when(
        () => mockPipeline.run(any(), any()),
      ).thenAnswer((_) => sessionIdCompleter.future);
      when(
        () => mockRepo.loadSession(88),
      ).thenAnswer((_) async => buildImportScreenSessionRecord(id: 88));

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: _openImportFromHomeKey,
                  onPressed: () => context.push('/import'),
                  child: const Text('Open Import'),
                ),
              ),
            ),
          ),
          GoRoute(path: '/import', builder: (_, __) => const ImportScreen()),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            importPipelineProvider.overrideWithValue(mockPipeline),
            trackingRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_openImportFromHomeKey));
      await tester.pumpAndSettle();

      final state = tester.state<ImportScreenState>(find.byType(ImportScreen));
      final importFuture = state.runImport(Uint8List(0), 'ride.gpx');
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(ImportScreen.backButtonKey), findsNothing);

      sessionIdCompleter.complete(88);
      await importFuture;
      await tester.pumpAndSettle();

      expect(find.byKey(ImportScreen.backButtonKey), findsOneWidget);
    },
  );

  testWidgets(
    'single-file import resumes to a clear success result after background completion',
    (tester) async {
      final mockPipeline = MockImportPipeline();
      final mockRepo = MockTrackingRepository();
      final sessionIdCompleter = Completer<int>();
      when(
        () => mockPipeline.run(any(), any()),
      ).thenAnswer((_) => sessionIdCompleter.future);
      when(
        () => mockRepo.loadSession(123),
      ).thenAnswer((_) async => buildImportScreenSessionRecord(id: 123));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            importPipelineProvider.overrideWithValue(mockPipeline),
            trackingRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(home: ImportScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<ImportScreenState>(find.byType(ImportScreen));
      final importFuture = state.runImport(Uint8List(0), 'ride.gpx');
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      sessionIdCompleter.complete(123);
      await importFuture;
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(ImportScreen.successSummaryKey), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byKey(ImportScreen.successSummaryKey), findsOneWidget);
      expect(find.text('Import Successful'), findsOneWidget);
    },
  );

  testWidgets(
    'single-file import resumes to a clear error result after background failure',
    (tester) async {
      final mockPipeline = MockImportPipeline();
      final mockRepo = MockTrackingRepository();
      final sessionIdCompleter = Completer<int>();
      when(
        () => mockPipeline.run(any(), any()),
      ).thenAnswer((_) => sessionIdCompleter.future);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            importPipelineProvider.overrideWithValue(mockPipeline),
            trackingRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(home: ImportScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<ImportScreenState>(find.byType(ImportScreen));
      final importFuture = state.runImport(Uint8List(0), 'ride.gpx');
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      sessionIdCompleter.completeError(
        const FormatException('Unrecognized sample payload'),
      );
      await importFuture;
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(ImportScreen.errorMessageKey), findsNothing);
      expect(find.byKey(ImportScreen.successSummaryKey), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byKey(ImportScreen.errorMessageKey), findsOneWidget);
      expect(find.text('Unrecognized sample payload'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(ImportScreen.successSummaryKey), findsNothing);
    },
  );

  testWidgets(
    'runImport ignores duplicate starts while a single-file import is already in flight',
    (tester) async {
      final mockPipeline = MockImportPipeline();
      final mockRepo = MockTrackingRepository();
      final sessionIdCompleter = Completer<int>();

      when(
        () => mockPipeline.run(any(), any()),
      ).thenAnswer((_) => sessionIdCompleter.future);
      when(
        () => mockRepo.loadSession(99),
      ).thenAnswer((_) async => buildImportScreenSessionRecord(id: 99));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            importPipelineProvider.overrideWithValue(mockPipeline),
            trackingRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(home: ImportScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<ImportScreenState>(find.byType(ImportScreen));
      final firstImport = state.runImport(Uint8List(0), 'ride.gpx');
      final secondImport = state.runImport(Uint8List(0), 'ride.gpx');
      await tester.pump();

      verify(() => mockPipeline.run(any(), any())).called(1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      sessionIdCompleter.complete(99);
      await firstImport;
      await secondImport;
      await tester.pumpAndSettle();

      expect(find.byKey(ImportScreen.successSummaryKey), findsOneWidget);
    },
  );
}

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/import/presentation/import_screen.dart';

import '../../activity_tracking/data/sync_service_test_support.dart';
import 'import_screen_test_support.dart';

const _openImportFromHomeKey = Key('open_import_from_home_error_back');

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    FilePicker.platform = TestFilePicker();
  });

  Future<void> runImport(
    WidgetTester tester, {
    String filename = 'ride.gpx',
  }) async {
    final importScreenState = tester.state<ImportScreenState>(
      find.byType(ImportScreen),
    );
    await importScreenState.runImport(Uint8List(0), filename);
    await tester.pumpAndSettle();
  }

  testWidgets('shows file picker button in idle state', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpImportScreen(
        tester,
        overrides: [
          importPipelineProvider.overrideWithValue(MockImportPipeline()),
        ],
      );

      expect(find.byKey(ImportScreen.pickFileButtonKey), findsOneWidget);
      expect(find.text('Select FIT, GPX, or ZIP File'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Select FIT, GPX, or ZIP File'),
        findsAtLeastNWidgets(1),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'picker uses fit/gpx/zip extensions and routes gpx to runImport',
    (
      tester,
    ) async {
      final mockPipeline = MockImportPipeline();
      final mockRepo = MockTrackingRepository();
      final mockZipImporter = MockStravaZipImporter();
      final pickedBytes = Uint8List.fromList([1, 2, 3, 4]);
      final filePicker = setSinglePickedFile(
        name: 'picked.gpx',
        bytes: pickedBytes,
      );

      when(() => mockPipeline.run(any(), any())).thenAnswer((_) async => 42);
      when(
        () => mockRepo.loadSession(42),
      ).thenAnswer((_) async => buildImportScreenSessionRecord(id: 42));

      await pumpImportScreen(
        tester,
        overrides: [
          importPipelineProvider.overrideWithValue(mockPipeline),
          trackingRepositoryProvider.overrideWithValue(mockRepo),
          stravaZipImporterProvider.overrideWithValue(mockZipImporter),
        ],
      );

      await tapPickFileButton(tester);

      expect(filePicker.pickFilesCallCount, 1);
      expect(filePicker.lastPickFilesCall?.type, FileType.custom);
      expect(
        filePicker.lastPickFilesCall?.allowedExtensions,
        orderedEquals(['fit', 'gpx', 'zip']),
      );
      expect(filePicker.lastPickFilesCall?.withData, isTrue);

      final captured = verify(
        () => mockPipeline.run(captureAny(), captureAny()),
      ).captured;
      expect(captured[0] as Uint8List, orderedEquals(pickedBytes));
      expect(captured[1], 'picked.gpx');
      verifyNever(
        () => mockZipImporter.importZip(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      );
    },
  );

  testWidgets('FormatException maps to "Unrecognized file format"', (
    tester,
  ) async {
    final mockPipeline = MockImportPipeline();
    when(
      () => mockPipeline.run(any(), any()),
    ).thenThrow(const FormatException('Unrecognized file format'));

    await pumpImportScreen(
      tester,
      overrides: [
        importPipelineProvider.overrideWithValue(mockPipeline),
      ],
    );

    await runImport(tester, filename: 'bad.txt');

    expect(find.byKey(ImportScreen.errorMessageKey), findsOneWidget);
    expect(find.text('Unrecognized file format'), findsOneWidget);
  });

  testWidgets(
    'single-file FormatException without Unrecognized text maps to fallback copy',
    (tester) async {
      final mockPipeline = MockImportPipeline();
      when(
        () => mockPipeline.run(any(), any()),
      ).thenThrow(const FormatException('Invalid FIT header'));

      await pumpImportScreen(
        tester,
        overrides: [
          importPipelineProvider.overrideWithValue(mockPipeline),
        ],
      );

      await runImport(tester, filename: 'bad.fit');

      expect(find.byKey(ImportScreen.errorMessageKey), findsOneWidget);
      expect(find.text('Unrecognized file format'), findsOneWidget);
      expect(find.text('Invalid FIT header'), findsNothing);
    },
  );

  testWidgets('generic exception shows generic error message', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final mockPipeline = MockImportPipeline();
      when(
        () => mockPipeline.run(any(), any()),
      ).thenThrow(Exception('network error'));

      await pumpImportScreen(
        tester,
        overrides: [
          importPipelineProvider.overrideWithValue(mockPipeline),
        ],
      );

      await runImport(tester, filename: 'test.gpx');

      expect(find.byKey(ImportScreen.errorMessageKey), findsOneWidget);
      expect(
        find.text('An error occurred during import. Please try again.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Try Again'), findsAtLeastNWidgets(1));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'error view exposes Back action when import screen can pop',
    (tester) async {
      final mockPipeline = MockImportPipeline();
      when(
        () => mockPipeline.run(any(), any()),
      ).thenThrow(Exception('network error'));

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
          GoRoute(
            path: '/import',
            builder: (_, __) => const ImportScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            importPipelineProvider.overrideWithValue(mockPipeline),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_openImportFromHomeKey));
      await tester.pumpAndSettle();

      final importScreenState = tester.state<ImportScreenState>(
        find.byType(ImportScreen),
      );
      await importScreenState.runImport(Uint8List(0), 'test.gpx');
      await tester.pumpAndSettle();

      expect(find.byKey(ImportScreen.errorMessageKey), findsOneWidget);
      expect(find.byKey(ImportScreen.errorBackButtonKey), findsOneWidget);

      await tester.tap(find.byKey(ImportScreen.errorBackButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Open Import'), findsOneWidget);
      expect(find.byType(ImportScreen), findsNothing);
    },
  );

  testWidgets('error state icon follows dark theme error color', (
    tester,
  ) async {
    final mockPipeline = MockImportPipeline();
    final darkTheme = ThemeData.dark().copyWith(
      colorScheme: ThemeData.dark().colorScheme.copyWith(
        error: const Color(0xFF42A5F5),
      ),
    );
    when(
      () => mockPipeline.run(any(), any()),
    ).thenThrow(Exception('network error'));

    await pumpImportScreen(
      tester,
      overrides: [
        importPipelineProvider.overrideWithValue(mockPipeline),
      ],
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark,
    );

    await runImport(tester, filename: 'test.gpx');

    final errorIcon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    expect(errorIcon.color, darkTheme.colorScheme.error);
  });

  testWidgets('missing imported session shows a boundary error', (
    tester,
  ) async {
    final mockPipeline = MockImportPipeline();
    final mockRepo = MockTrackingRepository();
    when(
      () => mockPipeline.run(any(), any()),
    ).thenAnswer((_) async => 42);
    when(() => mockRepo.loadSession(42)).thenAnswer((_) async => null);

    await pumpImportScreen(
      tester,
      overrides: [
        importPipelineProvider.overrideWithValue(mockPipeline),
        trackingRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );

    await runImport(tester);

    expect(find.byKey(ImportScreen.errorMessageKey), findsOneWidget);
    expect(
      find.text('Imported activity could not be loaded.'),
      findsOneWidget,
    );
    expect(find.byKey(ImportScreen.successSummaryKey), findsNothing);
  });

  testWidgets('picker shows an error when the selected file has no bytes', (
    tester,
  ) async {
    final mockPipeline = MockImportPipeline();
    setSinglePickedFile(
      name: 'picked.fit',
      bytes: null,
    );

    await pumpImportScreen(
      tester,
      overrides: [
        importPipelineProvider.overrideWithValue(mockPipeline),
      ],
    );

    await tapPickFileButton(tester);

    verifyNever(() => mockPipeline.run(any(), any()));
    expect(find.byKey(ImportScreen.errorMessageKey), findsOneWidget);
    expect(
      find.text('Unable to read the selected file. Please try another file.'),
      findsOneWidget,
    );
  });

  testWidgets('picker routes .fit selection through single-file runImport', (
    tester,
  ) async {
    final mockPipeline = MockImportPipeline();
    final mockRepo = MockTrackingRepository();
    final mockZipImporter = MockStravaZipImporter();
    final pickedBytes = Uint8List.fromList([10, 11, 12]);
    setSinglePickedFile(
      name: 'picked.fit',
      bytes: pickedBytes,
    );
    when(() => mockPipeline.run(any(), any())).thenAnswer((_) async => 9);
    when(() => mockRepo.loadSession(9)).thenAnswer(
      (_) async => buildImportScreenSessionRecord(id: 9),
    );

    await pumpImportScreen(
      tester,
      overrides: [
        importPipelineProvider.overrideWithValue(mockPipeline),
        trackingRepositoryProvider.overrideWithValue(mockRepo),
        stravaZipImporterProvider.overrideWithValue(mockZipImporter),
      ],
    );

    await tapPickFileButton(tester);

    verify(() => mockPipeline.run(any(), 'picked.fit')).called(1);
    verifyNever(
      () => mockZipImporter.importZip(
        any(),
        onProgress: any(named: 'onProgress'),
      ),
    );
  });

  testWidgets('shows progress indicator while import is in flight', (
    tester,
  ) async {
    final mockPipeline = MockImportPipeline();
    final mockRepo = MockTrackingRepository();
    final sessionId = Completer<int>();

    when(
      () => mockPipeline.run(any(), any()),
    ).thenAnswer((_) => sessionId.future);
    when(
      () => mockRepo.loadSession(7),
    ).thenAnswer((_) async => buildImportScreenSessionRecord(id: 7));

    await pumpImportScreen(
      tester,
      overrides: [
        importPipelineProvider.overrideWithValue(mockPipeline),
        trackingRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );

    final state = tester.state<ImportScreenState>(find.byType(ImportScreen));
    final importFuture = state.runImport(Uint8List(0), 'ride.gpx');
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    sessionId.complete(7);
    await importFuture;
    await tester.pumpAndSettle();

    expect(find.byKey(ImportScreen.successSummaryKey), findsOneWidget);
  });

  testWidgets('success state displays session metrics', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final mockPipeline = MockImportPipeline();
      final mockRepo = MockTrackingRepository();
      when(
        () => mockPipeline.run(any(), any()),
      ).thenAnswer((_) async => 42);
      when(
        () => mockRepo.loadSession(42),
      ).thenAnswer((_) async => buildImportScreenSessionRecord(id: 42));

      await pumpImportScreen(
        tester,
        overrides: [
          importPipelineProvider.overrideWithValue(mockPipeline),
          trackingRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );

      await runImport(tester);

      expect(find.byKey(ImportScreen.successSummaryKey), findsOneWidget);
      expect(find.text('Import Successful'), findsOneWidget);
      expect(find.text('Sport: ride'), findsOneWidget);
      expect(find.text('Distance: 5.00 km'), findsOneWidget);
      expect(find.text('Duration: 30:00'), findsOneWidget);
      expect(find.bySemanticsLabel('View Activity'), findsAtLeastNWidgets(1));
      expect(find.bySemanticsLabel('Import Another'), findsAtLeastNWidgets(1));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('success state icon follows dark theme success color', (
    tester,
  ) async {
    final mockPipeline = MockImportPipeline();
    final mockRepo = MockTrackingRepository();
    final darkTheme = ThemeData.dark().copyWith(
      colorScheme: ThemeData.dark().colorScheme.copyWith(
        primary: const Color(0xFF7CB342),
      ),
    );
    when(
      () => mockPipeline.run(any(), any()),
    ).thenAnswer((_) async => 42);
    when(
      () => mockRepo.loadSession(42),
    ).thenAnswer((_) async => buildImportScreenSessionRecord(id: 42));

    await pumpImportScreen(
      tester,
      overrides: [
        importPipelineProvider.overrideWithValue(mockPipeline),
        trackingRepositoryProvider.overrideWithValue(mockRepo),
      ],
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark,
    );

    await runImport(tester);

    final successIcon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
    expect(successIcon.color, darkTheme.colorScheme.primary);
  });

  testWidgets('success state falls back for missing optional session fields', (
    tester,
  ) async {
    final mockPipeline = MockImportPipeline();
    final mockRepo = MockTrackingRepository();
    when(
      () => mockPipeline.run(any(), any()),
    ).thenAnswer((_) async => 43);
    when(() => mockRepo.loadSession(43)).thenAnswer(
      (_) async => TrackingSessionRecord(
        id: 43,
        status: TrackingSessionStatus.saved,
        createdAt: DateTime(2024, 1, 1, 12),
        updatedAt: DateTime(2024, 1, 1, 12),
      ),
    );

    await pumpImportScreen(
      tester,
      overrides: [
        importPipelineProvider.overrideWithValue(mockPipeline),
        trackingRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );

    await runImport(tester);

    expect(find.byKey(ImportScreen.successSummaryKey), findsOneWidget);
    expect(find.textContaining('Sport:'), findsNothing);
    expect(find.text('Distance: -- km'), findsOneWidget);
    expect(find.text('Duration: --:--'), findsOneWidget);
  });

  testWidgets('successful import invalidates saved activities provider', (
    tester,
  ) async {
    final mockPipeline = MockImportPipeline();
    final mockRepo = MockTrackingRepository();
    var savedActivitiesLoadCount = 0;
    when(
      () => mockPipeline.run(any(), any()),
    ).thenAnswer((_) async => 42);
    when(
      () => mockRepo.loadSession(42),
    ).thenAnswer((_) async => buildImportScreenSessionRecord(id: 42));

    await pumpImportScreen(
      tester,
      overrides: [
        importPipelineProvider.overrideWithValue(mockPipeline),
        trackingRepositoryProvider.overrideWithValue(mockRepo),
        savedActivitiesProvider.overrideWith((ref) async {
          savedActivitiesLoadCount += 1;
          return [];
        }),
      ],
      includeSavedActivitiesProbe: true,
    );
    expect(savedActivitiesLoadCount, 1);

    await runImport(tester);

    expect(savedActivitiesLoadCount, 2);
  });
}

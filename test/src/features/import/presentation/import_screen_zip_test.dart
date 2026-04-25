import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/import/domain/zip_import_result.dart';
import 'package:uff/src/features/import/presentation/import_screen.dart';

import 'import_screen_test_support.dart';

const _openImportFromHomeKey = Key('open_import_from_home_zip_back_guard');

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    FilePicker.platform = TestFilePicker();
  });

  testWidgets(
    'picker routes .zip selection through stravaZipImporterProvider',
    (tester) async {
      final mockPipeline = MockImportPipeline();
      final mockZipImporter = MockStravaZipImporter();
      final pickedBytes = Uint8List.fromList([9, 8, 7, 6]);
      setSinglePickedFile(name: 'strava_export.zip', bytes: pickedBytes);
      stubZipImportResult(
        mockZipImporter,
        const ZipImportResult(
          successCount: 1,
          failureCount: 0,
          importedSessionIds: [55],
          errors: [],
        ),
      );

      await pumpZipImportScreen(
        tester,
        zipImporter: mockZipImporter,
        pipeline: mockPipeline,
        includeSavedActivitiesProbe: true,
      );

      await tapPickFileButton(tester);

      final captured = verify(
        () => mockZipImporter.importZip(
          captureAny(),
          onProgress: captureAny(named: 'onProgress'),
        ),
      ).captured;
      expect(captured[0] as Uint8List, orderedEquals(pickedBytes));
      verifyNever(() => mockPipeline.run(any(), any()));
    },
  );

  testWidgets('zip import renders deferred progress updates', (tester) async {
    final mockZipImporter = MockStravaZipImporter();
    setPickedImportFile(name: 'strava_export.zip', bytes: [3, 2, 1]);

    void Function(int current, int total)? onProgress;
    final resultCompleter = Completer<ZipImportResult>();
    when(
      () => mockZipImporter.importZip(
        any(),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((invocation) {
      onProgress =
          invocation.namedArguments[#onProgress]
              as void Function(int current, int total)?;
      return resultCompleter.future;
    });

    await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
    await tapPickFileButton(
      tester,
      settle: false,
      pumpFor: const Duration(milliseconds: 300),
    );

    onProgress?.call(1, 3);
    await tester.pump();

    expect(find.text('Importing 1 of 3 activities...'), findsOneWidget);

    resultCompleter.complete(
      const ZipImportResult(
        successCount: 3,
        failureCount: 0,
        importedSessionIds: [1, 2, 3],
        errors: [],
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
    'zip import renders initial progress before an immediate success summary',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'fast.zip', bytes: [8, 8, 8]);

      when(
        () => mockZipImporter.importZip(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((invocation) async {
        final onProgress =
            invocation.namedArguments[#onProgress]
                as void Function(int current, int total)?;
        onProgress?.call(0, 1);
        return const ZipImportResult(
          successCount: 1,
          failureCount: 0,
          importedSessionIds: [1],
          errors: [],
        );
      });

      await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
      await tapPickFileButton(tester, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Importing activities...'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Importing 0 of 1 activities...'), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.text('ZIP Import Complete'), findsOneWidget);
    },
  );

  testWidgets(
    'zip import shows generic importing indicator before progress callback',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'slow.zip', bytes: [6, 6, 6]);

      final resultCompleter = Completer<ZipImportResult>();
      when(
        () => mockZipImporter.importZip(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) => resultCompleter.future);

      await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
      await tapPickFileButton(
        tester,
        settle: false,
        pumpFor: const Duration(milliseconds: 1),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Importing activities...'), findsOneWidget);

      resultCompleter.complete(
        const ZipImportResult(
          successCount: 1,
          failureCount: 0,
          importedSessionIds: [1],
          errors: [],
        ),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'zip import aborts cleanly if the screen unmounts during the start delay',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'aborted.zip', bytes: [1, 2, 3]);

      await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
      await tapPickFileButton(tester, settle: false);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      verifyNever(
        () => mockZipImporter.importZip(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      );
    },
  );

  testWidgets(
    'back navigation is blocked while zip import is in flight',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'in_flight.zip', bytes: [1, 2, 3]);

      final zipResultCompleter = Completer<ZipImportResult>();
      when(
        () => mockZipImporter.importZip(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) => zipResultCompleter.future);

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
            stravaZipImporterProvider.overrideWithValue(mockZipImporter),
            importPipelineProvider.overrideWithValue(MockImportPipeline()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_openImportFromHomeKey));
      await tester.pumpAndSettle();

      await tapPickFileButton(
        tester,
        settle: false,
        pumpFor: const Duration(milliseconds: 300),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(ImportScreen.backButtonKey), findsNothing);

      zipResultCompleter.complete(
        const ZipImportResult(
          successCount: 1,
          failureCount: 0,
          importedSessionIds: [1],
          errors: [],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ImportScreen.backButtonKey), findsOneWidget);
      expect(find.text('ZIP Import Complete'), findsOneWidget);
    },
  );

  testWidgets(
    'duplicate pick-file taps do not start a second zip import while one is in flight',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'double_tap.zip', bytes: [5, 5, 5]);

      final zipResultCompleter = Completer<ZipImportResult>();
      when(
        () => mockZipImporter.importZip(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) => zipResultCompleter.future);

      await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
      final pickFileButtonFinder = find.byKey(ImportScreen.pickFileButtonKey);
      await tester.tap(pickFileButtonFinder);
      await tester.tap(pickFileButtonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      verify(
        () => mockZipImporter.importZip(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).called(1);

      zipResultCompleter.complete(
        const ZipImportResult(
          successCount: 1,
          failureCount: 0,
          importedSessionIds: [33],
          errors: [],
        ),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'zip batch failure uses error view and Try Again returns to idle',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'broken.zip', bytes: [1, 0]);
      stubZipImportError(
        mockZipImporter,
        const FormatException('Invalid ZIP archive'),
      );

      await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
      await tapPickFileButton(tester);

      expect(find.byKey(ImportScreen.errorMessageKey), findsOneWidget);
      expect(find.text('Invalid ZIP archive'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.byKey(ImportScreen.pickFileButtonKey), findsOneWidget);
    },
  );

  testWidgets(
    'zip FormatException with empty message falls back to filename context',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'broken_payload.zip', bytes: [4, 4, 4]);
      stubZipImportError(mockZipImporter, const FormatException());

      await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
      await tapPickFileButton(tester);

      expect(find.byKey(ImportScreen.errorMessageKey), findsOneWidget);
      expect(
        find.text('Invalid ZIP archive: broken_payload.zip'),
        findsOneWidget,
      );
    },
  );

  testWidgets('zip generic exception uses generic error copy', (tester) async {
    final mockZipImporter = MockStravaZipImporter();
    setPickedImportFile(name: 'unexpected.zip', bytes: [9, 1, 9]);
    stubZipImportError(mockZipImporter, StateError('internal failure'));

    await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
    await tapPickFileButton(tester);

    expect(find.byKey(ImportScreen.errorMessageKey), findsOneWidget);
    expect(
      find.text('An error occurred during import. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('zip import all-success summary keeps View Activity hidden', (
    tester,
  ) async {
    final mockZipImporter = MockStravaZipImporter();
    setPickedImportFile(name: 'all_good.zip', bytes: [1, 2, 3]);
    stubZipImportResult(
      mockZipImporter,
      const ZipImportResult(
        successCount: 3,
        failureCount: 0,
        importedSessionIds: [11, 12, 13],
        errors: [],
      ),
    );

    await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
    await tapPickFileButton(tester);

    expect(find.text('ZIP Import Complete'), findsOneWidget);
    expect(find.text('Imported 3 of 3 activities.'), findsOneWidget);
    expect(find.text('Import Another'), findsOneWidget);
    expect(find.text('View Activity'), findsNothing);
  });

  testWidgets(
    'zip import mixed summary renders first five error descriptions',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'mixed.zip', bytes: [4, 3, 2, 1]);
      const errors = [
        'one.fit: Invalid FIT header',
        'two.fit: Parse failed',
        'three.gpx: Bad XML',
        'four.fit: Missing timestamp',
        'five.gpx: Empty track',
        'six.fit: Unsupported sport',
      ];
      stubZipImportResult(
        mockZipImporter,
        const ZipImportResult(
          successCount: 2,
          failureCount: 6,
          importedSessionIds: [2, 3],
          errors: errors,
        ),
      );

      await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
      await tapPickFileButton(tester);

      expect(find.text('ZIP Import Complete'), findsOneWidget);
      expect(find.text('Imported 2 of 8 activities.'), findsOneWidget);
      for (final error in errors.take(5)) {
        expect(find.text(error), findsOneWidget);
      }
      expect(find.text(errors.last), findsNothing);
    },
  );

  testWidgets(
    'zip summary Import Another resets to picker and clears prior summary copy',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'batch_with_failures.zip', bytes: [5, 4, 3]);
      stubZipImportResult(
        mockZipImporter,
        const ZipImportResult(
          successCount: 1,
          failureCount: 1,
          importedSessionIds: [101],
          errors: ['bad.fit: Invalid FIT header'],
        ),
      );

      await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
      await tapPickFileButton(tester);
      expect(find.text('Imported 1 of 2 activities.'), findsOneWidget);
      expect(find.text('Failed imports: 1'), findsOneWidget);

      await tester.tap(find.text('Import Another'));
      await tester.pumpAndSettle();

      expect(find.byKey(ImportScreen.pickFileButtonKey), findsOneWidget);
      expect(find.text('ZIP Import Complete'), findsNothing);
      expect(find.text('Imported 1 of 2 activities.'), findsNothing);
      expect(find.text('Failed imports: 1'), findsNothing);
      expect(find.text('bad.fit: Invalid FIT header'), findsNothing);
    },
  );

  testWidgets(
    'zip with zero supported activity files shows deterministic terminal summary',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'no_activities.zip', bytes: [7]);
      stubZipImportResult(
        mockZipImporter,
        const ZipImportResult(
          successCount: 0,
          failureCount: 0,
          importedSessionIds: [],
          errors: [],
        ),
      );

      await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
      await tapPickFileButton(tester);

      expect(find.text('ZIP Import Complete'), findsOneWidget);
      expect(
        find.text('No supported activity files were found in this ZIP.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'zip summary with all failures shows deterministic counts and failures label',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'all_failed.zip', bytes: [1, 3, 5]);
      stubZipImportResult(
        mockZipImporter,
        const ZipImportResult(
          successCount: 0,
          failureCount: 2,
          importedSessionIds: [],
          errors: [
            'run.fit: Invalid FIT header',
            'ride.gpx: Parse failed',
          ],
        ),
      );

      await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
      await tapPickFileButton(tester);

      expect(find.text('ZIP Import Complete'), findsOneWidget);
      expect(find.text('Imported 0 of 2 activities.'), findsOneWidget);
      expect(find.text('Failed imports: 2'), findsOneWidget);
      expect(find.text('run.fit: Invalid FIT header'), findsOneWidget);
      expect(find.text('ride.gpx: Parse failed'), findsOneWidget);
    },
  );

  testWidgets(
    'successful zip import invalidates saved activities provider once after completion',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'batch.zip', bytes: [9, 9, 9]);

      void Function(int current, int total)? onProgress;
      final zipCompleter = Completer<ZipImportResult>();
      when(
        () => mockZipImporter.importZip(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((invocation) {
        onProgress =
            invocation.namedArguments[#onProgress]
                as void Function(int current, int total)?;
        return zipCompleter.future;
      });

      var savedActivitiesLoadCount = 0;
      await pumpZipImportScreen(
        tester,
        zipImporter: mockZipImporter,
        overrides: [
          savedActivitiesProvider.overrideWith((ref) async {
            savedActivitiesLoadCount += 1;
            return [];
          }),
        ],
        includeSavedActivitiesProbe: true,
      );
      expect(savedActivitiesLoadCount, 1);

      await tapPickFileButton(tester, settle: false);

      onProgress?.call(1, 3);
      await tester.pump();
      onProgress?.call(2, 3);
      await tester.pump();
      expect(savedActivitiesLoadCount, 1);

      zipCompleter.complete(
        const ZipImportResult(
          successCount: 2,
          failureCount: 1,
          importedSessionIds: [21, 22],
          errors: ['bad.fit: Invalid FIT header'],
        ),
      );
      await tester.pumpAndSettle();

      expect(savedActivitiesLoadCount, 2);
    },
  );

  testWidgets(
    'zip import with zero successful activities does not invalidate saved activities provider',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'all_failed.zip', bytes: [8, 8, 8]);
      stubZipImportResult(
        mockZipImporter,
        const ZipImportResult(
          successCount: 0,
          failureCount: 2,
          importedSessionIds: [],
          errors: [
            'run.fit: Invalid FIT header',
            'ride.gpx: Parse failed',
          ],
        ),
      );

      var savedActivitiesLoadCount = 0;
      await pumpZipImportScreen(
        tester,
        zipImporter: mockZipImporter,
        overrides: [
          savedActivitiesProvider.overrideWith((ref) async {
            savedActivitiesLoadCount += 1;
            return [];
          }),
        ],
        includeSavedActivitiesProbe: true,
      );
      expect(savedActivitiesLoadCount, 1);

      await tapPickFileButton(tester);

      expect(find.text('Imported 0 of 2 activities.'), findsOneWidget);
      expect(savedActivitiesLoadCount, 1);
    },
  );
}

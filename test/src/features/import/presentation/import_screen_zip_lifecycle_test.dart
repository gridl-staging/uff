import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/import/domain/zip_import_result.dart';
import 'package:uff/src/features/import/presentation/import_screen.dart';

import 'import_screen_test_support.dart';

const _openImportFromHomeKey = Key(
  'open_import_from_home_zip_lifecycle_back_guard',
);

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    FilePicker.platform = TestFilePicker();
  });

  testWidgets(
    'zip import ignores late progress and completion callbacks after dispose',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'dispose.zip', bytes: [1, 2, 3]);

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

      verify(
        () => mockZipImporter.importZip(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).called(1);

      await tester.pumpWidget(const SizedBox.shrink());
      onProgress?.call(1, 1);
      resultCompleter.complete(
        const ZipImportResult(
          successCount: 1,
          failureCount: 0,
          importedSessionIds: [7],
          errors: [],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'zip import ignores late importer errors after dispose',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'dispose_error.zip', bytes: [4, 5, 6]);

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
        pumpFor: const Duration(milliseconds: 300),
      );

      verify(
        () => mockZipImporter.importZip(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).called(1);

      await tester.pumpWidget(const SizedBox.shrink());
      resultCompleter.completeError(StateError('late zip failure'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late callbacks from disposed zip screen do not affect a newly mounted screen',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'stale_callbacks.zip', bytes: [9, 8, 7]);

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

      verify(
        () => mockZipImporter.importZip(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).called(1);

      await tester.pumpWidget(const SizedBox.shrink());

      await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
      expect(find.byKey(ImportScreen.pickFileButtonKey), findsOneWidget);

      onProgress?.call(1, 1);
      resultCompleter.complete(
        const ZipImportResult(
          successCount: 1,
          failureCount: 0,
          importedSessionIds: [99],
          errors: [],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(ImportScreen.pickFileButtonKey), findsOneWidget);
      expect(find.text('ZIP Import Complete'), findsNothing);
      expect(find.textContaining('Importing '), findsNothing);
    },
  );

  testWidgets(
    'callbacks from a disposed zip import do not interfere with a new in-flight import',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      final callbacks = <void Function(int current, int total)?>[];
      final firstImportCompleter = Completer<ZipImportResult>();
      final secondImportCompleter = Completer<ZipImportResult>();
      var callCount = 0;
      when(
        () => mockZipImporter.importZip(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((invocation) {
        callbacks.add(
          invocation.namedArguments[#onProgress]
              as void Function(int current, int total)?,
        );
        callCount += 1;
        return callCount == 1
            ? firstImportCompleter.future
            : secondImportCompleter.future;
      });

      setPickedImportFile(name: 'first.zip', bytes: [1, 2, 3]);
      await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
      await tapPickFileButton(
        tester,
        settle: false,
        pumpFor: const Duration(milliseconds: 300),
      );
      verify(
        () => mockZipImporter.importZip(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).called(1);

      await tester.pumpWidget(const SizedBox.shrink());

      setPickedImportFile(name: 'second.zip', bytes: [4, 5, 6]);
      await pumpZipImportScreen(tester, zipImporter: mockZipImporter);
      await tapPickFileButton(
        tester,
        settle: false,
        pumpFor: const Duration(milliseconds: 300),
      );
      verify(
        () => mockZipImporter.importZip(
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).called(1);
      expect(callCount, 2);

      callbacks[0]?.call(1, 1);
      firstImportCompleter.complete(
        const ZipImportResult(
          successCount: 1,
          failureCount: 0,
          importedSessionIds: [1],
          errors: [],
        ),
      );
      await tester.pump();
      expect(find.text('Imported 1 of 1 activities.'), findsNothing);

      callbacks[1]?.call(0, 2);
      await tester.pump();
      expect(find.text('Importing 0 of 2 activities...'), findsOneWidget);

      secondImportCompleter.complete(
        const ZipImportResult(
          successCount: 2,
          failureCount: 0,
          importedSessionIds: [2, 3],
          errors: [],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Imported 2 of 2 activities.'), findsOneWidget);
    },
  );

  testWidgets(
    'back button stays hidden during zip import until the screen disposes',
    (tester) async {
      final mockZipImporter = MockStravaZipImporter();
      setPickedImportFile(name: 'guarded.zip', bytes: [7, 7, 7]);

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

      await tester.pumpWidget(const SizedBox.shrink());
      zipResultCompleter.complete(
        const ZipImportResult(
          successCount: 1,
          failureCount: 0,
          importedSessionIds: [70],
          errors: [],
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

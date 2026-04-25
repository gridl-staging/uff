import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/import/application/import_pipeline.dart';
import 'package:uff/src/features/import/data/strava_zip_importer.dart';
import 'package:uff/src/features/import/presentation/import_screen.dart';
import 'package:uff/src/utils/app_logger.dart';

import '../../activity_tracking/data/sync_service_test_support.dart';

class MockImportPipeline extends Mock implements ImportPipeline {}

class MockSyncService extends Mock implements SyncService {}

/// Build a ZIP archive in memory from a map of {filename: content bytes}.
/// Entries with names ending in '/' are created as directories.
Uint8List buildZipBytes(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    if (entry.key.endsWith('/')) {
      archive.add(ArchiveFile.directory(entry.key));
    } else {
      archive.add(ArchiveFile.bytes(entry.key, entry.value));
    }
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

/// Gzip-compress the given bytes.
Uint8List gzipCompress(List<int> bytes) {
  return const GZipEncoder().encodeBytes(bytes);
}

typedef ZipScaleFixture = ({Uint8List zipBytes, List<String> supportedFiles});

ZipScaleFixture buildInterleavedScaleZipFixture({
  required int supportedFileCount,
}) {
  final entries = <String, List<int>>{
    'meta/profile.json': [0x7B, 0x7D],
    'meta/athlete.csv': [0x69, 0x64],
  };
  final supportedFiles = <String>[];

  for (var index = 0; index < supportedFileCount; index += 1) {
    final bucket = index % 3;
    final baseName = 'activity_${index.toString().padLeft(3, '0')}';
    if (bucket == 0) {
      final filename = '$baseName.fit';
      entries['activities/$filename'] = _fitPayload(index);
      supportedFiles.add(filename);
    } else if (bucket == 1) {
      final filename = '$baseName.gpx';
      entries['activities/$filename'] = _gpxPayload(index);
      supportedFiles.add(filename);
    } else {
      final filename = '$baseName.fit.gz';
      entries['activities/$filename'] = gzipCompress(_fitPayload(index));
      supportedFiles.add(filename);
    }

    // Interleaved ignored files should never affect attempted totals.
    entries['metadata/$baseName.json'] = [index % 255];
  }

  entries['photos/cover.jpg'] = [0xFF, 0xD8, 0xFF];
  entries['notes/readme.txt'] = [0x68, 0x69];
  return (
    zipBytes: buildZipBytes(entries),
    supportedFiles: supportedFiles,
  );
}

List<int> _fitPayload(int seed) => [0x0E, 0x10, seed % 251, (seed * 7) % 251];

List<int> _gpxPayload(int seed) => [0x3C, 0x67, 0x70, 0x78, seed % 251];

/// ## Test Scenarios
/// - `[positive]` Supported archive entries import in deterministic order across file types.
/// - `[error]` Per-file pipeline failures stay filename-scoped and do not abort the batch.
/// - `[edge]` Corrupted gzip and invalid ZIP payloads produce normalized failure messages.
/// - `[statemachine]` Progress and telemetry outputs cover batch start, per-file, and completion states.
void main() {
  late MockImportPipeline mockPipeline;

  setUp(() {
    mockPipeline = MockImportPipeline();
    registerFallbackValue(Uint8List(0));
  });

  group('StravaZipImporter', () {
    test('imports mixed .fit, .gpx, and .fit.gz files', () async {
      final fitBytes = [0x0E, 0x10, 0x01, 0x02]; // dummy FIT content
      final gpxBytes = [0x3C, 0x67, 0x70, 0x78]; // dummy GPX content
      final fitGzContent = [0x0E, 0x10, 0x03, 0x04]; // dummy FIT content
      final fitGzBytes = gzipCompress(fitGzContent);

      final zipBytes = buildZipBytes({
        'activities/morning_run.fit': fitBytes,
        'activities/afternoon_ride.gpx': gpxBytes,
        'activities/evening_walk.fit.gz': fitGzBytes,
      });

      var callIndex = 0;
      when(() => mockPipeline.run(any(), any())).thenAnswer((_) async {
        callIndex++;
        return callIndex * 10; // returns 10, 20, 30
      });

      final importer = StravaZipImporter(pipeline: mockPipeline);
      final result = await importer.importZip(zipBytes);

      expect(result.successCount, 3);
      expect(result.failureCount, 0);
      expect(result.importedSessionIds, hasLength(3));
      expect(result.importedSessionIds, containsAll([10, 20, 30]));
      expect(result.errors, isEmpty);

      verify(() => mockPipeline.run(any(), any())).called(3);
    });

    test('skips non-activity files and directories', () async {
      final fitBytes = [0x0E, 0x10, 0x01, 0x02];

      final zipBytes = buildZipBytes({
        'activities/': [], // directory
        'activities/run.fit': fitBytes,
        'activities/summary.csv': [0x01, 0x02],
        'profile.json': [0x7B, 0x7D],
        'readme.txt': [0x48, 0x65, 0x6C, 0x6C, 0x6F],
        'images/photo.jpg': [0xFF, 0xD8],
      });

      when(() => mockPipeline.run(any(), any())).thenAnswer((_) async => 42);

      final importer = StravaZipImporter(pipeline: mockPipeline);
      final result = await importer.importZip(zipBytes);

      expect(result.successCount, 1);
      expect(result.failureCount, 0);
      expect(result.importedSessionIds, [42]);
      expect(result.errors, isEmpty);

      // Pipeline should only be called once — for the .fit file
      verify(() => mockPipeline.run(any(), any())).called(1);
    });

    test(
      'catches per-file failures without aborting remaining files',
      () async {
        final fitBytes1 = [0x0E, 0x10, 0x01, 0x02];
        final fitBytes2 = [0x0E, 0x10, 0x03, 0x04];
        final gpxBytes = [0x3C, 0x67, 0x70, 0x78];

        final zipBytes = buildZipBytes({
          'activities/good_run.fit': fitBytes1,
          'activities/bad_ride.fit': fitBytes2,
          'activities/good_walk.gpx': gpxBytes,
        });

        var callCount = 0;
        when(() => mockPipeline.run(any(), any())).thenAnswer((_) async {
          callCount++;
          if (callCount == 2) {
            throw const FormatException('Invalid FIT header');
          }
          return callCount * 10;
        });

        final importer = StravaZipImporter(pipeline: mockPipeline);
        final result = await importer.importZip(zipBytes);

        expect(result.successCount, 2);
        expect(result.failureCount, 1);
        expect(result.importedSessionIds, hasLength(2));
        expect(result.errors, ['bad_ride.fit: Invalid FIT header']);

        // All three files should have been attempted
        verify(() => mockPipeline.run(any(), any())).called(3);
      },
    );

    test(
      'normalizes Exception and StateError prefixes in file failures',
      () async {
        final zipBytes = buildZipBytes({
          'activities/first.fit': [0x0E, 0x10, 0x01, 0x02],
          'activities/second.fit': [0x0E, 0x10, 0x03, 0x04],
          'activities/third.gpx': [0x3C, 0x67, 0x70, 0x78],
        });

        var callCount = 0;
        when(() => mockPipeline.run(any(), any())).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            throw Exception('pipeline exploded');
          }
          if (callCount == 2) {
            throw StateError('invalid session state');
          }
          return 300;
        });

        final importer = StravaZipImporter(pipeline: mockPipeline);
        final result = await importer.importZip(zipBytes);

        expect(result.successCount, 1);
        expect(result.failureCount, 2);
        expect(result.importedSessionIds, [300]);
        expect(
          result.errors,
          [
            'first.fit: pipeline exploded',
            'second.fit: invalid session state',
          ],
        );
      },
    );

    test('normalizes Invalid argument(s) prefix in file failures', () async {
      final zipBytes = buildZipBytes({
        'activities/broken.fit': [0x0E, 0x10, 0x01, 0x02],
      });

      when(() => mockPipeline.run(any(), any())).thenThrow(
        ArgumentError('unsupported checksum'),
      );

      final importer = StravaZipImporter(pipeline: mockPipeline);
      final result = await importer.importZip(zipBytes);

      expect(result.successCount, 0);
      expect(result.failureCount, 1);
      expect(
        result.errors,
        ['broken.fit: unsupported checksum'],
      );
    });

    test(
      'decompresses .fit.gz before passing to pipeline with stripped suffix',
      () async {
        final originalFitBytes = [0x0E, 0x10, 0x05, 0x06, 0x07, 0x08];
        final gzippedBytes = gzipCompress(originalFitBytes);

        final zipBytes = buildZipBytes({
          'activities/2024-01-15-morning_run.fit.gz': gzippedBytes,
        });

        when(() => mockPipeline.run(any(), any())).thenAnswer((_) async => 99);

        final importer = StravaZipImporter(pipeline: mockPipeline);
        final result = await importer.importZip(zipBytes);

        expect(result.successCount, 1);
        expect(result.importedSessionIds, [99]);

        // Verify the pipeline received decompressed bytes and stripped filename
        final captured = verify(
          () => mockPipeline.run(captureAny(), captureAny()),
        ).captured;
        final passedBytes = captured[0] as Uint8List;
        final passedFilename = captured[1] as String;

        expect(passedBytes, orderedEquals(originalFitBytes));
        expect(passedFilename, '2024-01-15-morning_run.fit');
      },
    );

    test(
      'treats uppercase .FIT.GZ as supported and strips only gzip suffix',
      () async {
        final originalFitBytes = [0x0E, 0x10, 0x09, 0x0A];
        final gzippedBytes = gzipCompress(originalFitBytes);

        final zipBytes = buildZipBytes({
          'activities/NIGHT_RUN.FIT.GZ': gzippedBytes,
        });

        when(() => mockPipeline.run(any(), any())).thenAnswer((_) async => 101);

        final importer = StravaZipImporter(pipeline: mockPipeline);
        final result = await importer.importZip(zipBytes);

        expect(result.successCount, 1);
        expect(result.failureCount, 0);
        expect(result.importedSessionIds, [101]);

        final captured = verify(
          () => mockPipeline.run(captureAny(), captureAny()),
        ).captured;
        final passedBytes = captured[0] as Uint8List;
        final passedFilename = captured[1] as String;

        expect(passedBytes, orderedEquals(originalFitBytes));
        expect(passedFilename, 'NIGHT_RUN.FIT');
      },
    );

    test(
      'captures corrupted .fit.gz as file failure and continues batch',
      () async {
        final zipBytes = buildZipBytes({
          'activities/broken.fit.gz': [0x00, 0x01, 0x02],
          'activities/good_walk.gpx': [0x3C, 0x67, 0x70, 0x78],
        });

        when(() => mockPipeline.run(any(), any())).thenAnswer((_) async => 77);

        final importer = StravaZipImporter(pipeline: mockPipeline);
        final result = await importer.importZip(zipBytes);

        expect(result.successCount, 1);
        expect(result.failureCount, 1);
        expect(result.importedSessionIds, [77]);
        expect(result.errors, hasLength(1));
        expect(result.errors.single, startsWith('broken.fit.gz: '));
        expect(result.errors.single, isNot('broken.fit.gz: '));

        final captured = verify(
          () => mockPipeline.run(captureAny(), captureAny()),
        ).captured;
        expect(captured[1], 'good_walk.gpx');
      },
    );

    test(
      'onProgress callback reports initial and per-file current/total values',
      () async {
        final fitBytes = [0x0E, 0x10, 0x01, 0x02];
        final gpxBytes = [0x3C, 0x67, 0x70, 0x78];

        final zipBytes = buildZipBytes({
          'activities/run.fit': fitBytes,
          'activities/ride.gpx': gpxBytes,
          'summary.csv': [0x01], // should be skipped, not counted in total
        });

        when(() => mockPipeline.run(any(), any())).thenAnswer((_) async => 1);

        final progressCalls = <(int, int)>[];
        final importer = StravaZipImporter(pipeline: mockPipeline);
        await importer.importZip(
          zipBytes,
          onProgress: (int current, int total) =>
              progressCalls.add((current, total)),
        );

        expect(progressCalls, [(0, 2), (1, 2), (2, 2)]);
      },
    );

    test('onProgress advances for failed files and continues batch', () async {
      final zipBytes = buildZipBytes({
        'activities/good.fit': [0x0E, 0x10, 0x01, 0x02],
        'activities/bad.fit': [0x0E, 0x10, 0x03, 0x04],
      });

      var callCount = 0;
      when(() => mockPipeline.run(any(), any())).thenAnswer((_) async {
        callCount++;
        if (callCount == 2) {
          throw const FormatException('Invalid FIT payload');
        }
        return 44;
      });

      final progressCalls = <(int, int)>[];
      final importer = StravaZipImporter(pipeline: mockPipeline);
      final result = await importer.importZip(
        zipBytes,
        onProgress: (int current, int total) =>
            progressCalls.add((current, total)),
      );

      expect(result.successCount, 1);
      expect(result.failureCount, 1);
      expect(result.errors, ['bad.fit: Invalid FIT payload']);
      expect(progressCalls, [(0, 2), (1, 2), (2, 2)]);
    });

    test('empty ZIP with no activity files returns zero counts', () async {
      final zipBytes = buildZipBytes({
        'profile.json': [0x7B, 0x7D],
        'readme.txt': [0x48, 0x69],
      });

      final importer = StravaZipImporter(pipeline: mockPipeline);
      final result = await importer.importZip(zipBytes);

      expect(result.successCount, 0);
      expect(result.failureCount, 0);
      expect(result.importedSessionIds, isEmpty);
      expect(result.errors, isEmpty);

      verifyNever(() => mockPipeline.run(any(), any()));
    });

    test('invalid ZIP payload throws a normalized FormatException', () async {
      final importer = StravaZipImporter(pipeline: mockPipeline);
      final validZip = buildZipBytes({
        'activities/run.fit': [0x0E, 0x10, 0x01, 0x02],
      });
      final truncatedZip = Uint8List.sublistView(validZip, 0, 10);

      await expectLater(
        () => importer.importZip(truncatedZip),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Invalid ZIP archive',
          ),
        ),
      );

      verifyNever(() => mockPipeline.run(any(), any()));
    });

    test('emits structured per-file and batch summary logs', () async {
      final loggedEvents = <Map<String, Object?>>[];
      final zipBytes = buildZipBytes({
        'activities/good.fit': [0x0E, 0x10, 0x01, 0x02],
        'activities/bad.fit': [0x0E, 0x10, 0x03, 0x04],
      });
      var callCount = 0;
      when(() => mockPipeline.run(any(), any())).thenAnswer((_) async {
        callCount++;
        if (callCount == 2) {
          throw const FormatException('Invalid FIT payload');
        }
        return 55;
      });

      final importer = StravaZipImporter(
        pipeline: mockPipeline,
        logger: AppLogger(sink: loggedEvents.add),
      );
      final result = await importer.importZip(zipBytes);

      expect(result.successCount, 1);
      expect(result.failureCount, 1);
      expect(
        loggedEvents,
        contains(
          allOf(
            containsPair('event_type', 'import.zip.file'),
            containsPair('outcome', 'success'),
            containsPair(
              'identifiers',
              allOf(
                containsPair('file_type', 'fit'),
                containsPair('session_id', 55),
              ),
            ),
          ),
        ),
      );
      expect(
        loggedEvents,
        contains(
          allOf(
            containsPair('event_type', 'import.zip.file'),
            containsPair('outcome', 'failure'),
          ),
        ),
      );
      expect(
        loggedEvents,
        contains(
          allOf(
            containsPair('event_type', 'import.zip.batch'),
            containsPair('outcome', 'complete'),
          ),
        ),
      );
    });

    test('records telemetry breadcrumb for zip import boundary', () async {
      final recordedBreadcrumbs = <Map<String, Object?>>[];
      Future<void> breadcrumbRecorder({
        required String message,
        required Map<String, Object?> metadata,
      }) async {
        recordedBreadcrumbs.add(<String, Object?>{
          'message': message,
          'metadata': Map<String, Object?>.from(metadata),
        });
      }

      final zipBytes = buildZipBytes({
        'activities/good.fit': [0x0E, 0x10, 0x01, 0x02],
      });
      when(() => mockPipeline.run(any(), any())).thenAnswer((_) async => 5);
      final importer = StravaZipImporter(
        pipeline: mockPipeline,
        breadcrumbRecorder: breadcrumbRecorder,
      );

      await importer.importZip(zipBytes);

      expect(recordedBreadcrumbs, hasLength(1));
      expect(recordedBreadcrumbs.single['message'], 'import.zip.import');
      expect(
        recordedBreadcrumbs.single['metadata'],
        allOf(
          containsPair('boundary', 'strava_zip_importer'),
          containsPair('operation', 'import_zip'),
        ),
      );
    });

    test(
      'ignores synchronous breadcrumb recorder failures and still imports files',
      () async {
        Future<void> breadcrumbRecorder({
          required String message,
          required Map<String, Object?> metadata,
        }) {
          throw StateError('breadcrumb sink failed');
        }

        final zipBytes = buildZipBytes({
          'activities/good.fit': [0x0E, 0x10, 0x01, 0x02],
        });
        when(() => mockPipeline.run(any(), any())).thenAnswer((_) async => 5);
        final importer = StravaZipImporter(
          pipeline: mockPipeline,
          breadcrumbRecorder: breadcrumbRecorder,
        );

        final result = await importer.importZip(zipBytes);

        expect(result.successCount, 1);
        expect(result.failureCount, 0);
        expect(result.importedSessionIds, [5]);
        expect(result.errors, isEmpty);
        verify(() => mockPipeline.run(any(), any())).called(1);
      },
    );

    test(
      'imports interleaved large archives in stable order with full progress range',
      () async {
        final fixture = buildInterleavedScaleZipFixture(supportedFileCount: 90);
        final attemptedFiles = <String>[];
        when(() => mockPipeline.run(any(), any())).thenAnswer((invocation) {
          final filename = invocation.positionalArguments[1] as String;
          attemptedFiles.add(filename);
          return Future<int>.value(1000 + attemptedFiles.length);
        });

        final progressCalls = <(int, int)>[];
        final importer = StravaZipImporter(pipeline: mockPipeline);
        final result = await importer.importZip(
          fixture.zipBytes,
          onProgress: (current, total) => progressCalls.add((current, total)),
        );

        final total = fixture.supportedFiles.length;
        final expectedPipelineFilenames = fixture.supportedFiles
            .map(
              (filename) => filename.toLowerCase().endsWith('.fit.gz')
                  ? filename.substring(0, filename.length - 3)
                  : filename,
            )
            .toList(growable: false);
        expect(total, 90);
        expect(attemptedFiles, expectedPipelineFilenames);
        expect(result.successCount, total);
        expect(result.failureCount, 0);
        expect(result.successCount + result.failureCount, total);
        expect(result.importedSessionIds, hasLength(total));
        expect(result.importedSessionIds.first, 1001);
        expect(result.importedSessionIds.last, 1000 + total);
        expect(result.errors, isEmpty);

        expect(progressCalls, hasLength(total + 1));
        expect(progressCalls.first, (0, total));
        expect(progressCalls.last, (total, total));
        for (var index = 0; index < progressCalls.length; index += 1) {
          expect(progressCalls[index], (index, total));
        }

        verify(() => mockPipeline.run(any(), any())).called(total);
      },
    );

    test(
      'continues large mixed-outcome batches and preserves filename-scoped errors',
      () async {
        final fixture = buildInterleavedScaleZipFixture(supportedFileCount: 75);
        final attemptedFiles = <String>[];
        const failureIndexes = {2, 7, 15, 29, 44, 63, 70};

        when(() => mockPipeline.run(any(), any())).thenAnswer((invocation) {
          final filename = invocation.positionalArguments[1] as String;
          final index = attemptedFiles.length;
          attemptedFiles.add(filename);
          if (failureIndexes.contains(index)) {
            throw FormatException('seed-$index decode failure');
          }
          return Future<int>.value(2000 + index);
        });

        final progressCalls = <(int, int)>[];
        final importer = StravaZipImporter(pipeline: mockPipeline);
        final result = await importer.importZip(
          fixture.zipBytes,
          onProgress: (current, total) => progressCalls.add((current, total)),
        );

        final total = fixture.supportedFiles.length;
        final expectedPipelineFilenames = fixture.supportedFiles
            .map(
              (filename) => filename.toLowerCase().endsWith('.fit.gz')
                  ? filename.substring(0, filename.length - 3)
                  : filename,
            )
            .toList(growable: false);
        final expectedFailureErrors = failureIndexes
            .map(
              (index) =>
                  '${fixture.supportedFiles[index]}: seed-$index decode failure',
            )
            .toList(growable: false);

        expect(attemptedFiles, expectedPipelineFilenames);
        expect(result.successCount, total - failureIndexes.length);
        expect(result.failureCount, failureIndexes.length);
        expect(result.successCount + result.failureCount, total);
        expect(
          result.importedSessionIds,
          hasLength(total - failureIndexes.length),
        );
        expect(result.errors, expectedFailureErrors);
        expect(result.errors.every((error) => error.contains('.')), isTrue);
        expect(
          result.errors.every(
            (error) =>
                !error.startsWith('metadata/') && !error.startsWith('meta/'),
          ),
          isTrue,
        );

        expect(progressCalls, hasLength(total + 1));
        expect(progressCalls.first, (0, total));
        expect(progressCalls.last, (total, total));
        verify(() => mockPipeline.run(any(), any())).called(total);
      },
    );
  });

  test('stravaZipImporterProvider resolves without error', () {
    final container = ProviderContainer(
      overrides: [
        trackingRepositoryProvider.overrideWithValue(MockTrackingRepository()),
        syncServiceProvider.overrideWithValue(MockSyncService()),
      ],
    );
    addTearDown(container.dispose);

    final importer = container.read(stravaZipImporterProvider);
    expect(importer.runtimeType, StravaZipImporter);
  });
}

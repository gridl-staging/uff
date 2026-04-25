import 'dart:convert';
import 'dart:typed_data';

import 'package:fit_tool/fit_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/import/application/import_pipeline.dart';
import 'package:uff/src/utils/app_logger.dart';

import '../../activity_tracking/data/sync_service_test_support.dart';
import '../data/fit_test_helpers.dart';

/// ## Test Scenarios
/// - [positive] FIT and GPX imports persist normalized sessions and points
/// - [positive] Import queues the exact persisted session id for sync
/// - [positive] Import sets visibility to private before queueForSync
/// - [positive] Import preserves exact visibility snapshot across save -> queueForSync
/// - [negative] Unsupported or extensionless files throw `FormatException`
/// - [isolation] Each pipeline run produces an independent session with its own visibility
/// - [edge] Import remains resilient when telemetry breadcrumb recording fails

class MockSyncService extends Mock implements SyncService {}

void main() {
  late MockTrackingRepository repository;
  late MockSyncService syncService;
  late ImportPipeline pipeline;

  setUpAll(() {
    registerFallbackValue(
      TrackingSessionRecord(
        id: 0,
        status: TrackingSessionStatus.saved,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      ),
    );
    registerFallbackValue(<TrackingPoint>[]);
  });

  setUp(() {
    repository = MockTrackingRepository();
    syncService = MockSyncService();
    pipeline = ImportPipeline(
      repository: repository,
      syncService: syncService,
    );
  });

  group('ImportPipeline.run', () {
    test('throws FormatException for unsupported file extension', () {
      expect(
        () => pipeline.run(Uint8List(0), 'data.txt'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException for file with no extension', () {
      expect(
        () => pipeline.run(Uint8List(0), 'noext'),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'selects FitImporter for .fit extension and persists result',
      () async {
        final fitBytes = buildFitBytes(
          records: [
            FitTestRecord(
              timestampMs: fitBaseTimestamp,
              latitude: testLatitude,
              longitude: testLongitude,
              altitude: 10,
            ),
            FitTestRecord(
              timestampMs: fitBaseTimestamp + 600000,
              latitude: testLatitude + 0.01,
              longitude: testLongitude + 0.01,
              altitude: 20,
            ),
          ],
          sport: Sport.running,
        );

        when(
          () => repository.saveImportedSession(any(), any()),
        ).thenAnswer((_) async => 42);
        when(() => syncService.queueForSync(42)).thenAnswer((_) async {});

        final sessionId = await pipeline.run(fitBytes, 'morning_run.fit');

        expect(sessionId, 42);

        final captured = verify(
          () => repository.saveImportedSession(captureAny(), captureAny()),
        ).captured;
        final session = captured[0] as TrackingSessionRecord;
        final points = captured[1] as List<TrackingPoint>;

        expect(session.status, TrackingSessionStatus.saved);
        expect(session.sportType, 'run');
        expect(
          session.startedAt,
          DateTime.fromMillisecondsSinceEpoch(fitBaseTimestamp, isUtc: true),
        );
        expect(
          session.stoppedAt,
          DateTime.fromMillisecondsSinceEpoch(
            fitBaseTimestamp + 600000,
            isUtc: true,
          ),
        );
        expect(points, hasLength(2));

        verify(() => syncService.queueForSync(42)).called(1);
      },
    );

    test(
      'selects GpxImporter for .gpx extension and persists result',
      () async {
        final gpxBytes = utf8.encode(_minimalGpx);

        when(
          () => repository.saveImportedSession(any(), any()),
        ).thenAnswer((_) async => 99);
        when(() => syncService.queueForSync(99)).thenAnswer((_) async {});

        final sessionId = await pipeline.run(
          Uint8List.fromList(gpxBytes),
          'ride.gpx',
        );

        expect(sessionId, 99);

        final captured = verify(
          () => repository.saveImportedSession(captureAny(), captureAny()),
        ).captured;
        final session = captured[0] as TrackingSessionRecord;

        expect(session.status, TrackingSessionStatus.saved);
        expect(session.sportType, 'ride');
        verify(() => syncService.queueForSync(99)).called(1);
      },
    );

    test(
      'calls queueForSync only after saveImportedSession and with returned session id',
      () async {
        final gpxBytes = utf8.encode(_minimalGpx);
        when(
          () => repository.saveImportedSession(any(), any()),
        ).thenAnswer((_) async => 246);
        when(() => syncService.queueForSync(any())).thenAnswer((_) async {});

        final sessionId = await pipeline.run(
          Uint8List.fromList(gpxBytes),
          'ordered.gpx',
        );

        expect(sessionId, 246);
        verifyInOrder([
          () => repository.saveImportedSession(any(), any()),
          () => syncService.queueForSync(246),
        ]);
      },
    );

    test('handles .FIT extension case-insensitively', () async {
      final fitBytes = buildFitBytes(
        records: [
          FitTestRecord(
            timestampMs: fitBaseTimestamp,
            latitude: testLatitude,
            longitude: testLongitude,
          ),
          FitTestRecord(
            timestampMs: fitBaseTimestamp + 600000,
            latitude: testLatitude + 0.01,
            longitude: testLongitude + 0.01,
          ),
        ],
        sport: Sport.running,
      );

      when(
        () => repository.saveImportedSession(any(), any()),
      ).thenAnswer((_) async => 10);
      when(() => syncService.queueForSync(10)).thenAnswer((_) async {});

      final sessionId = await pipeline.run(fitBytes, 'WORKOUT.FIT');

      expect(sessionId, 10);
    });

    test('constructs session with sportType, title, and metrics', () async {
      final gpxBytes = utf8.encode(_titledGpx);

      when(
        () => repository.saveImportedSession(any(), any()),
      ).thenAnswer((_) async => 55);
      when(() => syncService.queueForSync(55)).thenAnswer((_) async {});

      await pipeline.run(Uint8List.fromList(gpxBytes), 'track.gpx');

      final captured = verify(
        () => repository.saveImportedSession(captureAny(), captureAny()),
      ).captured;
      final session = captured[0] as TrackingSessionRecord;

      expect(session.sportType, 'run');
      expect(session.title, 'Morning Run');
      expect(session.distanceMeters, closeTo(2790, 5.0));
      expect(session.movingTimeSeconds, equals(1200));
      expect(session.elevationGainMeters, closeTo(20, 0.1));
    });

    test('emits structured parser-selection and success events', () async {
      final loggedEvents = <Map<String, Object?>>[];
      final logger = AppLogger(sink: loggedEvents.add);
      final pipelineWithLogger = ImportPipeline(
        repository: repository,
        syncService: syncService,
        logger: logger,
      );
      final gpxBytes = utf8.encode(_minimalGpx);

      when(
        () => repository.saveImportedSession(any(), any()),
      ).thenAnswer((_) async => 111);
      when(() => syncService.queueForSync(111)).thenAnswer((_) async {});

      await pipelineWithLogger.run(Uint8List.fromList(gpxBytes), 'ride.gpx');

      expect(
        loggedEvents,
        contains(
          allOf(
            containsPair('event_type', 'import.pipeline.parse'),
            containsPair('outcome', 'selected'),
          ),
        ),
      );
      expect(
        loggedEvents,
        contains(
          allOf(
            containsPair('event_type', 'import.pipeline.run'),
            containsPair('outcome', 'success'),
            containsPair(
              'identifiers',
              allOf(
                containsPair('file_type', 'gpx'),
                containsPair('session_id', 111),
              ),
            ),
          ),
        ),
      );
    });

    test('records telemetry breadcrumb for pipeline run boundary', () async {
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

      final pipelineWithBreadcrumbs = ImportPipeline(
        repository: repository,
        syncService: syncService,
        breadcrumbRecorder: breadcrumbRecorder,
      );
      final gpxBytes = utf8.encode(_minimalGpx);
      when(
        () => repository.saveImportedSession(any(), any()),
      ).thenAnswer((_) async => 711);
      when(() => syncService.queueForSync(711)).thenAnswer((_) async {});

      await pipelineWithBreadcrumbs.run(
        Uint8List.fromList(gpxBytes),
        'ride.gpx',
      );

      expect(recordedBreadcrumbs, hasLength(1));
      expect(recordedBreadcrumbs.single['message'], 'import.pipeline.run');
      expect(
        recordedBreadcrumbs.single['metadata'],
        allOf(
          containsPair('boundary', 'import_pipeline'),
          containsPair('file_type', 'gpx'),
          containsPair('operation', 'run'),
        ),
      );
    });

    test(
      'ignores synchronous breadcrumb recorder failures and still persists import',
      () async {
        Future<void> breadcrumbRecorder({
          required String message,
          required Map<String, Object?> metadata,
        }) {
          throw StateError('breadcrumb sink failed');
        }

        final pipelineWithBreadcrumbs = ImportPipeline(
          repository: repository,
          syncService: syncService,
          breadcrumbRecorder: breadcrumbRecorder,
        );
        final gpxBytes = utf8.encode(_minimalGpx);
        when(
          () => repository.saveImportedSession(any(), any()),
        ).thenAnswer((_) async => 812);
        when(() => syncService.queueForSync(812)).thenAnswer((_) async {});

        final sessionId = await pipelineWithBreadcrumbs.run(
          Uint8List.fromList(gpxBytes),
          'ride.gpx',
        );

        expect(sessionId, 812);
        verify(() => repository.saveImportedSession(any(), any())).called(1);
        verify(() => syncService.queueForSync(812)).called(1);
      },
    );

    test(
      'emits structured failure event for unsupported file extensions',
      () async {
        final loggedEvents = <Map<String, Object?>>[];
        final pipelineWithLogger = ImportPipeline(
          repository: repository,
          syncService: syncService,
          logger: AppLogger(sink: loggedEvents.add),
        );

        await expectLater(
          () => pipelineWithLogger.run(Uint8List(0), 'data.txt'),
          throwsA(isA<FormatException>()),
        );

        expect(
          loggedEvents,
          contains(
            allOf(
              containsPair('event_type', 'import.pipeline.run'),
              containsPair('outcome', 'failure'),
            ),
          ),
        );
      },
    );

    test(
      'persists full cleaned point set for deterministic high-volume FIT input',
      () async {
        final records = buildDeterministicFitRecords();
        final fitBytes = buildLargeDeterministicFitBytes();

        when(
          () => repository.saveImportedSession(any(), any()),
        ).thenAnswer((_) async => 314);
        when(() => syncService.queueForSync(314)).thenAnswer((_) async {});

        final sessionId = await pipeline.run(fitBytes, 'high_volume.fit');

        expect(sessionId, 314);
        final verification = verify(
          () => repository.saveImportedSession(captureAny(), captureAny()),
        )..called(1);
        final captured = verification.captured;
        final savedSession = captured[0] as TrackingSessionRecord;
        final savedPoints = captured[1] as List<TrackingPoint>;

        expect(savedSession.sportType, 'run');
        expect(savedPoints, hasLength(records.length));

        const sampleIndexes = [0, 1, 300, 750, 1199];
        for (final index in sampleIndexes) {
          final expected = records[index];
          final persisted = savedPoints[index];
          expect(
            persisted.timestamp,
            DateTime.fromMillisecondsSinceEpoch(
              expected.timestampMs,
              isUtc: true,
            ),
          );
          expect(persisted.latitude, closeTo(expected.latitude!, 1e-6));
          expect(persisted.longitude, closeTo(expected.longitude!, 1e-6));
          expect(persisted.heartRateBpm, expected.heartRate);
          expect(persisted.cadenceRpm, expected.cadence);
          expect(persisted.powerWatts, expected.power);
        }

        verify(() => syncService.queueForSync(314)).called(1);
      },
    );

    test(
      'import sets visibility to private before queueForSync',
      () async {
        final gpxBytes = utf8.encode(_minimalGpx);

        when(
          () => repository.saveImportedSession(any(), any()),
        ).thenAnswer((_) async => 500);
        when(() => syncService.queueForSync(500)).thenAnswer((_) async {});

        await pipeline.run(Uint8List.fromList(gpxBytes), 'privacy.gpx');

        final captured = verify(
          () => repository.saveImportedSession(captureAny(), captureAny()),
        ).captured;
        final session = captured[0] as TrackingSessionRecord;

        // The import pipeline MUST set visibility to private before persisting.
        // If visibility is null, the sync payload builder omits it and the
        // backend defaults to 'public' — a P0 privacy leak.
        expect(
          session.visibility,
          privateTrackingSessionVisibility,
          reason:
              'Import must set visibility to private before saveImportedSession',
        );

        // Confirm queueForSync was called after save (run() is sequential,
        // and the capture above already consumed the saveImportedSession call).
        verify(() => syncService.queueForSync(500)).called(1);
      },
    );

    test(
      'import preserves exact visibility snapshot across save -> queueForSync',
      () async {
        final fitBytes = buildFitBytes(
          records: [
            FitTestRecord(
              timestampMs: fitBaseTimestamp,
              latitude: testLatitude,
              longitude: testLongitude,
            ),
            FitTestRecord(
              timestampMs: fitBaseTimestamp + 600000,
              latitude: testLatitude + 0.01,
              longitude: testLongitude + 0.01,
            ),
          ],
          sport: Sport.running,
        );

        TrackingSessionRecord? savedSession;
        when(
          () => repository.saveImportedSession(any(), any()),
        ).thenAnswer((invocation) async {
          savedSession =
              invocation.positionalArguments[0] as TrackingSessionRecord;
          return 600;
        });
        when(() => syncService.queueForSync(600)).thenAnswer((_) async {
          // At the moment queueForSync is called, the session that was passed
          // to saveImportedSession must already have had private visibility.
          // This proves the visibility was set in _buildSession, not patched
          // after the fact by some downstream default.
          expect(
            savedSession?.visibility,
            privateTrackingSessionVisibility,
            reason:
                'Visibility must be private at the point queueForSync executes',
          );
        });

        await pipeline.run(fitBytes, 'statemachine.fit');

        verify(() => repository.saveImportedSession(any(), any())).called(1);
        verify(() => syncService.queueForSync(600)).called(1);
      },
    );
  });
}

// ---------------------------------------------------------------------------
// GPX test fixtures
// ---------------------------------------------------------------------------

const _minimalGpx = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test">
  <trk>
    <type>Biking</type>
    <trkseg>
      <trkpt lat="40.7128" lon="-74.006">
        <ele>10</ele>
        <time>2024-01-01T12:00:00Z</time>
      </trkpt>
      <trkpt lat="40.7228" lon="-74.016">
        <ele>20</ele>
        <time>2024-01-01T12:10:00Z</time>
      </trkpt>
      <trkpt lat="40.7328" lon="-74.026">
        <ele>30</ele>
        <time>2024-01-01T12:20:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

const _titledGpx = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test">
  <trk>
    <name>Morning Run</name>
    <type>Running</type>
    <trkseg>
      <trkpt lat="40.7128" lon="-74.006">
        <ele>10</ele>
        <time>2024-01-01T12:00:00Z</time>
      </trkpt>
      <trkpt lat="40.7228" lon="-74.016">
        <ele>20</ele>
        <time>2024-01-01T12:10:00Z</time>
      </trkpt>
      <trkpt lat="40.7328" lon="-74.026">
        <ele>30</ele>
        <time>2024-01-01T12:20:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

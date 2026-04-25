import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/photos/application/pending_photo_upload_service.dart';
import 'package:uff/src/features/photos/data/photo_repository.dart';
import 'package:uff/src/utils/app_logger.dart';
import 'sync_service_test_support.dart';

/// Records calls to [uploadPendingPhotos] so sync integration tests can
/// verify the hook fires with the correct arguments.
class FakePendingPhotoUploadService extends PendingPhotoUploadService {
  FakePendingPhotoUploadService()
    : super(
        db: _throwingDb,
        photoRepository: _throwingRepo,
      );

  final List<({int sessionId, String remoteActivityId})> uploadCalls = [];
  Object? throwOnUpload;

  @override
  Future<void> uploadPendingPhotos({
    required int sessionId,
    required String remoteActivityId,
  }) async {
    uploadCalls.add((
      sessionId: sessionId,
      remoteActivityId: remoteActivityId,
    ));
    if (throwOnUpload != null) {
      throw throwOnUpload!;
    }
  }
}

// Stubs that are never actually called — the fake overrides uploadPendingPhotos.
final _throwingDb = _ThrowingTrackingDatabase();
final _throwingRepo = _ThrowingPhotoRepository();

class _ThrowingTrackingDatabase implements TrackingDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('stub');
}

class _ThrowingPhotoRepository implements PhotoRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('stub');
}

void main() {
  late MockTrackingRepository repository;
  late MockSupabaseClient supabaseClient;
  late List<RecordedOperation> operations;
  late StreamController<List<ConnectivityResult>> connectivityController;

  setUpAll(() {
    registerFallbackValue(SyncQueueEntryStatus.queued);
  });

  FakeSyncQueryBuilder builderForTable(
    String table, {
    bool throwOnUpsert = false,
    Object? insertError,
  }) {
    return FakeSyncQueryBuilder(
      table: table,
      operations: operations,
      throwOnUpsert: throwOnUpsert,
      insertError: insertError,
    );
  }

  setUp(() {
    repository = MockTrackingRepository();
    supabaseClient = MockSupabaseClient();
    operations = <RecordedOperation>[];
    connectivityController =
        StreamController<List<ConnectivityResult>>.broadcast();
  });

  tearDown(() async {
    await connectivityController.close();
  });

  group('SupabaseSyncService.processQueue', () {
    Future<Map<String, dynamic>> processQueueAndReadActivityPayload({
      required TrackingSessionRecord session,
      required List<TrackingPoint> points,
    }) async {
      final queuedAt = DateTime(2026, 2, 1, 11);
      var currentQueueEntry = SyncQueueEntry(
        sessionId: session.id,
        status: SyncQueueEntryStatus.queued,
        retryCount: 0,
        queuedAt: queuedAt,
      );

      when(
        () => repository.loadPendingSyncQueueEntries(),
      ).thenAnswer((_) async => [currentQueueEntry]);
      when(
        () => repository.updateSyncQueueEntryStatus(
          sessionId: any(named: 'sessionId'),
          status: any(named: 'status'),
          retryCount: any(named: 'retryCount'),
          lastError: any(named: 'lastError'),
        ),
      ).thenAnswer((invocation) async {
        currentQueueEntry = SyncQueueEntry(
          sessionId: currentQueueEntry.sessionId,
          status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
          retryCount:
              invocation.namedArguments[#retryCount] as int? ??
              currentQueueEntry.retryCount,
          lastError: invocation.namedArguments[#lastError] as String?,
          queuedAt: currentQueueEntry.queuedAt,
        );
      });
      when(() => repository.loadSession(session.id)).thenAnswer(
        (_) async => session,
      );
      when(() => repository.loadPointsForSession(session.id)).thenAnswer(
        (_) async => points,
      );
      when(() => repository.loadSyncQueueEntry(session.id)).thenAnswer(
        (_) async => currentQueueEntry,
      );
      when(() => supabaseClient.from(any())).thenAnswer(
        (invocation) =>
            builderForTable(invocation.positionalArguments.first as String),
      );

      final service = SupabaseSyncService(
        repository: repository,
        supabaseClient: supabaseClient,
        connectivityChanges: connectivityController.stream,
        checkConnectivity: buildConnectivityCheckSequence([
          [ConnectivityResult.wifi],
        ]),
        currentUserIdProvider: () => 'user-1',
        uuidGenerator: () => 'should-not-be-used',
      );
      addTearDown(service.dispose);

      await service.processQueue();

      final activityUpsert = operations.firstWhere(
        (operation) =>
            operation.table == 'activities' && operation.kind == 'upsert',
      );
      return activityUpsert.payload! as Map<String, dynamic>;
    }

    Future<SyncQueueEntry> processQueueWithLimitTokenFailure({
      required String token,
      required int sessionId,
      int initialRetryCount = 0,
      AppLogger? logger,
    }) async {
      final queuedAt = DateTime(2026, 2, 1, 11);
      var currentQueueEntry = SyncQueueEntry(
        sessionId: sessionId,
        status: SyncQueueEntryStatus.queued,
        retryCount: initialRetryCount,
        queuedAt: queuedAt,
      );
      final session = TrackingSessionRecord(
        id: sessionId,
        status: TrackingSessionStatus.saved,
        createdAt: DateTime(2026, 2, 1, 9),
        updatedAt: DateTime(2026, 2, 1, 10),
      );
      final points = buildTestPoints(sessionId: session.id, count: 5);

      when(
        () => repository.loadPendingSyncQueueEntries(),
      ).thenAnswer((_) async => [currentQueueEntry]);
      when(
        () => repository.updateSyncQueueEntryStatus(
          sessionId: any(named: 'sessionId'),
          status: any(named: 'status'),
          retryCount: any(named: 'retryCount'),
          lastError: any(named: 'lastError'),
        ),
      ).thenAnswer((invocation) async {
        currentQueueEntry = SyncQueueEntry(
          sessionId: currentQueueEntry.sessionId,
          status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
          retryCount:
              invocation.namedArguments[#retryCount] as int? ??
              currentQueueEntry.retryCount,
          lastError: invocation.namedArguments[#lastError] as String?,
          queuedAt: currentQueueEntry.queuedAt,
        );
      });
      when(() => repository.loadSession(session.id)).thenAnswer(
        (_) async => session,
      );
      when(() => repository.loadPointsForSession(session.id)).thenAnswer(
        (_) async => points,
      );
      when(
        () => repository.updateSessionRemoteId(session.id, 'remote-$sessionId'),
      ).thenAnswer((_) async {});
      when(() => repository.loadSyncQueueEntry(session.id)).thenAnswer(
        (_) async => currentQueueEntry,
      );
      if (token == 'UFF_LIMIT_TRACK_POINTS_PER_ACTIVITY') {
        when(
          () => supabaseClient.from('activities'),
        ).thenAnswer((_) => builderForTable('activities'));
        when(
          () => supabaseClient.from('track_points'),
        ).thenAnswer(
          (_) => builderForTable(
            'track_points',
            insertError: StateError(token),
          ),
        );
      } else {
        when(
          () => supabaseClient.from('activities'),
        ).thenThrow(StateError(token));
      }

      final service = SupabaseSyncService(
        repository: repository,
        supabaseClient: supabaseClient,
        connectivityChanges: connectivityController.stream,
        checkConnectivity: buildConnectivityCheckSequence([
          [ConnectivityResult.none],
          [ConnectivityResult.wifi],
        ]),
        currentUserIdProvider: () => 'user-1',
        uuidGenerator: () => 'remote-$sessionId',
        logger: logger,
      );
      addTearDown(service.dispose);

      await service.processQueue();
      return currentQueueEntry;
    }

    test(
      'assigns remoteId before Supabase writes and uses delete plus <=1100 point inserts',
      () async {
        final queuedAt = DateTime(2026, 2, 1, 11);
        var currentQueueEntry = SyncQueueEntry(
          sessionId: 7,
          status: SyncQueueEntryStatus.queued,
          retryCount: 0,
          queuedAt: queuedAt,
        );
        final session = TrackingSessionRecord(
          id: 7,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 1, 9),
          updatedAt: DateTime(2026, 2, 1, 10),
          startedAt: DateTime(2026, 2, 1, 9),
          stoppedAt: DateTime(2026, 2, 1, 10),
          title: 'Long run',
          description: 'steady',
        );
        final points = buildTestPoints(sessionId: session.id, count: 2205);
        final cleanedPoints = cleanTrackingPoints(points).cleanedPoints;
        final metrics = calculateProcessedActivityMetrics(
          session: session,
          cleanedPoints: cleanedPoints,
        );

        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer(
          (_) async => [
            SyncQueueEntry(
              sessionId: session.id,
              status: SyncQueueEntryStatus.queued,
              retryCount: 0,
              queuedAt: queuedAt,
            ),
          ],
        );
        when(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: any(named: 'sessionId'),
            status: any(named: 'status'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          currentQueueEntry = SyncQueueEntry(
            sessionId: currentQueueEntry.sessionId,
            status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
            retryCount:
                invocation.namedArguments[#retryCount] as int? ??
                currentQueueEntry.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: currentQueueEntry.queuedAt,
          );
        });
        when(
          () => repository.loadSession(session.id),
        ).thenAnswer((_) async => session);
        when(
          () => repository.loadPointsForSession(session.id),
        ).thenAnswer((_) async => points);
        when(
          () => repository.updateSessionRemoteId(session.id, 'remote-abc'),
        ).thenAnswer((_) async {});
        when(() => repository.loadSyncQueueEntry(session.id)).thenAnswer(
          (_) async => currentQueueEntry,
        );

        when(
          () => supabaseClient.from('activities'),
        ).thenAnswer((_) => builderForTable('activities'));
        when(
          () => supabaseClient.from('track_points'),
        ).thenAnswer((_) => builderForTable('track_points'));
        when(
          () => supabaseClient.from('splits'),
        ).thenAnswer((_) => builderForTable('splits'));

        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: buildConnectivityCheckSequence([
            [ConnectivityResult.none],
            [ConnectivityResult.wifi],
          ]),
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'remote-abc',
        );
        addTearDown(service.dispose);

        await service.processQueue();

        verifyInOrder([
          () => repository.updateSessionRemoteId(session.id, 'remote-abc'),
          () => supabaseClient.from('activities'),
        ]);

        final activityUpsert = operations.firstWhere(
          (operation) =>
              operation.table == 'activities' && operation.kind == 'upsert',
        );
        final activityPayload = activityUpsert.payload! as Map<String, dynamic>;
        expect(activityPayload['id'], 'remote-abc');
        expect(activityPayload['user_id'], 'user-1');
        expect(activityPayload['sport_type'], 'workout');
        expect(activityPayload.containsKey('visibility'), isFalse);
        expect(
          activityPayload['distance_meters'],
          metrics.trackSummary.distanceMeters,
        );
        expect(
          activityPayload['duration_seconds'],
          metrics.trackSummary.movingTime.inSeconds,
        );

        final deleteFilter = operations.firstWhere(
          (operation) =>
              operation.table == 'track_points' &&
              operation.kind == 'eq' &&
              operation.eqColumn == 'activity_id',
        );
        expect(deleteFilter.eqValue, 'remote-abc');

        final insertOperations = operations
            .where(
              (operation) =>
                  operation.table == 'track_points' &&
                  operation.kind == 'insert',
            )
            .toList(growable: false);
        expect(insertOperations, hasLength(3));
        final insertSizes = insertOperations
            .map((operation) => (operation.payload! as List<dynamic>).length)
            .toList(growable: false);
        expect(insertSizes, [1100, 1100, cleanedPoints.length - 2200]);

        final splitsUpsert = operations.firstWhere(
          (operation) =>
              operation.table == 'splits' && operation.kind == 'upsert',
        );
        final splitPayload = splitsUpsert.payload! as List<dynamic>;
        expect(splitPayload.length, metrics.splits.length);

        verify(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: session.id,
            status: SyncQueueEntryStatus.successful,
            retryCount: 0,
          ),
        ).called(1);
      },
    );

    test(
      'splits a 5000-point payload into deterministic <=1100 chunks',
      () async {
        final queuedAt = DateTime(2026, 2, 1, 11);
        var currentQueueEntry = SyncQueueEntry(
          sessionId: 40,
          status: SyncQueueEntryStatus.queued,
          retryCount: 0,
          queuedAt: queuedAt,
        );
        final session = TrackingSessionRecord(
          id: 40,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 1, 9),
          updatedAt: DateTime(2026, 2, 1, 10),
        );
        final points = buildTestPoints(sessionId: session.id, count: 5000);
        final cleanedPoints = cleanTrackingPoints(points).cleanedPoints;

        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer(
          (_) async => [
            SyncQueueEntry(
              sessionId: session.id,
              status: SyncQueueEntryStatus.queued,
              retryCount: 0,
              queuedAt: queuedAt,
            ),
          ],
        );
        when(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: any(named: 'sessionId'),
            status: any(named: 'status'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          currentQueueEntry = SyncQueueEntry(
            sessionId: currentQueueEntry.sessionId,
            status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
            retryCount:
                invocation.namedArguments[#retryCount] as int? ??
                currentQueueEntry.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: currentQueueEntry.queuedAt,
          );
        });
        when(
          () => repository.loadSession(session.id),
        ).thenAnswer((_) async => session);
        when(
          () => repository.loadPointsForSession(session.id),
        ).thenAnswer((_) async => points);
        when(
          () => repository.updateSessionRemoteId(session.id, 'remote-5000'),
        ).thenAnswer((_) async {});
        when(
          () => repository.loadSyncQueueEntry(session.id),
        ).thenAnswer((_) async => currentQueueEntry);
        when(
          () => supabaseClient.from(any()),
        ).thenAnswer(
          (invocation) =>
              builderForTable(invocation.positionalArguments.first as String),
        );

        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: buildConnectivityCheckSequence([
            [ConnectivityResult.none],
            [ConnectivityResult.wifi],
          ]),
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'remote-5000',
        );
        addTearDown(service.dispose);

        await service.processQueue();

        final insertOperations = operations
            .where(
              (operation) =>
                  operation.table == 'track_points' &&
                  operation.kind == 'insert',
            )
            .toList(growable: false);
        final insertSizes = insertOperations
            .map((operation) => (operation.payload! as List<dynamic>).length)
            .toList(growable: false);
        final expectedChunkSizes = <int>[];
        for (var offset = 0; offset < cleanedPoints.length; offset += 1100) {
          final remaining = cleanedPoints.length - offset;
          expectedChunkSizes.add(remaining >= 1100 ? 1100 : remaining);
        }

        expect(insertSizes, expectedChunkSizes);
        expect(
          insertSizes.every((size) => size <= 1100),
          isTrue,
        );
        expect(
          insertSizes.fold<int>(0, (sum, size) => sum + size),
          cleanedPoints.length,
        );
      },
    );

    test(
      'uses a single track_points insert when cleaned points are exactly 1100',
      () async {
        final queuedAt = DateTime(2026, 2, 2, 11);
        var currentQueueEntry = SyncQueueEntry(
          sessionId: 41,
          status: SyncQueueEntryStatus.queued,
          retryCount: 0,
          queuedAt: queuedAt,
        );
        final session = TrackingSessionRecord(
          id: 41,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 2, 9),
          updatedAt: DateTime(2026, 2, 2, 10),
        );
        final points = buildTestPoints(sessionId: session.id, count: 1100);
        final cleanedPoints = cleanTrackingPoints(points).cleanedPoints;

        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer(
          (_) async => [
            SyncQueueEntry(
              sessionId: session.id,
              status: SyncQueueEntryStatus.queued,
              retryCount: 0,
              queuedAt: queuedAt,
            ),
          ],
        );
        when(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: any(named: 'sessionId'),
            status: any(named: 'status'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          currentQueueEntry = SyncQueueEntry(
            sessionId: currentQueueEntry.sessionId,
            status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
            retryCount:
                invocation.namedArguments[#retryCount] as int? ??
                currentQueueEntry.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: currentQueueEntry.queuedAt,
          );
        });
        when(
          () => repository.loadSession(session.id),
        ).thenAnswer((_) async => session);
        when(
          () => repository.loadPointsForSession(session.id),
        ).thenAnswer((_) async => points);
        when(
          () => repository.updateSessionRemoteId(session.id, 'remote-1100'),
        ).thenAnswer((_) async {});
        when(
          () => repository.loadSyncQueueEntry(session.id),
        ).thenAnswer((_) async => currentQueueEntry);
        when(
          () => supabaseClient.from(any()),
        ).thenAnswer(
          (invocation) =>
              builderForTable(invocation.positionalArguments.first as String),
        );

        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: buildConnectivityCheckSequence([
            [ConnectivityResult.none],
            [ConnectivityResult.wifi],
          ]),
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'remote-1100',
        );
        addTearDown(service.dispose);

        await service.processQueue();

        final insertOperations = operations
            .where(
              (operation) =>
                  operation.table == 'track_points' &&
                  operation.kind == 'insert',
            )
            .toList(growable: false);
        expect(insertOperations, hasLength(1));
        final insertedRows = insertOperations.single.payload! as List<dynamic>;
        expect(insertedRows, hasLength(cleanedPoints.length));
        expect(insertedRows.length, 1100);
      },
    );

    test(
      'splits cleaned points into [1100, 1] when payload size is 1101',
      () async {
        final queuedAt = DateTime(2026, 2, 3, 11);
        var currentQueueEntry = SyncQueueEntry(
          sessionId: 42,
          status: SyncQueueEntryStatus.queued,
          retryCount: 0,
          queuedAt: queuedAt,
        );
        final session = TrackingSessionRecord(
          id: 42,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 3, 9),
          updatedAt: DateTime(2026, 2, 3, 10),
        );
        final points = buildTestPoints(sessionId: session.id, count: 1101);
        final cleanedPoints = cleanTrackingPoints(points).cleanedPoints;

        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer(
          (_) async => [
            SyncQueueEntry(
              sessionId: session.id,
              status: SyncQueueEntryStatus.queued,
              retryCount: 0,
              queuedAt: queuedAt,
            ),
          ],
        );
        when(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: any(named: 'sessionId'),
            status: any(named: 'status'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          currentQueueEntry = SyncQueueEntry(
            sessionId: currentQueueEntry.sessionId,
            status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
            retryCount:
                invocation.namedArguments[#retryCount] as int? ??
                currentQueueEntry.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: currentQueueEntry.queuedAt,
          );
        });
        when(
          () => repository.loadSession(session.id),
        ).thenAnswer((_) async => session);
        when(
          () => repository.loadPointsForSession(session.id),
        ).thenAnswer((_) async => points);
        when(
          () => repository.updateSessionRemoteId(session.id, 'remote-1101'),
        ).thenAnswer((_) async {});
        when(
          () => repository.loadSyncQueueEntry(session.id),
        ).thenAnswer((_) async => currentQueueEntry);
        when(
          () => supabaseClient.from(any()),
        ).thenAnswer(
          (invocation) =>
              builderForTable(invocation.positionalArguments.first as String),
        );

        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: buildConnectivityCheckSequence([
            [ConnectivityResult.none],
            [ConnectivityResult.wifi],
          ]),
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'remote-1101',
        );
        addTearDown(service.dispose);

        await service.processQueue();

        final insertOperations = operations
            .where(
              (operation) =>
                  operation.table == 'track_points' &&
                  operation.kind == 'insert',
            )
            .toList(growable: false);
        final insertSizes = insertOperations
            .map((operation) => (operation.payload! as List<dynamic>).length)
            .toList(growable: false);

        expect(insertSizes, [1100, cleanedPoints.length - 1100]);
        expect(
          insertSizes.fold<int>(0, (sum, size) => sum + size),
          cleanedPoints.length,
        );
      },
    );

    test(
      'drains deep queued backlogs by syncing every queued session in one pass',
      () async {
        final queuedAt = DateTime(2026, 2, 5, 11);
        const sessionCount = 15;
        final sessions = <int, TrackingSessionRecord>{};
        final pointsBySession = <int, List<TrackingPoint>>{};
        final queueBySessionId = <int, SyncQueueEntry>{};
        var expectedTotalInsertedRows = 0;

        for (var index = 0; index < sessionCount; index += 1) {
          final sessionId = 800 + index;
          sessions[sessionId] = TrackingSessionRecord(
            id: sessionId,
            status: TrackingSessionStatus.saved,
            createdAt: DateTime(2026, 2, 5, 9),
            updatedAt: DateTime(2026, 2, 5, 10),
            remoteId: 'remote-$sessionId',
          );
          final points = buildTestPoints(
            sessionId: sessionId,
            count: 3 + (index % 4),
          );
          pointsBySession[sessionId] = points;
          expectedTotalInsertedRows += cleanTrackingPoints(
            points,
          ).cleanedPoints.length;
          queueBySessionId[sessionId] = SyncQueueEntry(
            sessionId: sessionId,
            status: SyncQueueEntryStatus.queued,
            retryCount: 0,
            queuedAt: queuedAt,
          );
        }

        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer((_) async {
          return queueBySessionId.values
              .where((entry) => entry.status == SyncQueueEntryStatus.queued)
              .toList(growable: false);
        });
        when(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: any(named: 'sessionId'),
            status: any(named: 'status'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          final sessionId = invocation.namedArguments[#sessionId] as int;
          final existingEntry = queueBySessionId[sessionId]!;
          queueBySessionId[sessionId] = SyncQueueEntry(
            sessionId: sessionId,
            status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
            retryCount:
                invocation.namedArguments[#retryCount] as int? ??
                existingEntry.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: existingEntry.queuedAt,
          );
        });
        when(() => repository.loadSyncQueueEntry(any())).thenAnswer((
          invocation,
        ) async {
          final sessionId = invocation.positionalArguments.first as int;
          return queueBySessionId[sessionId];
        });
        when(() => repository.loadSession(any())).thenAnswer((
          invocation,
        ) async {
          final sessionId = invocation.positionalArguments.first as int;
          return sessions[sessionId]!;
        });
        when(
          () => repository.loadPointsForSession(any()),
        ).thenAnswer((invocation) async {
          final sessionId = invocation.positionalArguments.first as int;
          return pointsBySession[sessionId]!;
        });
        when(
          () => supabaseClient.from(any()),
        ).thenAnswer(
          (invocation) =>
              builderForTable(invocation.positionalArguments.first as String),
        );

        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: buildConnectivityCheckSequence([
            [ConnectivityResult.none],
            [ConnectivityResult.wifi],
          ]),
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'unused',
        );
        addTearDown(service.dispose);

        await service.processQueue();

        final activityUpserts = operations
            .where(
              (operation) =>
                  operation.table == 'activities' && operation.kind == 'upsert',
            )
            .toList(growable: false);
        final pointInserts = operations
            .where(
              (operation) =>
                  operation.table == 'track_points' &&
                  operation.kind == 'insert',
            )
            .toList(growable: false);

        expect(activityUpserts, hasLength(sessionCount));
        expect(pointInserts, hasLength(sessionCount));
        expect(
          pointInserts
              .map((operation) => (operation.payload! as List<dynamic>).length)
              .fold<int>(0, (sum, size) => sum + size),
          expectedTotalInsertedRows,
        );
        expect(
          queueBySessionId.values.every(
            (entry) => entry.status == SyncQueueEntryStatus.successful,
          ),
          isTrue,
        );
      },
    );

    test(
      'includes visibility in activities payload when session visibility is set',
      () async {
        final session = TrackingSessionRecord(
          id: 17,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 1, 9),
          updatedAt: DateTime(2026, 2, 1, 10),
          startedAt: DateTime(2026, 2, 1, 9),
          stoppedAt: DateTime(2026, 2, 1, 10),
          remoteId: 'existing-remote-17',
          visibility: 'private',
        );
        final points = buildTestPoints(sessionId: session.id, count: 20);

        final activityPayload = await processQueueAndReadActivityPayload(
          session: session,
          points: points,
        );
        expect(activityPayload['visibility'], 'private');
      },
    );

    test(
      'omits unsupported visibility values from activities payload',
      () async {
        final session = TrackingSessionRecord(
          id: 18,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 1, 9),
          updatedAt: DateTime(2026, 2, 1, 10),
          startedAt: DateTime(2026, 2, 1, 9),
          stoppedAt: DateTime(2026, 2, 1, 10),
          remoteId: 'existing-remote-18',
          visibility: 'team-only',
        );
        final points = buildTestPoints(sessionId: session.id, count: 20);

        final activityPayload = await processQueueAndReadActivityPayload(
          session: session,
          points: points,
        );

        expect(activityPayload.containsKey('visibility'), isFalse);
      },
    );

    test(
      're-sync reuses existing remoteId and does not generate a new one',
      () async {
        final queuedAt = DateTime(2026, 2, 1, 11);
        var currentQueueEntry = SyncQueueEntry(
          sessionId: 8,
          status: SyncQueueEntryStatus.queued,
          retryCount: 0,
          queuedAt: queuedAt,
        );
        final session = TrackingSessionRecord(
          id: 8,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 1, 9),
          updatedAt: DateTime(2026, 2, 1, 10),
          startedAt: DateTime(2026, 2, 1, 9),
          stoppedAt: DateTime(2026, 2, 1, 10),
          remoteId: 'existing-remote-id',
        );
        final points = buildTestPoints(sessionId: session.id, count: 20);
        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer(
          (_) async => [
            SyncQueueEntry(
              sessionId: session.id,
              status: SyncQueueEntryStatus.queued,
              retryCount: 0,
              queuedAt: queuedAt,
            ),
          ],
        );
        when(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: any(named: 'sessionId'),
            status: any(named: 'status'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          currentQueueEntry = SyncQueueEntry(
            sessionId: currentQueueEntry.sessionId,
            status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
            retryCount:
                invocation.namedArguments[#retryCount] as int? ??
                currentQueueEntry.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: currentQueueEntry.queuedAt,
          );
        });
        when(
          () => repository.loadSession(session.id),
        ).thenAnswer((_) async => session);
        when(
          () => repository.loadPointsForSession(session.id),
        ).thenAnswer((_) async => points);
        when(() => repository.loadSyncQueueEntry(session.id)).thenAnswer(
          (_) async => currentQueueEntry,
        );

        when(() => supabaseClient.from(any())).thenAnswer(
          (invocation) =>
              builderForTable(invocation.positionalArguments.first as String),
        );

        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: buildConnectivityCheckSequence([
            [ConnectivityResult.none],
            [ConnectivityResult.mobile],
          ]),
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'should-not-be-used',
        );
        addTearDown(service.dispose);

        await service.processQueue();

        verifyNever(() => repository.updateSessionRemoteId(any(), any()));
        final activityUpsert = operations.firstWhere(
          (operation) =>
              operation.table == 'activities' && operation.kind == 'upsert',
        );
        final activityPayload = activityUpsert.payload! as Map<String, dynamic>;
        expect(activityPayload['id'], 'existing-remote-id');
      },
    );

    test(
      're-queued sessions stay pending until a follow-up pass completes',
      () async {
        final initialQueuedAt = DateTime(2026, 2, 1, 11);
        final refreshedQueuedAt = DateTime(2026, 3, 15, 11, 45);
        final session = TrackingSessionRecord(
          id: 9,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 1, 9),
          updatedAt: DateTime(2026, 2, 1, 10),
          remoteId: 'existing-remote-id',
        );
        final points = buildTestPoints(sessionId: session.id, count: 8);
        final firstPassPoints = Completer<List<TrackingPoint>>();
        final processingStarted = Completer<void>();
        var currentQueueEntry = SyncQueueEntry(
          sessionId: session.id,
          status: SyncQueueEntryStatus.queued,
          retryCount: 0,
          queuedAt: initialQueuedAt,
        );
        var pointLoadCount = 0;

        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer((_) async {
          final entry = currentQueueEntry;
          if (entry.status == SyncQueueEntryStatus.queued) {
            return [entry];
          }
          return const [];
        });
        when(
          () => repository.upsertSyncQueueEntry(
            sessionId: session.id,
            status: SyncQueueEntryStatus.queued,
            queuedAt: any(named: 'queuedAt'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          currentQueueEntry = SyncQueueEntry(
            sessionId: session.id,
            status: SyncQueueEntryStatus.queued,
            retryCount: invocation.namedArguments[#retryCount] as int,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: invocation.namedArguments[#queuedAt] as DateTime,
          );
        });
        when(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: session.id,
            status: any(named: 'status'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          final status =
              invocation.namedArguments[#status] as SyncQueueEntryStatus;
          final retryCount = invocation.namedArguments[#retryCount] as int?;
          final lastError = invocation.namedArguments[#lastError] as String?;
          currentQueueEntry = SyncQueueEntry(
            sessionId: session.id,
            status: status,
            retryCount: retryCount ?? currentQueueEntry.retryCount,
            lastError: lastError,
            queuedAt: currentQueueEntry.queuedAt,
          );
          if (status == SyncQueueEntryStatus.processing &&
              !processingStarted.isCompleted) {
            processingStarted.complete();
          }
        });
        when(() => repository.loadSyncQueueEntry(session.id)).thenAnswer(
          (_) async => currentQueueEntry,
        );
        when(
          () => repository.loadSession(session.id),
        ).thenAnswer((_) async => session);
        when(() => repository.loadPointsForSession(session.id)).thenAnswer((_) {
          pointLoadCount += 1;
          if (pointLoadCount == 1) {
            return firstPassPoints.future;
          }
          return Future<List<TrackingPoint>>.value(points);
        });

        when(() => supabaseClient.from(any())).thenAnswer(
          (invocation) =>
              builderForTable(invocation.positionalArguments.first as String),
        );

        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: buildConnectivityCheckSequence([
            [ConnectivityResult.none],
            [ConnectivityResult.wifi],
          ]),
          currentUserIdProvider: () => 'user-1',
          now: () => refreshedQueuedAt,
        );
        addTearDown(service.dispose);

        final processFuture = service.processQueue();
        await processingStarted.future;
        await service.queueForSync(session.id);
        firstPassPoints.complete(points);
        await processFuture;

        final activityUpserts = operations.where(
          (operation) =>
              operation.table == 'activities' && operation.kind == 'upsert',
        );
        expect(activityUpserts, hasLength(2));
        expect(pointLoadCount, 2);
        expect(currentQueueEntry.status, SyncQueueEntryStatus.successful);
        expect(currentQueueEntry.queuedAt, refreshedQueuedAt);
      },
    );

    test(
      'refreshes queued state before processing later entries from the same snapshot',
      () async {
        final firstQueuedAt = DateTime(2026, 2, 1, 11);
        final refreshedQueuedAt = DateTime(2026, 3, 15, 12);
        final firstSession = TrackingSessionRecord(
          id: 20,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 1, 9),
          updatedAt: DateTime(2026, 2, 1, 10),
          remoteId: 'remote-20',
        );
        final secondSession = TrackingSessionRecord(
          id: 21,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 1, 9),
          updatedAt: DateTime(2026, 2, 1, 10),
          remoteId: 'remote-21',
        );
        final queueBySessionId = <int, SyncQueueEntry>{
          firstSession.id: SyncQueueEntry(
            sessionId: firstSession.id,
            status: SyncQueueEntryStatus.queued,
            retryCount: 0,
            queuedAt: firstQueuedAt,
          ),
          secondSession.id: SyncQueueEntry(
            sessionId: secondSession.id,
            status: SyncQueueEntryStatus.queued,
            retryCount: 4,
            queuedAt: firstQueuedAt,
          ),
        };
        final firstSessionPoints = Completer<List<TrackingPoint>>();
        final processingStarted = Completer<void>();

        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer((_) async {
          final entries = <SyncQueueEntry>[];
          for (final sessionId in [firstSession.id, secondSession.id]) {
            final entry = queueBySessionId[sessionId];
            if (entry != null && entry.status == SyncQueueEntryStatus.queued) {
              entries.add(entry);
            }
          }
          return entries;
        });
        when(
          () => repository.upsertSyncQueueEntry(
            sessionId: any(named: 'sessionId'),
            status: SyncQueueEntryStatus.queued,
            queuedAt: any(named: 'queuedAt'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          final sessionId = invocation.namedArguments[#sessionId] as int;
          queueBySessionId[sessionId] = SyncQueueEntry(
            sessionId: sessionId,
            status: SyncQueueEntryStatus.queued,
            retryCount: invocation.namedArguments[#retryCount] as int,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: invocation.namedArguments[#queuedAt] as DateTime,
          );
        });
        when(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: any(named: 'sessionId'),
            status: any(named: 'status'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          final sessionId = invocation.namedArguments[#sessionId] as int;
          final existingEntry = queueBySessionId[sessionId]!;
          final status =
              invocation.namedArguments[#status] as SyncQueueEntryStatus;
          final retryCount = invocation.namedArguments[#retryCount] as int?;
          queueBySessionId[sessionId] = SyncQueueEntry(
            sessionId: sessionId,
            status: status,
            retryCount: retryCount ?? existingEntry.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: existingEntry.queuedAt,
          );
          if (sessionId == firstSession.id &&
              status == SyncQueueEntryStatus.processing &&
              !processingStarted.isCompleted) {
            processingStarted.complete();
          }
        });
        when(
          () => repository.loadSyncQueueEntry(any()),
        ).thenAnswer((invocation) async {
          final sessionId = invocation.positionalArguments.first as int;
          return queueBySessionId[sessionId];
        });
        when(() => repository.loadSession(firstSession.id)).thenAnswer(
          (_) async => firstSession,
        );
        when(() => repository.loadSession(secondSession.id)).thenAnswer(
          (_) async => secondSession,
        );
        when(() => repository.loadPointsForSession(firstSession.id)).thenAnswer(
          (_) => firstSessionPoints.future,
        );
        when(
          () => repository.loadPointsForSession(secondSession.id),
        ).thenAnswer(
          (_) async => buildTestPoints(sessionId: secondSession.id, count: 5),
        );

        when(() => supabaseClient.from(any())).thenAnswer(
          (invocation) =>
              builderForTable(invocation.positionalArguments.first as String),
        );

        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: buildConnectivityCheckSequence([
            [ConnectivityResult.none],
            [ConnectivityResult.wifi],
          ]),
          currentUserIdProvider: () => 'user-1',
          now: () => refreshedQueuedAt,
        );
        addTearDown(service.dispose);

        final processFuture = service.processQueue();
        await processingStarted.future;
        await service.queueForSync(secondSession.id);
        firstSessionPoints.complete(
          buildTestPoints(sessionId: firstSession.id, count: 5),
        );
        await processFuture;

        verify(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: secondSession.id,
            status: SyncQueueEntryStatus.processing,
            retryCount: 0,
          ),
        ).called(1);
        expect(
          queueBySessionId[secondSession.id]!.status,
          SyncQueueEntryStatus.successful,
        );
        expect(queueBySessionId[secondSession.id]!.retryCount, 0);
        expect(queueBySessionId[secondSession.id]!.queuedAt, refreshedQueuedAt);
      },
    );

    test(
      'on fifth failure marks queue row as failed with retryCount 5',
      () async {
        final queuedAt = DateTime(2026, 2, 1, 11);
        var currentQueueEntry = SyncQueueEntry(
          sessionId: 11,
          status: SyncQueueEntryStatus.queued,
          retryCount: 4,
          queuedAt: queuedAt,
        );
        final session = TrackingSessionRecord(
          id: 11,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 1, 9),
          updatedAt: DateTime(2026, 2, 1, 10),
        );
        final points = buildTestPoints(sessionId: session.id, count: 5);
        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer(
          (_) async => [
            SyncQueueEntry(
              sessionId: session.id,
              status: SyncQueueEntryStatus.queued,
              retryCount: 4,
              queuedAt: queuedAt,
            ),
          ],
        );
        when(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: any(named: 'sessionId'),
            status: any(named: 'status'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          currentQueueEntry = SyncQueueEntry(
            sessionId: currentQueueEntry.sessionId,
            status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
            retryCount:
                invocation.namedArguments[#retryCount] as int? ??
                currentQueueEntry.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: currentQueueEntry.queuedAt,
          );
        });
        when(
          () => repository.loadSession(session.id),
        ).thenAnswer((_) async => session);
        when(
          () => repository.loadPointsForSession(session.id),
        ).thenAnswer((_) async => points);
        when(
          () => repository.updateSessionRemoteId(session.id, 'remote-11'),
        ).thenAnswer((_) async {});
        when(() => repository.loadSyncQueueEntry(session.id)).thenAnswer(
          (_) async => currentQueueEntry,
        );
        when(
          () => supabaseClient.from('activities'),
        ).thenAnswer((_) => builderForTable('activities', throwOnUpsert: true));

        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: buildConnectivityCheckSequence([
            [ConnectivityResult.none],
            [ConnectivityResult.wifi],
          ]),
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'remote-11',
        );
        addTearDown(service.dispose);

        await service.processQueue();

        verify(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: session.id,
            status: SyncQueueEntryStatus.failed,
            retryCount: 5,
            lastError: any(named: 'lastError'),
          ),
        ).called(1);
      },
    );

    test(
      'translates UFF_LIMIT_TRACK_POINTS_PER_ACTIVITY to stable queue error text',
      () async {
        final queueEntry = await processQueueWithLimitTokenFailure(
          token: 'UFF_LIMIT_TRACK_POINTS_PER_ACTIVITY',
          sessionId: 31,
        );

        expect(queueEntry.status, SyncQueueEntryStatus.queued);
        expect(queueEntry.retryCount, 1);
        expect(
          queueEntry.lastError,
          syncQueueTrackPointsLimitErrorMessage,
        );
      },
    );

    test(
      'emits structured retry event when a queued item is retried',
      () async {
        final loggedEvents = <Map<String, Object?>>[];

        await processQueueWithLimitTokenFailure(
          token: 'UFF_LIMIT_TRACK_POINTS_PER_ACTIVITY',
          sessionId: 33,
          logger: AppLogger(sink: loggedEvents.add),
        );

        expect(
          loggedEvents,
          contains(
            allOf(
              containsPair('event_type', 'sync.queue.retry'),
              containsPair('outcome', 'scheduled'),
            ),
          ),
        );
      },
    );

    test('reports queued retry work in the final idle process event', () async {
      final loggedEvents = <Map<String, Object?>>[];

      await processQueueWithLimitTokenFailure(
        token: 'UFF_LIMIT_TRACK_POINTS_PER_ACTIVITY',
        sessionId: 35,
        logger: AppLogger(sink: loggedEvents.add),
      );

      expect(
        loggedEvents,
        contains(
          allOf(
            containsPair('event_type', 'sync.queue.process'),
            containsPair('outcome', 'idle'),
            containsPair('identifiers', {'pending_entries': 1}),
          ),
        ),
      );
    });

    test(
      'translates UFF_LIMIT_ACTIVITIES_PER_USER to stable queue error text',
      () async {
        final queueEntry = await processQueueWithLimitTokenFailure(
          token: 'UFF_LIMIT_ACTIVITIES_PER_USER',
          sessionId: 32,
        );

        expect(queueEntry.status, SyncQueueEntryStatus.queued);
        expect(queueEntry.retryCount, 1);
        expect(
          queueEntry.lastError,
          syncQueueActivitiesPerUserLimitErrorMessage,
        );
      },
    );

    test(
      'emits structured terminal failure event on fifth retry failure',
      () async {
        final loggedEvents = <Map<String, Object?>>[];
        final queueEntry = await processQueueWithLimitTokenFailure(
          token: 'UFF_LIMIT_ACTIVITIES_PER_USER',
          sessionId: 34,
          initialRetryCount: 4,
          logger: AppLogger(sink: loggedEvents.add),
        );

        expect(queueEntry.status, SyncQueueEntryStatus.failed);
        expect(
          loggedEvents,
          contains(
            allOf(
              containsPair('event_type', 'sync.queue.failure'),
              containsPair('outcome', 'terminal'),
            ),
          ),
        );
      },
    );

    test(
      'triggers pending photo upload after sync succeeds with the correct remoteActivityId',
      () async {
        final queuedAt = DateTime(2026, 2, 1, 11);
        var currentQueueEntry = SyncQueueEntry(
          sessionId: 50,
          status: SyncQueueEntryStatus.queued,
          retryCount: 0,
          queuedAt: queuedAt,
        );
        final session = TrackingSessionRecord(
          id: 50,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 1, 9),
          updatedAt: DateTime(2026, 2, 1, 10),
        );
        final points = buildTestPoints(sessionId: session.id, count: 5);

        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer((_) async => [currentQueueEntry]);
        when(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: any(named: 'sessionId'),
            status: any(named: 'status'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          currentQueueEntry = SyncQueueEntry(
            sessionId: currentQueueEntry.sessionId,
            status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
            retryCount:
                invocation.namedArguments[#retryCount] as int? ??
                currentQueueEntry.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: currentQueueEntry.queuedAt,
          );
        });
        when(
          () => repository.loadSession(session.id),
        ).thenAnswer((_) async => session);
        when(
          () => repository.loadPointsForSession(session.id),
        ).thenAnswer((_) async => points);
        when(
          () => repository.updateSessionRemoteId(session.id, 'remote-50'),
        ).thenAnswer((_) async {});
        when(() => repository.loadSyncQueueEntry(session.id)).thenAnswer(
          (_) async => currentQueueEntry,
        );
        when(() => supabaseClient.from(any())).thenAnswer(
          (invocation) => builderForTable(
            invocation.positionalArguments.first as String,
          ),
        );

        final fakePhotoUploader = FakePendingPhotoUploadService();
        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: buildConnectivityCheckSequence([
            [ConnectivityResult.none],
            [ConnectivityResult.wifi],
          ]),
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'remote-50',
          pendingPhotoUploadService: fakePhotoUploader,
        );
        addTearDown(service.dispose);

        await service.processQueue();

        // Sync should succeed.
        expect(currentQueueEntry.status, SyncQueueEntryStatus.successful);
        // Photo upload should have been triggered once with the correct args.
        expect(fakePhotoUploader.uploadCalls.length, 1);
        expect(fakePhotoUploader.uploadCalls.first.sessionId, 50);
        expect(
          fakePhotoUploader.uploadCalls.first.remoteActivityId,
          'remote-50',
        );
      },
    );

    test(
      'sync still succeeds even if pending photo upload throws',
      () async {
        final queuedAt = DateTime(2026, 2, 1, 11);
        var currentQueueEntry = SyncQueueEntry(
          sessionId: 51,
          status: SyncQueueEntryStatus.queued,
          retryCount: 0,
          queuedAt: queuedAt,
        );
        final session = TrackingSessionRecord(
          id: 51,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 1, 9),
          updatedAt: DateTime(2026, 2, 1, 10),
        );
        final points = buildTestPoints(sessionId: session.id, count: 5);

        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer((_) async => [currentQueueEntry]);
        when(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: any(named: 'sessionId'),
            status: any(named: 'status'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          currentQueueEntry = SyncQueueEntry(
            sessionId: currentQueueEntry.sessionId,
            status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
            retryCount:
                invocation.namedArguments[#retryCount] as int? ??
                currentQueueEntry.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: currentQueueEntry.queuedAt,
          );
        });
        when(
          () => repository.loadSession(session.id),
        ).thenAnswer((_) async => session);
        when(
          () => repository.loadPointsForSession(session.id),
        ).thenAnswer((_) async => points);
        when(
          () => repository.updateSessionRemoteId(session.id, 'remote-51'),
        ).thenAnswer((_) async {});
        when(() => repository.loadSyncQueueEntry(session.id)).thenAnswer(
          (_) async => currentQueueEntry,
        );
        when(() => supabaseClient.from(any())).thenAnswer(
          (invocation) => builderForTable(
            invocation.positionalArguments.first as String,
          ),
        );

        // Configure the photo uploader to throw.
        final fakePhotoUploader = FakePendingPhotoUploadService();
        fakePhotoUploader.throwOnUpload = Exception(
          'photo upload network failure',
        );

        final loggedEvents = <Map<String, Object?>>[];
        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: buildConnectivityCheckSequence([
            [ConnectivityResult.none],
            [ConnectivityResult.wifi],
          ]),
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'remote-51',
          pendingPhotoUploadService: fakePhotoUploader,
          logger: AppLogger(sink: loggedEvents.add),
        );
        addTearDown(service.dispose);

        await service.processQueue();

        // Sync should still be marked as successful despite photo upload
        // failure — photo upload errors must not propagate.
        expect(currentQueueEntry.status, SyncQueueEntryStatus.successful);

        // The photo upload failure should be logged.
        expect(
          loggedEvents,
          contains(
            allOf(
              containsPair('event_type', 'sync.pending_photo_upload'),
              containsPair('outcome', 'failure'),
            ),
          ),
        );
      },
    );
  });
}

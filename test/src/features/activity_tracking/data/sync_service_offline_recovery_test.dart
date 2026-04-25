import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'sync_service_test_support.dart';

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
  }) {
    return FakeSyncQueryBuilder(
      table: table,
      operations: operations,
      throwOnUpsert: throwOnUpsert,
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

  group('SupabaseSyncService offline-to-online recovery', () {
    test(
      'rounds fractional cadence before inserting remote track points',
      () async {
        const sessionId = 299;
        var queueEntry = SyncQueueEntry(
          sessionId: sessionId,
          status: SyncQueueEntryStatus.queued,
          retryCount: 0,
          queuedAt: DateTime(2026, 2, 10, 11),
        );
        final session = TrackingSessionRecord(
          id: sessionId,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 10, 9),
          updatedAt: DateTime(2026, 2, 10, 10),
          remoteId: 'remote-299',
        );
        final points = [
          TrackingPoint(
            sessionId: sessionId,
            timestamp: DateTime(2026, 2, 10, 9),
            coordinate: const GeoCoordinate(latitude: 37, longitude: -122),
            cadenceRpm: 85.75,
          ),
          TrackingPoint(
            sessionId: sessionId,
            timestamp: DateTime(2026, 2, 10, 9, 0, 5),
            coordinate: const GeoCoordinate(latitude: 37.0001, longitude: -122),
            cadenceRpm: 90,
          ),
        ];
        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer((_) async {
          if (queueEntry.status == SyncQueueEntryStatus.queued) {
            return [queueEntry];
          }
          return const [];
        });
        when(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: sessionId,
            status: any(named: 'status'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          final existing = queueEntry;
          queueEntry = SyncQueueEntry(
            sessionId: sessionId,
            status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
            retryCount:
                invocation.namedArguments[#retryCount] as int? ??
                existing.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: existing.queuedAt,
          );
        });
        when(
          () => repository.loadSyncQueueEntry(sessionId),
        ).thenAnswer((_) async => queueEntry);
        when(
          () => repository.loadSession(sessionId),
        ).thenAnswer((_) async => session);
        when(
          () => repository.loadPointsForSession(sessionId),
        ).thenAnswer((_) async => points);
        when(() => supabaseClient.from(any())).thenAnswer(
          (invocation) =>
              builderForTable(invocation.positionalArguments.first as String),
        );

        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: () async => [ConnectivityResult.none],
          currentUserIdProvider: () => 'user-1',
        );
        addTearDown(service.dispose);

        await service.processQueue();

        final trackPointInsert = operations.singleWhere(
          (operation) =>
              operation.table == 'track_points' && operation.kind == 'insert',
        );
        final insertedRows = trackPointInsert.payload! as List<dynamic>;
        expect(insertedRows, hasLength(2));
        final insertedCadenceValues = insertedRows
            .map(
              (row) => (row as Map<String, dynamic>)['cadence'] as int?,
            )
            .toList(growable: false);
        expect(insertedCadenceValues, equals([86, 90]));
      },
    );

    test(
      'retains offline-queued work and uploads all cleaned track points after reconnect',
      () async {
        const sessionId = 300;
        SyncQueueEntry? queueEntry;
        final session = TrackingSessionRecord(
          id: sessionId,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 10, 9),
          updatedAt: DateTime(2026, 2, 10, 10),
          remoteId: 'remote-300',
        );
        final points = buildTestPoints(sessionId: sessionId, count: 1500);
        final cleanedPoints = cleanTrackingPoints(points).cleanedPoints;

        when(
          () => repository.upsertSyncQueueEntry(
            sessionId: sessionId,
            status: SyncQueueEntryStatus.queued,
            queuedAt: any(named: 'queuedAt'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          queueEntry = SyncQueueEntry(
            sessionId: sessionId,
            status: SyncQueueEntryStatus.queued,
            retryCount: invocation.namedArguments[#retryCount] as int,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: invocation.namedArguments[#queuedAt] as DateTime,
          );
        });
        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer((_) async {
          final currentEntry = queueEntry;
          if (currentEntry != null &&
              currentEntry.status == SyncQueueEntryStatus.queued) {
            return [currentEntry];
          }
          return const [];
        });
        when(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: sessionId,
            status: any(named: 'status'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          final existing = queueEntry!;
          queueEntry = SyncQueueEntry(
            sessionId: sessionId,
            status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
            retryCount:
                invocation.namedArguments[#retryCount] as int? ??
                existing.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: existing.queuedAt,
          );
        });
        when(
          () => repository.loadSyncQueueEntry(sessionId),
        ).thenAnswer((_) async => queueEntry);
        when(
          () => repository.loadSession(sessionId),
        ).thenAnswer((_) async => session);
        when(
          () => repository.loadPointsForSession(sessionId),
        ).thenAnswer((_) async => points);
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
          ]),
          currentUserIdProvider: () => 'user-1',
        );
        addTearDown(service.dispose);

        await service.queueForSync(sessionId);

        expect(
          operations.where(
            (operation) =>
                operation.table == 'activities' && operation.kind == 'upsert',
          ),
          isEmpty,
        );

        connectivityController.add([ConnectivityResult.wifi]);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final activityUpserts = operations.where(
          (operation) =>
              operation.table == 'activities' && operation.kind == 'upsert',
        );
        final pointInserts = operations.where(
          (operation) =>
              operation.table == 'track_points' && operation.kind == 'insert',
        );
        expect(activityUpserts, hasLength(1));
        expect(
          pointInserts
              .map((operation) => (operation.payload! as List<dynamic>).length)
              .fold<int>(0, (sum, size) => sum + size),
          cleanedPoints.length,
        );
        expect(queueEntry!.status, SyncQueueEntryStatus.successful);
        expect(queueEntry!.retryCount, 0);
      },
    );

    test(
      'reconnect drains a multi-session backlog queued while offline',
      () async {
        final queueBySessionId = <int, SyncQueueEntry>{};
        final sessions = <int, TrackingSessionRecord>{};
        final pointsBySession = <int, List<TrackingPoint>>{};
        var expectedTotalInsertedRows = 0;

        for (final sessionId in [401, 402, 403, 404, 405, 406]) {
          sessions[sessionId] = TrackingSessionRecord(
            id: sessionId,
            status: TrackingSessionStatus.saved,
            createdAt: DateTime(2026, 2, 11, 9),
            updatedAt: DateTime(2026, 2, 11, 10),
            remoteId: 'remote-$sessionId',
          );
          final points = buildTestPoints(
            sessionId: sessionId,
            count: 4 + (sessionId % 3),
          );
          pointsBySession[sessionId] = points;
          expectedTotalInsertedRows += cleanTrackingPoints(
            points,
          ).cleanedPoints.length;
        }

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
          final existing = queueBySessionId[sessionId]!;
          queueBySessionId[sessionId] = SyncQueueEntry(
            sessionId: sessionId,
            status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
            retryCount:
                invocation.namedArguments[#retryCount] as int? ??
                existing.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: existing.queuedAt,
          );
        });
        when(
          () => repository.loadSyncQueueEntry(any()),
        ).thenAnswer((invocation) async {
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
          ]),
          currentUserIdProvider: () => 'user-1',
        );
        addTearDown(service.dispose);

        for (final sessionId in sessions.keys) {
          await service.queueForSync(sessionId);
        }

        expect(
          operations.where(
            (operation) =>
                operation.table == 'activities' && operation.kind == 'upsert',
          ),
          isEmpty,
        );

        connectivityController.add([ConnectivityResult.wifi]);
        await Future<void>.delayed(const Duration(milliseconds: 40));

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

        expect(activityUpserts, hasLength(sessions.length));
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
      'transient reconnect failure increments retry once then succeeds on next reconnect',
      () async {
        const sessionId = 500;
        SyncQueueEntry? queueEntry;
        var failFirstActivityUpsert = true;
        final session = TrackingSessionRecord(
          id: sessionId,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 2, 12, 9),
          updatedAt: DateTime(2026, 2, 12, 10),
          remoteId: 'remote-500',
        );
        final points = buildTestPoints(sessionId: sessionId, count: 14);
        final cleanedPoints = cleanTrackingPoints(points).cleanedPoints;

        when(
          () => repository.upsertSyncQueueEntry(
            sessionId: sessionId,
            status: SyncQueueEntryStatus.queued,
            queuedAt: any(named: 'queuedAt'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          queueEntry = SyncQueueEntry(
            sessionId: sessionId,
            status: SyncQueueEntryStatus.queued,
            retryCount: invocation.namedArguments[#retryCount] as int,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: invocation.namedArguments[#queuedAt] as DateTime,
          );
        });
        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer((_) async {
          final currentEntry = queueEntry;
          if (currentEntry != null &&
              currentEntry.status == SyncQueueEntryStatus.queued) {
            return [currentEntry];
          }
          return const [];
        });
        when(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: sessionId,
            status: any(named: 'status'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((invocation) async {
          final existing = queueEntry!;
          queueEntry = SyncQueueEntry(
            sessionId: sessionId,
            status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
            retryCount:
                invocation.namedArguments[#retryCount] as int? ??
                existing.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: existing.queuedAt,
          );
        });
        when(
          () => repository.loadSyncQueueEntry(sessionId),
        ).thenAnswer((_) async => queueEntry);
        when(
          () => repository.loadSession(sessionId),
        ).thenAnswer((_) async => session);
        when(
          () => repository.loadPointsForSession(sessionId),
        ).thenAnswer((_) async => points);
        when(() => supabaseClient.from(any())).thenAnswer((invocation) {
          final table = invocation.positionalArguments.first as String;
          if (table == 'activities') {
            final throwOnUpsert = failFirstActivityUpsert;
            failFirstActivityUpsert = false;
            return builderForTable('activities', throwOnUpsert: throwOnUpsert);
          }
          return builderForTable(table);
        });

        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: buildConnectivityCheckSequence([
            [ConnectivityResult.none],
          ]),
          currentUserIdProvider: () => 'user-1',
        );
        addTearDown(service.dispose);

        await service.queueForSync(sessionId);

        connectivityController.add([ConnectivityResult.wifi]);
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(queueEntry!.status, SyncQueueEntryStatus.queued);
        expect(queueEntry!.retryCount, 1);

        connectivityController.add([ConnectivityResult.none]);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        connectivityController.add([ConnectivityResult.wifi]);
        await Future<void>.delayed(const Duration(milliseconds: 30));

        final activityUpserts = operations.where(
          (operation) =>
              operation.table == 'activities' && operation.kind == 'upsert',
        );
        final pointInserts = operations.where(
          (operation) =>
              operation.table == 'track_points' && operation.kind == 'insert',
        );
        expect(activityUpserts, hasLength(1));
        expect(
          pointInserts
              .map((operation) => (operation.payload! as List<dynamic>).length)
              .fold<int>(0, (sum, size) => sum + size),
          cleanedPoints.length,
        );
        expect(queueEntry!.status, SyncQueueEntryStatus.successful);
        expect(queueEntry!.retryCount, 1);
      },
    );
  });
}

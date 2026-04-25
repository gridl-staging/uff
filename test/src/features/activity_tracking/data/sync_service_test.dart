import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/utils/app_logger.dart';
import 'sync_service_delete_remote_activity_test_group.dart';
import 'sync_service_test_support.dart';

/// Creates a breadcrumb recorder and its backing list for telemetry tests.
({
  List<Map<String, Object?>> recorded,
  Future<void> Function({
    required String message,
    required Map<String, Object?> metadata,
  })
  recorder,
})
_createBreadcrumbRecorder() {
  final recorded = <Map<String, Object?>>[];
  return (
    recorded: recorded,
    recorder:
        ({
          required String message,
          required Map<String, Object?> metadata,
        }) async {
          recorded.add(<String, Object?>{
            'message': message,
            'metadata': Map<String, Object?>.from(metadata),
          });
        },
  );
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
    List<Map<String, dynamic>> selectRows = const <Map<String, dynamic>>[],
    Object? selectError,
  }) {
    return FakeSyncQueryBuilder(
      table: table,
      operations: operations,
      throwOnUpsert: throwOnUpsert,
      selectRows: selectRows,
      selectError: selectError,
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

  group('SupabaseSyncService.queueForSync', () {
    test(
      'inserts pending queue row and triggers immediate processing when online',
      () async {
        when(
          () => repository.loadSyncQueueEntry(99),
        ).thenAnswer((_) async => null);
        when(
          () => repository.upsertSyncQueueEntry(
            sessionId: 99,
            status: SyncQueueEntryStatus.queued,
            queuedAt: any(named: 'queuedAt'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer((_) async => const []);

        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: buildConnectivityCheckSequence([
            [ConnectivityResult.none],
            [ConnectivityResult.wifi],
          ]),
          currentUserIdProvider: () => 'user-1',
          now: () => DateTime(2026, 3, 15, 10),
        );
        addTearDown(service.dispose);

        await service.queueForSync(99);

        verify(
          () => repository.upsertSyncQueueEntry(
            sessionId: 99,
            status: SyncQueueEntryStatus.queued,
            queuedAt: DateTime(2026, 3, 15, 10),
            retryCount: 0,
          ),
        ).called(1);
        verify(() => repository.loadPendingSyncQueueEntries()).called(1);
      },
    );

    test(
      'refreshing an existing queue row resets retry count and clears error',
      () async {
        when(
          () => repository.upsertSyncQueueEntry(
            sessionId: 100,
            status: SyncQueueEntryStatus.queued,
            queuedAt: any(named: 'queuedAt'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer((_) async => const []);

        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: () async => [ConnectivityResult.none],
          currentUserIdProvider: () => 'user-1',
          now: () => DateTime(2026, 3, 15, 10, 30),
        );
        addTearDown(service.dispose);

        await service.queueForSync(100);

        verify(
          () => repository.upsertSyncQueueEntry(
            sessionId: 100,
            status: SyncQueueEntryStatus.queued,
            queuedAt: DateTime(2026, 3, 15, 10, 30),
            retryCount: 0,
          ),
        ).called(1);
        verifyNever(() => repository.loadPendingSyncQueueEntries());
      },
    );

    test(
      'emits structured queue lifecycle logs for enqueue and immediate idle processing',
      () async {
        final loggedEvents = <Map<String, Object?>>[];
        when(
          () => repository.upsertSyncQueueEntry(
            sessionId: 101,
            status: SyncQueueEntryStatus.queued,
            queuedAt: any(named: 'queuedAt'),
            retryCount: any(named: 'retryCount'),
            lastError: any(named: 'lastError'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer((_) async => const []);

        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: buildConnectivityCheckSequence([
            [ConnectivityResult.none],
            [ConnectivityResult.wifi],
          ]),
          currentUserIdProvider: () => 'user-1',
          now: () => DateTime(2026, 3, 15, 11),
          logger: AppLogger(sink: loggedEvents.add),
        );
        addTearDown(service.dispose);

        await service.queueForSync(101);

        expect(
          loggedEvents,
          contains(
            allOf(
              containsPair('event_type', 'sync.queue.enqueue'),
              containsPair('outcome', 'queued'),
            ),
          ),
        );
        expect(
          loggedEvents,
          contains(
            allOf(
              containsPair('event_type', 'sync.queue.process'),
              containsPair('outcome', 'idle'),
            ),
          ),
        );
      },
    );
  });

  group('SupabaseSyncService telemetry breadcrumbs', () {
    test('queueForSync records a boundary breadcrumb', () async {
      final (:recorded, :recorder) = _createBreadcrumbRecorder();

      when(
        () => repository.upsertSyncQueueEntry(
          sessionId: 901,
          status: SyncQueueEntryStatus.queued,
          queuedAt: any(named: 'queuedAt'),
          retryCount: any(named: 'retryCount'),
          lastError: any(named: 'lastError'),
        ),
      ).thenAnswer((_) async {});
      final service = SupabaseSyncService(
        repository: repository,
        supabaseClient: supabaseClient,
        connectivityChanges: connectivityController.stream,
        checkConnectivity: () async => [ConnectivityResult.none],
        currentUserIdProvider: () => 'user-1',
        breadcrumbRecorder: recorder,
      );
      addTearDown(service.dispose);

      await service.queueForSync(901);

      expect(recorded, hasLength(1));
      expect(recorded.single['message'], 'sync.queue_for_sync');
      expect(
        recorded.single['metadata'],
        allOf(
          containsPair('boundary', 'sync_service'),
          containsPair('operation', 'queue_for_sync'),
          containsPair('session_id', 901),
        ),
      );
    });

    test('processQueue records a boundary breadcrumb', () async {
      final (:recorded, :recorder) = _createBreadcrumbRecorder();

      when(
        () => repository.loadPendingSyncQueueEntries(),
      ).thenAnswer((_) async => const []);
      final service = SupabaseSyncService(
        repository: repository,
        supabaseClient: supabaseClient,
        connectivityChanges: connectivityController.stream,
        checkConnectivity: () async => [ConnectivityResult.none],
        currentUserIdProvider: () => 'user-1',
        breadcrumbRecorder: recorder,
      );
      addTearDown(service.dispose);

      await service.processQueue();

      expect(
        recorded.map((entry) => entry['message']),
        contains('sync.process_queue'),
      );
      expect(
        recorded
            .where((entry) => entry['message'] == 'sync.process_queue')
            .single['metadata'],
        allOf(
          containsPair('boundary', 'sync_service'),
          containsPair('operation', 'process_queue'),
        ),
      );
    });

    test(
      'processQueue records entry-level breadcrumb from _processQueueEntry',
      () async {
        final (:recorded, :recorder) = _createBreadcrumbRecorder();

        const sessionId = 902;
        var queueEntry = SyncQueueEntry(
          sessionId: sessionId,
          status: SyncQueueEntryStatus.queued,
          retryCount: 0,
          queuedAt: DateTime(2026, 3, 20, 9),
        );
        final session = TrackingSessionRecord(
          id: sessionId,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 3, 20, 9),
          updatedAt: DateTime(2026, 3, 20, 10),
          remoteId: 'remote-902',
        );
        final points = buildTestPoints(sessionId: sessionId, count: 8);
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
          queueEntry = SyncQueueEntry(
            sessionId: sessionId,
            status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
            retryCount:
                invocation.namedArguments[#retryCount] as int? ??
                queueEntry.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: queueEntry.queuedAt,
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
          breadcrumbRecorder: recorder,
        );
        addTearDown(service.dispose);

        await service.processQueue();

        expect(
          recorded.map((entry) => entry['message']),
          containsAll(<String>[
            'sync.process_queue',
            'sync.process_queue_entry',
          ]),
        );
        expect(
          recorded
              .where((entry) => entry['message'] == 'sync.process_queue_entry')
              .single['metadata'],
          allOf(
            containsPair('boundary', 'sync_service'),
            containsPair('operation', 'process_queue_entry'),
            containsPair('session_id', sessionId),
          ),
        );
      },
    );

    test(
      'processQueue ignores synchronous breadcrumb recorder failures and still processes entries',
      () async {
        Future<void> breadcrumbRecorder({
          required String message,
          required Map<String, Object?> metadata,
        }) {
          throw StateError('breadcrumb sink failed');
        }

        const sessionId = 903;
        var queueEntry = SyncQueueEntry(
          sessionId: sessionId,
          status: SyncQueueEntryStatus.queued,
          retryCount: 0,
          queuedAt: DateTime(2026, 3, 20, 9),
        );
        final session = TrackingSessionRecord(
          id: sessionId,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2026, 3, 20, 9),
          updatedAt: DateTime(2026, 3, 20, 10),
          remoteId: 'remote-903',
        );
        final points = buildTestPoints(sessionId: sessionId, count: 8);
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
          queueEntry = SyncQueueEntry(
            sessionId: sessionId,
            status: invocation.namedArguments[#status] as SyncQueueEntryStatus,
            retryCount:
                invocation.namedArguments[#retryCount] as int? ??
                queueEntry.retryCount,
            lastError: invocation.namedArguments[#lastError] as String?,
            queuedAt: queueEntry.queuedAt,
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
          breadcrumbRecorder: breadcrumbRecorder,
        );
        addTearDown(service.dispose);

        await service.processQueue();

        verify(
          () => repository.updateSyncQueueEntryStatus(
            sessionId: sessionId,
            status: SyncQueueEntryStatus.successful,
            retryCount: 0,
          ),
        ).called(1);
        expect(
          operations.where(
            (operation) =>
                operation.table == 'activities' && operation.kind == 'upsert',
          ),
          hasLength(1),
        );
      },
    );
  });

  group('SupabaseSyncService connectivity listener', () {
    test('processes queued work on startup when already online', () async {
      when(
        () => repository.loadPendingSyncQueueEntries(),
      ).thenAnswer((_) async => const []);

      final service = SupabaseSyncService(
        repository: repository,
        supabaseClient: supabaseClient,
        connectivityChanges: connectivityController.stream,
        checkConnectivity: buildConnectivityCheckSequence([
          [ConnectivityResult.wifi],
        ]),
        currentUserIdProvider: () => 'user-1',
      );
      addTearDown(service.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      verify(() => repository.loadPendingSyncQueueEntries()).called(1);
    });

    test('processes queue when connectivity transitions to online', () async {
      when(
        () => repository.loadPendingSyncQueueEntries(),
      ).thenAnswer((_) async => const []);

      final service = SupabaseSyncService(
        repository: repository,
        supabaseClient: supabaseClient,
        connectivityChanges: connectivityController.stream,
        checkConnectivity: () async => [ConnectivityResult.none],
        currentUserIdProvider: () => 'user-1',
      );
      addTearDown(service.dispose);

      connectivityController.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      verify(() => repository.loadPendingSyncQueueEntries()).called(1);
    });

    test(
      'processes queue when connectivity transitions to bluetooth',
      () async {
        when(
          () => repository.loadPendingSyncQueueEntries(),
        ).thenAnswer((_) async => const []);

        final service = SupabaseSyncService(
          repository: repository,
          supabaseClient: supabaseClient,
          connectivityChanges: connectivityController.stream,
          checkConnectivity: () async => [ConnectivityResult.none],
          currentUserIdProvider: () => 'user-1',
        );
        addTearDown(service.dispose);

        connectivityController.add([ConnectivityResult.bluetooth]);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        verify(() => repository.loadPendingSyncQueueEntries()).called(1);
      },
    );

    test('processes queue when connectivity reports other transport', () async {
      when(
        () => repository.loadPendingSyncQueueEntries(),
      ).thenAnswer((_) async => const []);

      final service = SupabaseSyncService(
        repository: repository,
        supabaseClient: supabaseClient,
        connectivityChanges: connectivityController.stream,
        checkConnectivity: () async => [ConnectivityResult.none],
        currentUserIdProvider: () => 'user-1',
      );
      addTearDown(service.dispose);

      connectivityController.add([ConnectivityResult.other]);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      verify(() => repository.loadPendingSyncQueueEntries()).called(1);
    });
  });

  registerDeleteRemoteActivityTests(
    repository: () => repository,
    supabaseClient: () => supabaseClient,
    operations: () => operations,
    connectivityController: () => connectivityController,
    builderForTable: builderForTable,
  );
}

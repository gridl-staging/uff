import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/data/activity_gear_assignment_repository.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_repository.dart';
import 'package:uff/src/features/gear/application/gear_providers.dart';

import '../../../test_helpers/gear_test_support.dart';

class FakeActivityTrackingRepository implements TrackingRepository {
  FakeActivityTrackingRepository();

  final Map<int, TrackingSessionRecord> sessionsById = {};
  final Map<int, List<TrackingPoint>> pointsBySessionId = {};
  final Map<int, SyncQueueEntry> syncQueueBySessionId = {};

  @override
  Future<TrackingSessionRecord> createSession() {
    throw UnsupportedError('createSession not supported in this fake');
  }

  @override
  Future<void> appendPointBatch(List<TrackingPoint> points) async {
    throw UnsupportedError('appendPointBatch not supported in this fake');
  }

  @override
  Future<List<TrackingPoint>> loadPointsForSession(int sessionId) async {
    return pointsBySessionId[sessionId] ?? [];
  }

  @override
  FutureOr<TrackingSessionRecord?> loadSession(int sessionId) {
    return sessionsById[sessionId];
  }

  @override
  Future<List<TrackingSessionRecord>> loadSavedSessions() {
    return Future.value(
      sessionsById.values
          .where((session) => session.status == TrackingSessionStatus.saved)
          .toList(growable: false)
        ..sort(
          (left, right) {
            final leftSort = left.startedAt ?? left.updatedAt;
            final rightSort = right.startedAt ?? right.updatedAt;
            return rightSort.compareTo(leftSort);
          },
        ),
    );
  }

  @override
  Future<TrackingSessionRecord?> loadActiveSession() {
    if (sessionsById.isEmpty) {
      return Future.value();
    }

    return Future.value(sessionsById.values.first);
  }

  @override
  Future<void> saveSession(TrackingSessionRecord session) async {
    sessionsById[session.id] = session;
  }

  @override
  Future<void> updateSessionStatus(
    int sessionId,
    TrackingSessionStatus status,
    DateTime at,
  ) async {
    final current = sessionsById[sessionId];
    if (current == null) {
      return;
    }
    sessionsById[sessionId] = current.copyWith(status: status, updatedAt: at);
  }

  @override
  Future<void> finalizeSession(int sessionId) async {
    final current = sessionsById[sessionId];
    if (current == null) {
      return;
    }
    sessionsById[sessionId] = current.copyWith(
      status: TrackingSessionStatus.saved,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> discardSession(int sessionId) async {
    final current = sessionsById[sessionId];
    if (current == null) {
      return;
    }
    sessionsById[sessionId] = current.copyWith(
      status: TrackingSessionStatus.discarded,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> updateSessionRemoteId(int sessionId, String remoteId) async {
    final session = sessionsById[sessionId];
    if (session == null) {
      return;
    }
    sessionsById[sessionId] = session.copyWith(remoteId: remoteId);
  }

  @override
  Future<void> upsertSyncQueueEntry({
    required int sessionId,
    required SyncQueueEntryStatus status,
    required DateTime queuedAt,
    int retryCount = 0,
    String? lastError,
  }) async {
    syncQueueBySessionId[sessionId] = SyncQueueEntry(
      sessionId: sessionId,
      status: status,
      retryCount: retryCount,
      lastError: lastError,
      queuedAt: queuedAt,
    );
  }

  @override
  Future<List<SyncQueueEntry>> loadPendingSyncQueueEntries() async {
    return syncQueueBySessionId.values
        .where((entry) => entry.status == SyncQueueEntryStatus.queued)
        .toList(growable: false);
  }

  @override
  Future<SyncQueueEntry?> loadSyncQueueEntry(int sessionId) async {
    return syncQueueBySessionId[sessionId];
  }

  @override
  Future<void> updateSyncQueueEntryStatus({
    required int sessionId,
    required SyncQueueEntryStatus status,
    int? retryCount,
    String? lastError,
  }) async {
    final existing = syncQueueBySessionId[sessionId];
    if (existing == null) {
      return;
    }
    syncQueueBySessionId[sessionId] = SyncQueueEntry(
      sessionId: existing.sessionId,
      status: status,
      retryCount: retryCount ?? existing.retryCount,
      lastError: lastError,
      queuedAt: existing.queuedAt,
    );
  }

  @override
  Future<void> deleteActivity(int sessionId) async {
    syncQueueBySessionId.remove(sessionId);
    pointsBySessionId.remove(sessionId);
    sessionsById.remove(sessionId);
  }

  @override
  Future<int> saveImportedSession(
    TrackingSessionRecord session,
    List<TrackingPoint> points,
  ) async {
    throw UnsupportedError('saveImportedSession not used in this test');
  }
}

class FakeActivityGearAssignmentRepository
    implements ActivityGearAssignmentRepository {
  final Map<String, String?> assignedGearByRemoteActivityId = {};

  int loadCallCount = 0;
  int updateCallCount = 0;
  String? lastLoadedRemoteActivityId;
  String? lastUpdatedRemoteActivityId;
  String? lastUpdatedGearId;

  @override
  Future<String?> loadAssignedGearId(String remoteActivityId) async {
    loadCallCount += 1;
    lastLoadedRemoteActivityId = remoteActivityId;
    return assignedGearByRemoteActivityId[remoteActivityId];
  }

  @override
  Future<void> updateAssignedGearId(
    String remoteActivityId,
    String? gearId,
  ) async {
    updateCallCount += 1;
    lastUpdatedRemoteActivityId = remoteActivityId;
    lastUpdatedGearId = gearId;
    assignedGearByRemoteActivityId[remoteActivityId] = gearId;
  }
}

void main() {
  group('Activity tracking providers', () {
    test(
      'detail provider loads session points and computes metrics for full detail view',
      () async {
        final repository = FakeActivityTrackingRepository();
        final session = TrackingSessionRecord(
          id: 12,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2025),
          updatedAt: DateTime(2025),
          startedAt: DateTime(2025, 1, 1, 12),
        );
        repository.sessionsById[session.id] = session;
        repository.pointsBySessionId[session.id] = [
          TrackingPoint(
            sessionId: session.id,
            timestamp: DateTime(2025, 1, 1, 12),
            coordinate: const GeoCoordinate(latitude: 0, longitude: 0),
          ),
          TrackingPoint(
            sessionId: session.id,
            timestamp: DateTime(2025, 1, 1, 12, 0, 5),
            coordinate: const GeoCoordinate(
              latitude: 0,
              longitude: 0.0005,
            ),
          ),
        ];

        final container = ProviderContainer(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        final detailState = await container.read(
          activityDetailProvider(session.id).future,
        );

        expect(detailState?.session.id, session.id);
        expect(detailState?.cleanedPoints, hasLength(2));
        final expectedDistance = calculateTrackDistanceMeters(
          repository.pointsBySessionId[session.id]!,
        );
        expect(
          detailState?.processedMetrics.trackSummary.distanceMeters,
          closeTo(expectedDistance, 0.5),
        );
      },
    );

    test(
      'history provider exposes saved sessions sorted by repository output',
      () async {
        final repository = FakeActivityTrackingRepository();
        repository.sessionsById[1] = TrackingSessionRecord(
          id: 1,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2025, 1, 1, 12),
          updatedAt: DateTime(2025, 1, 1, 12),
          startedAt: DateTime(2025, 1, 1, 12),
          distanceMeters: 1200,
          movingTimeSeconds: 420,
        );
        repository.sessionsById[2] = TrackingSessionRecord(
          id: 2,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2025, 1, 2, 12),
          updatedAt: DateTime(2025, 1, 2, 12),
          startedAt: DateTime(2025, 1, 2, 12),
          distanceMeters: 1100,
          movingTimeSeconds: 360,
        );

        final container = ProviderContainer(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        final sessions = await container.read(savedActivitiesProvider.future);
        expect(sessions, hasLength(2));
        expect(sessions.first.id, 2);
        expect(sessions.last.id, 1);
      },
    );

    test(
      'history provider reloads after invalidation when new sessions are saved',
      () async {
        final repository = FakeActivityTrackingRepository();
        repository.sessionsById[1] = TrackingSessionRecord(
          id: 1,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2025, 1, 1, 12),
          updatedAt: DateTime(2025, 1, 1, 12),
          startedAt: DateTime(2025, 1, 1, 12),
          distanceMeters: 1200,
          movingTimeSeconds: 420,
        );

        final container = ProviderContainer(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        final initialSessions = await container.read(
          savedActivitiesProvider.future,
        );
        expect(initialSessions.map((session) => session.id), [1]);

        repository.sessionsById[2] = TrackingSessionRecord(
          id: 2,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2025, 1, 2, 12),
          updatedAt: DateTime(2025, 1, 2, 12),
          startedAt: DateTime(2025, 1, 2, 12),
          distanceMeters: 1100,
          movingTimeSeconds: 360,
        );

        container.invalidate(savedActivitiesProvider);
        final refreshedSessions = await container.read(
          savedActivitiesProvider.future,
        );
        expect(refreshedSessions.map((session) => session.id), [2, 1]);
      },
    );

    test(
      'activity detail gear provider exposes active shoe and bike selections',
      () async {
        final trackingRepository = FakeActivityTrackingRepository();
        final assignmentRepository = FakeActivityGearAssignmentRepository();
        final gearRepository = RecordingGearRepository(
          itemsToReturn: [
            testRetiredComponentGear,
            testBikeGear,
            testShoeGear,
          ],
        );
        const remoteActivityId = 'remote-activity-1';
        trackingRepository.sessionsById[42] = TrackingSessionRecord(
          id: 42,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2025),
          updatedAt: DateTime(2025),
          remoteId: remoteActivityId,
        );
        assignmentRepository.assignedGearByRemoteActivityId[remoteActivityId] =
            testBikeGear.id;

        final container = ProviderContainer(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(trackingRepository),
            activityGearAssignmentRepositoryProvider.overrideWithValue(
              assignmentRepository,
            ),
            gearRepositoryProvider.overrideWithValue(gearRepository),
          ],
        );
        addTearDown(container.dispose);

        // Keep auto-dispose provider alive during the async chain.
        container.listen(activityDetailGearProvider(42), (_, __) {});

        final state = await container.read(
          activityDetailGearProvider(42).future,
        );

        expect(state.isEditable, isTrue);
        expect(state.remoteActivityId, remoteActivityId);
        expect(state.selectedGearId, testBikeGear.id);
        expect(state.hasStaleAssignedGear, isFalse);
        expect(
          state.selectableGear.map((item) => item.id),
          [testBikeGear.id, testShoeGear.id],
        );
        expect(assignmentRepository.loadCallCount, 1);
        expect(
          assignmentRepository.lastLoadedRemoteActivityId,
          remoteActivityId,
        );
      },
    );

    test(
      'activity detail gear provider returns non-editable state for unsynced activity',
      () async {
        final trackingRepository = FakeActivityTrackingRepository();
        final assignmentRepository = FakeActivityGearAssignmentRepository();
        final gearRepository = RecordingGearRepository(
          itemsToReturn: [testShoeGear, testBikeGear],
        );
        trackingRepository.sessionsById[43] = TrackingSessionRecord(
          id: 43,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2025),
          updatedAt: DateTime(2025),
        );

        final container = ProviderContainer(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(trackingRepository),
            activityGearAssignmentRepositoryProvider.overrideWithValue(
              assignmentRepository,
            ),
            gearRepositoryProvider.overrideWithValue(gearRepository),
          ],
        );
        addTearDown(container.dispose);

        // Keep auto-dispose provider alive during the async chain.
        container.listen(activityDetailGearProvider(43), (_, __) {});

        final state = await container.read(
          activityDetailGearProvider(43).future,
        );

        expect(state.isEditable, isFalse);
        expect(state.remoteActivityId, isNull);
        expect(state.nonEditableMessage, contains('sync'));
        expect(assignmentRepository.loadCallCount, 0);
      },
    );

    test(
      'activity detail gear provider handles stale assigned gear id safely',
      () async {
        final trackingRepository = FakeActivityTrackingRepository();
        final assignmentRepository = FakeActivityGearAssignmentRepository();
        final gearRepository = RecordingGearRepository(
          itemsToReturn: [testShoeGear],
        );
        const remoteActivityId = 'remote-activity-2';
        trackingRepository.sessionsById[44] = TrackingSessionRecord(
          id: 44,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2025),
          updatedAt: DateTime(2025),
          remoteId: remoteActivityId,
        );
        assignmentRepository.assignedGearByRemoteActivityId[remoteActivityId] =
            'deleted-gear-id';

        final container = ProviderContainer(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(trackingRepository),
            activityGearAssignmentRepositoryProvider.overrideWithValue(
              assignmentRepository,
            ),
            gearRepositoryProvider.overrideWithValue(gearRepository),
          ],
        );
        addTearDown(container.dispose);

        // Keep auto-dispose provider alive during the async chain.
        container.listen(activityDetailGearProvider(44), (_, __) {});

        final state = await container.read(
          activityDetailGearProvider(44).future,
        );

        expect(state.isEditable, isTrue);
        expect(state.hasStaleAssignedGear, isTrue);
        expect(state.selectedGearId, isNull);
        expect(state.selectableGear.map((item) => item.id), [testShoeGear.id]);
      },
    );
  });
}

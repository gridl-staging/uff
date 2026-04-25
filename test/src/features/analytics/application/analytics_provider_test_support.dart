import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_repository.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';

/// TODO: Document FakeTrackingRepository.
class FakeTrackingRepository implements TrackingRepository {
  final Map<int, TrackingSessionRecord> sessionsById = {};
  final Map<int, List<TrackingPoint>> pointsBySessionId = {};
  int loadSavedSessionsCallCount = 0;
  int loadSessionCallCount = 0;
  int loadPointsForSessionCallCount = 0;

  @override
  Future<List<TrackingSessionRecord>> loadSavedSessions() async {
    loadSavedSessionsCallCount++;
    return sessionsById.values
        .where((s) => s.status == TrackingSessionStatus.saved)
        .toList(growable: false)
      ..sort((a, b) {
        final aSort = a.startedAt ?? a.updatedAt;
        final bSort = b.startedAt ?? b.updatedAt;
        return bSort.compareTo(aSort);
      });
  }

  @override
  FutureOr<TrackingSessionRecord?> loadSession(int sessionId) {
    loadSessionCallCount++;
    return sessionsById[sessionId];
  }

  @override
  Future<List<TrackingPoint>> loadPointsForSession(int sessionId) async {
    loadPointsForSessionCallCount++;
    return pointsBySessionId[sessionId] ?? [];
  }

  @override
  Future<TrackingSessionRecord> createSession() =>
      throw UnsupportedError('not needed');

  @override
  Future<void> appendPointBatch(List<TrackingPoint> points) =>
      throw UnsupportedError('not needed');

  @override
  Future<void> saveSession(TrackingSessionRecord session) =>
      throw UnsupportedError('not needed');

  @override
  Future<void> updateSessionStatus(
    int sessionId,
    TrackingSessionStatus status,
    DateTime at,
  ) => throw UnsupportedError('not needed');

  @override
  Future<void> finalizeSession(int sessionId) =>
      throw UnsupportedError('not needed');

  @override
  Future<void> discardSession(int sessionId) =>
      throw UnsupportedError('not needed');

  @override
  Future<void> updateSessionRemoteId(int sessionId, String remoteId) =>
      throw UnsupportedError('not needed');

  @override
  Future<int> saveImportedSession(
    TrackingSessionRecord session,
    List<TrackingPoint> points,
  ) => throw UnsupportedError('not needed');

  @override
  Future<void> upsertSyncQueueEntry({
    required int sessionId,
    required SyncQueueEntryStatus status,
    required DateTime queuedAt,
    int retryCount = 0,
    String? lastError,
  }) => throw UnsupportedError('not needed');

  @override
  Future<List<SyncQueueEntry>> loadPendingSyncQueueEntries() async => const [];

  @override
  Future<SyncQueueEntry?> loadSyncQueueEntry(int sessionId) async => null;

  @override
  Future<void> updateSyncQueueEntryStatus({
    required int sessionId,
    required SyncQueueEntryStatus status,
    int? retryCount,
    String? lastError,
  }) => throw UnsupportedError('not needed');

  @override
  Future<TrackingSessionRecord?> loadActiveSession() =>
      throw UnsupportedError('not needed');

  @override
  Future<void> deleteActivity(int sessionId) =>
      throw UnsupportedError('not needed');
}

TrackingSessionRecord savedSession({
  required int id,
  required DateTime startedAt,
  double? distanceMeters,
  int? movingTimeSeconds,
}) {
  return TrackingSessionRecord(
    id: id,
    status: TrackingSessionStatus.saved,
    createdAt: startedAt,
    updatedAt: startedAt,
    startedAt: startedAt,
    distanceMeters: distanceMeters,
    movingTimeSeconds: movingTimeSeconds,
  );
}

ProviderContainer createContainer(
  FakeTrackingRepository repository, {
  AsyncValue<Profile?> profileState = const AsyncData<Profile?>(null),
}) {
  return ProviderContainer(
    overrides: [
      trackingRepositoryProvider.overrideWithValue(repository),
      profileProvider.overrideWith(() => _FakeProfileNotifier(profileState)),
    ],
  );
}

/// Fake [ProfileNotifier] that returns a fixed [AsyncValue] state.
class _FakeProfileNotifier extends ProfileNotifier {
  _FakeProfileNotifier(this.profileState);

  final AsyncValue<Profile?> profileState;

  @override
  FutureOr<Profile?> build() {
    return profileState.when(
      data: (profile) => profile,
      loading: () => Completer<Profile?>().future,
      error: Error.throwWithStackTrace,
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_controller.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

import 'tracking_controller_test_support.dart';

/// ## Test Scenarios
/// - `[edge]` Restore exits without applying state when no active session exists.
/// - `[positive]` Restore applies persisted points once when engine recovery is empty.
/// - `[positive]` Restore applies state twice when recovered engine samples are merged.
/// - `[negative]` Stopped sessions skip engine recovery and apply state once.
/// - `[statemachine]` Restored timeline segment start is set for recording and cleared for paused.
void main() {
  group('SessionRestorer', () {
    test('does not call applyState when no active session exists', () async {
      final repository = FakeTrackingRepository();
      final engine = FakeTrackingEngine();
      final restorer = SessionRestorer(
        repository: repository,
        trackingEngine: engine,
        clock: () => DateTime(2026, 1, 1, 9),
      );
      final appliedStates = <RecordingControllerState>[];

      await restorer.restore(
        currentErrorState: const RecordingErrorState(message: 'existing'),
        applyState: appliedStates.add,
      );

      expect(appliedStates.length, equals(0));
      expect(engine.recoveredSessionId, equals(null));
    });

    test(
      'applies state once with persisted points when engine recovery is empty',
      () async {
        final now = DateTime(2026, 1, 1, 9, 0, 30);
        final startedAt = DateTime(2026, 1, 1, 9);
        final persistedPoint = TrackingPoint(
          sessionId: 7,
          timestamp: DateTime(2026, 1, 1, 9, 0, 5),
          coordinate: const GeoCoordinate(latitude: 1, longitude: 2),
        );
        final repository = FakeTrackingRepository()
          ..activeSession = TrackingSessionRecord(
            id: 7,
            status: TrackingSessionStatus.recording,
            createdAt: startedAt,
            updatedAt: startedAt,
            startedAt: startedAt,
          )
          ..points.add(persistedPoint);
        final engine = FakeTrackingEngine();
        final restorer = SessionRestorer(
          repository: repository,
          trackingEngine: engine,
          clock: () => now,
        );
        final appliedStates = <RecordingControllerState>[];

        await restorer.restore(
          currentErrorState: const RecordingErrorState(message: 'existing'),
          applyState: appliedStates.add,
        );

        expect(appliedStates.length, equals(1));
        final restored = appliedStates.single;
        expect(restored.status, equals(TrackingSessionStatus.recording));
        expect(restored.pointCount, equals(1));
        expect(
          restored.points.single.timestamp,
          equals(persistedPoint.timestamp),
        );
        expect(restored.segmentStartTimestamp, equals(now));
        expect(restored.activeDuration, equals(now.difference(startedAt)));
        expect(restored.lastFixTimestamp, equals(persistedPoint.timestamp));
        expect(restored.errorState.message, equals('existing'));
        expect(engine.recoveredSessionId, equals(7));
      },
    );

    test(
      'applies state twice with merged points when engine recovery finds samples',
      () async {
        final now = DateTime(2026, 1, 1, 9, 10);
        final startedAt = DateTime(2026, 1, 1, 9);
        final persistedPoint = TrackingPoint(
          sessionId: 17,
          timestamp: DateTime(2026, 1, 1, 9, 0, 1),
          coordinate: const GeoCoordinate(latitude: 10, longitude: 10),
        );
        final recoveredPointOne = TrackingPoint(
          sessionId: 17,
          timestamp: DateTime(2026, 1, 1, 9, 0, 2),
          coordinate: const GeoCoordinate(latitude: 10.1, longitude: 10.1),
        );
        final recoveredPointTwo = TrackingPoint(
          sessionId: 17,
          timestamp: DateTime(2026, 1, 1, 9, 0, 3),
          coordinate: const GeoCoordinate(latitude: 10.2, longitude: 10.2),
        );
        final repository = FakeTrackingRepository()
          ..activeSession = TrackingSessionRecord(
            id: 17,
            status: TrackingSessionStatus.recording,
            createdAt: startedAt,
            updatedAt: startedAt,
            startedAt: startedAt,
          )
          ..points.add(persistedPoint);
        final engine = FakeTrackingEngine(
          recoveredSamples: [recoveredPointOne, recoveredPointTwo],
        );
        final restorer = SessionRestorer(
          repository: repository,
          trackingEngine: engine,
          clock: () => now,
        );
        final appliedStates = <RecordingControllerState>[];

        await restorer.restore(
          currentErrorState: const RecordingErrorState.none(),
          applyState: appliedStates.add,
        );

        expect(appliedStates.length, equals(2));
        final firstState = appliedStates.first;
        final secondState = appliedStates.last;
        expect(firstState.pointCount, equals(1));
        expect(firstState.lastFixTimestamp, equals(persistedPoint.timestamp));
        expect(secondState.pointCount, equals(3));
        expect(
          secondState.lastFixTimestamp,
          equals(recoveredPointTwo.timestamp),
        );
        expect(secondState.segmentStartTimestamp, equals(now));
        expect(repository.points.length, equals(3));
        expect(engine.recoveredSessionId, equals(17));
      },
    );

    test(
      'applies state once and skips engine recovery for stopped session',
      () async {
        final now = DateTime(2026, 1, 1, 10);
        final startedAt = DateTime(2026, 1, 1, 9);
        final stoppedPoint = TrackingPoint(
          sessionId: 22,
          timestamp: DateTime(2026, 1, 1, 9, 30),
          coordinate: const GeoCoordinate(latitude: 30, longitude: 30),
        );
        final repository = FakeTrackingRepository()
          ..activeSession = TrackingSessionRecord(
            id: 22,
            status: TrackingSessionStatus.stopped,
            createdAt: startedAt,
            updatedAt: now,
            startedAt: startedAt,
            stoppedAt: now,
          )
          ..points.add(stoppedPoint);
        final engine = FakeTrackingEngine(
          recoveredSamples: [
            TrackingPoint(
              sessionId: 22,
              timestamp: DateTime(2026, 1, 1, 9, 31),
              coordinate: const GeoCoordinate(latitude: 31, longitude: 31),
            ),
          ],
        );
        final restorer = SessionRestorer(
          repository: repository,
          trackingEngine: engine,
          clock: () => now,
        );
        final appliedStates = <RecordingControllerState>[];

        await restorer.restore(
          currentErrorState: const RecordingErrorState.none(),
          applyState: appliedStates.add,
        );

        expect(appliedStates.length, equals(1));
        expect(
          appliedStates.single.status,
          equals(TrackingSessionStatus.stopped),
        );
        expect(appliedStates.single.pointCount, equals(1));
        expect(appliedStates.single.segmentStartTimestamp, equals(null));
        expect(appliedStates.single.activeDuration, equals(Duration.zero));
        expect(engine.recoveredSessionId, equals(null));
        expect(repository.points.length, equals(1));
      },
    );

    test(
      'sets segmentStartTimestamp for recording sessions and clears it for paused sessions',
      () async {
        final now = DateTime(2026, 1, 1, 12);
        final startedAt = DateTime(2026, 1, 1, 11, 45);
        final recordingRepository = FakeTrackingRepository()
          ..activeSession = TrackingSessionRecord(
            id: 30,
            status: TrackingSessionStatus.recording,
            createdAt: startedAt,
            updatedAt: startedAt,
            startedAt: startedAt,
          );
        final pausedRepository = FakeTrackingRepository()
          ..activeSession = TrackingSessionRecord(
            id: 31,
            status: TrackingSessionStatus.paused,
            createdAt: startedAt,
            updatedAt: startedAt,
            startedAt: startedAt,
          );
        final recordingStates = <RecordingControllerState>[];
        final pausedStates = <RecordingControllerState>[];

        await SessionRestorer(
          repository: recordingRepository,
          trackingEngine: FakeTrackingEngine(),
          clock: () => now,
        ).restore(
          currentErrorState: const RecordingErrorState.none(),
          applyState: recordingStates.add,
        );

        await SessionRestorer(
          repository: pausedRepository,
          trackingEngine: FakeTrackingEngine(),
          clock: () => now,
        ).restore(
          currentErrorState: const RecordingErrorState.none(),
          applyState: pausedStates.add,
        );

        expect(recordingStates.length, equals(1));
        expect(recordingStates.single.segmentStartTimestamp, equals(now));
        expect(
          recordingStates.single.activeDuration,
          equals(now.difference(startedAt)),
        );
        expect(pausedStates.length, equals(1));
        expect(pausedStates.single.segmentStartTimestamp, equals(null));
        expect(pausedStates.single.activeDuration, equals(Duration.zero));
      },
    );
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_controller.dart';
import 'package:uff/src/features/activity_tracking/data/permission_service.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

import 'tracking_controller_test_support.dart';

/// ## Test Scenarios
/// - `[negative]` Invalid transitions reject impossible state changes like
///   pausing while idle.
/// - `[positive]` Recording lifecycle transitions enforce valid status changes.
/// - `[positive]` Saving persists computed metrics and enqueues sync.
/// - `[positive]` Provider invalidation rebuild keeps the shared tracking
///   engine usable for a new recording session.
/// - `[positive]` `finishRecording()` ends a paused session using the same
///   terminal transition as stop/save workflows.
/// - `[negative]` A second stop call after entering `stopped` throws an
///   invalid transition error.
/// - `[error]` Permission, engine, and persistence failures surface stable user-safe messages.
/// - `[isolation]` Restore paths replay only samples for the active session id.
/// - `[negative]` Starting a new recording after discard creates a fresh
///   session and clears in-memory points.
void main() {
  ProviderContainer createManagedControllerContainer({
    required FakeTrackingRepository repository,
    required FakeTrackingEngine engine,
    required FakePermissionService permissions,
    FakeSyncService? syncService,
  }) {
    final container = createControllerContainer(
      repository: repository,
      engine: engine,
      permissions: permissions,
      syncService: syncService,
    );
    addTearDown(container.dispose);
    return container;
  }

  group('TrackingController', () {
    test('throws on invalid transition from idle to pause', () {
      final container = createManagedControllerContainer(
        repository: FakeTrackingRepository(),
        engine: FakeTrackingEngine(),
        permissions: FakePermissionService(
          const [TrackingPermissionDecision.granted],
        ),
      );

      final notifier = container.read(recordingControllerProvider.notifier);
      expect(
        notifier.pauseRecording(),
        throwsA(isA<InvalidTrackingTransition>()),
      );
    });

    test('throws on invalid transition from stopped to stopped', () async {
      final container = createManagedControllerContainer(
        repository: FakeTrackingRepository(),
        engine: FakeTrackingEngine(),
        permissions: FakePermissionService(
          const [
            TrackingPermissionDecision.granted,
            TrackingPermissionDecision.granted,
          ],
        ),
      );
      final notifier = container.read(recordingControllerProvider.notifier);

      await notifier.startRecording();
      await notifier.pauseRecording();
      await notifier.resumeRecording();
      await notifier.stopRecording();
      expect(
        notifier.stopRecording(),
        throwsA(isA<InvalidTrackingTransition>()),
      );
    });

    test(
      'finishRecording ends a paused session the same way stop does',
      () async {
        final repository = FakeTrackingRepository();
        final engine = FakeTrackingEngine();
        final permissions = FakePermissionService(
          const [
            TrackingPermissionDecision.granted,
            TrackingPermissionDecision.granted,
          ],
        );
        final container = createManagedControllerContainer(
          repository: repository,
          engine: engine,
          permissions: permissions,
        );
        final notifier = container.read(recordingControllerProvider.notifier);

        await notifier.startRecording();
        await notifier.pauseRecording();
        await notifier.finishRecording();

        final state = container.read(recordingControllerProvider);
        expect(state.status, TrackingSessionStatus.stopped);
        expect(repository.activeSession?.status, TrackingSessionStatus.stopped);
        expect(engine.stopCalled, isTrue);
      },
    );

    test('records a full happy-path state transition flow', () async {
      final repository = FakeTrackingRepository();
      final engine = FakeTrackingEngine();
      final permissions = FakePermissionService(
        const [
          TrackingPermissionDecision.granted,
          TrackingPermissionDecision.granted,
        ],
      );
      final container = createManagedControllerContainer(
        repository: repository,
        engine: engine,
        permissions: permissions,
      );
      final notifier = container.read(recordingControllerProvider.notifier);

      await notifier.startRecording();
      final startedState = container.read(recordingControllerProvider);
      final startedSession = startedState.session!;
      expect(startedState.status, TrackingSessionStatus.recording);
      expect(
        startedSession.startedAt?.isAfter(startedSession.createdAt),
        isTrue,
      );
      expect(startedSession.startedAt, startedSession.updatedAt);
      expect(repository.activeSession?.status, TrackingSessionStatus.recording);
      expect(startedState.errorMessage, isNull);

      final sessionId = repository.activeSession!.id;
      engine.emitSample(
        TrackingPoint(
          sessionId: sessionId,
          timestamp: DateTime(2025, 1, 1, 12, 0, 1),
          coordinate: const GeoCoordinate(latitude: 1, longitude: 2),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(recordingControllerProvider).pointCount, 1);
      expect(repository.points.length, 1);

      await notifier.pauseRecording();
      expect(
        container.read(recordingControllerProvider).status,
        TrackingSessionStatus.paused,
      );
      expect(
        container.read(recordingControllerProvider).segmentStartTimestamp,
        isNull,
      );

      await notifier.resumeRecording();
      expect(
        container.read(recordingControllerProvider).status,
        TrackingSessionStatus.recording,
      );

      await notifier.stopRecording();
      final stoppedState = container.read(recordingControllerProvider);
      final stoppedSession = stoppedState.session!;
      expect(stoppedState.status, TrackingSessionStatus.stopped);
      expect(
        stoppedState.segmentStartTimestamp,
        isNull,
      );
      expect(
        stoppedSession.stoppedAt,
        stoppedSession.updatedAt,
      );
      expect(
        stoppedSession.stoppedAt?.isAfter(stoppedSession.startedAt!),
        isTrue,
      );
    });

    test(
      'starts recording with a warning when background permission is denied',
      () async {
        final repository = FakeTrackingRepository();
        final engine = FakeTrackingEngine();
        final permissions = FakePermissionService(
          const [
            TrackingPermissionDecision.granted,
            TrackingPermissionDecision.deniedPermanently,
          ],
        );
        final container = createManagedControllerContainer(
          repository: repository,
          engine: engine,
          permissions: permissions,
        );
        final notifier = container.read(recordingControllerProvider.notifier);

        await notifier.startRecording();

        final state = container.read(recordingControllerProvider);
        expect(state.status, TrackingSessionStatus.recording);
        expect(
          state.errorMessage,
          'Background location access is off. Recording started, but it may '
          'stop when the app is in the background or the phone is locked. '
          'Enable "Always" in Settings for full run tracking.',
        );
        expect(
          repository.activeSession?.status,
          TrackingSessionStatus.recording,
        );
      },
    );

    test('keeps start blocked when foreground permission is denied', () async {
      final repository = FakeTrackingRepository();
      final engine = FakeTrackingEngine();
      final permissions = FakePermissionService(
        const [TrackingPermissionDecision.deniedPermanently],
      );
      final container = createManagedControllerContainer(
        repository: repository,
        engine: engine,
        permissions: permissions,
      );
      final notifier = container.read(recordingControllerProvider.notifier);

      await notifier.startRecording();

      final state = container.read(recordingControllerProvider);
      expect(state.status, TrackingSessionStatus.idle);
      expect(
        state.errorMessage,
        'Location permission is permanently denied. Open app settings.',
      );
      expect(repository.activeSession, isNull);
    });

    test('saves and then clears active state', () async {
      final repository = FakeTrackingRepository();
      final engine = FakeTrackingEngine();
      final permissions = FakePermissionService(
        const [
          TrackingPermissionDecision.granted,
          TrackingPermissionDecision.granted,
        ],
      );
      final container = createManagedControllerContainer(
        repository: repository,
        engine: engine,
        permissions: permissions,
      );
      final notifier = container.read(recordingControllerProvider.notifier);

      await notifier.startRecording();
      await notifier.stopRecording();
      await notifier.saveRecording();

      final state = container.read(recordingControllerProvider);
      expect(state.status, TrackingSessionStatus.idle);
      expect(repository.activeSession?.status, TrackingSessionStatus.saved);
    });

    test(
      'rebuild after provider invalidation keeps shared engine usable',
      () async {
        final repository = FakeTrackingRepository();
        final engine = FakeTrackingEngine();
        final permissions = FakePermissionService(
          const [
            TrackingPermissionDecision.granted,
            TrackingPermissionDecision.granted,
            TrackingPermissionDecision.granted,
            TrackingPermissionDecision.granted,
          ],
        );
        final container = createManagedControllerContainer(
          repository: repository,
          engine: engine,
          permissions: permissions,
        );
        final notifier = container.read(recordingControllerProvider.notifier);

        await notifier.startRecording();
        await notifier.stopRecording();
        final firstSessionId = container
            .read(recordingControllerProvider)
            .session!
            .id;
        await notifier.saveRecording();

        container.invalidate(recordingControllerProvider);
        await Future<void>.delayed(Duration.zero);

        expect(engine.disposeCalled, isFalse);

        final rebuiltNotifier = container.read(
          recordingControllerProvider.notifier,
        );
        await rebuiltNotifier.startRecording();

        final rebuiltState = container.read(recordingControllerProvider);
        expect(rebuiltState.status, TrackingSessionStatus.recording);
        expect(rebuiltState.errorMessage, isNull);
        expect(rebuiltState.session?.id, equals(firstSessionId + 1));
        expect(engine.startedSessionId, equals(firstSessionId + 1));
      },
    );

    test('persists processed metrics and queues sync when saving', () async {
      final repository = FakeTrackingRepository();
      final syncService = FakeSyncService();
      final engine = FakeTrackingEngine();
      final permissions = FakePermissionService(
        const [
          TrackingPermissionDecision.granted,
          TrackingPermissionDecision.granted,
        ],
      );
      final container = createManagedControllerContainer(
        repository: repository,
        engine: engine,
        permissions: permissions,
        syncService: syncService,
      );
      final notifier = container.read(recordingControllerProvider.notifier);

      await notifier.startRecording();
      final sessionId = container.read(recordingControllerProvider).session!.id;
      final start = DateTime(2025, 1, 1, 12);
      final stop = DateTime(2025, 1, 1, 12, 0, 10);
      engine
        ..emitSample(
          TrackingPoint(
            sessionId: sessionId,
            timestamp: start,
            coordinate: const GeoCoordinate(latitude: 0, longitude: 0),
          ),
        )
        ..emitSample(
          TrackingPoint(
            sessionId: sessionId,
            timestamp: stop,
            coordinate: const GeoCoordinate(latitude: 0, longitude: 0.0005),
          ),
        );
      await Future<void>.delayed(Duration.zero);

      await notifier.stopRecording();
      final savedSessionId = await notifier.saveRecording();
      expect(savedSessionId, sessionId);

      final savedSession = repository.sessionsById[savedSessionId];
      expect(savedSession?.movingTimeSeconds, equals(10));
      expect(savedSession?.elevationGainMeters, closeTo(0, 0.1));
      expect(
        savedSession?.distanceMeters,
        closeTo(
          calculateTrackDistanceMeters(
            [
              TrackingPoint(
                sessionId: sessionId,
                timestamp: start,
                coordinate: const GeoCoordinate(latitude: 0, longitude: 0),
              ),
              TrackingPoint(
                sessionId: sessionId,
                timestamp: stop,
                coordinate: const GeoCoordinate(
                  latitude: 0,
                  longitude: 0.0005,
                ),
              ),
            ],
          ),
          0.5,
        ),
      );
      expect(syncService.queuedSessionIds, equals([sessionId]));
    });

    test('discards after stop', () async {
      final repository = FakeTrackingRepository();
      final engine = FakeTrackingEngine();
      final permissions = FakePermissionService(
        const [
          TrackingPermissionDecision.granted,
          TrackingPermissionDecision.granted,
        ],
      );
      final container = createManagedControllerContainer(
        repository: repository,
        engine: engine,
        permissions: permissions,
      );
      final notifier = container.read(recordingControllerProvider.notifier);

      await notifier.startRecording();
      await notifier.stopRecording();
      await notifier.discardRecording();

      final state = container.read(recordingControllerProvider);
      expect(state.status, TrackingSessionStatus.idle);
      expect(repository.activeSession?.status, TrackingSessionStatus.discarded);
    });

    test(
      'starting again after discard creates a fresh recording session',
      () async {
        final repository = FakeTrackingRepository();
        final engine = FakeTrackingEngine();
        final permissions = FakePermissionService(
          const [
            TrackingPermissionDecision.granted,
            TrackingPermissionDecision.granted,
            TrackingPermissionDecision.granted,
            TrackingPermissionDecision.granted,
          ],
        );
        final container = createManagedControllerContainer(
          repository: repository,
          engine: engine,
          permissions: permissions,
        );
        final notifier = container.read(recordingControllerProvider.notifier);

        await notifier.startRecording();
        final firstSessionId = notifier.state.session!.id;
        engine.emitSample(
          TrackingPoint(
            sessionId: firstSessionId,
            timestamp: DateTime(2025, 1, 1, 12, 0, 1),
            coordinate: const GeoCoordinate(latitude: 1, longitude: 2),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        await notifier.stopRecording();
        await notifier.discardRecording();
        await notifier.startRecording();

        final restartedState = notifier.state;
        final secondSessionId = restartedState.session!.id;
        expect(secondSessionId, isNot(firstSessionId));
        expect(restartedState.points, isEmpty);
        expect(restartedState.status, TrackingSessionStatus.recording);
      },
    );

    test(
      'returns to idle and discards session when engine start fails',
      () async {
        final repository = FakeTrackingRepository();
        final engine = FakeTrackingEngine(throwOnStart: true);
        final permissions = FakePermissionService(
          const [
            TrackingPermissionDecision.granted,
            TrackingPermissionDecision.granted,
          ],
        );
        final container = createManagedControllerContainer(
          repository: repository,
          engine: engine,
          permissions: permissions,
        );
        final notifier = container.read(recordingControllerProvider.notifier);

        await notifier.startRecording();

        final state = container.read(recordingControllerProvider);
        expect(state.status, TrackingSessionStatus.idle);
        expect(
          state.errorMessage,
          contains(
            'Unable to start recording: Bad state: Failed to start tracking engine.',
          ),
        );
        expect(
          repository.activeSession?.status,
          TrackingSessionStatus.discarded,
        );
      },
    );

    test(
      'keeps idle recovery when rollback discard fails after engine start error',
      () async {
        final repository = FakeTrackingRepository(throwOnDiscard: true);
        final engine = FakeTrackingEngine(throwOnStart: true);
        final permissions = FakePermissionService(
          const [
            TrackingPermissionDecision.granted,
            TrackingPermissionDecision.granted,
          ],
        );
        final container = createManagedControllerContainer(
          repository: repository,
          engine: engine,
          permissions: permissions,
        );
        final notifier = container.read(recordingControllerProvider.notifier);

        await expectLater(notifier.startRecording(), completes);

        final state = container.read(recordingControllerProvider);
        expect(state.status, TrackingSessionStatus.idle);
        expect(
          state.errorMessage,
          contains(
            'Unable to start recording: Bad state: Failed to start tracking engine.',
          ),
        );
      },
    );

    test(
      'replays persisted engine samples when restoring an active session',
      () async {
        final sessionStart = DateTime(2025, 1, 1, 12);
        final repository = FakeTrackingRepository()
          ..activeSession = TrackingSessionRecord(
            id: 11,
            status: TrackingSessionStatus.recording,
            createdAt: sessionStart,
            updatedAt: sessionStart,
            startedAt: sessionStart,
          )
          ..points.add(
            TrackingPoint(
              sessionId: 11,
              timestamp: DateTime(2025, 1, 1, 12, 0, 1),
              coordinate: const GeoCoordinate(latitude: 40, longitude: -73),
            ),
          );
        final engine = FakeTrackingEngine(
          recoveredSamples: [
            TrackingPoint(
              sessionId: 11,
              timestamp: DateTime(2025, 1, 1, 12, 0, 2),
              coordinate: const GeoCoordinate(latitude: 40.1, longitude: -73.1),
            ),
            TrackingPoint(
              sessionId: 11,
              timestamp: DateTime(2025, 1, 1, 12, 0, 3),
              coordinate: const GeoCoordinate(latitude: 40.2, longitude: -73.2),
            ),
          ],
        );
        final container = createManagedControllerContainer(
          repository: repository,
          engine: engine,
          permissions: FakePermissionService(const []),
        );

        final notifier = container.read(recordingControllerProvider.notifier);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final restoredState = notifier.state;
        expect(restoredState.status, TrackingSessionStatus.recording);
        expect(restoredState.pointCount, 3);
        expect(repository.points, hasLength(3));
        expect(engine.recoveredSessionId, 11);

        engine.emitSample(
          TrackingPoint(
            sessionId: 11,
            timestamp: DateTime(2025, 1, 1, 12, 0, 4),
            coordinate: const GeoCoordinate(latitude: 40.3, longitude: -73.3),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(notifier.state.pointCount, 4);
      },
    );

    test(
      'captures live samples emitted while restore recovery is in progress',
      () async {
        final sessionStart = DateTime(2025, 1, 1, 12);
        final repository = FakeTrackingRepository()
          ..activeSession = TrackingSessionRecord(
            id: 17,
            status: TrackingSessionStatus.recording,
            createdAt: sessionStart,
            updatedAt: sessionStart,
            startedAt: sessionStart,
          )
          ..points.add(
            TrackingPoint(
              sessionId: 17,
              timestamp: DateTime(2025, 1, 1, 12, 0, 1),
              coordinate: const GeoCoordinate(latitude: 10, longitude: 10),
            ),
          );
        final engine = FakeTrackingEngine(
          sampleDuringRecovery: TrackingPoint(
            sessionId: 17,
            timestamp: DateTime(2025, 1, 1, 12, 0, 2),
            coordinate: const GeoCoordinate(latitude: 10.1, longitude: 10.1),
          ),
        );
        final container = createManagedControllerContainer(
          repository: repository,
          engine: engine,
          permissions: FakePermissionService(const []),
        );

        final notifier = container.read(recordingControllerProvider.notifier);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final restoredState = notifier.state;
        expect(restoredState.pointCount, 2);
        expect(repository.points, hasLength(2));
        expect(
          restoredState.lastFixTimestamp,
          DateTime(2025, 1, 1, 12, 0, 2),
        );
      },
    );

    test(
      'restore computes lastAccuracy and gpsSignalQuality from latest point',
      () async {
        final sessionStart = DateTime(2025, 1, 1, 12);
        final repository = FakeTrackingRepository()
          ..activeSession = TrackingSessionRecord(
            id: 42,
            status: TrackingSessionStatus.recording,
            createdAt: sessionStart,
            updatedAt: sessionStart,
            startedAt: sessionStart,
          )
          ..points.addAll([
            TrackingPoint(
              sessionId: 42,
              timestamp: DateTime(2025, 1, 1, 12, 0, 1),
              coordinate: const GeoCoordinate(latitude: 40, longitude: -73),
              accuracy: 50.0,
            ),
            TrackingPoint(
              sessionId: 42,
              timestamp: DateTime(2025, 1, 1, 12, 0, 2),
              coordinate: const GeoCoordinate(latitude: 40.1, longitude: -73.1),
              accuracy: 5.0,
            ),
          ]);
        final container = createManagedControllerContainer(
          repository: repository,
          engine: FakeTrackingEngine(),
          permissions: FakePermissionService(const []),
        );

        container.read(recordingControllerProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        final state = container.read(recordingControllerProvider);
        expect(state.timeline.lastAccuracy, 5.0);
        expect(state.gpsSignalQuality, GpsSignalQuality.green);
      },
    );

    test(
      'keeps persisted status stopped when save finalization fails',
      () async {
        final repository = FakeTrackingRepository(throwOnFinalize: true);
        final engine = FakeTrackingEngine();
        final permissions = FakePermissionService(
          const [
            TrackingPermissionDecision.granted,
            TrackingPermissionDecision.granted,
          ],
        );
        final container = createManagedControllerContainer(
          repository: repository,
          engine: engine,
          permissions: permissions,
        );
        final notifier = container.read(recordingControllerProvider.notifier);

        await notifier.startRecording();
        await notifier.stopRecording();
        await notifier.saveRecording();

        final state = container.read(recordingControllerProvider);
        expect(state.status, TrackingSessionStatus.stopped);
        expect(
          state.errorMessage,
          contains('Unable to save recording: Bad state: Failed to finalize'),
        );
        expect(repository.activeSession?.status, TrackingSessionStatus.stopped);
        expect(
          repository.sessionStatusUpdates,
          isNot(contains(TrackingSessionStatus.saving)),
        );
      },
    );

    test(
      'persists stopped session elapsed time when a stationary recording has no usable points',
      () async {
        final repository = FakeTrackingRepository();
        final engine = FakeTrackingEngine();
        final permissions = FakePermissionService(
          const [
            TrackingPermissionDecision.granted,
            TrackingPermissionDecision.granted,
          ],
        );
        final container = createManagedControllerContainer(
          repository: repository,
          engine: engine,
          permissions: permissions,
        );
        final notifier = container.read(recordingControllerProvider.notifier);

        await notifier.startRecording();
        final sessionId = container
            .read(recordingControllerProvider)
            .session!
            .id;
        final startedAt = DateTime(2025, 1, 1, 12);
        final stoppedAt = startedAt.add(const Duration(minutes: 10));
        repository.sessionsById[sessionId] = repository.sessionsById[sessionId]!
            .copyWith(
              status: TrackingSessionStatus.stopped,
              startedAt: startedAt,
              stoppedAt: stoppedAt,
              updatedAt: stoppedAt,
            );
        repository.activeSession = repository.sessionsById[sessionId];
        notifier.state = notifier.state.copyWith(
          status: TrackingSessionStatus.stopped,
          session: repository.sessionsById[sessionId],
          timeline: const RecordingTimeline(
            activeDuration: Duration(minutes: 10),
          ),
        );

        final savedSessionId = await notifier.saveRecording();

        expect(savedSessionId, sessionId);
        final savedSession = repository.sessionsById[savedSessionId];
        expect(savedSession?.movingTimeSeconds, 600);
      },
    );

    test('surfaces persistence error when point append fails', () async {
      final repository = FakeTrackingRepository(throwOnAppendPoints: true);
      final engine = FakeTrackingEngine();
      final permissions = FakePermissionService(
        const [
          TrackingPermissionDecision.granted,
          TrackingPermissionDecision.granted,
        ],
      );
      final container = createManagedControllerContainer(
        repository: repository,
        engine: engine,
        permissions: permissions,
      );
      final notifier = container.read(recordingControllerProvider.notifier);

      await notifier.startRecording();
      final sessionId = container.read(recordingControllerProvider).session!.id;

      engine.emitSample(
        TrackingPoint(
          sessionId: sessionId,
          timestamp: DateTime(2025, 1, 1, 12, 0, 1),
          coordinate: const GeoCoordinate(latitude: 1, longitude: 2),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final state = container.read(recordingControllerProvider);
      expect(state.pointCount, 1);
      expect(state.errorMessage, contains('Unable to persist tracking point'));
    });
  });
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_controller.dart';
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_routes.dart';
import 'package:uff/src/features/activity_tracking/presentation/recording_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';
import 'package:uff/src/features/maps/presentation/map_view.dart';
import 'package:uff/src/features/photos/application/pending_photo_providers.dart';
import 'package:uff/src/features/photos/application/pending_photo_service.dart';
import 'package:uff/src/features/photos/data/photo_picker_service.dart';
import 'package:uff/src/features/photos/domain/pending_photo.dart';

import '../../../test_helpers/mapbox_platform_channel_stub.dart';

/// ## Test Scenarios
/// - `[positive]` Idle, recording, and paused states expose the exact enabled
///   and disabled action controls from the recording-action availability rules.
/// - `[negative]` Recording state does not expose a stop action alongside the
///   primary pause control.
/// - `[isolation]` A new recording session rebuilds the map view so the old
///   route cannot leak into the next run.
/// - `[statemachine]` Compass tap locks north-up while a second tap unlocks
///   heading-follow rotation again.
/// - `[statemachine]` Camera-mode button is a persistent toggle that alternates
///   between perspective-heading mode and top-down north-up mode.
/// - `[positive]` Finish and stopped-review actions both route the user into
///   draft review on the activity detail screen instead of saving on-map.
/// - `[positive]` Photo capture button is visible during recording and paused
///   states, hidden in idle and stopped states.
/// - `[edge]` Photo capture stays hidden while the pending camera service is
///   still loading, avoiding a dead tappable affordance.
/// - `[positive]` Photo capture forwards the latest tracked coordinate in
///   active and paused states.
/// - `[edge]` Photo capture forwards null coordinates when no points exist.
/// - `[positive]` Metrics and status label typography use fixed bold values
///   for readability (`48sp` metrics, `24sp` status).
/// - `[positive]` Start remains disabled for red GPS quality, and signal
///   status is visible via an explicit red/amber/green indicator dot.
/// - `[positive]` Dedicated re-center does not change north-lock mode and
///   triggers a map camera fly-to request.
class IdleRecordingController extends RecordingController {
  @override
  RecordingControllerState build() {
    return const RecordingControllerState.idle();
  }
}

class PausedRecordingController extends RecordingController {
  @override
  RecordingControllerState build() {
    return const RecordingControllerState(
      status: TrackingSessionStatus.paused,
      points: [],
      timeline: RecordingTimeline.idle(),
    );
  }
}

class RecordingActiveController extends RecordingController {
  @override
  RecordingControllerState build() {
    return const RecordingControllerState(
      status: TrackingSessionStatus.recording,
      points: [],
      timeline: RecordingTimeline.idle(),
    );
  }
}

class MutableRecordingController extends RecordingController {
  MutableRecordingController(this._state);

  RecordingControllerState _state;

  @override
  RecordingControllerState build() => _state;

  void setStateForTest(RecordingControllerState nextState) {
    _state = nextState;
    state = nextState;
  }
}

class FinishReviewRecordingController extends RecordingController {
  FinishReviewRecordingController({
    required this.pausedState,
    required this.stoppedState,
  });

  final RecordingControllerState pausedState;
  final RecordingControllerState stoppedState;

  @override
  RecordingControllerState build() => pausedState;

  @override
  Future<void> finishRecording() async {
    state = stoppedState;
  }
}

class _NoopTrackingDatabase implements TrackingDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('noop test stub');
  }
}

class RecordingCaptureSpyPendingPhotoService extends PendingPhotoService {
  RecordingCaptureSpyPendingPhotoService()
    : super(
        db: _NoopTrackingDatabase(),
        photoPickerService: const PhotoPickerService(),
        compressPhoto: _identityCompressor,
        pendingPhotosDirectory: Directory.systemTemp,
        uuidGenerator: () => 'test-photo-uuid',
      );

  int captureCallCount = 0;
  int? capturedSessionId;
  double? capturedLatitude;
  double? capturedLongitude;

  static Future<Uint8List> _identityCompressor(Uint8List bytes) async => bytes;

  @override
  Future<PendingPhoto?> capturePhoto(
    int sessionId, {
    double? latitude,
    double? longitude,
  }) async {
    captureCallCount += 1;
    capturedSessionId = sessionId;
    capturedLatitude = latitude;
    capturedLongitude = longitude;
    return null;
  }
}

final _cameraAnimationRecorder = MapCameraAnimationRecorder();

void main() {
  setUpMapboxPlatformChannelStub(
    mapCameraAnimationRecorder: _cameraAnimationRecorder,
  );
  setUp(_cameraAnimationRecorder.reset);

  Future<void> pumpScreen(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(child);
    await tester.pumpAndSettle();
  }

  /// Builds a ready-to-use pending photo service so the capture button can
  /// be shown in tests without relying on the async app bootstrap path.
  Future<PendingPhotoService> buildReadyPendingPhotoService() async {
    final db = _NoopTrackingDatabase();

    Future<Uint8List> identityCompressor(Uint8List bytes) async => bytes;

    return PendingPhotoService(
      db: db,
      photoPickerService: const PhotoPickerService(),
      compressPhoto: identityCompressor,
      pendingPhotosDirectory: Directory.systemTemp,
      uuidGenerator: () => 'test-photo-uuid',
    );
  }

  RecordingControllerState captureReadyControllerState({
    required TrackingSessionStatus status,
    required List<TrackingPoint> points,
  }) {
    return RecordingControllerState(
      status: status,
      session: TrackingSessionRecord(
        id: 777,
        status: status,
        createdAt: DateTime(2026, 3, 30, 11),
        updatedAt: DateTime(2026, 3, 30, 11),
      ),
      points: points,
      timeline: const RecordingTimeline.idle(),
    );
  }

  RecordingControllerState idleControllerStateWithOptionalFix({
    DateTime? lastFixTimestamp,
    double? lastAccuracy,
  }) {
    return RecordingControllerState(
      status: TrackingSessionStatus.idle,
      points: const [],
      timeline: RecordingTimeline(
        activeDuration: Duration.zero,
        lastFixTimestamp: lastFixTimestamp,
        lastAccuracy: lastAccuracy,
      ),
    );
  }

  /// Verifies that only the expected buttons are visible (present in the
  /// widget tree) and that hidden buttons are absent. After the state-aware
  /// button UX refactor, only the buttons relevant to the current recording
  /// state are rendered — no disabled grey buttons cluttering the UI.
  void expectVisibleButtons(WidgetTester tester, {required Set<Key> visible}) {
    final allButtonKeys = {
      RecordingScreen.startButtonKey,
      RecordingScreen.pauseButtonKey,
      RecordingScreen.resumeButtonKey,
      RecordingScreen.stopButtonKey,
      RecordingScreen.finishButtonKey,
      RecordingScreen.reviewButtonKey,
      RecordingScreen.saveButtonKey,
      RecordingScreen.discardButtonKey,
    };
    for (final key in allButtonKeys) {
      if (visible.contains(key)) {
        expect(
          find.byKey(key),
          findsOneWidget,
          reason: 'Expected button $key to be visible',
        );
      } else {
        expect(
          find.byKey(key),
          findsNothing,
          reason: 'Expected button $key to be hidden',
        );
      }
    }
  }

  MapView currentMapView(WidgetTester tester) {
    return tester.widget<MapView>(find.byType(MapView));
  }

  MapWidget currentMapWidget(WidgetTester tester) {
    return tester.widget<MapWidget>(find.byType(MapWidget));
  }

  testWidgets('idle state enables only the start action', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpScreen(
        tester,
        ProviderScope(
          overrides: [
            recordingControllerProvider.overrideWith(
              IdleRecordingController.new,
            ),
          ],
          child: const MaterialApp(home: RecordingScreen()),
        ),
      );

      expect(find.byKey(RecordingScreen.distanceTextKey), findsOneWidget);
      expect(find.byKey(RecordingScreen.elapsedTextKey), findsOneWidget);

      // In idle state, only the Start button is visible.
      expectVisibleButtons(tester, visible: {RecordingScreen.startButtonKey});

      expect(find.bySemanticsLabel('Start'), findsAtLeastNWidgets(1));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('metrics use fixed 48sp bold typography', (tester) async {
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(IdleRecordingController.new),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );

    final distanceText = tester.widget<Text>(
      find.byKey(RecordingScreen.distanceTextKey),
    );
    final elapsedText = tester.widget<Text>(
      find.byKey(RecordingScreen.elapsedTextKey),
    );
    expect(distanceText.style?.fontSize, 48);
    expect(distanceText.style?.fontWeight, FontWeight.bold);
    expect(elapsedText.style?.fontSize, 48);
    expect(elapsedText.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('status label uses fixed 24sp bold typography', (tester) async {
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(IdleRecordingController.new),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );

    final statusText = tester.widget<Text>(find.text('Ready'));
    expect(statusText.style?.fontSize, 24);
    expect(statusText.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('action buttons enforce 56dp minimum height', (tester) async {
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(IdleRecordingController.new),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );

    final startButton = tester.widget<ElevatedButton>(
      find.byKey(RecordingScreen.startButtonKey),
    );
    final minimumSize = startButton.style?.minimumSize?.resolve({});
    expect(minimumSize?.height, 56);
  });

  testWidgets('non-debug overlay does not render raw Last fix timestamp', (
    tester,
  ) async {
    final controller = MutableRecordingController(
      idleControllerStateWithOptionalFix(
        lastFixTimestamp: DateTime(2026, 4, 18, 10, 30),
      ),
    );
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [recordingControllerProvider.overrideWith(() => controller)],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );

    expect(find.textContaining('Last fix:'), findsNothing);
  });

  testWidgets('start is disabled without GPS fix', (tester) async {
    final noFixController = MutableRecordingController(
      idleControllerStateWithOptionalFix(),
    );
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(() => noFixController),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );
    final startWithoutFix = tester.widget<ElevatedButton>(
      find.byKey(RecordingScreen.startButtonKey),
    );
    expect(startWithoutFix.onPressed, isNull);
  });

  testWidgets('start is enabled when GPS quality is green', (tester) async {
    final fixController = MutableRecordingController(
      idleControllerStateWithOptionalFix(
        lastFixTimestamp: DateTime(2026, 4, 18, 10, 30),
        lastAccuracy: 5.0,
      ),
    );
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(() => fixController),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );
    final startWithFix = tester.widget<ElevatedButton>(
      find.byKey(RecordingScreen.startButtonKey),
    );
    expect(startWithFix.onPressed == null, isFalse);
  });

  testWidgets('GPS indicator dot is red without fix', (tester) async {
    final noFixController = MutableRecordingController(
      idleControllerStateWithOptionalFix(),
    );
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(() => noFixController),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );
    final noFixDot = tester.widget<Container>(
      find.byKey(RecordingScreen.gpsSignalDotKey),
    );
    final noFixDecoration = noFixDot.decoration as BoxDecoration?;
    expect(noFixDecoration?.color, Colors.redAccent);
  });

  testWidgets('GPS indicator dot is green with good GPS accuracy', (
    tester,
  ) async {
    final fixController = MutableRecordingController(
      idleControllerStateWithOptionalFix(
        lastFixTimestamp: DateTime(2026, 4, 18, 10, 30),
        lastAccuracy: 5.0,
      ),
    );
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(() => fixController),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );
    final fixDot = tester.widget<Container>(
      find.byKey(RecordingScreen.gpsSignalDotKey),
    );
    final fixDecoration = fixDot.decoration as BoxDecoration?;
    expect(fixDecoration?.color, Colors.greenAccent);
  });

  testWidgets(
    'north-lock persists across pause/resume state changes and remount',
    (tester) async {
      final controller = MutableRecordingController(
        RecordingControllerState(
          status: TrackingSessionStatus.recording,
          session: TrackingSessionRecord(
            id: 311,
            status: TrackingSessionStatus.recording,
            createdAt: DateTime(2026, 4, 18, 10),
            updatedAt: DateTime(2026, 4, 18, 10),
          ),
          points: const [],
          timeline: const RecordingTimeline.idle(),
        ),
      );
      final container = ProviderContainer(
        overrides: [recordingControllerProvider.overrideWith(() => controller)],
      );
      addTearDown(container.dispose);

      await pumpScreen(
        tester,
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: KeyedSubtree(
              key: ValueKey<String>('recording-screen-initial'),
              child: RecordingScreen(),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(RecordingScreen.compassButtonKey));
      await tester.pumpAndSettle();
      expect(find.text('North locked'), findsOneWidget);

      controller.setStateForTest(
        controller.state.copyWith(status: TrackingSessionStatus.paused),
      );
      await tester.pumpAndSettle();
      controller.setStateForTest(
        controller.state.copyWith(status: TrackingSessionStatus.recording),
      );
      await tester.pumpAndSettle();

      await pumpScreen(
        tester,
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: KeyedSubtree(
              key: ValueKey<String>('recording-screen-remount'),
              child: RecordingScreen(),
            ),
          ),
        ),
      );

      expect(find.text('North locked'), findsOneWidget);
    },
  );

  testWidgets(
    're-center button triggers map flyTo without changing north-lock mode',
    (tester) async {
      final controller = MutableRecordingController(
        RecordingControllerState(
          status: TrackingSessionStatus.recording,
          session: TrackingSessionRecord(
            id: 312,
            status: TrackingSessionStatus.recording,
            createdAt: DateTime(2026, 4, 18, 10),
            updatedAt: DateTime(2026, 4, 18, 10),
          ),
          points: [
            TrackingPoint(
              sessionId: 312,
              timestamp: DateTime(2026, 4, 18, 10, 5),
              coordinate: const GeoCoordinate(
                latitude: 40.7128,
                longitude: -74.006,
              ),
            ),
          ],
          timeline: const RecordingTimeline.idle(),
        ),
      );

      await pumpScreen(
        tester,
        ProviderScope(
          overrides: [
            recordingControllerProvider.overrideWith(() => controller),
          ],
          child: const MaterialApp(home: RecordingScreen()),
        ),
      );

      await tester.tap(find.byKey(RecordingScreen.compassButtonKey));
      await tester.pumpAndSettle();
      expect(find.text('North locked'), findsOneWidget);
      expect(_cameraAnimationRecorder.flyToCount, 0);

      await tester.tap(find.byKey(RecordingScreen.reCenterButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('North locked'), findsOneWidget);
      expect(_cameraAnimationRecorder.flyToCount, 1);
      expect(_cameraAnimationRecorder.lastFlyToCenter?.latitude, 40.7128);
      expect(_cameraAnimationRecorder.lastFlyToCenter?.longitude, -74.006);
    },
  );

  testWidgets('paused state enables resume and finish actions only', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(
            PausedRecordingController.new,
          ),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );

    // In paused state, Resume and Finish are visible.
    expectVisibleButtons(
      tester,
      visible: {
        RecordingScreen.resumeButtonKey,
        RecordingScreen.finishButtonKey,
      },
    );
  });

  testWidgets('recording state shows pause action only', (tester) async {
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(
            RecordingActiveController.new,
          ),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );

    // In recording state, Pause is visible and Finish stays hidden.
    expectVisibleButtons(tester, visible: {RecordingScreen.pauseButtonKey});
  });

  testWidgets('compass tap locks north-up and shows the locked state', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(IdleRecordingController.new),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );

    final cameraModeButton = tester.widget<IconButton>(
      find.byKey(RecordingScreen.cameraModeButtonKey),
    );
    final initialMapView = currentMapView(tester);

    expect(find.text('Free rotate'), findsOneWidget);
    expect(cameraModeButton.tooltip, 'Switch to top-down view');
    expect(
      initialMapView.userLocationCameraMode,
      MapViewUserLocationCameraMode.perspective,
    );
    expect(initialMapView.followUserHeading, isTrue);

    await tester.tap(find.byKey(RecordingScreen.compassButtonKey));
    await tester.pumpAndSettle();
    final afterCompassTapMapView = currentMapView(tester);
    final afterCompassTapCameraModeButton = tester.widget<IconButton>(
      find.byKey(RecordingScreen.cameraModeButtonKey),
    );
    expect(
      afterCompassTapMapView.userLocationCameraMode,
      MapViewUserLocationCameraMode.perspective,
    );
    expect(afterCompassTapMapView.followUserHeading, isFalse);
    expect(afterCompassTapCameraModeButton.tooltip, 'Switch to top-down view');
    expect(find.text('North locked'), findsOneWidget);
  });

  testWidgets(
    'camera mode button toggles between top-down/north-up and perspective/heading-follow',
    (tester) async {
      await pumpScreen(
        tester,
        ProviderScope(
          overrides: [
            recordingControllerProvider.overrideWith(
              IdleRecordingController.new,
            ),
          ],
          child: const MaterialApp(home: RecordingScreen()),
        ),
      );

      await tester.tap(find.byKey(RecordingScreen.cameraModeButtonKey));
      await tester.pumpAndSettle();
      final afterFirstCameraToggle = currentMapView(tester);
      final firstToggleButton = tester.widget<IconButton>(
        find.byKey(RecordingScreen.cameraModeButtonKey),
      );
      expect(
        afterFirstCameraToggle.userLocationCameraMode,
        MapViewUserLocationCameraMode.topDown,
      );
      expect(afterFirstCameraToggle.followUserHeading, isFalse);
      expect(firstToggleButton.tooltip, 'Switch to perspective view');

      await tester.tap(find.byKey(RecordingScreen.cameraModeButtonKey));
      await tester.pumpAndSettle();
      final afterSecondCameraToggle = currentMapView(tester);
      final secondToggleButton = tester.widget<IconButton>(
        find.byKey(RecordingScreen.cameraModeButtonKey),
      );
      expect(
        afterSecondCameraToggle.userLocationCameraMode,
        MapViewUserLocationCameraMode.perspective,
      );
      expect(afterSecondCameraToggle.followUserHeading, isTrue);
      expect(secondToggleButton.tooltip, 'Switch to top-down view');
    },
  );

  testWidgets('second compass tap unlocks heading-follow rotation again', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(IdleRecordingController.new),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );

    final compassButtonFinder = find.byKey(RecordingScreen.compassButtonKey);

    await tester.tap(compassButtonFinder);
    await tester.pumpAndSettle();
    final afterFirstCompassTap = currentMapView(tester);
    expect(
      afterFirstCompassTap.userLocationCameraMode,
      MapViewUserLocationCameraMode.perspective,
    );
    expect(afterFirstCompassTap.followUserHeading, isFalse);
    final firstNorthUpViewport =
        currentMapWidget(tester).viewport as FollowPuckViewportState?;
    expect(firstNorthUpViewport?.pitch, 45);
    final firstBearing =
        firstNorthUpViewport?.bearing
            as FollowPuckViewportStateBearingConstant?;
    expect(firstBearing?.bearing, 0);

    await tester.tap(compassButtonFinder);
    await tester.pumpAndSettle();
    final afterSecondCompassTap = currentMapView(tester);
    expect(
      afterSecondCompassTap.userLocationCameraMode,
      MapViewUserLocationCameraMode.perspective,
    );
    expect(afterSecondCompassTap.followUserHeading, isTrue);
    expect(find.text('Free rotate'), findsOneWidget);
    final secondCompassViewport =
        currentMapWidget(tester).viewport as FollowPuckViewportState?;
    expect(
      secondCompassViewport?.bearing.runtimeType,
      FollowPuckViewportStateBearingHeading,
    );
  });

  testWidgets('stopped review state routes to detail without saving on-map', (
    tester,
  ) async {
    final routePoints = [
      TrackingPoint(
        sessionId: 23,
        timestamp: DateTime(2025, 1, 10, 7, 30),
        coordinate: const GeoCoordinate(latitude: 0, longitude: 0),
      ),
      TrackingPoint(
        sessionId: 23,
        timestamp: DateTime(2025, 1, 10, 7, 45),
        coordinate: const GeoCoordinate(latitude: 0, longitude: 0.01),
      ),
    ];
    const elapsed = Duration(minutes: 15);
    final controllerState = RecordingControllerState(
      status: TrackingSessionStatus.stopped,
      session: TrackingSessionRecord(
        id: 23,
        status: TrackingSessionStatus.stopped,
        createdAt: DateTime(2025, 1, 10, 7, 30),
        updatedAt: DateTime(2025, 1, 10, 7, 45),
        startedAt: DateTime(2025, 1, 10, 7, 30),
        stoppedAt: DateTime(2025, 1, 10, 7, 45),
      ),
      points: routePoints,
      timeline: const RecordingTimeline(activeDuration: elapsed),
    );
    final expectedDistance = formatDistanceKilometers(
      calculateTrackDistanceMeters(routePoints),
    );
    final router = GoRouter(
      initialLocation: '/record',
      routes: [
        GoRoute(path: '/record', builder: (_, __) => const RecordingScreen()),
        GoRoute(
          path: ActivityRoutes.activityPathPattern,
          builder: (_, state) =>
              Scaffold(body: Text('Activity ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(
            () => MutableRecordingController(controllerState),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    expect(find.byKey(RecordingScreen.distanceTextKey), findsOneWidget);
    expect(find.text('Distance: $expectedDistance'), findsOneWidget);
    expect(find.byKey(RecordingScreen.elapsedTextKey), findsOneWidget);
    expect(find.text('Elapsed: ${formatDuration(elapsed)}'), findsOneWidget);
    expectVisibleButtons(tester, visible: {RecordingScreen.reviewButtonKey});

    await tester.tap(find.byKey(RecordingScreen.reviewButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Activity 23'), findsOneWidget);
  });

  testWidgets('finish routes directly into draft review on activity detail', (
    tester,
  ) async {
    final pausedState = RecordingControllerState(
      status: TrackingSessionStatus.paused,
      session: TrackingSessionRecord(
        id: 24,
        status: TrackingSessionStatus.paused,
        createdAt: DateTime(2025, 1, 10, 7, 30),
        updatedAt: DateTime(2025, 1, 10, 7, 40),
      ),
      points: const [],
      timeline: const RecordingTimeline(activeDuration: Duration(minutes: 10)),
    );
    final stoppedState = pausedState.copyWith(
      status: TrackingSessionStatus.stopped,
      session: pausedState.session?.copyWith(
        status: TrackingSessionStatus.stopped,
        stoppedAt: DateTime(2025, 1, 10, 7, 40),
        updatedAt: DateTime(2025, 1, 10, 7, 40),
      ),
    );
    final router = GoRouter(
      initialLocation: '/record',
      routes: [
        GoRoute(path: '/record', builder: (_, __) => const RecordingScreen()),
        GoRoute(
          path: ActivityRoutes.activityPathPattern,
          builder: (_, state) =>
              Scaffold(body: Text('Activity ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(
            () => FinishReviewRecordingController(
              pausedState: pausedState,
              stoppedState: stoppedState,
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    expectVisibleButtons(
      tester,
      visible: {
        RecordingScreen.resumeButtonKey,
        RecordingScreen.finishButtonKey,
      },
    );

    await tester.tap(find.byKey(RecordingScreen.finishButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Activity 24'), findsOneWidget);
  });

  testWidgets(
    'photo capture button is hidden after recording stops for review',
    (tester) async {
      final stoppedState = RecordingControllerState(
        status: TrackingSessionStatus.stopped,
        session: TrackingSessionRecord(
          id: 23,
          status: TrackingSessionStatus.stopped,
          createdAt: DateTime(2025, 1, 10, 7, 30),
          updatedAt: DateTime(2025, 1, 10, 7, 45),
        ),
        points: const [],
        timeline: const RecordingTimeline.idle(),
      );
      final readyPendingPhotoService = await buildReadyPendingPhotoService();

      await pumpScreen(
        tester,
        ProviderScope(
          overrides: [
            recordingControllerProvider.overrideWith(
              () => MutableRecordingController(stoppedState),
            ),
            pendingPhotoServiceProvider.overrideWith(
              (ref) async => readyPendingPhotoService,
            ),
          ],
          child: const MaterialApp(home: RecordingScreen()),
        ),
      );

      expect(find.byKey(RecordingScreen.photoCaptureButtonKey), findsNothing);
    },
  );

  testWidgets('photo capture button is hidden in idle state', (tester) async {
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(IdleRecordingController.new),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );
    expect(find.byKey(RecordingScreen.photoCaptureButtonKey), findsNothing);
  });

  testWidgets('photo capture button is visible during active recording', (
    tester,
  ) async {
    final readyPendingPhotoService = await buildReadyPendingPhotoService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(
            RecordingActiveController.new,
          ),
          pendingPhotoServiceProvider.overrideWith(
            (ref) async => readyPendingPhotoService,
          ),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(RecordingScreen.photoCaptureButtonKey), findsOneWidget);
  });

  testWidgets('photo capture button is visible when paused', (tester) async {
    final readyPendingPhotoService = await buildReadyPendingPhotoService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(
            PausedRecordingController.new,
          ),
          pendingPhotoServiceProvider.overrideWith(
            (ref) async => readyPendingPhotoService,
          ),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(RecordingScreen.photoCaptureButtonKey), findsOneWidget);
  });

  testWidgets(
    'photo capture stays hidden while the pending service is loading',
    (tester) async {
      final pendingPhotoServiceCompleter = Completer<PendingPhotoService>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recordingControllerProvider.overrideWith(
              RecordingActiveController.new,
            ),
            pendingPhotoServiceProvider.overrideWith(
              (ref) => pendingPhotoServiceCompleter.future,
            ),
          ],
          child: const MaterialApp(home: RecordingScreen()),
        ),
      );
      await tester.pump();

      expect(find.byKey(RecordingScreen.photoCaptureButtonKey), findsNothing);
    },
  );

  testWidgets(
    'photo capture forwards latest tracked coordinate in active state',
    (tester) async {
      final captureSpyService = RecordingCaptureSpyPendingPhotoService();
      final controller = MutableRecordingController(
        captureReadyControllerState(
          status: TrackingSessionStatus.recording,
          points: [
            TrackingPoint(
              sessionId: 777,
              timestamp: DateTime(2026, 3, 30, 11, 0, 10),
              coordinate: const GeoCoordinate(
                latitude: 40.7128,
                longitude: -74,
              ),
            ),
            TrackingPoint(
              sessionId: 777,
              timestamp: DateTime(2026, 3, 30, 11, 0, 20),
              coordinate: const GeoCoordinate(
                latitude: 40.7131,
                longitude: -73.9995,
              ),
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recordingControllerProvider.overrideWith(() => controller),
            pendingPhotoServiceProvider.overrideWith(
              (ref) async => captureSpyService,
            ),
          ],
          child: const MaterialApp(home: RecordingScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(RecordingScreen.photoCaptureButtonKey));
      await tester.pumpAndSettle();

      expect(captureSpyService.captureCallCount, 1);
      expect(captureSpyService.capturedSessionId, 777);
      expect(captureSpyService.capturedLatitude, 40.7131);
      expect(captureSpyService.capturedLongitude, -73.9995);
    },
  );

  testWidgets(
    'photo capture forwards latest tracked coordinate in paused state',
    (tester) async {
      final captureSpyService = RecordingCaptureSpyPendingPhotoService();
      final controller = MutableRecordingController(
        captureReadyControllerState(
          status: TrackingSessionStatus.paused,
          points: [
            TrackingPoint(
              sessionId: 777,
              timestamp: DateTime(2026, 3, 30, 11, 1, 10),
              coordinate: const GeoCoordinate(latitude: 41.0, longitude: -73.7),
            ),
            TrackingPoint(
              sessionId: 777,
              timestamp: DateTime(2026, 3, 30, 11, 1, 20),
              coordinate: const GeoCoordinate(
                latitude: 41.0002,
                longitude: -73.6998,
              ),
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recordingControllerProvider.overrideWith(() => controller),
            pendingPhotoServiceProvider.overrideWith(
              (ref) async => captureSpyService,
            ),
          ],
          child: const MaterialApp(home: RecordingScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(RecordingScreen.photoCaptureButtonKey));
      await tester.pumpAndSettle();

      expect(captureSpyService.captureCallCount, 1);
      expect(captureSpyService.capturedSessionId, 777);
      expect(captureSpyService.capturedLatitude, 41.0002);
      expect(captureSpyService.capturedLongitude, -73.6998);
    },
  );

  testWidgets('photo capture forwards null coordinates when no points exist', (
    tester,
  ) async {
    final captureSpyService = RecordingCaptureSpyPendingPhotoService();
    final controller = MutableRecordingController(
      captureReadyControllerState(
        status: TrackingSessionStatus.recording,
        points: const [],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(() => controller),
          pendingPhotoServiceProvider.overrideWith(
            (ref) async => captureSpyService,
          ),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(RecordingScreen.photoCaptureButtonKey));
    await tester.pumpAndSettle();

    expect(captureSpyService.captureCallCount, 1);
    expect(captureSpyService.capturedSessionId, 777);
    expect(captureSpyService.capturedLatitude, isNull);
    expect(captureSpyService.capturedLongitude, isNull);
  });

  testWidgets('new session rebuilds the map view with a fresh key', (
    tester,
  ) async {
    final controller = MutableRecordingController(
      RecordingControllerState(
        status: TrackingSessionStatus.stopped,
        session: TrackingSessionRecord(
          id: 77,
          status: TrackingSessionStatus.stopped,
          createdAt: DateTime(2025, 1, 1, 12),
          updatedAt: DateTime(2025, 1, 1, 12, 5),
        ),
        points: [
          TrackingPoint(
            sessionId: 77,
            timestamp: DateTime(2025, 1, 1, 12, 1),
            coordinate: const GeoCoordinate(latitude: 40.0, longitude: -74.0),
          ),
          TrackingPoint(
            sessionId: 77,
            timestamp: DateTime(2025, 1, 1, 12, 2),
            coordinate: const GeoCoordinate(
              latitude: 40.0005,
              longitude: -73.9995,
            ),
          ),
        ],
        timeline: const RecordingTimeline(activeDuration: Duration(minutes: 5)),
      ),
    );

    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [recordingControllerProvider.overrideWith(() => controller)],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );

    expect(currentMapView(tester).key, const ValueKey<Object?>(77));

    controller.setStateForTest(const RecordingControllerState.idle());
    await tester.pumpAndSettle();
    expect(currentMapView(tester).key, const ValueKey<Object?>('idle'));

    controller.setStateForTest(
      RecordingControllerState(
        status: TrackingSessionStatus.recording,
        session: TrackingSessionRecord(
          id: 78,
          status: TrackingSessionStatus.recording,
          createdAt: DateTime(2025, 1, 1, 12, 10),
          updatedAt: DateTime(2025, 1, 1, 12, 10),
        ),
        points: const [],
        timeline: const RecordingTimeline.idle(),
      ),
    );
    await tester.pumpAndSettle();

    expect(currentMapView(tester).key, const ValueKey<Object?>(78));
  });

  testWidgets('status label shows human-friendly text and color per state', (
    tester,
  ) async {
    // Idle state should show "Ready" (not the raw enum name "idle").
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(IdleRecordingController.new),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );
    expect(find.text('Ready'), findsOneWidget);
    // The raw enum name should NOT appear in the UI.
    expect(find.text('Status: idle'), findsNothing);
  });

  testWidgets('recording state shows green "Recording" label', (tester) async {
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(
            RecordingActiveController.new,
          ),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );
    expect(find.text('Recording'), findsOneWidget);

    // Verify the label uses greenAccent color.
    final labelWidget = tester.widget<Text>(find.text('Recording'));
    expect(labelWidget.style?.color, Colors.greenAccent);
  });

  testWidgets('paused state shows amber "Paused" label', (tester) async {
    await pumpScreen(
      tester,
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(
            PausedRecordingController.new,
          ),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );
    expect(find.text('Paused'), findsOneWidget);

    final labelWidget = tester.widget<Text>(find.text('Paused'));
    expect(labelWidget.style?.color, Colors.amberAccent);
  });
}

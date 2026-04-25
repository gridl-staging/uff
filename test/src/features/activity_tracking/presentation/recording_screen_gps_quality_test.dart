import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_controller.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_smoke_overrides.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/recording_screen.dart';

import '../../../test_helpers/mapbox_platform_channel_stub.dart';

/// ## Test Scenarios
/// - [positive] Amber and green accuracy render distinct GPS quality colors.
/// - [edge] Red states (no fix, null accuracy, zero accuracy) disable Start.
/// - [edge] Smoke replay override enables Start before the first live fix.
/// - [negative] Amber quality never renders as green.
/// - [isolation] A fresh idle construction resets GPS quality state.
void main() {
  setUpMapboxPlatformChannelStub();

  Future<void> pumpScreen(
    WidgetTester tester,
    RecordingController controller,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [recordingControllerProvider.overrideWith(() => controller)],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  RecordingControllerState idleControllerStateWithGps({
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

  testWidgets('red state without fix keeps start disabled and dot red', (
    tester,
  ) async {
    final controller = _MutableRecordingController(
      idleControllerStateWithGps(),
    );
    await pumpScreen(tester, controller);

    final startButton = tester.widget<ElevatedButton>(
      find.byKey(RecordingScreen.startButtonKey),
    );
    final dot = tester.widget<Container>(
      find.byKey(RecordingScreen.gpsSignalDotKey),
    );
    final decoration = dot.decoration as BoxDecoration?;

    expect(startButton.onPressed, isNull);
    expect(decoration?.color, Colors.redAccent);
  });

  testWidgets('red state with null accuracy keeps start disabled and dot red', (
    tester,
  ) async {
    final controller = _MutableRecordingController(
      idleControllerStateWithGps(
        lastFixTimestamp: DateTime(2026, 4, 19, 10, 0),
        lastAccuracy: null,
      ),
    );
    await pumpScreen(tester, controller);

    final startButton = tester.widget<ElevatedButton>(
      find.byKey(RecordingScreen.startButtonKey),
    );
    final dot = tester.widget<Container>(
      find.byKey(RecordingScreen.gpsSignalDotKey),
    );
    final decoration = dot.decoration as BoxDecoration?;

    expect(startButton.onPressed, isNull);
    expect(decoration?.color, Colors.redAccent);
  });

  testWidgets('red state with zero accuracy keeps start disabled and dot red', (
    tester,
  ) async {
    final controller = _MutableRecordingController(
      idleControllerStateWithGps(
        lastFixTimestamp: DateTime(2026, 4, 19, 10, 0),
        lastAccuracy: 0.0,
      ),
    );
    await pumpScreen(tester, controller);

    final startButton = tester.widget<ElevatedButton>(
      find.byKey(RecordingScreen.startButtonKey),
    );
    final dot = tester.widget<Container>(
      find.byKey(RecordingScreen.gpsSignalDotKey),
    );
    final decoration = dot.decoration as BoxDecoration?;

    expect(startButton.onPressed, isNull);
    expect(decoration?.color, Colors.redAccent);
  });

  testWidgets('amber state enables start and renders amber dot', (
    tester,
  ) async {
    final controller = _MutableRecordingController(
      idleControllerStateWithGps(
        lastFixTimestamp: DateTime(2026, 4, 19, 10, 0),
        lastAccuracy: 50.0,
      ),
    );
    await pumpScreen(tester, controller);

    final startButton = tester.widget<ElevatedButton>(
      find.byKey(RecordingScreen.startButtonKey),
    );
    final dot = tester.widget<Container>(
      find.byKey(RecordingScreen.gpsSignalDotKey),
    );
    final decoration = dot.decoration as BoxDecoration?;

    expect(startButton.onPressed == null, isFalse);
    expect(decoration?.color, Colors.amberAccent);
  });

  testWidgets('green state enables start and renders green dot', (
    tester,
  ) async {
    final controller = _MutableRecordingController(
      idleControllerStateWithGps(
        lastFixTimestamp: DateTime(2026, 4, 19, 10, 0),
        lastAccuracy: 5.0,
      ),
    );
    await pumpScreen(tester, controller);

    final startButton = tester.widget<ElevatedButton>(
      find.byKey(RecordingScreen.startButtonKey),
    );
    final dot = tester.widget<Container>(
      find.byKey(RecordingScreen.gpsSignalDotKey),
    );
    final decoration = dot.decoration as BoxDecoration?;

    expect(startButton.onPressed == null, isFalse);
    expect(decoration?.color, Colors.greenAccent);
  });

  testWidgets('amber state does not render green dot', (tester) async {
    final controller = _MutableRecordingController(
      idleControllerStateWithGps(
        lastFixTimestamp: DateTime(2026, 4, 19, 10, 0),
        lastAccuracy: 50.0,
      ),
    );
    await pumpScreen(tester, controller);

    final dot = tester.widget<Container>(
      find.byKey(RecordingScreen.gpsSignalDotKey),
    );
    final decoration = dot.decoration as BoxDecoration?;

    expect(decoration?.color, Colors.amberAccent);
    expect(decoration?.color, isNot(Colors.greenAccent));
  });

  testWidgets('smoke replay override enables start without a GPS fix', (
    tester,
  ) async {
    final controller = _MutableRecordingController(
      idleControllerStateWithGps(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(() => controller),
          allowRecordingStartWithoutGpsFixProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final startButton = tester.widget<ElevatedButton>(
      find.byKey(RecordingScreen.startButtonKey),
    );
    expect(startButton.onPressed == null, isFalse);
  });

  testWidgets('new idle state construction resets to red quality', (
    tester,
  ) async {
    final amberState = idleControllerStateWithGps(
      lastFixTimestamp: DateTime(2026, 4, 19, 10, 0),
      lastAccuracy: 50.0,
    );
    final resetState = idleControllerStateWithGps();
    final controller = _MutableRecordingController(resetState);
    await pumpScreen(tester, controller);

    final startButton = tester.widget<ElevatedButton>(
      find.byKey(RecordingScreen.startButtonKey),
    );
    final dot = tester.widget<Container>(
      find.byKey(RecordingScreen.gpsSignalDotKey),
    );
    final decoration = dot.decoration as BoxDecoration?;

    expect(amberState.lastFixTimestamp, DateTime(2026, 4, 19, 10, 0));
    expect(resetState.lastFixTimestamp, isNull);
    expect(startButton.onPressed, isNull);
    expect(decoration?.color, Colors.redAccent);
  });
}

class _MutableRecordingController extends RecordingController {
  _MutableRecordingController(this._state);

  final RecordingControllerState _state;

  @override
  RecordingControllerState build() => _state;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_controller.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

/// ## Test Scenarios
/// - [positive] Accuracy values in the green and amber bands classify exactly.
/// - [edge] Null, non-finite, and non-positive values classify red.
/// - [positive] Controller state quality derives from timeline accuracy.
void main() {
  group('classifyGpsAccuracy', () {
    test('returns red for null, non-finite, and non-positive accuracy', () {
      expect(classifyGpsAccuracy(null), GpsSignalQuality.red);
      expect(classifyGpsAccuracy(double.nan), GpsSignalQuality.red);
      expect(classifyGpsAccuracy(double.infinity), GpsSignalQuality.red);
      expect(
        classifyGpsAccuracy(double.negativeInfinity),
        GpsSignalQuality.red,
      );
      expect(classifyGpsAccuracy(-1.0), GpsSignalQuality.red);
      expect(classifyGpsAccuracy(-0.001), GpsSignalQuality.red);
      expect(classifyGpsAccuracy(0.0), GpsSignalQuality.red);
    });

    test('returns green for contract boundary values in good band', () {
      expect(classifyGpsAccuracy(0.001), GpsSignalQuality.green);
      expect(classifyGpsAccuracy(5.0), GpsSignalQuality.green);
      expect(classifyGpsAccuracy(10.0), GpsSignalQuality.green);
    });

    test('returns amber for contract boundary values above good band', () {
      expect(classifyGpsAccuracy(10.001), GpsSignalQuality.amber);
      expect(classifyGpsAccuracy(50.0), GpsSignalQuality.amber);
      expect(classifyGpsAccuracy(1000.0), GpsSignalQuality.amber);
    });
  });

  group('RecordingControllerState.gpsSignalQuality', () {
    test('derives from timeline lastAccuracy through classifyGpsAccuracy', () {
      final state = RecordingControllerState(
        status: TrackingSessionStatus.idle,
        points: const [],
        timeline: RecordingTimeline(
          activeDuration: Duration.zero,
          lastAccuracy: 50.0,
        ),
      );

      expect(state.gpsSignalQuality, classifyGpsAccuracy(50.0));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_controller.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

void main() {
  group('RecordingControllerState', () {
    test('tracks timing data through a dedicated timeline value object', () {
      final baseTimestamp = DateTime.utc(2025, 1, 1, 12);
      final activeTimeline = RecordingTimeline(
        activeDuration: const Duration(minutes: 5),
        segmentStartTimestamp: baseTimestamp,
        lastFixTimestamp: baseTimestamp.add(const Duration(seconds: 10)),
      );
      final state = RecordingControllerState(
        status: TrackingSessionStatus.recording,
        points: const [],
        timeline: activeTimeline,
      );

      expect(state.activeDuration, const Duration(minutes: 5));
      expect(state.segmentStartTimestamp, baseTimestamp);
      expect(
        state.lastFixTimestamp,
        baseTimestamp.add(const Duration(seconds: 10)),
      );
      expect(state.pointCount, 0);
      expect(
        state.elapsed(now: baseTimestamp.add(const Duration(minutes: 1))),
        const Duration(minutes: 6),
      );
    });

    test('copyWith can update and clear error state without extra flags', () {
      const initialState = RecordingControllerState(
        status: TrackingSessionStatus.idle,
        points: [],
        timeline: RecordingTimeline.idle(),
        errorState: RecordingErrorState(message: 'initial error'),
      );

      final cleared = initialState.copyWith(
        errorState: const RecordingErrorState.none(),
      );

      final replaced = cleared.copyWith(
        errorState: const RecordingErrorState(message: 'next error'),
      );

      expect(initialState.errorMessage, 'initial error');
      expect(cleared.errorMessage, isNull);
      expect(replaced.errorMessage, 'next error');
    });
  });

  group('TrackingPoint', () {
    test('stores a coordinate value object and retains lat/lng accessors', () {
      final point = TrackingPoint(
        sessionId: 10,
        timestamp: DateTime.utc(2025),
        coordinate: const GeoCoordinate(latitude: 12.345, longitude: -67.89),
      );

      expect(point.coordinate.latitude, 12.345);
      expect(point.coordinate.longitude, -67.89);
      expect(point.latitude, 12.345);
      expect(point.longitude, -67.89);
    });
  });
}

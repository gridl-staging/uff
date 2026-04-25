import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/track_metrics.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

const _sessionId = 77;

TrackingPoint _pointAtMeters({
  required int seconds,
  required double metersFromOrigin,
  int? timestampSeconds,
}) {
  const metersPerDegreeAtEquator = earthRadiusMeters * (math.pi / 180);

  return TrackingPoint(
    sessionId: _sessionId,
    timestamp: DateTime.utc(2025).add(
      Duration(seconds: timestampSeconds ?? seconds),
    ),
    coordinate: GeoCoordinate(
      latitude: 0,
      longitude: metersFromOrigin / metersPerDegreeAtEquator,
    ),
  );
}

void main() {
  group('track metrics edge cases', () {
    test(
      'returns zero distance for empty, single-point, and stationary tracks',
      () {
        final emptyDistance = calculateTrackDistanceMeters(const []);
        final singlePointDistance = calculateTrackDistanceMeters([
          _pointAtMeters(seconds: 0, metersFromOrigin: 0),
        ]);
        final stationaryDistance = calculateTrackDistanceMeters([
          _pointAtMeters(seconds: 0, metersFromOrigin: 100),
          _pointAtMeters(seconds: 10, metersFromOrigin: 100),
          _pointAtMeters(seconds: 20, metersFromOrigin: 100),
        ]);

        expect(emptyDistance, 0);
        expect(singlePointDistance, 0);
        expect(stationaryDistance, closeTo(0, 0.001));
      },
    );

    test('returns zero elapsed time when consecutive timestamps are equal', () {
      final elapsed = calculateElapsedTime([
        _pointAtMeters(seconds: 0, metersFromOrigin: 0, timestampSeconds: 0),
        _pointAtMeters(seconds: 1, metersFromOrigin: 10, timestampSeconds: 0),
        _pointAtMeters(seconds: 2, metersFromOrigin: 20, timestampSeconds: 10),
      ]);

      expect(elapsed, Duration.zero);
    });

    test('returns null pace for negative or zero guard-path inputs', () {
      final negativeDistancePace = calculatePaceForUnit(
        distanceMeters: -100,
        elapsedTime: const Duration(seconds: 10),
        splitUnit: SplitUnit.kilometer,
      );
      final negativeElapsedPace = calculatePaceForUnit(
        distanceMeters: 1000,
        elapsedTime: const Duration(seconds: -10),
        splitUnit: SplitUnit.kilometer,
      );
      final zeroedInputsPace = calculatePaceForUnit(
        distanceMeters: 0,
        elapsedTime: Duration.zero,
        splitUnit: SplitUnit.mile,
      );

      expect(negativeDistancePace, isNull);
      expect(negativeElapsedPace, isNull);
      expect(zeroedInputsPace, isNull);
    });

    test(
      'calculates exact pace durations across fast, slow, and floored cases',
      () {
        final veryFastPace = calculatePaceForUnit(
          distanceMeters: 100,
          elapsedTime: const Duration(seconds: 10),
          splitUnit: SplitUnit.kilometer,
        );
        final verySlowPace = calculatePaceForUnit(
          distanceMeters: 1000,
          elapsedTime: const Duration(seconds: 1200),
          splitUnit: SplitUnit.kilometer,
        );
        final flooredPace = calculatePaceForUnit(
          distanceMeters: 300,
          elapsedTime: const Duration(seconds: 92),
          splitUnit: SplitUnit.kilometer,
        );

        expect(veryFastPace, const Duration(minutes: 1, seconds: 40));
        expect(verySlowPace, const Duration(minutes: 20));
        expect(flooredPace, const Duration(minutes: 5, seconds: 6));
      },
    );

    test(
      'uses split unit conversion so mile pace is about 1.609x kilometer pace',
      () {
        final kilometerPace = calculatePaceForUnit(
          distanceMeters: 5000,
          elapsedTime: const Duration(minutes: 25),
          splitUnit: SplitUnit.kilometer,
        );
        final milePace = calculatePaceForUnit(
          distanceMeters: 5000,
          elapsedTime: const Duration(minutes: 25),
          splitUnit: SplitUnit.mile,
        );

        expect(kilometerPace, const Duration(minutes: 5));
        expect(milePace, const Duration(seconds: 482));
        final paceRatio = milePace!.inSeconds / kilometerPace!.inSeconds;
        expect(paceRatio, closeTo(1.609344, 0.01));
      },
    );
  });
}

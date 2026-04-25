import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/analytics/domain/analytics_point.dart';
import 'package:uff/src/features/analytics/domain/power_curve_calculator.dart';
import 'package:uff/src/features/analytics/domain/power_curve_point.dart';

/// Builds one-second-apart points with the given per-segment power values.
List<AnalyticsPoint> _buildPowerPoints({
  required List<int> segmentDurations,
  required List<int?> segmentPowers,
}) {
  assert(
    segmentDurations.length == segmentPowers.length,
    'segmentDurations and segmentPowers must have the same length',
  );

  final start = DateTime.utc(2026, 3, 14);
  final points = <AnalyticsPoint>[];
  var elapsed = 0;

  for (var seg = 0; seg < segmentDurations.length; seg++) {
    final power = segmentPowers[seg];
    for (var s = 0; s < segmentDurations[seg]; s++) {
      points.add(
        AnalyticsPoint(
          timestamp: start.add(Duration(seconds: elapsed)),
          latitude: 0,
          longitude: 0,
          powerWatts: power,
        ),
      );
      elapsed++;
    }
  }

  return points;
}

/// Finds the PowerCurvePoint entry for a given duration in seconds.
double? _avgWattsAt(List<PowerCurvePoint> result, int durationSeconds) {
  for (final point in result) {
    if (point.duration == Duration(seconds: durationSeconds)) {
      return point.avgWatts;
    }
  }
  return null;
}

void main() {
  group('PowerCurveCalculator.calculate()', () {
    group('120-second multi-segment fixture', () {
      // 121 points: [100W×30, 300W×30, 200W×30, 150W×31] → t=0..120
      late final List<PowerCurvePoint> results;

      setUpAll(() {
        final points = _buildPowerPoints(
          segmentDurations: [30, 30, 30, 31],
          segmentPowers: [100, 300, 200, 150],
        );
        // Verify fixture produces 121 points.
        expect(points, hasLength(121));

        results = PowerCurveCalculator.calculate(points: points);
      });

      test('returns entries only for standard durations ≤ 120s', () {
        // Standard durations ≤ 120: 5, 10, 30, 60, 120 → 5 entries.
        expect(results, hasLength(5));
      });

      test('sorted by ascending duration', () {
        for (var i = 1; i < results.length; i++) {
          expect(results[i].duration, greaterThan(results[i - 1].duration));
        }
      });

      test('best 5s is 300W', () {
        expect(_avgWattsAt(results, 5), closeTo(300, 1));
      });

      test('best 10s is 300W', () {
        expect(_avgWattsAt(results, 10), closeTo(300, 1));
      });

      test('best 30s is 300W', () {
        expect(_avgWattsAt(results, 30), closeTo(300, 1));
      });

      test('best 60s is 250W (window [t=30,t=90])', () {
        expect(_avgWattsAt(results, 60), closeTo(250, 1));
      });

      test('best 120s is 187.5W (full recording)', () {
        expect(_avgWattsAt(results, 120), closeTo(187.5, 1));
      });
    });

    group('edge cases', () {
      test('empty points returns empty list', () {
        expect(PowerCurveCalculator.calculate(points: const []), isEmpty);
      });

      test('all-null power returns empty list', () {
        final points = _buildPowerPoints(
          segmentDurations: [60],
          segmentPowers: [null],
        );
        expect(PowerCurveCalculator.calculate(points: points), isEmpty);
      });

      test('recording shorter than 5s returns empty list', () {
        // 3 points → 2 seconds elapsed, shortest standard = 5s.
        final points = _buildPowerPoints(
          segmentDurations: [3],
          segmentPowers: [200],
        );
        expect(PowerCurveCalculator.calculate(points: points), isEmpty);
      });

      test('constant 250W for 10s returns 5s=250 and 10s=250', () {
        // 11 points → 10 seconds elapsed.
        final points = _buildPowerPoints(
          segmentDurations: [11],
          segmentPowers: [250],
        );
        final results = PowerCurveCalculator.calculate(points: points);
        expect(results, hasLength(2));
        expect(_avgWattsAt(results, 5), closeTo(250, 1));
        expect(_avgWattsAt(results, 10), closeTo(250, 1));
      });

      test('single non-null power point returns empty list', () {
        final start = DateTime.utc(2026, 3, 14);
        final points = [
          AnalyticsPoint(
            timestamp: start,
            latitude: 0,
            longitude: 0,
            powerWatts: 200,
          ),
        ];
        expect(PowerCurveCalculator.calculate(points: points), isEmpty);
      });
    });

    group('boundary regression', () {
      test('exactly 5s of constant 200W → single entry at 5s with 200W', () {
        // 6 points → 5 seconds elapsed, exactly matches shortest standard.
        final points = _buildPowerPoints(
          segmentDurations: [6],
          segmentPowers: [200],
        );
        final results = PowerCurveCalculator.calculate(points: points);
        expect(results, hasLength(1));
        expect(results.first.duration, const Duration(seconds: 5));
        expect(results.first.avgWatts, closeTo(200, 1));
      });
    });
  });
}

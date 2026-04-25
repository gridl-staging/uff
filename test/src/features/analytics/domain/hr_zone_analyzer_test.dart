import 'package:test/test.dart';
import 'package:uff/src/features/analytics/domain/analytics_point.dart';
import 'package:uff/src/features/analytics/domain/hr_zone_analyzer.dart';
import 'package:uff/src/features/analytics/domain/hr_zone_calculator.dart';
import 'package:uff/src/features/analytics/domain/sport_type.dart';

/// Builds [count] points at 1-second intervals with the given [heartRateBpm].
List<AnalyticsPoint> _buildUniformHrPoints({
  required int count,
  required int? heartRateBpm,
  DateTime? start,
}) {
  final t0 = start ?? DateTime.utc(2026, 3, 14);
  return List.generate(count, (i) {
    return AnalyticsPoint(
      timestamp: t0.add(Duration(seconds: i)),
      latitude: 0,
      longitude: 0,
      heartRateBpm: heartRateBpm,
    );
  });
}

/// Builds points from a list of (heartRateBpm, durationSeconds) segments.
/// Each segment's HR is placed on the leading point (the point at the start
/// of the segment), matching the previous-sample convention. The final
/// trailing point carries the last segment's HR. Returns N+1 points for
/// N segments.
List<AnalyticsPoint> _buildHrPointsFromSegments(
  List<(int?, int)> hrDurationPairs,
) {
  if (hrDurationPairs.isEmpty) return const [];

  final t0 = DateTime.utc(2026, 3, 14);
  final points = <AnalyticsPoint>[];
  var elapsedSeconds = 0;

  for (final (hr, duration) in hrDurationPairs) {
    points.add(
      AnalyticsPoint(
        timestamp: t0.add(Duration(seconds: elapsedSeconds)),
        latitude: 0,
        longitude: 0,
        heartRateBpm: hr,
      ),
    );
    elapsedSeconds += duration;
  }

  // Trailing fence-post point (HR won't be used as a leading sample).
  points.add(
    AnalyticsPoint(
      timestamp: t0.add(Duration(seconds: elapsedSeconds)),
      latitude: 0,
      longitude: 0,
      heartRateBpm: hrDurationPairs.last.$1,
    ),
  );

  return points;
}

void main() {
  // Single source of truth — use the calculator, not hand-rolled zones.
  final zones = HrZoneCalculator.forLthr(160, SportType.run);

  group('HrZoneAnalyzer.analyze()', () {
    group('single-zone attribution', () {
      test('all points in Z3 → 100% of time in Z3', () {
        // 5 points at 1s intervals → 4 intervals = 4.0 seconds
        final points = _buildUniformHrPoints(count: 5, heartRateBpm: 150);
        final result = HrZoneAnalyzer.analyze(points: points, zones: zones);

        expect(result.secondsPerZone[3], 4.0);
        expect(result.totalSeconds, 4.0);
        // Only Z3 should be present
        expect(result.secondsPerZone.keys, [3]);
      });
    });

    group('multi-zone time split', () {
      test(
        'crossing Z3/Z4 boundary attributes time to leading sample zone',
        () {
          // 150 BPM = Z3 (144–151), 155 BPM = Z4 (152–159)
          // Segment at 150 for 10s, then segment at 155 for 5s
          final points = _buildHrPointsFromSegments([
            (150, 10), // leading HR=150 (Z3) for 10s
            (155, 5), // leading HR=155 (Z4) for 5s
          ]);

          final result = HrZoneAnalyzer.analyze(points: points, zones: zones);

          expect(result.secondsPerZone[3], 10.0);
          expect(result.secondsPerZone[4], 5.0);
          expect(result.totalSeconds, 15.0);
        },
      );
    });

    group('null HR handling', () {
      test('null HR leading point excludes that interval', () {
        // A(valid=150, t=0) → B(null, t=5) → C(valid=150, t=10)
        // A→B: leading A has valid HR → 5s in Z3
        // B→C: leading B has null HR → excluded
        // Total: 5s
        final t0 = DateTime.utc(2026, 3, 14);
        final points = [
          AnalyticsPoint(
            timestamp: t0,
            latitude: 0,
            longitude: 0,
            heartRateBpm: 150,
          ),
          AnalyticsPoint(
            timestamp: t0.add(const Duration(seconds: 5)),
            latitude: 0,
            longitude: 0,
          ),
          AnalyticsPoint(
            timestamp: t0.add(const Duration(seconds: 10)),
            latitude: 0,
            longitude: 0,
            heartRateBpm: 150,
          ),
        ];

        final result = HrZoneAnalyzer.analyze(points: points, zones: zones);

        expect(result.secondsPerZone[3], 5.0);
        expect(result.totalSeconds, 5.0);
      });
    });

    group('single point and empty', () {
      test('single point yields empty breakdown', () {
        final points = _buildUniformHrPoints(count: 1, heartRateBpm: 150);
        final result = HrZoneAnalyzer.analyze(points: points, zones: zones);

        expect(result.secondsPerZone, isEmpty);
        expect(result.totalSeconds, 0.0);
      });

      test('empty points list yields empty breakdown', () {
        final result = HrZoneAnalyzer.analyze(
          points: const [],
          zones: zones,
        );

        expect(result.secondsPerZone, isEmpty);
        expect(result.totalSeconds, 0.0);
      });
    });

    group('boundary-value attribution', () {
      test('HR at exact zone transitions attributed correctly', () {
        // LTHR=160 run: Z1 upper=135, Z2 lower=136, Z5c lower=170
        final points = _buildHrPointsFromSegments([
          (135, 5), // Z1 upper boundary → Z1
          (136, 5), // Z2 lower boundary → Z2
          (170, 5), // Z5c lower boundary → Z5c
        ]);

        final result = HrZoneAnalyzer.analyze(points: points, zones: zones);

        expect(result.secondsPerZone[1], 5.0); // Z1
        expect(result.secondsPerZone[2], 5.0); // Z2
        expect(result.secondsPerZone[7], 5.0); // Z5c
        expect(result.totalSeconds, 15.0);
      });
    });

    group('timestamp-gap weighting', () {
      test('sparse and dense point streams produce identical breakdown', () {
        // Dense: 31 points at 1s intervals → 30 intervals × 1s = 30s
        final densePoints = _buildUniformHrPoints(count: 31, heartRateBpm: 150);

        // Sparse: 2 points 30s apart → 1 interval × 30s = 30s
        final t0 = DateTime.utc(2026, 3, 14);
        final sparsePoints = [
          AnalyticsPoint(
            timestamp: t0,
            latitude: 0,
            longitude: 0,
            heartRateBpm: 150,
          ),
          AnalyticsPoint(
            timestamp: t0.add(const Duration(seconds: 30)),
            latitude: 0,
            longitude: 0,
            heartRateBpm: 150,
          ),
        ];

        final denseResult = HrZoneAnalyzer.analyze(
          points: densePoints,
          zones: zones,
        );
        final sparseResult = HrZoneAnalyzer.analyze(
          points: sparsePoints,
          zones: zones,
        );

        expect(denseResult.secondsPerZone, sparseResult.secondsPerZone);
        expect(denseResult.totalSeconds, sparseResult.totalSeconds);
      });

      test('zero or negative timestamp deltas are excluded', () {
        final t0 = DateTime.utc(2026, 3, 14, 12);
        final points = [
          AnalyticsPoint(
            timestamp: t0,
            latitude: 0,
            longitude: 0,
            heartRateBpm: 150,
          ),
          AnalyticsPoint(
            timestamp: t0,
            latitude: 0,
            longitude: 0,
            heartRateBpm: 150,
          ),
          AnalyticsPoint(
            timestamp: t0.subtract(const Duration(seconds: 5)),
            latitude: 0,
            longitude: 0,
            heartRateBpm: 150,
          ),
        ];

        final result = HrZoneAnalyzer.analyze(points: points, zones: zones);

        expect(result.secondsPerZone, isEmpty);
        expect(result.totalSeconds, 0.0);
      });
    });
  });
}

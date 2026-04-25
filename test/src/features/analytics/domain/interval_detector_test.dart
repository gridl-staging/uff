import 'package:test/test.dart';
import 'package:uff/src/features/analytics/domain/analytics_point.dart';
import 'package:uff/src/features/analytics/domain/interval_detector.dart';
import 'package:uff/src/features/analytics/domain/interval_event.dart';

/// Builds one-second-apart points for alternating fast/slow segments.
///
/// [segmentDurations] and [segmentSpeeds] define each segment's length (in
/// seconds, i.e. number of points) and speed. [heartRates] optionally provides
/// per-segment HR values.
List<AnalyticsPoint> _buildAlternatingPoints({
  required List<int> segmentDurations,
  required List<double> segmentSpeeds,
  List<int?>? heartRates,
}) {
  assert(
    segmentDurations.length == segmentSpeeds.length,
    'segmentDurations and segmentSpeeds must have matching lengths',
  );
  assert(
    heartRates == null || heartRates.length == segmentSpeeds.length,
    'heartRates must be null or match segmentSpeeds length',
  );

  final start = DateTime.utc(2026, 3, 14);
  final points = <AnalyticsPoint>[];
  var elapsed = 0;
  var cumulativeDistance = 0.0;

  for (var seg = 0; seg < segmentDurations.length; seg++) {
    final speed = segmentSpeeds[seg];
    final hr = heartRates?[seg];

    for (var s = 0; s < segmentDurations[seg]; s++) {
      points.add(
        AnalyticsPoint(
          timestamp: start.add(Duration(seconds: elapsed)),
          latitude: 0,
          longitude: 0,
          speedMs: speed,
          heartRateBpm: hr,
          cumulativeDistanceMeters: cumulativeDistance,
        ),
      );
      cumulativeDistance += speed; // 1 second × speed m/s
      elapsed++;
    }
  }

  return points;
}

void main() {
  group('IntervalDetector.detect()', () {
    group('clean alternating intervals', () {
      // 6 segments × 60 points: hard-easy-hard-easy-hard-easy
      // Hard: 5.0 m/s → pace 200 s/km, HR 170
      // Easy: 2.5 m/s → pace 400 s/km, HR 130
      late final List<IntervalEvent> results;

      setUpAll(() {
        final points = _buildAlternatingPoints(
          segmentDurations: [60, 60, 60, 60, 60, 60],
          segmentSpeeds: [5.0, 2.5, 5.0, 2.5, 5.0, 2.5],
          heartRates: [170, 130, 170, 130, 170, 130],
        );

        results = IntervalDetector.detect(
          points: points,
          smoothingWindow: 1,
        );
      });

      test('returns 6 intervals', () {
        expect(results, hasLength(6));
      });

      test('alternates hard/easy starting with hard', () {
        expect(results[0].intensity, IntervalIntensity.hard);
        expect(results[1].intensity, IntervalIntensity.easy);
        expect(results[2].intensity, IntervalIntensity.hard);
        expect(results[3].intensity, IntervalIntensity.easy);
        expect(results[4].intensity, IntervalIntensity.hard);
        expect(results[5].intensity, IntervalIntensity.easy);
      });

      test('hard intervals have correct pace, distance, and HR', () {
        for (var i = 0; i < results.length; i += 2) {
          final event = results[i];
          expect(event.avgPaceSecsPerKm, closeTo(200, 10));
          expect(event.distanceMeters, closeTo(300, 10));
          expect(event.avgHeartRateBpm, closeTo(170, 5));
        }
      });

      test('easy intervals have correct pace, distance, and HR', () {
        for (var i = 1; i < results.length; i += 2) {
          final event = results[i];
          expect(event.avgPaceSecsPerKm, closeTo(400, 10));
          expect(event.distanceMeters, closeTo(150, 10));
          expect(event.avgHeartRateBpm, closeTo(130, 5));
        }
      });
    });

    group('edge cases', () {
      test('empty points returns empty list', () {
        expect(IntervalDetector.detect(points: const []), isEmpty);
      });

      test('single point returns empty list', () {
        final points = _buildAlternatingPoints(
          segmentDurations: [1],
          segmentSpeeds: [5.0],
        );
        expect(IntervalDetector.detect(points: points), isEmpty);
      });

      test('uniform speed returns empty list (1 segment, fails ≥3 check)', () {
        final points = _buildAlternatingPoints(
          segmentDurations: [120],
          segmentSpeeds: [4.0],
        );
        expect(
          IntervalDetector.detect(points: points, smoothingWindow: 1),
          isEmpty,
        );
      });

      test('2 segments returns empty list (below ≥3 threshold)', () {
        final points = _buildAlternatingPoints(
          segmentDurations: [60, 60],
          segmentSpeeds: [5.0, 2.5],
        );
        expect(
          IntervalDetector.detect(points: points, smoothingWindow: 1),
          isEmpty,
        );
      });

      test('3 segments returns 3 events (minimum valid)', () {
        final points = _buildAlternatingPoints(
          segmentDurations: [60, 60, 60],
          segmentSpeeds: [5.0, 2.5, 5.0],
        );
        final results = IntervalDetector.detect(
          points: points,
          smoothingWindow: 1,
        );
        expect(results, hasLength(3));
        expect(results[0].intensity, IntervalIntensity.hard);
        expect(results[1].intensity, IntervalIntensity.easy);
        expect(results[2].intensity, IntervalIntensity.hard);
      });

      test('all null speedMs returns empty list', () {
        final start = DateTime.utc(2026, 3, 14);
        final points = List.generate(
          60,
          (i) => AnalyticsPoint(
            timestamp: start.add(Duration(seconds: i)),
            latitude: 0,
            longitude: 0,
          ),
        );
        expect(IntervalDetector.detect(points: points), isEmpty);
      });

      test('null HR produces null avgHeartRateBpm', () {
        final points = _buildAlternatingPoints(
          segmentDurations: [60, 60, 60],
          segmentSpeeds: [5.0, 2.5, 5.0],
          // no heartRates → all null
        );
        final results = IntervalDetector.detect(
          points: points,
          smoothingWindow: 1,
        );
        expect(results, hasLength(3));
        for (final event in results) {
          expect(event.avgHeartRateBpm, isNull);
        }
      });
    });

    group('noise filtering', () {
      // 5 segments: hard-60s, easy-60s, hard-10s (noise), easy-60s, hard-60s
      late final List<AnalyticsPoint> noiseFixture;

      setUpAll(() {
        noiseFixture = _buildAlternatingPoints(
          segmentDurations: [60, 60, 10, 60, 60],
          segmentSpeeds: [5.0, 2.5, 5.0, 2.5, 5.0],
        );
      });

      test('filters noise and merges flanking segments → 3 events', () {
        // Default minSegmentSeconds=30 filters the 10s hard noise.
        // Two easy segments merge → [hard, easy, hard].
        final results = IntervalDetector.detect(points: noiseFixture);
        expect(results, hasLength(3));
        expect(results[0].intensity, IntervalIntensity.hard);
        expect(results[1].intensity, IntervalIntensity.easy);
        expect(results[2].intensity, IntervalIntensity.hard);
      });

      test('minSegmentSeconds=0 disables filtering → 5 events', () {
        final results = IntervalDetector.detect(
          points: noiseFixture,
          minSegmentSeconds: 0,
        );
        expect(results, hasLength(5));
        expect(results[0].intensity, IntervalIntensity.hard);
        expect(results[1].intensity, IntervalIntensity.easy);
        expect(results[2].intensity, IntervalIntensity.hard);
        expect(results[3].intensity, IntervalIntensity.easy);
        expect(results[4].intensity, IntervalIntensity.hard);
      });
    });

    group('boundary regression', () {
      test('threshold equal to segment pace labels that segment easy', () {
        // 3 segments: hard(200 s/km) - easy(400 s/km) - hard(200 s/km)
        // Set threshold to 400 — matches easy segment's exact pace.
        // pace < threshold → hard; pace == threshold → easy.
        final points = _buildAlternatingPoints(
          segmentDurations: [60, 60, 60],
          segmentSpeeds: [5.0, 2.5, 5.0], // paces: 200, 400, 200
        );
        final results = IntervalDetector.detect(
          points: points,
          smoothingWindow: 1,
          thresholdPaceSecsPerKm: 400,
        );
        expect(results, hasLength(3));
        expect(results[0].intensity, IntervalIntensity.hard);
        expect(results[1].intensity, IntervalIntensity.easy);
        expect(results[2].intensity, IntervalIntensity.hard);
      });

      test('all segments below minSegmentSeconds → all filtered → empty', () {
        // 5 segments × 10s each, default minSegmentSeconds=30.
        // All 5 filtered → empty → < 3 → empty list.
        final points = _buildAlternatingPoints(
          segmentDurations: [10, 10, 10, 10, 10],
          segmentSpeeds: [5.0, 2.5, 5.0, 2.5, 5.0],
        );
        final results = IntervalDetector.detect(
          points: points,
          smoothingWindow: 1,
        );
        expect(results, isEmpty);
      });
    });
  });
}

import 'package:test/test.dart';

import 'fixture_loader.dart';

void main() {
  group('loadFixtureTrackingPoints', () {
    test('matches manifest pointCount for every fixture', () async {
      final expectedMetrics = loadExpectedMetrics();

      for (final entry in expectedMetrics.entries) {
        final fixtureName = entry.key;
        final expectedPointCount =
            (entry.value as Map<String, dynamic>)['pointCount'] as int;

        final points = await loadFixtureTrackingPoints(fixtureName);

        expect(
          points,
          hasLength(expectedPointCount),
          reason: '$fixtureName should match manifest pointCount',
        );
      }
    });
  });

  group('toAnalyticsPoints', () {
    test(
      'preserves long_easy_run sensor fields with cadence converted to int',
      () async {
        final trackingPoints = await loadFixtureTrackingPoints('long_easy_run');

        final analyticsPoints = toAnalyticsPoints(trackingPoints);

        expect(analyticsPoints, hasLength(trackingPoints.length));

        for (var index = 0; index < trackingPoints.length; index += 1) {
          final trackingPoint = trackingPoints[index];
          final analyticsPoint = analyticsPoints[index];

          expect(analyticsPoint.heartRateBpm, trackingPoint.heartRateBpm);
          expect(analyticsPoint.powerWatts, trackingPoint.powerWatts);
          expect(analyticsPoint.cadenceRpm, trackingPoint.cadenceRpm?.toInt());
        }
      },
    );
  });

  group('loadExpectedMetrics', () {
    test('returns all five fixture keys', () {
      final expectedMetrics = loadExpectedMetrics();

      expect(expectedMetrics, hasLength(5));
      expect(expectedMetrics.keys.toSet(), fixturePathsByName.keys.toSet());
    });
  });
}

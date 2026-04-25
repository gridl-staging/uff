import 'package:test/test.dart';
import 'package:uff/src/features/analytics/domain/interval_detector.dart';
import 'package:uff/src/features/analytics/domain/interval_event.dart';

import '../../../../fixtures/fixture_loader.dart';

double _mean(Iterable<double> values) {
  final valueList = values.toList(growable: false);
  if (valueList.isEmpty) {
    throw StateError('Cannot average empty values');
  }

  return valueList.reduce((left, right) => left + right) / valueList.length;
}

void main() {
  group('fixture interval detection', () {
    test(
      'interval_workout detection matches manifest and intensity behavior',
      () async {
        final expected = loadExpectedFixture('interval_workout');
        final analyticsPoints = await loadFixtureAnalyticsPoints(
          'interval_workout',
        );

        final intervals = IntervalDetector.detect(
          points: analyticsPoints,
          smoothingWindow: 1,
        );

        expect(
          intervals,
          hasLength((expected['intervalSegmentCount'] as num).toInt()),
        );

        for (var index = 0; index < intervals.length; index += 1) {
          final expectedIntensity = index.isEven
              ? IntervalIntensity.hard
              : IntervalIntensity.easy;
          expect(intervals[index].intensity, expectedIntensity);
        }

        final hardIntervals = intervals
            .where((interval) => interval.intensity == IntervalIntensity.hard)
            .toList(growable: false);
        final easyIntervals = intervals
            .where((interval) => interval.intensity == IntervalIntensity.easy)
            .toList(growable: false);
        final expectedHardCount = (intervals.length + 1) ~/ 2;
        final expectedEasyCount = intervals.length ~/ 2;

        expect(hardIntervals, hasLength(expectedHardCount));
        expect(easyIntervals, hasLength(expectedEasyCount));

        final meanHardPaceSecondsPerKm = _mean(
          hardIntervals.map((interval) => interval.avgPaceSecsPerKm),
        );
        final meanEasyPaceSecondsPerKm = _mean(
          easyIntervals.map((interval) => interval.avgPaceSecsPerKm),
        );
        expect(meanHardPaceSecondsPerKm, lessThan(meanEasyPaceSecondsPerKm));

        final hardHeartRates = hardIntervals
            .map((interval) => interval.avgHeartRateBpm)
            .whereType<double>();
        final easyHeartRates = easyIntervals
            .map((interval) => interval.avgHeartRateBpm)
            .whereType<double>();
        expect(_mean(hardHeartRates), greaterThan(_mean(easyHeartRates)));
      },
    );

    test('long_easy_run does not produce false interval detections', () async {
      final analyticsPoints = await loadFixtureAnalyticsPoints('long_easy_run');

      final intervals = IntervalDetector.detect(points: analyticsPoints);

      expect(intervals, isEmpty);
    });
  });
}

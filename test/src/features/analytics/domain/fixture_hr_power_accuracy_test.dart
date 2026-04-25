import 'package:test/test.dart';
import 'package:uff/src/features/analytics/domain/hr_zone_analyzer.dart';
import 'package:uff/src/features/analytics/domain/hr_zone_calculator.dart';
import 'package:uff/src/features/analytics/domain/power_curve_calculator.dart';
import 'package:uff/src/features/analytics/domain/sport_type.dart';

import '../../../../fixtures/fixture_loader.dart';

const int _sharedLthrBpm = 155;

const Map<int, double> _expectedLongEasyZoneSeconds = <int, double>{
  3: 3600.0,
};

const Map<int, double> _expectedIntervalZoneSeconds = <int, double>{
  2: 225.0,
  3: 375.0,
  7: 720.0,
};

const List<int> _expectedPowerCurveDurationsSeconds = <int>[
  5,
  10,
  30,
  60,
  120,
  300,
  600,
  1200,
  1800,
  3600,
];

void _expectSecondsPerZone(
  Map<int, double> actual,
  Map<int, double> expected,
) {
  expect(actual.keys.toSet(), expected.keys.toSet());
  for (final entry in expected.entries) {
    expect(actual[entry.key], closeTo(entry.value, 1e-9));
  }
}

void main() {
  group('fixture HR and power accuracy', () {
    test('forLthr(155) yields expected running zone boundaries', () {
      final zones = HrZoneCalculator.forLthr(_sharedLthrBpm, SportType.run);

      expect(zones.zones[0].lowerBpm, 0);
      expect(zones.zones[0].upperBpm, 130);
      expect(zones.zones[1].lowerBpm, 131);
      expect(zones.zones[1].upperBpm, 138);
      expect(zones.zones[2].lowerBpm, 139);
      expect(zones.zones[2].upperBpm, 146);
      expect(zones.zones[3].lowerBpm, 147);
      expect(zones.zones[3].upperBpm, 154);
      expect(zones.zones[4].lowerBpm, 155);
      expect(zones.zones[4].upperBpm, 158);
      expect(zones.zones[5].lowerBpm, 159);
      expect(zones.zones[5].upperBpm, 164);
      expect(zones.zones[6].lowerBpm, 165);
      expect(zones.zones[6].upperBpm, isNull);
    });

    test(
      'long_easy_run and interval_workout match HR-zone and power oracles',
      () async {
        final zones = HrZoneCalculator.forLthr(_sharedLthrBpm, SportType.run);

        final longEasyPoints = await loadFixtureAnalyticsPoints(
          'long_easy_run',
        );
        final longEasyBreakdown = HrZoneAnalyzer.analyze(
          points: longEasyPoints,
          zones: zones,
        );
        _expectSecondsPerZone(
          longEasyBreakdown.secondsPerZone,
          _expectedLongEasyZoneSeconds,
        );

        final longEasyCurve = PowerCurveCalculator.calculate(
          points: longEasyPoints,
        );
        expect(
          longEasyCurve,
          hasLength(_expectedPowerCurveDurationsSeconds.length),
        );
        for (var index = 0; index < longEasyCurve.length; index += 1) {
          expect(
            longEasyCurve[index].duration,
            Duration(seconds: _expectedPowerCurveDurationsSeconds[index]),
          );
          expect(longEasyCurve[index].avgWatts, closeTo(200.0, 1e-9));
        }

        final intervalPoints = await loadFixtureAnalyticsPoints(
          'interval_workout',
        );
        final intervalBreakdown = HrZoneAnalyzer.analyze(
          points: intervalPoints,
          zones: zones,
        );
        _expectSecondsPerZone(
          intervalBreakdown.secondsPerZone,
          _expectedIntervalZoneSeconds,
        );

        final intervalCurve = PowerCurveCalculator.calculate(
          points: intervalPoints,
        );
        expect(intervalCurve, isEmpty);
      },
    );
  });
}

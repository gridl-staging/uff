import 'package:test/test.dart';
import 'package:uff/src/features/analytics/domain/training_stress.dart';
import 'package:uff/src/features/analytics/domain/tss_calculator.dart';

import '../../../../fixtures/fixture_loader.dart';

const double _sharedThresholdPaceSecsPerKm = 250;
const int _sharedFtpWatts = 250;

double _expectedTss({
  required int durationSeconds,
  required double intensityFactor,
}) {
  return (durationSeconds / 3600) * intensityFactor * intensityFactor * 100;
}

void main() {
  group('fixture TSS accuracy', () {
    test(
      'long_easy_run simpleTSS and cTSS match independently-derived formulas',
      () async {
        final expected = loadExpectedFixture('long_easy_run');
        final analyticsPoints = await loadFixtureAnalyticsPoints(
          'long_easy_run',
        );

        final durationSeconds = (expected['movingSeconds'] as num).toInt();
        final averagePaceSecondsPerKm =
            averagePaceSecondsPerKmFromExpectedMetrics(expected);

        final simpleTss = TssCalculator.simpleTss(
          durationSeconds: durationSeconds,
          avgPaceSecsPerKm: averagePaceSecondsPerKm,
          thresholdPaceSecsPerKm: _sharedThresholdPaceSecsPerKm,
        );

        final expectedSimpleTss = _expectedTss(
          durationSeconds: durationSeconds,
          intensityFactor:
              _sharedThresholdPaceSecsPerKm / averagePaceSecondsPerKm,
        );

        // simpleTss with valid fixture inputs returns simpleTSS method
        expect(simpleTss?.method, TssMethod.simpleTSS);
        // verify TSS matches independently-derived formula
        expect(simpleTss!.tss, closeTo(expectedSimpleTss, 1e-9));

        final observedPowerValues = analyticsPoints
            .map((point) => point.powerWatts)
            .whereType<int>()
            .toSet();
        expect(observedPowerValues.length, 1);

        final normalizedPowerWatts = observedPowerValues.single.toDouble();
        final expectedCtss = _expectedTss(
          durationSeconds: durationSeconds,
          intensityFactor: normalizedPowerWatts / _sharedFtpWatts,
        );

        final cTss = TssCalculator.cTss(
          points: analyticsPoints,
          ftpWatts: _sharedFtpWatts,
        );

        // cTss with valid fixture power data returns cTSS method
        expect(cTss?.method, TssMethod.cTSS);
        // verify TSS matches independently-derived formula
        expect(cTss!.tss, closeTo(expectedCtss, 1e-9));
      },
    );

    test(
      'rTSS tracks simpleTSS on flat fixture and diverges on hilly fixture',
      () async {
        final longEasyExpected = loadExpectedFixture('long_easy_run');
        final longEasyPoints = await loadFixtureAnalyticsPoints(
          'long_easy_run',
        );
        final longEasySimpleTss = TssCalculator.simpleTss(
          durationSeconds: (longEasyExpected['movingSeconds'] as num).toInt(),
          avgPaceSecsPerKm: averagePaceSecondsPerKmFromExpectedMetrics(
            longEasyExpected,
          ),
          thresholdPaceSecsPerKm: _sharedThresholdPaceSecsPerKm,
        );
        final longEasyRtss = TssCalculator.rTss(
          points: longEasyPoints,
          thresholdPaceSecsPerKm: _sharedThresholdPaceSecsPerKm,
        );

        // flat fixture → simpleTSS method
        expect(longEasySimpleTss?.method, TssMethod.simpleTSS);
        // rTss on fixture data → rTSS method
        expect(longEasyRtss?.method, TssMethod.rTSS);

        // Fixture points omit cumulativeDistanceMeters, so rTSS uses the
        // documented speedMs × deltaSeconds distance fallback.
        final flatDeltaFraction =
            (longEasyRtss!.tss - longEasySimpleTss!.tss).abs() /
            longEasySimpleTss.tss;
        expect(flatDeltaFraction, lessThanOrEqualTo(0.05));

        final hillyExpected = loadExpectedFixture('hilly_10k');
        final hillyPoints = await loadFixtureAnalyticsPoints('hilly_10k');
        final hillySimpleTss = TssCalculator.simpleTss(
          durationSeconds: (hillyExpected['movingSeconds'] as num).toInt(),
          avgPaceSecsPerKm: averagePaceSecondsPerKmFromExpectedMetrics(
            hillyExpected,
          ),
          thresholdPaceSecsPerKm: _sharedThresholdPaceSecsPerKm,
        );
        final hillyRtss = TssCalculator.rTss(
          points: hillyPoints,
          thresholdPaceSecsPerKm: _sharedThresholdPaceSecsPerKm,
        );

        // hilly fixture → simpleTSS method for simple calculation
        expect(hillySimpleTss?.method, TssMethod.simpleTSS);
        // rTss on hilly fixture → rTSS method
        expect(hillyRtss?.method, TssMethod.rTSS);
        // hilly terrain Minetti adjustment → rTSS diverges below simpleTSS
        expect(hillyRtss!.tss, lessThan(hillySimpleTss!.tss * 0.9));
      },
    );
  });
}

import 'package:test/test.dart';
import 'package:uff/src/features/analytics/domain/pmc_calculator.dart';
import 'package:uff/src/features/analytics/domain/tss_calculator.dart';

import '../../../../fixtures/fixture_loader.dart';

const double _thresholdPaceSecsPerKm = 250;

DateTime _utcDay(int year, int month, int day) =>
    DateTime.utc(year, month, day);

Future<double> _longEasyRunDailyTss() async {
  final expected = loadExpectedFixture('long_easy_run');

  final tss = TssCalculator.simpleTss(
    durationSeconds: (expected['movingSeconds'] as num).toInt(),
    avgPaceSecsPerKm: averagePaceSecondsPerKmFromExpectedMetrics(expected),
    thresholdPaceSecsPerKm: _thresholdPaceSecsPerKm,
  );

  if (tss == null) {
    throw StateError('Expected simpleTss for long_easy_run to be non-null');
  }

  return tss.tss;
}

/// ## Test Scenarios
/// - `[positive]` Sustained load raises CTL monotonically across a multi-week block.
/// - `[statemachine]` ATL reacts faster than CTL and drives expected TSB swings.
/// - `[edge]` Rest blocks recover TSB back above zero after heavy training.
void main() {
  group('PMC multi-week fixture scenarios', () {
    test(
      'constant load for 28 days increases CTL monotonically and keeps ATL above CTL',
      () async {
        final dailyTss = await _longEasyRunDailyTss();
        final rangeStart = _utcDay(2026, 1, 1);
        final rangeEnd = rangeStart.add(const Duration(days: 27));
        final trainingSeries = <DateTime, double>{
          for (var dayOffset = 0; dayOffset < 28; dayOffset += 1)
            rangeStart.add(Duration(days: dayOffset)): dailyTss,
        };

        final pmc = PmcCalculator.calculate(
          dailyTss: trainingSeries,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
        );

        expect(pmc, hasLength(28));

        for (var index = 1; index < pmc.length; index += 1) {
          expect(
            pmc[index].ctl,
            greaterThan(pmc[index - 1].ctl),
            reason: 'CTL should rise every day during sustained constant load',
          );
        }

        for (final day in pmc) {
          expect(day.atl, greaterThan(day.ctl));
        }
      },
    );

    test(
      '14-day training block then 14-day rest moves TSB from negative to positive',
      () async {
        final dailyTss = await _longEasyRunDailyTss();
        final rangeStart = _utcDay(2026, 2, 1);
        final rangeEnd = rangeStart.add(const Duration(days: 27));
        final trainingThenRestSeries = <DateTime, double>{
          for (var dayOffset = 0; dayOffset < 14; dayOffset += 1)
            rangeStart.add(Duration(days: dayOffset)): dailyTss,
        };

        final pmc = PmcCalculator.calculate(
          dailyTss: trainingThenRestSeries,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
        );

        expect(pmc, hasLength(28));

        final trainingBlock = pmc.take(14).toList(growable: false);
        final restBlock = pmc.skip(14).toList(growable: false);
        final mostNegativeTrainingTsb = trainingBlock
            .map((day) => day.tsb)
            .reduce((left, right) => left < right ? left : right);

        // ATL uses a 7-day decay constant and reacts faster than the 42-day CTL,
        // so TSB becomes negative during the training block.
        expect(mostNegativeTrainingTsb, lessThan(0));

        // During rest, ATL decays faster than CTL under the same constants,
        // so TSB recovers and should turn positive by the end of the block.
        expect(restBlock.last.tsb > 0, isTrue);
      },
    );
  });
}

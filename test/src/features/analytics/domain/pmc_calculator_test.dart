import 'package:test/test.dart';
import 'package:uff/src/features/analytics/domain/pmc_calculator.dart';

/// Returns a UTC-midnight DateTime for the given date.
DateTime _utcDay(int year, int month, int day) =>
    DateTime.utc(year, month, day);

/// Returns a local-time instant that crosses a UTC day boundary, or null in UTC.
DateTime? _localUtcDayRolloverInstant() {
  final offset = DateTime(2026, 3, 14, 12).timeZoneOffset;
  if (offset == Duration.zero) {
    return null;
  }

  // West of UTC: late local evening rolls into next UTC day.
  // East of UTC: early local morning rolls into previous UTC day.
  return offset.isNegative
      ? DateTime(2026, 3, 14, 23)
      : DateTime(2026, 3, 14, 0, 30);
}

void main() {
  group('PmcCalculator.calculate()', () {
    group('empty and boundary ranges', () {
      test('rangeEnd before rangeStart returns empty list', () {
        final result = PmcCalculator.calculate(
          dailyTss: const {},
          rangeStart: _utcDay(2026, 3, 15),
          rangeEnd: _utcDay(2026, 3, 14),
        );

        expect(result, isEmpty);
      });

      test('single-day range with no TSS entry emits one rest PmcDay', () {
        final result = PmcCalculator.calculate(
          dailyTss: const {},
          rangeStart: _utcDay(2026, 3, 14),
          rangeEnd: _utcDay(2026, 3, 14),
        );

        expect(result, hasLength(1));
        expect(result.first.date, _utcDay(2026, 3, 14));
        expect(result.first.tssOnDay, 0);
        expect(result.first.ctl, 0);
        expect(result.first.atl, 0);
        expect(result.first.tsb, 0);
      });
    });

    group('single-day active', () {
      test('TSS=100 on day 1 yields correct EWMA values', () {
        final result = PmcCalculator.calculate(
          dailyTss: {_utcDay(2026, 3, 14): 100},
          rangeStart: _utcDay(2026, 3, 14),
          rangeEnd: _utcDay(2026, 3, 14),
        );

        expect(result, hasLength(1));
        final day = result.first;
        expect(day.date, _utcDay(2026, 3, 14));
        expect(day.tssOnDay, 100);
        expect(day.ctl, closeTo(2.353, 1e-3));
        expect(day.atl, closeTo(13.312, 1e-3));
        expect(day.tsb, closeTo(-10.959, 1e-3));
      });
    });

    group('rest-day decay', () {
      test('active day followed by rest day decays correctly', () {
        final result = PmcCalculator.calculate(
          dailyTss: {_utcDay(2026, 3, 14): 100},
          rangeStart: _utcDay(2026, 3, 14),
          rangeEnd: _utcDay(2026, 3, 15),
        );

        expect(result, hasLength(2));

        // Day 1: active
        expect(result[0].tssOnDay, 100);
        expect(result[0].ctl, closeTo(2.353, 1e-3));
        expect(result[0].atl, closeTo(13.312, 1e-3));

        // Day 2: rest
        final restDay = result[1];
        expect(restDay.date, _utcDay(2026, 3, 15));
        expect(restDay.tssOnDay, 0);
        expect(restDay.ctl, closeTo(2.298, 1e-3));
        expect(restDay.atl, closeTo(11.540, 1e-3));
        expect(restDay.tsb, closeTo(-9.243, 1e-3));
      });
    });

    group('seeded start', () {
      test('initialCtl and initialAtl affect the first emitted day', () {
        final result = PmcCalculator.calculate(
          dailyTss: {_utcDay(2026, 3, 14): 100},
          rangeStart: _utcDay(2026, 3, 14),
          rangeEnd: _utcDay(2026, 3, 14),
          initialCtl: 50,
          initialAtl: 30,
        );

        expect(result, hasLength(1));
        final day = result.first;
        expect(day.ctl, closeTo(51.176, 1e-3));
        expect(day.atl, closeTo(39.319, 1e-3));
        expect(day.tsb, closeTo(11.858, 1e-3));
      });

      test('seeded rest-only produces pure decay', () {
        final result = PmcCalculator.calculate(
          dailyTss: const {},
          rangeStart: _utcDay(2026, 3, 14),
          rangeEnd: _utcDay(2026, 3, 14),
          initialCtl: 50,
          initialAtl: 30,
        );

        expect(result, hasLength(1));
        final day = result.first;
        expect(day.tssOnDay, 0);
        expect(day.ctl, closeTo(48.824, 1e-3));
        expect(day.atl, closeTo(26.006, 1e-3));
        expect(day.tsb, closeTo(22.817, 1e-3));
      });
    });

    group('UTC-day normalization', () {
      test('non-midnight timestamp is read through its UTC-day key', () {
        // A TSS entry at 14:30 UTC on March 14 should be treated as March 14
        final result = PmcCalculator.calculate(
          dailyTss: {DateTime.utc(2026, 3, 14, 14, 30): 100},
          rangeStart: _utcDay(2026, 3, 14),
          rangeEnd: _utcDay(2026, 3, 14),
        );

        expect(result, hasLength(1));
        expect(result.first.date, _utcDay(2026, 3, 14));
        expect(result.first.tssOnDay, 100);
        expect(result.first.ctl, closeTo(2.353, 1e-3));
      });

      test('non-midnight rangeStart and rangeEnd are normalized', () {
        final result = PmcCalculator.calculate(
          dailyTss: {_utcDay(2026, 3, 14): 100},
          rangeStart: DateTime.utc(2026, 3, 14, 5),
          rangeEnd: DateTime.utc(2026, 3, 15, 23, 59),
        );

        expect(result, hasLength(2));
        expect(result[0].date, _utcDay(2026, 3, 14));
        expect(result[1].date, _utcDay(2026, 3, 15));
      });

      test('emitted PmcDay.date values are always UTC midnight', () {
        final result = PmcCalculator.calculate(
          dailyTss: {DateTime.utc(2026, 3, 14, 8): 50},
          rangeStart: DateTime.utc(2026, 3, 14, 12),
          rangeEnd: DateTime.utc(2026, 3, 16, 6),
        );

        for (final day in result) {
          expect(day.date.hour, 0);
          expect(day.date.minute, 0);
          expect(day.date.second, 0);
          expect(day.date.isUtc, isTrue);
        }
      });

      test('local-time DateTime crossing UTC day normalizes correctly', () {
        final localInput = _localUtcDayRolloverInstant();
        if (localInput == null) {
          markTestSkipped(
            'Local timezone is UTC; no local instant crosses a UTC day.',
          );
          return;
        }

        final utcEquivalent = localInput.toUtc();
        final expectedUtcDay = DateTime.utc(
          utcEquivalent.year,
          utcEquivalent.month,
          utcEquivalent.day,
        );

        final result = PmcCalculator.calculate(
          dailyTss: {localInput: 100},
          rangeStart: expectedUtcDay,
          rangeEnd: expectedUtcDay,
        );

        expect(result, hasLength(1));
        expect(result.first.date, expectedUtcDay);
        expect(result.first.tssOnDay, 100);
      });

      test('local-time range boundaries crossing UTC day are normalized', () {
        final localRangeBoundary = _localUtcDayRolloverInstant();
        if (localRangeBoundary == null) {
          markTestSkipped(
            'Local timezone is UTC; no local instant crosses a UTC day.',
          );
          return;
        }

        final utcEquivalent = localRangeBoundary.toUtc();
        final expectedUtcDay = DateTime.utc(
          utcEquivalent.year,
          utcEquivalent.month,
          utcEquivalent.day,
        );

        final result = PmcCalculator.calculate(
          dailyTss: {expectedUtcDay: 100},
          rangeStart: localRangeBoundary,
          rangeEnd: localRangeBoundary,
        );

        expect(result, hasLength(1));
        expect(result.first.date, expectedUtcDay);
        expect(result.first.tssOnDay, 100);
      });

      test('two keys normalizing to the same UTC day throws ArgumentError', () {
        expect(
          () => PmcCalculator.calculate(
            dailyTss: {
              DateTime.utc(2026, 3, 14, 6): 50,
              DateTime.utc(2026, 3, 14, 18): 75,
            },
            rangeStart: _utcDay(2026, 3, 14),
            rangeEnd: _utcDay(2026, 3, 14),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'message',
              contains('pre-sum daily TSS'),
            ),
          ),
        );
      });

      test(
        'normalized-key collision outside requested range still throws',
        () {
          expect(
            () => PmcCalculator.calculate(
              dailyTss: {
                DateTime.utc(2026, 3, 14, 6): 50,
                DateTime.utc(2026, 3, 14, 18): 75,
              },
              rangeStart: _utcDay(2026, 3, 20),
              rangeEnd: _utcDay(2026, 3, 20),
            ),
            throwsA(
              isA<ArgumentError>().having(
                (error) => error.message,
                'message',
                contains('pre-sum daily TSS'),
              ),
            ),
          );
        },
      );
    });

    group('long-horizon regression', () {
      test('90-day ramp at 100 TSS/day yields CTL≈88.3 on day 90', () {
        final dailyTss = <DateTime, double>{};
        final start = _utcDay(2026, 1, 1);
        for (var i = 0; i < 90; i++) {
          dailyTss[start.add(Duration(days: i))] = 100;
        }

        final result = PmcCalculator.calculate(
          dailyTss: dailyTss,
          rangeStart: start,
          rangeEnd: start.add(const Duration(days: 89)),
        );

        expect(result, hasLength(90));
        final day90 = result.last;
        expect(day90.ctl, closeTo(88.268, 1e-3));
        expect(day90.atl, closeTo(100.0, 0.01));
        expect(day90.tsb, closeTo(-11.732, 1e-3));
      });

      test('pre-summed high-load day value is consumed as one total', () {
        // 250 TSS = two activities summed by caller (150 + 100)
        // PmcCalculator just sees 250 as the daily total
        final result = PmcCalculator.calculate(
          dailyTss: {_utcDay(2026, 3, 14): 250},
          rangeStart: _utcDay(2026, 3, 14),
          rangeEnd: _utcDay(2026, 3, 14),
        );

        expect(result, hasLength(1));
        expect(result.first.tssOnDay, 250);
        // CTL = 0 * ctlDecay + 250 * ctlFactor = 250 * 0.023528... ≈ 5.882
        expect(result.first.ctl, closeTo(5.882, 1e-3));
        // ATL = 0 * atlDecay + 250 * atlFactor = 250 * 0.133122... ≈ 33.281
        expect(result.first.atl, closeTo(33.281, 1e-3));
      });
    });

    group('ascending order', () {
      test('emits PmcDay entries in ascending date order', () {
        final result = PmcCalculator.calculate(
          dailyTss: {
            _utcDay(2026, 3, 16): 80,
            _utcDay(2026, 3, 14): 100,
          },
          rangeStart: _utcDay(2026, 3, 14),
          rangeEnd: _utcDay(2026, 3, 16),
        );

        expect(result, hasLength(3));
        expect(result[0].date, _utcDay(2026, 3, 14));
        expect(result[1].date, _utcDay(2026, 3, 15));
        expect(result[2].date, _utcDay(2026, 3, 16));
      });
    });
  });
}

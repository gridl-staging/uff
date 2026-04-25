import 'dart:math' as math;

import 'package:uff/src/features/analytics/domain/pmc_day.dart';

/// Computes daily CTL/ATL/TSB values from pre-summed daily TSS input.
abstract final class PmcCalculator {
  static final double _ctlDecay = math.exp(-1 / 42);
  static final double _atlDecay = math.exp(-1 / 7);
  static final double _ctlFactor = 1 - _ctlDecay;
  static final double _atlFactor = 1 - _atlDecay;

  /// Computes a PMC time series from daily TSS totals.
  ///
  /// [dailyTss] maps calendar days to their pre-summed TSS total. Days absent
  /// from the map are rest days (TSS = 0). All keys are normalized to UTC
  /// midnight internally; if two keys normalize to the same day, an
  /// [ArgumentError] is thrown.
  ///
  /// Returns one [PmcDay] per calendar day in [rangeStart, rangeEnd] inclusive,
  /// in ascending date order. Returns an empty list if [rangeEnd] is before
  /// [rangeStart].
  static List<PmcDay> calculate({
    required Map<DateTime, double> dailyTss,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    double initialCtl = 0,
    double initialAtl = 0,
  }) {
    final normalizedStart = _toUtcDay(rangeStart);
    final normalizedEnd = _toUtcDay(rangeEnd);

    if (normalizedEnd.isBefore(normalizedStart)) {
      return const [];
    }

    final normalizedTss = _normalizeDailyTss(dailyTss);

    final result = <PmcDay>[];
    var prevCtl = initialCtl;
    var prevAtl = initialAtl;

    var current = normalizedStart;
    while (!current.isAfter(normalizedEnd)) {
      final tss = normalizedTss[current] ?? 0;
      final ctl = prevCtl * _ctlDecay + tss * _ctlFactor;
      final atl = prevAtl * _atlDecay + tss * _atlFactor;
      final tsb = ctl - atl;

      result.add(
        PmcDay(
          date: current,
          ctl: ctl,
          atl: atl,
          tsb: tsb,
          tssOnDay: tss,
        ),
      );

      prevCtl = ctl;
      prevAtl = atl;
      current = current.add(const Duration(days: 1));
    }

    return result;
  }

  /// Normalizes all [dailyTss] keys to UTC midnight and rejects collisions.
  static Map<DateTime, double> _normalizeDailyTss(
    Map<DateTime, double> dailyTss,
  ) {
    final normalized = <DateTime, double>{};
    for (final entry in dailyTss.entries) {
      final key = _toUtcDay(entry.key);
      if (normalized.containsKey(key)) {
        throw ArgumentError(
          'Multiple dailyTss entries normalize to the same UTC day: $key. '
          'The caller must pre-sum daily TSS before passing to PmcCalculator.',
        );
      }
      normalized[key] = entry.value;
    }
    return normalized;
  }

  /// Single source of truth for calendar-day normalization.
  ///
  /// Converts to UTC first so that a local-time instant near midnight
  /// normalizes to the correct UTC calendar day.
  static DateTime _toUtcDay(DateTime dt) {
    final utc = dt.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }
}

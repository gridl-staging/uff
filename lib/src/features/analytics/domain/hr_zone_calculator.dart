import 'package:uff/src/features/analytics/domain/hr_zone.dart';
import 'package:uff/src/features/analytics/domain/sport_type.dart';

/// Computes Friel 7-zone heart rate zones from a lactate threshold heart rate.
///
/// Running and cycling use slightly different zone boundary percentages:
///   Running: Z1 <85%, Z2 85-89%, Z3 90-94%, Z4 95-99%,
///            Z5a 100-102%, Z5b 103-106%, Z5c >106%
///   Cycling: Z1 <81%, Z2 81-89%, Z3 90-93%, Z4 94-99%,
///            Z5a 100-102%, Z5b 103-106%, Z5c >106%
abstract final class HrZoneCalculator {
  static const _labels = ['Z1', 'Z2', 'Z3', 'Z4', 'Z5a', 'Z5b', 'Z5c'];

  // Breakpoints are the start-of-zone percentages for zones 2–6 (Z2–Z5b),
  // stored as exact integer ratios to avoid floating-point floor errors.
  static const _percentScale = 100;
  static const _runBreakPercents = [85, 90, 95, 100, 103];
  static const _rideBreakPercents = [81, 90, 94, 100, 103];

  // Z5b's upper bound is inclusive at 106% of LTHR.
  static const _z5bEndPercent = 106;

  /// Returns [HrZones] with 7 contiguous Friel zones for the given [lthr]
  /// and [sport].
  ///
  /// Zone boundaries are computed as `floor(lthr × percentage)`.
  /// Throws [ArgumentError] if [lthr] is not positive or too low to produce
  /// seven non-empty zones.
  static HrZones forLthr(int lthr, SportType sport) {
    if (lthr <= 0) {
      throw ArgumentError.value(lthr, 'lthr', 'must be positive');
    }

    final breaks = switch (sport) {
      SportType.run => _runBreakPercents,
      SportType.ride => _rideBreakPercents,
    };
    final breakBpms = [
      for (final percent in breaks) _floorPercentOf(lthr, percent),
    ];
    final z5bUpper = _floorPercentOf(lthr, _z5bEndPercent);
    if (!_canBuildSevenNonEmptyZones(breakBpms, z5bUpper)) {
      throw ArgumentError.value(
        lthr,
        'lthr',
        'must be high enough to produce seven non-empty zones',
      );
    }

    final zones = <HrZone>[];
    for (var i = 0; i < 7; i++) {
      final int lowerBpm;
      final int? upperBpm;

      if (i == 0) {
        lowerBpm = 0;
        upperBpm = breakBpms[0] - 1;
      } else if (i <= 4) {
        // Zones 2–5 (Z2–Z5a): lower from previous break, upper from next.
        lowerBpm = breakBpms[i - 1];
        upperBpm = breakBpms[i] - 1;
      } else if (i == 5) {
        // Z5b: lower from last break, upper at 106% inclusive.
        lowerBpm = breakBpms[4];
        upperBpm = z5bUpper;
      } else {
        // Z5c: starts above Z5b, no upper bound.
        lowerBpm = z5bUpper + 1;
        upperBpm = null;
      }

      zones.add(
        HrZone(
          number: i + 1,
          label: _labels[i],
          lowerBpm: lowerBpm,
          upperBpm: upperBpm,
        ),
      );
    }

    return HrZones(lthr: lthr, zones: zones);
  }

  static int _floorPercentOf(int lthr, int percent) =>
      (lthr * percent) ~/ _percentScale;

  static bool _canBuildSevenNonEmptyZones(List<int> breakBpms, int z5bUpper) {
    if (breakBpms.first <= 0) {
      return false;
    }

    for (var i = 1; i < breakBpms.length; i++) {
      if (breakBpms[i] <= breakBpms[i - 1]) {
        return false;
      }
    }

    return z5bUpper > breakBpms.last;
  }
}

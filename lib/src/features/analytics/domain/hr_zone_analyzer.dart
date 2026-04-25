import 'package:uff/src/features/analytics/domain/analytics_point.dart';
import 'package:uff/src/features/analytics/domain/hr_zone.dart';

/// Distributes elapsed time between consecutive points across HR zones.
///
/// Time for an interval [pointN, pointN+1] is attributed to the zone
/// matching pointN's heart rate (previous-sample convention).
/// Points with null [AnalyticsPoint.heartRateBpm] are excluded from zone
/// accounting. Returned total seconds may be less than activity duration
/// when HR data has gaps — this is expected and correct.
abstract final class HrZoneAnalyzer {
  /// Returns a [HrZoneBreakdown] distributing elapsed time across the
  /// provided [zones] based on each point's heart rate.
  static HrZoneBreakdown analyze({
    required List<AnalyticsPoint> points,
    required HrZones zones,
  }) {
    final secondsPerZone = <int, double>{};

    for (var i = 0; i < points.length - 1; i++) {
      final leading = points[i];
      final trailing = points[i + 1];
      final elapsedSeconds =
          trailing.timestamp.difference(leading.timestamp).inMilliseconds /
          1000.0;
      if (elapsedSeconds <= 0) continue;

      final hr = leading.heartRateBpm;
      if (hr == null) continue;

      final zoneNumber = _zoneForBpm(hr, zones);
      if (zoneNumber == null) continue;

      secondsPerZone[zoneNumber] =
          (secondsPerZone[zoneNumber] ?? 0.0) + elapsedSeconds;
    }

    return HrZoneBreakdown(secondsPerZone: secondsPerZone);
  }

  /// Returns the zone number containing [bpm], or null if no zone matches.
  static int? _zoneForBpm(int bpm, HrZones zones) {
    for (final zone in zones.zones) {
      if (bpm >= zone.lowerBpm &&
          (zone.upperBpm == null || bpm <= zone.upperBpm!)) {
        return zone.number;
      }
    }
    return null;
  }
}

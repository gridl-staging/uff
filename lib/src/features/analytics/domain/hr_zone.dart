import 'package:meta/meta.dart';

/// Inclusive heart-rate range representing one training zone.
@immutable
class HrZone {
  const HrZone({
    required this.number,
    required this.label,
    required this.lowerBpm,
    this.upperBpm,
  });

  final int number;
  final String label;
  final int lowerBpm;
  final int? upperBpm;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is HrZone &&
        other.number == number &&
        other.label == label &&
        other.lowerBpm == lowerBpm &&
        other.upperBpm == upperBpm;
  }

  @override
  int get hashCode => Object.hash(number, label, lowerBpm, upperBpm);
}

/// Seven-zone heart-rate model anchored to an athlete's LTHR.
@immutable
class HrZones {
  HrZones({
    required this.lthr,
    required List<HrZone> zones,
  }) : zones = _freezeZones(zones);

  final int lthr;
  final List<HrZone> zones;

  static List<HrZone> _freezeZones(List<HrZone> zones) {
    if (zones.length != 7) {
      throw ArgumentError.value(
        zones.length,
        'zones',
        'must contain exactly 7 zones',
      );
    }
    return List<HrZone>.unmodifiable(zones);
  }
}

@immutable
class HrZoneBreakdown {
  HrZoneBreakdown({
    required Map<int, double> secondsPerZone,
  }) : secondsPerZone = Map<int, double>.unmodifiable(secondsPerZone);

  final Map<int, double> secondsPerZone;

  double get totalSeconds => secondsPerZone.values.fold(
    0,
    (sum, seconds) => sum + seconds,
  );
}

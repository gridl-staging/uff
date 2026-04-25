import 'package:meta/meta.dart';

import 'package:uff/src/features/analytics/domain/sport_type.dart';

/// Athlete-specific thresholds and sport context used by analytics engines.
@immutable
class FitnessProfile {
  const FitnessProfile({
    this.thresholdPaceSecsPerKm,
    this.lthr,
    this.ftpWatts,
    this.riegelExponent = 1.06,
    this.sport = SportType.run,
  });

  final double? thresholdPaceSecsPerKm;
  final int? lthr;
  final int? ftpWatts;
  final double riegelExponent;
  final SportType sport;
}

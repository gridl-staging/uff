import 'package:meta/meta.dart';

enum TssMethod {
  rTSS,
  cTSS,
  simpleTSS,
}

@immutable
class TrainingStressResult {
  const TrainingStressResult({
    required this.tss,
    required this.intensityFactor,
    required this.method,
    this.normalizedEffortSecsPerKm,
  });

  final double tss;
  final double intensityFactor;
  final TssMethod method;
  final double? normalizedEffortSecsPerKm;
}

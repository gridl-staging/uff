import 'package:meta/meta.dart';

@immutable
class PowerCurvePoint {
  const PowerCurvePoint({
    required this.duration,
    required this.avgWatts,
  });

  final Duration duration;
  final double avgWatts;
}

import 'package:test/test.dart';
import 'package:uff/src/features/analytics/domain/race_prediction.dart';
import 'package:uff/src/features/analytics/domain/vdot_calculator.dart';

void main() {
  group('VdotCalculator.estimate()', () {
    test('5K in 20:00 → VDOT closeTo 49.8', () {
      const result = RaceResult(
        distanceMeters: 5000,
        duration: Duration(seconds: 1200),
      );

      final vdot = VdotCalculator.estimate(result);

      expect(vdot, closeTo(49.8, 0.1));
    });

    test('1500m in 4:20 → VDOT closeTo 64.0', () {
      const result = RaceResult(
        distanceMeters: 1500,
        duration: Duration(seconds: 260),
      );

      final vdot = VdotCalculator.estimate(result);

      expect(vdot, closeTo(64.0, 0.5));
    });

    test('distance ≤ 0 throws ArgumentError', () {
      expect(
        () => VdotCalculator.estimate(
          const RaceResult(
            distanceMeters: 0,
            duration: Duration(seconds: 1200),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => VdotCalculator.estimate(
          const RaceResult(
            distanceMeters: -100,
            duration: Duration(seconds: 1200),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('duration zero throws ArgumentError', () {
      expect(
        () => VdotCalculator.estimate(
          const RaceResult(
            distanceMeters: 5000,
            duration: Duration.zero,
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('regression', () {
    test('400m sprint produces finite positive VDOT', () {
      const result = RaceResult(
        distanceMeters: 400,
        duration: Duration(seconds: 50),
      );

      final vdot = VdotCalculator.estimate(result);

      expect(vdot, isPositive);
      expect(vdot.isFinite, isTrue);
    });

    test('marathon produces finite positive VDOT', () {
      const result = RaceResult(
        distanceMeters: 42195,
        duration: Duration(hours: 3, minutes: 30),
      );

      final vdot = VdotCalculator.estimate(result);

      expect(vdot, isPositive);
      expect(vdot.isFinite, isTrue);
    });
  });
}

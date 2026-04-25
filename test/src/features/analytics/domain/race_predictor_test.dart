import 'package:test/test.dart';
import 'package:uff/src/features/analytics/domain/race_prediction.dart';
import 'package:uff/src/features/analytics/domain/race_predictor.dart';

void main() {
  group('RacePredictor.predictTime()', () {
    test('5K/20:00 → marathon closeTo 11509s with exponent 1.06', () {
      const reference = RaceResult(
        distanceMeters: 5000,
        duration: Duration(seconds: 1200),
      );

      final predicted = RacePredictor.predictTime(reference, 42195);

      // Dart's pow(42195/5000, 1.06) gives 9.59110... → 11509.3s
      expect(predicted.inSeconds, closeTo(11509, 1));
    });

    test('5K/20:00 → 10K closeTo 2502s with exponent 1.06', () {
      const reference = RaceResult(
        distanceMeters: 5000,
        duration: Duration(seconds: 1200),
      );

      final predicted = RacePredictor.predictTime(reference, 10000);

      expect(predicted.inSeconds, closeTo(2502, 1));
    });

    test('exponent=1.0 gives linear scaling (constant speed)', () {
      const reference = RaceResult(
        distanceMeters: 5000,
        duration: Duration(seconds: 1200),
      );

      final predicted = RacePredictor.predictTime(
        reference,
        10000,
        exponent: 1,
      );

      expect(predicted, const Duration(seconds: 2400));
    });

    test('distance ≤ 0 throws ArgumentError', () {
      const reference = RaceResult(
        distanceMeters: 5000,
        duration: Duration(seconds: 1200),
      );

      expect(
        () => RacePredictor.predictTime(reference, 0),
        throwsArgumentError,
      );
      expect(
        () => RacePredictor.predictTime(reference, -100),
        throwsArgumentError,
      );
    });

    test('reference distance ≤ 0 throws ArgumentError', () {
      const reference = RaceResult(
        distanceMeters: 0,
        duration: Duration(seconds: 1200),
      );

      expect(
        () => RacePredictor.predictTime(reference, 10000),
        throwsArgumentError,
      );
    });

    test('reference duration zero throws ArgumentError', () {
      const reference = RaceResult(
        distanceMeters: 5000,
        duration: Duration.zero,
      );

      expect(
        () => RacePredictor.predictTime(reference, 10000),
        throwsArgumentError,
      );
    });
  });

  group('RacePredictor.predictStandardRaces()', () {
    test('5K/20:00 → 5 predictions for longer standard races', () {
      const reference = RaceResult(
        distanceMeters: 5000,
        duration: Duration(seconds: 1200),
      );

      final predictions = RacePredictor.predictStandardRaces(reference);

      expect(predictions, hasLength(5));

      // Verify labels and distances match StandardRaces.all entries > 5000m
      expect(predictions[0].label, '10 km');
      expect(predictions[0].distanceMeters, 10000.0);
      expect(predictions[1].label, '15 km');
      expect(predictions[1].distanceMeters, 15000.0);
      expect(predictions[2].label, 'Half Marathon');
      expect(predictions[2].distanceMeters, 21097.5);
      expect(predictions[3].label, '30 km');
      expect(predictions[3].distanceMeters, 30000.0);
      expect(predictions[4].label, 'Marathon');
      expect(predictions[4].distanceMeters, 42195.0);
    });

    test('marathon reference → empty list', () {
      const reference = RaceResult(
        distanceMeters: 42195,
        duration: Duration(seconds: 11513),
      );

      final predictions = RacePredictor.predictStandardRaces(reference);

      expect(predictions, isEmpty);
    });

    test('intensityFactor equals predictedSpeed / referenceSpeed', () {
      const reference = RaceResult(
        distanceMeters: 5000,
        duration: Duration(seconds: 1200),
      );
      final referenceSpeed =
          reference.distanceMeters / reference.duration.inSeconds;

      final predictions = RacePredictor.predictStandardRaces(reference);

      for (final prediction in predictions) {
        final predictedSpeed =
            prediction.distanceMeters / prediction.predictedTime.inSeconds;
        final expectedIf = predictedSpeed / referenceSpeed;
        expect(
          prediction.intensityFactor,
          closeTo(expectedIf, 0.01),
          reason: '${prediction.label} IF should match speed ratio',
        );
      }

      // Marathon IF specifically closeTo 0.880
      final marathon = predictions.last;
      expect(marathon.intensityFactor, closeTo(0.880, 0.005));
    });
  });

  group('regression', () {
    test('same distance yields same duration (identity)', () {
      const reference = RaceResult(
        distanceMeters: 10000,
        duration: Duration(minutes: 42),
      );

      final predicted = RacePredictor.predictTime(reference, 10000);

      expect(predicted, reference.duration);
    });

    test('exactly 5000m reference excludes 5K from standard races', () {
      const reference = RaceResult(
        distanceMeters: 5000,
        duration: Duration(seconds: 1200),
      );

      final predictions = RacePredictor.predictStandardRaces(reference);

      expect(
        predictions.every((p) => p.distanceMeters > 5000),
        isTrue,
      );
      expect(predictions.any((p) => p.label == '5 km'), isFalse);
    });
  });
}

import 'package:test/test.dart';
import 'package:uff/src/features/analytics/domain/race_prediction.dart';
import 'package:uff/src/features/analytics/domain/race_predictor.dart';
import 'package:uff/src/features/analytics/domain/vdot_calculator.dart';

import '../../../../fixtures/fixture_loader.dart';

const Map<String, double> _expectedPredictionSecondsByLabel = <String, double>{
  '15 km': 3685.529,
  'Half Marathon': 5290.881,
  '30 km': 7684.076,
  'Marathon': 11031.124,
};

const double _expectedVdot = 51.995361;

RaceResult _buildHilly10kResultFromManifest() {
  final expected = loadExpectedFixture('hilly_10k');
  return RaceResult(
    distanceMeters: (expected['plannedDistanceMeters'] as num).toDouble(),
    duration: Duration(seconds: (expected['elapsedSeconds'] as num).toInt()),
  );
}

void main() {
  group('fixture prediction accuracy', () {
    test(
      'hilly_10k manifest result matches expected race predictions and VDOT',
      () {
        final reference = _buildHilly10kResultFromManifest();
        final predictions = RacePredictor.predictStandardRaces(reference);
        final vdot = VdotCalculator.estimate(reference);

        final predictionsByLabel = <String, RacePrediction>{
          for (final prediction in predictions) prediction.label: prediction,
        };
        expect(
          predictionsByLabel.keys.toSet(),
          _expectedPredictionSecondsByLabel.keys.toSet(),
        );

        for (final expected in _expectedPredictionSecondsByLabel.entries) {
          // key set equality above guarantees this lookup is non-null
          final prediction = predictionsByLabel[expected.key]!;

          final actualSeconds =
              prediction.predictedTime.inMicroseconds /
              Duration.microsecondsPerSecond;
          expect(actualSeconds, closeTo(expected.value, 1e-3));
        }

        expect(vdot, closeTo(_expectedVdot, 1e-6));
      },
    );
  });
}

import 'package:test/test.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing.dart';

import '../../../../fixtures/fixture_loader.dart';

void main() {
  group('fixture metrics accuracy', () {
    test('hilly_10k distance and elevation match fixture manifest', () async {
      final points = await loadFixtureTrackingPoints('hilly_10k');
      final expected = loadExpectedFixture('hilly_10k');

      final measuredDistanceMeters = calculateTrackDistanceMeters(points);
      final measuredElevationGainMeters = calculateElevationGainMeters(points);
      final expectedDistanceMeters = (expected['plannedDistanceMeters'] as num)
          .toDouble();
      final expectedElevationGainMeters =
          (expected['elevationGainMeters'] as num).toDouble();

      // Distance tolerance accounts for geodesic rounding on 7-decimal fixture coordinates.
      expect(measuredDistanceMeters, closeTo(expectedDistanceMeters, 25));
      // Elevation tolerance reflects >=1.0m delta filtering plus 2-decimal elevation rounding.
      expect(
        measuredElevationGainMeters,
        closeTo(expectedElevationGainMeters, 0.5),
      );
    });

    test('long_easy_run distance and pace align with fixture manifest', () async {
      final points = await loadFixtureTrackingPoints('long_easy_run');
      final expected = loadExpectedFixture('long_easy_run');

      final measuredDistanceMeters = calculateTrackDistanceMeters(points);
      final movingTime = Duration(
        seconds: (expected['movingSeconds'] as num).toInt(),
      );
      final measuredPace = calculatePacePerKilometer(
        distanceMeters: measuredDistanceMeters,
        elapsedTime: movingTime,
      );
      final expectedDistanceMeters = (expected['plannedDistanceMeters'] as num)
          .toDouble();
      final expectedPaceSecondsPerKm = (expected['paceSecondsPerKm'] as num)
          .toDouble();

      // Distance tolerance accounts for haversine accumulation over rounded coordinates.
      expect(measuredDistanceMeters, closeTo(expectedDistanceMeters, 25));
      // Pace tolerance covers floored Duration output plus rounded fixture coordinates.
      expect(
        measuredPace!.inSeconds.toDouble(),
        closeTo(expectedPaceSecondsPerKm, 1.0),
      );
    });

    test('interval_workout pace remains anchored to shared manifest', () async {
      final points = await loadFixtureTrackingPoints('interval_workout');
      final expected = loadExpectedFixture('interval_workout');

      final measuredDistanceMeters = calculateTrackDistanceMeters(points);
      final movingTime = Duration(
        seconds: (expected['movingSeconds'] as num).toInt(),
      );
      final measuredPace = calculatePacePerKilometer(
        distanceMeters: measuredDistanceMeters,
        elapsedTime: movingTime,
      );
      final expectedPaceSecondsPerKm = (expected['paceSecondsPerKm'] as num)
          .toDouble();

      // Pace tolerance covers floored Duration output plus geodesic-distance rounding.
      expect(
        measuredPace!.inSeconds.toDouble(),
        closeTo(expectedPaceSecondsPerKm, 1.0),
      );
    });

    test(
      'auto_pause_test windows and moving time match fixture manifest',
      () async {
        final points = await loadFixtureTrackingPoints('auto_pause_test');
        final expected = loadExpectedFixture('auto_pause_test');
        final autoPause = classifyAutoPauseWindows(points);
        final stoppedWindowCount = autoPause.windows
            .where((window) => window.state == AutoPauseState.stopped)
            .length;

        // Fixture generator uses deterministic move/pause scheduling for exact window count.
        expect(stoppedWindowCount, expected['pauseWindowCount']);
        expect(
          autoPause.totalMovingDuration.inSeconds,
          expected['movingSeconds'],
        );
      },
    );
  });
}

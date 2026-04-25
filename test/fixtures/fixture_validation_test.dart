import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/domain/auto_pause.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/elevation_gain.dart';
import 'package:uff/src/features/activity_tracking/domain/track_metrics.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

import '../../e2e_test/fixtures.dart';
import 'fixture_loader.dart';

/// Smoke and validation tests for all fixture files in the shared fixture tree.
///
/// Verifies that every generated fixture (plus the existing 5k_run.json) can
/// be parsed, has a non-empty point list, and contains field values in
/// reasonable physical ranges.
///
/// ## Test Scenarios
/// - `[positive]` Every fixture parses and matches manifest point counts.
/// - `[positive]` GPS and sensor fields remain within physical ranges.
/// - `[edge]` Auto-pause fixtures always include both stationary and moving phases.
/// - `[statemachine]` Manifest summaries stay aligned with derived fixture metrics.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> manifest;

  setUpAll(() {
    manifest = loadExpectedMetrics();
  });

  group(
    'fixture smoke tests — all fixtures parse with correct point counts',
    () {
      for (final fixtureName in fixturePathsByName.keys) {
        test(
          '$fixtureName.json loads and matches manifest point count',
          () async {
            await _expectFixtureMatchesManifestPointCount(
              fixtureName,
              manifest,
            );
          },
        );
      }
    },
  );

  group('fixture validation — field ranges are physically reasonable', () {
    test('all fixtures have valid latitude/longitude/timestamp', () async {
      for (final entry in fixturePathsByName.entries) {
        final points = await loadFixturePoints(entry.value, sessionId: 1);

        for (final point in points) {
          expect(
            point.coordinate.latitude,
            inInclusiveRange(-90, 90),
            reason: '${entry.value}: latitude out of range',
          );
          expect(
            point.coordinate.longitude,
            inInclusiveRange(-180, 180),
            reason: '${entry.value}: longitude out of range',
          );
          expect(
            point.timestamp.isAfter(DateTime(2020)),
            isTrue,
            reason: '${entry.value}: timestamp too old',
          );
        }
      }
    });

    test('hilly_10k has non-null elevation on all points', () async {
      final points = await _loadFixturePoints('hilly_10k');
      final missingElevationCount = points
          .where((point) => point.elevation == null)
          .length;
      expect(
        missingElevationCount,
        0,
        reason: 'hilly_10k: elevation must be present for every point',
      );
    });

    test('interval_workout has non-null HR on all points', () async {
      final points = await _loadFixturePoints('interval_workout');
      final heartRates = points
          .map((point) => point.heartRateBpm)
          .whereType<int>()
          .toList(growable: false);
      final missingHeartRateCount = points.length - heartRates.length;
      expect(
        missingHeartRateCount,
        0,
        reason: 'interval_workout: HR must be present for every point',
      );

      for (final heartRate in heartRates) {
        expect(
          heartRate,
          inInclusiveRange(100, 200),
          reason: 'interval_workout: HR out of physiological range',
        );
      }
    });

    test('long_easy_run has HR, cadence, and power on all points', () async {
      final points = await _loadFixturePoints('long_easy_run');
      final missingHeartRateCount = points
          .where((point) => point.heartRateBpm == null)
          .length;
      final missingCadenceCount = points
          .where((point) => point.cadenceRpm == null)
          .length;
      final missingPowerCount = points
          .where((point) => point.powerWatts == null)
          .length;

      expect(missingHeartRateCount, 0);
      expect(missingCadenceCount, 0);
      expect(missingPowerCount, 0);
    });

    test('auto_pause_test has stationary points with speed 0', () async {
      final points = await _loadFixturePoints('auto_pause_test');
      final stationaryCount = points.where((p) => p.speed == 0.0).length;
      final movingCount = points.where((p) => (p.speed ?? 0) > 0).length;

      expect(stationaryCount + movingCount, points.length);
      expect(
        stationaryCount == 0,
        isFalse,
        reason: 'auto_pause_test: must include at least one stationary point',
      );
      expect(
        movingCount == 0,
        isFalse,
        reason: 'auto_pause_test: must include at least one moving point',
      );
    });
  });

  group('manifest consistency', () {
    test('manifest contains entries for all 5 fixtures', () {
      expect(manifest, hasLength(5));
      expect(manifest.keys.toSet(), fixturePathsByName.keys.toSet());
    });

    test('hilly_10k manifest reports elevation gain >= 150m', () {
      final hilly = manifest['hilly_10k'] as Map<String, dynamic>;
      expect(
        hilly['elevationGainMeters'] as num,
        greaterThanOrEqualTo(150),
      );
    });

    test('auto_pause manifest reports >= 2 pause windows', () {
      final autoPause = manifest['auto_pause_test'] as Map<String, dynamic>;
      expect(autoPause['pauseWindowCount'] as int, greaterThanOrEqualTo(2));
    });

    test('auto_pause manifest moving time < elapsed time', () {
      final autoPause = manifest['auto_pause_test'] as Map<String, dynamic>;
      expect(
        autoPause['movingSeconds'] as int,
        lessThan(autoPause['elapsedSeconds'] as int),
      );
    });

    test(
      'auto_pause classifier matches manifest pause count and moving time',
      () async {
        final points = await _loadFixturePoints('auto_pause_test');
        final manifestEntry =
            manifest['auto_pause_test'] as Map<String, dynamic>;
        final autoPause = classifyAutoPauseWindows(points);
        final stoppedWindowCount = autoPause.windows
            .where((window) => window.state == AutoPauseState.stopped)
            .length;

        expect(stoppedWindowCount, manifestEntry['pauseWindowCount']);
        expect(
          autoPause.totalMovingDuration.inSeconds,
          manifestEntry['movingSeconds'],
        );
      },
    );

    test('interval_workout manifest reports >= 5 segments', () {
      final interval = manifest['interval_workout'] as Map<String, dynamic>;
      expect(
        interval['intervalSegmentCount'] as int,
        greaterThanOrEqualTo(5),
      );
    });

    test(
      'hilly_10k fixture elevation gain from points stays above threshold',
      () async {
        final points = await _loadFixturePoints('hilly_10k');
        final measuredGainMeters = calculateElevationGainMeters(points);

        expect(measuredGainMeters, greaterThanOrEqualTo(150));
      },
    );

    test(
      'interval_workout manifest pace matches fixture-derived pace',
      () async {
        final points = await _loadFixturePoints('interval_workout');
        final manifestEntry =
            manifest['interval_workout'] as Map<String, dynamic>;
        final expectedPaceSecondsPerKm =
            (manifestEntry['paceSecondsPerKm'] as num).toDouble();

        final distanceMeters = calculateTrackDistanceMeters(points);
        final elapsed = calculateElapsedTime(points);
        final measuredPaceSecondsPerKm =
            elapsed.inSeconds / (distanceMeters / 1000);

        expect(
          measuredPaceSecondsPerKm,
          closeTo(expectedPaceSecondsPerKm, 0.05),
        );
      },
    );
  });
}

Future<List<TrackingPoint>> _loadFixturePoints(String fixtureName) {
  return loadFixturePoints(fixturePathsByName[fixtureName]!, sessionId: 1);
}

Future<void> _expectFixtureMatchesManifestPointCount(
  String fixtureName,
  Map<String, dynamic> manifest,
) async {
  final points = await _loadFixturePoints(fixtureName);
  final expected = manifest[fixtureName] as Map<String, dynamic>;

  expect(points.length, expected['pointCount']);
}

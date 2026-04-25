import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/import/domain/import_normalizer.dart';
import 'package:uff/src/features/import/domain/imported_activity.dart';

const _baseTimestamp = 1704067200; // 2024-01-01T00:00:00Z epoch seconds

ImportedPoint _importedPointAt({
  required int seconds,
  required double metersFromOrigin,
  double? elevation,
  double? speed,
  int? heartRateBpm,
  double? cadenceRpm,
  int? powerWatts,
}) {
  const metersPerDegreeAtEquator =
      earthRadiusMeters * (3.141592653589793 / 180);

  return ImportedPoint(
    latitude: 0,
    longitude: metersFromOrigin / metersPerDegreeAtEquator,
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      (_baseTimestamp + seconds) * 1000,
      isUtc: true,
    ),
    elevation: elevation,
    speed: speed,
    heartRateBpm: heartRateBpm,
    cadenceRpm: cadenceRpm,
    powerWatts: powerWatts,
  );
}

void main() {
  group('normalizeImportedActivity', () {
    test('converts imported points through pipeline and returns metrics', () {
      final parsed = ParsedActivityData(
        sportType: 'run',
        points: [
          _importedPointAt(seconds: 0, metersFromOrigin: 0, elevation: 10),
          _importedPointAt(seconds: 600, metersFromOrigin: 1000, elevation: 20),
          _importedPointAt(
            seconds: 1200,
            metersFromOrigin: 2000,
            elevation: 30,
          ),
        ],
      );

      final result = normalizeImportedActivity(parsed);

      expect(result.sportType, 'run');
      expect(result.cleanedPoints, hasLength(3));
      expect(result.metrics.trackSummary.distanceMeters, closeTo(2000, 0.5));
      expect(
        result.metrics.trackSummary.movingTime,
        const Duration(minutes: 20),
      );
      expect(
        result.metrics.trackSummary.elevationGainMeters,
        closeTo(20, 0.01),
      );
      expect(result.metrics.splits, hasLength(2));
    });

    test('derives startedAt/finishedAt from point timestamps when absent', () {
      final parsed = ParsedActivityData(
        sportType: 'run',
        points: [
          _importedPointAt(seconds: 0, metersFromOrigin: 0),
          _importedPointAt(seconds: 300, metersFromOrigin: 500),
          _importedPointAt(seconds: 600, metersFromOrigin: 1000),
        ],
      );

      final result = normalizeImportedActivity(parsed);

      expect(
        result.startedAt,
        DateTime.fromMillisecondsSinceEpoch(
          _baseTimestamp * 1000,
          isUtc: true,
        ),
      );
      expect(
        result.finishedAt,
        DateTime.fromMillisecondsSinceEpoch(
          (_baseTimestamp + 600) * 1000,
          isUtc: true,
        ),
      );
    });

    test('uses parser-level session timestamps when provided', () {
      final sessionStart = DateTime.utc(2024, 1, 1, 8);
      final sessionEnd = DateTime.utc(2024, 1, 1, 9);

      final parsed = ParsedActivityData(
        sportType: 'ride',
        points: [
          _importedPointAt(seconds: 0, metersFromOrigin: 0),
          _importedPointAt(seconds: 600, metersFromOrigin: 1000),
        ],
        startedAt: sessionStart,
        finishedAt: sessionEnd,
      );

      final result = normalizeImportedActivity(parsed);

      expect(result.startedAt, sessionStart);
      expect(result.finishedAt, sessionEnd);
    });

    test('preserves title from parsed data', () {
      final parsed = ParsedActivityData(
        sportType: 'run',
        title: 'Morning Run',
        points: [
          _importedPointAt(seconds: 0, metersFromOrigin: 0),
          _importedPointAt(seconds: 600, metersFromOrigin: 1000),
        ],
      );

      final result = normalizeImportedActivity(parsed);

      expect(result.title, 'Morning Run');
    });

    test('cleaned points have valid coordinates matching input', () {
      final parsed = ParsedActivityData(
        sportType: 'run',
        points: [
          _importedPointAt(
            seconds: 0,
            metersFromOrigin: 0,
            elevation: 100,
            speed: 3,
          ),
          _importedPointAt(
            seconds: 600,
            metersFromOrigin: 1000,
            elevation: 110,
            speed: 3.5,
          ),
        ],
      );

      final result = normalizeImportedActivity(parsed);

      expect(result.cleanedPoints.first.latitude, 0);
      expect(result.cleanedPoints.first.elevation, 100);
      expect(result.cleanedPoints.first.speed, 3.0);
      expect(result.cleanedPoints.last.elevation, 110);
      expect(result.cleanedPoints.last.speed, 3.5);
    });

    test('cleaned point count matches metrics input', () {
      final parsed = ParsedActivityData(
        sportType: 'run',
        points: [
          _importedPointAt(seconds: 0, metersFromOrigin: 0),
          _importedPointAt(seconds: 300, metersFromOrigin: 500),
          _importedPointAt(seconds: 600, metersFromOrigin: 1000),
          _importedPointAt(seconds: 900, metersFromOrigin: 1500),
          _importedPointAt(seconds: 1200, metersFromOrigin: 2000),
        ],
      );

      final result = normalizeImportedActivity(parsed);

      // The cleaned points used for metrics should be the same list returned
      expect(result.cleanedPoints, hasLength(5));
      expect(result.metrics.trackSummary.distanceMeters, closeTo(2000, 0.5));
    });
  });

  group('normalizeImportedActivity edge cases', () {
    test('empty point list throws FormatException', () {
      const parsed = ParsedActivityData(
        sportType: 'run',
        points: [],
      );

      expect(
        () => normalizeImportedActivity(parsed),
        throwsA(isA<FormatException>()),
      );
    });

    test('single point produces zero distance and zero splits', () {
      final parsed = ParsedActivityData(
        sportType: 'run',
        points: [
          _importedPointAt(seconds: 0, metersFromOrigin: 0, elevation: 50),
        ],
      );

      final result = normalizeImportedActivity(parsed);

      expect(result.cleanedPoints, hasLength(1));
      expect(result.metrics.trackSummary.distanceMeters, 0);
      expect(result.metrics.splits, isEmpty);
      expect(result.startedAt, result.finishedAt);
    });

    test('all-duplicate timestamps produce a single cleaned point', () {
      final sameTime = DateTime.utc(2024, 1, 1, 12);
      final parsed = ParsedActivityData(
        sportType: 'run',
        points: [
          ImportedPoint(
            latitude: 0,
            longitude: 0,
            timestamp: sameTime,
          ),
          ImportedPoint(
            latitude: 0,
            longitude: 0.001,
            timestamp: sameTime,
          ),
          ImportedPoint(
            latitude: 0,
            longitude: 0.002,
            timestamp: sameTime,
          ),
        ],
      );

      final result = normalizeImportedActivity(parsed);

      expect(result.cleanedPoints, hasLength(1));
      expect(result.metrics.trackSummary.distanceMeters, 0);
    });

    test('geometric fields survive cleanup pipeline', () {
      final parsed = ParsedActivityData(
        sportType: 'run',
        points: [
          _importedPointAt(
            seconds: 0,
            metersFromOrigin: 0,
            elevation: 100,
            speed: 3,
          ),
          _importedPointAt(
            seconds: 300,
            metersFromOrigin: 500,
            elevation: 120,
            speed: 3.5,
          ),
          _importedPointAt(
            seconds: 600,
            metersFromOrigin: 1000,
            elevation: 140,
            speed: 4,
          ),
        ],
      );

      final result = normalizeImportedActivity(parsed);

      expect(result.cleanedPoints, hasLength(3));
      // Elevation survives
      expect(result.cleanedPoints[0].elevation, 100);
      expect(result.cleanedPoints[1].elevation, 120);
      expect(result.cleanedPoints[2].elevation, 140);
      // Speed survives
      expect(result.cleanedPoints[0].speed, 3.0);
      expect(result.cleanedPoints[1].speed, 3.5);
      expect(result.cleanedPoints[2].speed, 4.0);
      // Coordinates survive
      expect(result.cleanedPoints[0].latitude, 0);
      expect(result.cleanedPoints[2].latitude, 0);
    });

    test('outlier points are dropped by cleanup pipeline', () {
      final parsed = ParsedActivityData(
        sportType: 'run',
        points: [
          _importedPointAt(seconds: 0, metersFromOrigin: 0),
          _importedPointAt(seconds: 1, metersFromOrigin: 1.5),
          _importedPointAt(seconds: 2, metersFromOrigin: 2.1),
          // Impossible jump — exceeds max plausible speed
          _importedPointAt(seconds: 3, metersFromOrigin: 1000),
          _importedPointAt(seconds: 120, metersFromOrigin: 1005),
        ],
      );

      final result = normalizeImportedActivity(parsed);

      // The outlier at t=3 should be dropped
      expect(result.cleanedPoints, hasLength(4));
    });

    test(
      'derives finishedAt from parsed timestamps when cleanup drops the trailing endpoint',
      () {
        final parsed = ParsedActivityData(
          sportType: 'run',
          points: [
            _importedPointAt(seconds: 0, metersFromOrigin: 0),
            _importedPointAt(seconds: 1, metersFromOrigin: 1000),
            _importedPointAt(seconds: 120, metersFromOrigin: 1005),
            _importedPointAt(seconds: 121, metersFromOrigin: 2005),
          ],
        );

        final result = normalizeImportedActivity(parsed);

        expect(
          result.finishedAt,
          DateTime.fromMillisecondsSinceEpoch(
            (_baseTimestamp + 121) * 1000,
            isUtc: true,
          ),
        );
        expect(result.cleanedPoints, hasLength(2));
        expect(result.cleanedPoints.last.timestamp, isNot(result.finishedAt));
      },
    );
  });
}

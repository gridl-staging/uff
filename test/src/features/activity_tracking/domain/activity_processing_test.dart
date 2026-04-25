import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

const _sessionId = 77;

TrackingPoint _pointAtMeters({
  required int seconds,
  required double metersFromOrigin,
  double? elevation,
}) {
  const metersPerDegreeAtEquator =
      earthRadiusMeters * (3.141592653589793 / 180);

  return TrackingPoint(
    sessionId: _sessionId,
    timestamp: DateTime.utc(2025).add(Duration(seconds: seconds)),
    coordinate: GeoCoordinate(
      latitude: 0,
      longitude: metersFromOrigin / metersPerDegreeAtEquator,
    ),
    elevation: elevation,
  );
}

void main() {
  group('calculateGeodesicDistanceMeters', () {
    test('returns zero for identical coordinates', () {
      const coordinate = GeoCoordinate(latitude: 40.7128, longitude: -74.0060);

      final distance = calculateGeodesicDistanceMeters(coordinate, coordinate);

      expect(distance, 0);
    });

    test('matches known Nashville to Los Angeles example within tolerance', () {
      const nashville = GeoCoordinate(latitude: 36.12, longitude: -86.67);
      const losAngeles = GeoCoordinate(latitude: 33.94, longitude: -118.40);

      final distance = calculateGeodesicDistanceMeters(nashville, losAngeles);

      expect(distance, closeTo(2886449.0, 3000));
    });

    test('is accurate for a short local movement', () {
      const start = GeoCoordinate(latitude: 40.7128, longitude: -74.0060);
      const end = GeoCoordinate(latitude: 40.71285, longitude: -74.0060);

      final distance = calculateGeodesicDistanceMeters(start, end);

      expect(distance, closeTo(5.56, 0.5));
    });
  });

  group('cleanTrackingPoints', () {
    test(
      'sorts unsorted timestamps and rejects duplicate-timestamp samples',
      () {
        final points = [
          _pointAtMeters(seconds: 10, metersFromOrigin: 20),
          _pointAtMeters(seconds: 5, metersFromOrigin: 10),
          _pointAtMeters(seconds: 5, metersFromOrigin: 11),
          _pointAtMeters(seconds: 20, metersFromOrigin: 20),
        ];

        final result = cleanTrackingPoints(points);

        expect(result.cleanedPoints.map((point) => point.timestamp.second), [
          5,
          10,
          20,
        ]);
        expect(result.droppedDuplicateCount, 1);
        expect(result.droppedOutlierCount, 0);
      },
    );

    test(
      'keeps the earliest input sample when duplicate timestamps are dropped',
      () {
        final firstDuplicate = _pointAtMeters(seconds: 5, metersFromOrigin: 10);
        final secondDuplicate = _pointAtMeters(
          seconds: 5,
          metersFromOrigin: 11,
        );
        final points = [
          _pointAtMeters(seconds: 10, metersFromOrigin: 20),
          firstDuplicate,
          secondDuplicate,
        ];

        final result = cleanTrackingPoints(points);

        expect(result.cleanedPoints, hasLength(2));
        expect(result.cleanedPoints.first.longitude, firstDuplicate.longitude);
        expect(
          result.cleanedPoints.first.longitude,
          isNot(secondDuplicate.longitude),
        );
      },
    );

    test('preserves same-coordinate samples with different timestamps', () {
      final points = [
        _pointAtMeters(seconds: 0, metersFromOrigin: 100),
        _pointAtMeters(seconds: 30, metersFromOrigin: 100),
        _pointAtMeters(seconds: 60, metersFromOrigin: 100),
        _pointAtMeters(seconds: 90, metersFromOrigin: 200),
      ];

      final result = cleanTrackingPoints(points);

      expect(result.cleanedPoints, hasLength(4));
      expect(result.droppedDuplicateCount, 0);
      expect(result.droppedOutlierCount, 0);
    });

    test('keeps stationary jitter and removes one impossible jump', () {
      final points = [
        _pointAtMeters(seconds: 0, metersFromOrigin: 0),
        _pointAtMeters(seconds: 1, metersFromOrigin: 1.5),
        _pointAtMeters(seconds: 2, metersFromOrigin: 2.1),
        _pointAtMeters(seconds: 3, metersFromOrigin: 1000),
        _pointAtMeters(seconds: 120, metersFromOrigin: 1005),
      ];

      final result = cleanTrackingPoints(points);

      expect(result.cleanedPoints, hasLength(4));
      expect(result.droppedOutlierCount, 1);
      expect(
        result.cleanedPoints.map((point) => point.timestamp.second),
        [0, 1, 2, 0],
      );
    });

    test('preserves mixed valid sequence after dropping invalid sample', () {
      final points = [
        _pointAtMeters(seconds: 0, metersFromOrigin: 0),
        _pointAtMeters(seconds: 10, metersFromOrigin: 30),
        _pointAtMeters(seconds: 11, metersFromOrigin: 700),
        _pointAtMeters(seconds: 120, metersFromOrigin: 720),
        _pointAtMeters(seconds: 180, metersFromOrigin: 800),
      ];

      final result = cleanTrackingPoints(points);

      expect(result.cleanedPoints, hasLength(4));
      expect(result.droppedOutlierCount, 1);
      expect(result.cleanedPoints.last.timestamp.second, 0);
    });
  });

  group('track distance, elapsed time, and pace', () {
    test('accumulates track distance over cleaned points', () {
      final points = [
        _pointAtMeters(seconds: 0, metersFromOrigin: 0),
        _pointAtMeters(seconds: 30, metersFromOrigin: 100),
        _pointAtMeters(seconds: 60, metersFromOrigin: 200),
      ];

      final distance = calculateTrackDistanceMeters(points);

      expect(distance, closeTo(200, 0.5));
    });

    test(
      'returns zero elapsed time for empty single-point and malformed order',
      () {
        final emptyElapsed = calculateElapsedTime(const []);
        final singleElapsed = calculateElapsedTime([
          _pointAtMeters(seconds: 0, metersFromOrigin: 0),
        ]);
        final malformedElapsed = calculateElapsedTime([
          _pointAtMeters(seconds: 10, metersFromOrigin: 0),
          _pointAtMeters(seconds: 5, metersFromOrigin: 10),
        ]);

        expect(emptyElapsed, Duration.zero);
        expect(singleElapsed, Duration.zero);
        expect(malformedElapsed, Duration.zero);
      },
    );

    test('calculates kilometer and mile pace with zero guards', () {
      const elapsed = Duration(minutes: 50);
      final kilometerPace = calculatePacePerKilometer(
        distanceMeters: 10000,
        elapsedTime: elapsed,
      );
      final milePace = calculatePacePerMile(
        distanceMeters: 10000,
        elapsedTime: elapsed,
      );
      final missingForZeroDistance = calculatePacePerKilometer(
        distanceMeters: 0,
        elapsedTime: elapsed,
      );
      final missingForZeroDuration = calculatePacePerMile(
        distanceMeters: 10000,
        elapsedTime: Duration.zero,
      );

      expect(kilometerPace, const Duration(minutes: 5));
      expect(milePace, const Duration(minutes: 8, seconds: 2));
      expect(missingForZeroDistance, isNull);
      expect(missingForZeroDuration, isNull);
    });
  });

  group('generateSplits', () {
    test('emits split for exact boundary hit', () {
      final points = [
        _pointAtMeters(seconds: 0, metersFromOrigin: 0),
        _pointAtMeters(seconds: 600, metersFromOrigin: 1000),
      ];

      final splits = generateSplits(
        cleanedPoints: points,
        splitUnit: SplitUnit.kilometer,
      );

      expect(splits, hasLength(1));
      expect(splits.first.index, 1);
      expect(splits.first.cumulativeDistanceMeters, closeTo(1000, 0.1));
      expect(splits.first.splitDuration, const Duration(minutes: 10));
      expect(splits.first.pace, const Duration(minutes: 10));
    });

    test('interpolates boundary crossing when segment overshoots', () {
      final points = [
        _pointAtMeters(seconds: 0, metersFromOrigin: 0),
        _pointAtMeters(seconds: 720, metersFromOrigin: 1200),
      ];

      final splits = generateSplits(
        cleanedPoints: points,
        splitUnit: SplitUnit.kilometer,
      );

      expect(splits, hasLength(1));
      expect(splits.first.splitDuration, const Duration(minutes: 10));
      expect(splits.first.cumulativeDuration, const Duration(minutes: 10));
    });

    test('emits multiple splits and drops partial trailing distance', () {
      final points = [
        _pointAtMeters(seconds: 0, metersFromOrigin: 0),
        _pointAtMeters(seconds: 1500, metersFromOrigin: 2500),
      ];

      final splits = generateSplits(
        cleanedPoints: points,
        splitUnit: SplitUnit.kilometer,
      );

      expect(splits, hasLength(2));
      expect(splits.first.splitDuration, const Duration(minutes: 10));
      expect(splits.last.splitDuration, const Duration(minutes: 10));
      expect(splits.last.cumulativeDistanceMeters, closeTo(2000, 0.1));
    });
  });

  group('calculateElevationGainMeters', () {
    test('sums smooth climbing and rolling positive gains only', () {
      final climbOnly = [
        _pointAtMeters(seconds: 0, metersFromOrigin: 0, elevation: 100),
        _pointAtMeters(seconds: 10, metersFromOrigin: 30, elevation: 105),
        _pointAtMeters(seconds: 20, metersFromOrigin: 60, elevation: 112),
      ];

      final rolling = [
        _pointAtMeters(seconds: 0, metersFromOrigin: 0, elevation: 100),
        _pointAtMeters(seconds: 10, metersFromOrigin: 30, elevation: 110),
        _pointAtMeters(seconds: 20, metersFromOrigin: 60, elevation: 106),
        _pointAtMeters(seconds: 30, metersFromOrigin: 90, elevation: 114),
      ];

      expect(calculateElevationGainMeters(climbOnly), closeTo(12, 0.01));
      expect(calculateElevationGainMeters(rolling), closeTo(18, 0.01));
    });

    test('filters noisy jitter and skips missing elevation values', () {
      final noisyAndMissing = [
        _pointAtMeters(seconds: 0, metersFromOrigin: 0, elevation: 100),
        _pointAtMeters(seconds: 10, metersFromOrigin: 20, elevation: 100.3),
        _pointAtMeters(seconds: 20, metersFromOrigin: 40),
        _pointAtMeters(seconds: 30, metersFromOrigin: 60, elevation: 100.1),
        _pointAtMeters(seconds: 40, metersFromOrigin: 80, elevation: 101.7),
      ];

      expect(calculateElevationGainMeters(noisyAndMissing), closeTo(1.6, 0.05));
    });
  });

  group('classifyAutoPauseWindows', () {
    List<TrackingPoint> routeFromProfile(
      List<({int seconds, double metersFromOrigin})> profile,
    ) {
      return profile
          .map(
            (step) => _pointAtMeters(
              seconds: step.seconds,
              metersFromOrigin: step.metersFromOrigin,
            ),
          )
          .toList(growable: false);
    }

    test('keeps brief stoplight pause classified as moving', () {
      final points = routeFromProfile([
        (seconds: 0, metersFromOrigin: 0),
        (seconds: 30, metersFromOrigin: 60),
        (seconds: 60, metersFromOrigin: 120),
        (seconds: 80, metersFromOrigin: 120),
        (seconds: 110, metersFromOrigin: 180),
        (seconds: 140, metersFromOrigin: 240),
      ]);

      final result = classifyAutoPauseWindows(points);

      expect(result.windows, hasLength(1));
      expect(result.windows.single.state, AutoPauseState.moving);
      expect(result.totalMovingDuration, const Duration(seconds: 140));
    });

    test('detects sustained stop and resume without flapping', () {
      final points = routeFromProfile([
        (seconds: 0, metersFromOrigin: 0),
        (seconds: 30, metersFromOrigin: 60),
        (seconds: 60, metersFromOrigin: 120),
        (seconds: 120, metersFromOrigin: 120),
        (seconds: 180, metersFromOrigin: 120),
        (seconds: 240, metersFromOrigin: 120),
        (seconds: 300, metersFromOrigin: 240),
        (seconds: 360, metersFromOrigin: 360),
      ]);

      final result = classifyAutoPauseWindows(points);

      expect(result.windows.map((window) => window.state), [
        AutoPauseState.moving,
        AutoPauseState.stopped,
        AutoPauseState.moving,
      ]);
      // Stopped window should start at the actual stop onset (t=60),
      // not deferred by minimumAutoPauseDuration.
      expect(result.windows[0].duration, const Duration(seconds: 60));
      expect(result.windows[1].duration, const Duration(seconds: 180));
      expect(result.totalMovingDuration, const Duration(seconds: 180));
    });

    test('classifies slow walking as moving', () {
      final points = routeFromProfile([
        (seconds: 0, metersFromOrigin: 0),
        (seconds: 60, metersFromOrigin: 75),
        (seconds: 120, metersFromOrigin: 150),
        (seconds: 180, metersFromOrigin: 225),
      ]);

      final result = classifyAutoPauseWindows(points);

      expect(result.windows, hasLength(1));
      expect(result.windows.single.state, AutoPauseState.moving);
    });
  });

  group('calculateProcessedActivityMetrics', () {
    test('composes stage 4 metrics into one deterministic summary', () {
      final sessionTimestamp = DateTime.utc(2025, 1, 1, 12);
      final session = TrackingSessionRecord(
        id: _sessionId,
        status: TrackingSessionStatus.recording,
        createdAt: sessionTimestamp,
        updatedAt: sessionTimestamp,
      );
      final cleanedPoints = [
        _pointAtMeters(seconds: 0, metersFromOrigin: 0, elevation: 10),
        _pointAtMeters(seconds: 600, metersFromOrigin: 1000, elevation: 20),
        _pointAtMeters(seconds: 1200, metersFromOrigin: 2000, elevation: 30),
      ];

      final summary = calculateProcessedActivityMetrics(
        session: session,
        cleanedPoints: cleanedPoints,
      );

      expect(summary.session.id, _sessionId);
      expect(summary.trackSummary.distanceMeters, closeTo(2000, 0.5));
      expect(summary.trackSummary.movingTime, const Duration(minutes: 20));
      expect(
        summary.trackSummary.averagePace.perKilometer,
        const Duration(minutes: 10),
      );
      expect(
        summary.trackSummary.averagePace.perMile,
        const Duration(minutes: 16, seconds: 5),
      );
      expect(summary.trackSummary.elevationGainMeters, closeTo(20, 0.01));
      expect(summary.splits, hasLength(2));
    });
  });

  group('calculatePersistedActivityDuration', () {
    test(
      'falls back to session elapsed time when processed moving time is zero',
      () {
        final startedAt = DateTime.utc(2025, 1, 1, 12);
        final stoppedAt = startedAt.add(const Duration(minutes: 10));
        final session = TrackingSessionRecord(
          id: _sessionId,
          status: TrackingSessionStatus.stopped,
          createdAt: startedAt,
          updatedAt: stoppedAt,
          startedAt: startedAt,
          stoppedAt: stoppedAt,
        );

        final duration = calculatePersistedActivityDuration(
          session: session,
          processedMovingTime: Duration.zero,
        );

        expect(duration, const Duration(minutes: 10));
      },
    );
  });
}

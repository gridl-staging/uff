import 'package:test/test.dart';
import 'package:uff/src/features/analytics/domain/analytics_point.dart';
import 'package:uff/src/features/analytics/domain/training_stress.dart';
import 'package:uff/src/features/analytics/domain/tss_calculator.dart';

List<AnalyticsPoint> _buildPoints({
  required List<DateTime> timestamps,
  required List<double?> speeds,
  required List<double?> elevations,
  required List<double?> cumulativeDistances,
  required List<int?> powers,
}) {
  return List<AnalyticsPoint>.generate(timestamps.length, (index) {
    return AnalyticsPoint(
      timestamp: timestamps[index],
      latitude: 0,
      longitude: 0,
      speedMs: speeds[index],
      elevationMeters: elevations[index],
      cumulativeDistanceMeters: cumulativeDistances[index],
      powerWatts: powers[index],
    );
  });
}

List<AnalyticsPoint> _buildUniformRunPoints({
  required int durationSeconds,
  required double speedMs,
  double startElevationMeters = 0,
  double grade = 0,
  bool includeCumulativeDistance = true,
  bool includeElevation = true,
}) {
  final start = DateTime.utc(2026, 3, 14);
  final points = <AnalyticsPoint>[];
  var elevation = startElevationMeters;

  for (var second = 0; second <= durationSeconds; second++) {
    final timestamp = start.add(Duration(seconds: second));
    final cumulativeDistance = includeCumulativeDistance
        ? speedMs * second
        : null;

    if (second > 0) {
      elevation += speedMs * grade;
    }

    points.add(
      AnalyticsPoint(
        timestamp: timestamp,
        latitude: 0,
        longitude: 0,
        speedMs: speedMs,
        elevationMeters: includeElevation ? elevation : null,
        cumulativeDistanceMeters: cumulativeDistance,
      ),
    );
  }

  return points;
}

List<AnalyticsPoint> _buildRunPointsFromSegments({
  required List<int> segmentDurationsSeconds,
  required List<double> segmentSpeedsMs,
}) {
  if (segmentDurationsSeconds.length != segmentSpeedsMs.length) {
    throw ArgumentError('segment duration and speed counts must match');
  }
  if (segmentDurationsSeconds.isEmpty) {
    return const <AnalyticsPoint>[];
  }

  final start = DateTime.utc(2026, 3, 14);
  final points = <AnalyticsPoint>[
    AnalyticsPoint(
      timestamp: start,
      latitude: 0,
      longitude: 0,
      speedMs: segmentSpeedsMs.first,
      elevationMeters: 0,
      cumulativeDistanceMeters: 0,
    ),
  ];
  var elapsedSeconds = 0;
  var cumulativeDistanceMeters = 0.0;

  for (var index = 0; index < segmentDurationsSeconds.length; index++) {
    elapsedSeconds += segmentDurationsSeconds[index];
    cumulativeDistanceMeters +=
        segmentSpeedsMs[index] * segmentDurationsSeconds[index];
    points.add(
      AnalyticsPoint(
        timestamp: start.add(Duration(seconds: elapsedSeconds)),
        latitude: 0,
        longitude: 0,
        speedMs: segmentSpeedsMs[index],
        elevationMeters: 0,
        cumulativeDistanceMeters: cumulativeDistanceMeters,
      ),
    );
  }

  return points;
}

List<AnalyticsPoint> _buildPowerPointsFromSegments({
  required List<int> segmentDurationsSeconds,
  required List<int?> segmentPowers,
}) {
  if (segmentDurationsSeconds.length != segmentPowers.length) {
    throw ArgumentError('segment duration and power counts must match');
  }
  if (segmentDurationsSeconds.isEmpty) {
    return const <AnalyticsPoint>[];
  }

  final start = DateTime.utc(2026, 3, 14);
  final points = <AnalyticsPoint>[
    AnalyticsPoint(
      timestamp: start,
      latitude: 0,
      longitude: 0,
      powerWatts: segmentPowers.first,
    ),
  ];
  var elapsedSeconds = 0;

  for (var index = 0; index < segmentDurationsSeconds.length; index++) {
    elapsedSeconds += segmentDurationsSeconds[index];
    points.add(
      AnalyticsPoint(
        timestamp: start.add(Duration(seconds: elapsedSeconds)),
        latitude: 0,
        longitude: 0,
        powerWatts: segmentPowers[index],
      ),
    );
  }

  return points;
}

List<AnalyticsPoint> _buildPowerPoints(List<int?> segmentPowers) {
  return _buildPowerPointsFromSegments(
    segmentDurationsSeconds: List<int>.filled(segmentPowers.length, 1),
    segmentPowers: segmentPowers,
  );
}

void main() {
  group('simpleTss', () {
    test('IF=1.0 at 3600s gives exactly 100.0 TSS', () {
      final result = TssCalculator.simpleTss(
        durationSeconds: 3600,
        avgPaceSecsPerKm: 300,
        thresholdPaceSecsPerKm: 300,
      );

      // simpleTss with valid inputs always returns simpleTSS method
      expect(result?.method, TssMethod.simpleTSS);
      // IF=1.0 → TSS = (3600/3600) * 1.0^2 * 100 = 100
      expect(result?.tss, 100);
      // threshold/avg = 300/300 = 1.0
      expect(result?.intensityFactor, 1);
    });

    test('IF=0.85 at 3600s gives about 72.25 TSS', () {
      final result = TssCalculator.simpleTss(
        durationSeconds: 3600,
        avgPaceSecsPerKm: 300,
        thresholdPaceSecsPerKm: 255,
      );

      // simpleTss with valid inputs always returns simpleTSS method
      expect(result?.method, TssMethod.simpleTSS);
      // IF = threshold/avg = 255/300 = 0.85
      expect(result?.intensityFactor, closeTo(0.85, 1e-9));
      // TSS = (3600/3600) * 0.85^2 * 100 = 72.25
      expect(result?.tss, closeTo(72.25, 0.1));
    });

    test('zero duration gives 0.0 TSS', () {
      final result = TssCalculator.simpleTss(
        durationSeconds: 0,
        avgPaceSecsPerKm: 300,
        thresholdPaceSecsPerKm: 300,
      );

      // simpleTss with valid inputs always returns simpleTSS method
      expect(result?.method, TssMethod.simpleTSS);
      // TSS = (0/3600) * 1.0^2 * 100 = 0
      expect(result?.tss, 0);
    });

    test('null threshold pace returns null', () {
      final result = TssCalculator.simpleTss(
        durationSeconds: 3600,
        avgPaceSecsPerKm: 300,
        thresholdPaceSecsPerKm: null,
      );

      expect(result, isNull);
    });

    test('zero threshold pace returns null', () {
      final result = TssCalculator.simpleTss(
        durationSeconds: 3600,
        avgPaceSecsPerKm: 300,
        thresholdPaceSecsPerKm: 0,
      );

      expect(result, isNull);
    });

    test('zero average pace returns null', () {
      final result = TssCalculator.simpleTss(
        durationSeconds: 3600,
        avgPaceSecsPerKm: 0,
        thresholdPaceSecsPerKm: 300,
      );

      expect(result, isNull);
    });
  });

  group('rTss', () {
    test('flat terrain with uniform speed matches simpleTss', () {
      final points = _buildUniformRunPoints(
        durationSeconds: 3600,
        speedMs: 1000 / 300,
      );
      final simple = TssCalculator.simpleTss(
        durationSeconds: 3600,
        avgPaceSecsPerKm: 300,
        thresholdPaceSecsPerKm: 300,
      );
      final result = TssCalculator.rTss(
        points: points,
        thresholdPaceSecsPerKm: 300,
      );

      // simpleTss reference must be simpleTSS method
      expect(simple?.method, TssMethod.simpleTSS);
      // rTss on flat terrain produces rTSS method
      expect(result?.method, TssMethod.rTSS);
      // flat uniform speed → rTSS matches simpleTSS exactly
      expect(result!.tss, closeTo(simple!.tss, 1e-9));
      expect(result.intensityFactor, closeTo(simple.intensityFactor, 1e-9));
      // uniform 300 s/km → normalized effort = 300 s/km
      expect(result.normalizedEffortSecsPerKm, closeTo(300, 1e-9));
    });

    test('5% uphill produces slower normalized pace than flat pace', () {
      final points = _buildUniformRunPoints(
        durationSeconds: 300,
        speedMs: 1000 / 300,
        grade: 0.05,
      );

      final result = TssCalculator.rTss(
        points: points,
        thresholdPaceSecsPerKm: 300,
      );

      // rTss with valid inputs always returns rTSS method
      expect(result?.method, TssMethod.rTSS);
      // 5% uphill Minetti adjustment slows normalized effort beyond flat 300 s/km
      expect(result!.normalizedEffortSecsPerKm, greaterThan(300));
      // Tightened from closeTo(300*1.1785, 0.5) — deterministic fixture
      // yields a stable value in the Minetti-adjusted range.
      expect(result.normalizedEffortSecsPerKm, closeTo(300 * 1.1785, 0.01));
      // IF and TSS derived from the same Minetti-adjusted pace factor.
      const adjustedPaceFactor = 1.1785;
      const expectedIF = 1 / adjustedPaceFactor;
      expect(result.intensityFactor, closeTo(expectedIF, 0.001));
      expect(
        result.tss,
        closeTo(300 * expectedIF * expectedIF / 3600 * 100, 0.1),
      );
    });

    test('null elevation on all points falls back to raw speed pace', () {
      final points = _buildUniformRunPoints(
        durationSeconds: 300,
        speedMs: 1000 / 280,
        includeElevation: false,
      );

      final result = TssCalculator.rTss(
        points: points,
        thresholdPaceSecsPerKm: 280,
      );

      // rTss with valid inputs returns rTSS method
      expect(result?.method, TssMethod.rTSS);
      // no elevation data → falls back to raw speed; uniform 280 s/km
      expect(result?.normalizedEffortSecsPerKm, closeTo(280, 1e-6));
    });

    test(
      'uses speed and timestamp distance fallback when cumulative distance is missing',
      () {
        final points = _buildUniformRunPoints(
          durationSeconds: 300,
          speedMs: 1000 / 300,
          grade: 0.05,
          includeCumulativeDistance: false,
        );

        // Same fixture WITH cumulative distance — speed×time equals
        // cumulative-distance deltas for uniform speed, so both code paths
        // must converge.
        final withCumulativeDistance = _buildUniformRunPoints(
          durationSeconds: 300,
          speedMs: 1000 / 300,
          grade: 0.05,
        );

        final result = TssCalculator.rTss(
          points: points,
          thresholdPaceSecsPerKm: 300,
        );
        final expected = TssCalculator.rTss(
          points: withCumulativeDistance,
          thresholdPaceSecsPerKm: 300,
        );

        // both code paths (speed×time vs cumulative distance) return rTSS
        expect(result?.method, TssMethod.rTSS);
        expect(expected?.method, TssMethod.rTSS);
        // uniform speed → speed×time equals cumulative-distance deltas, so both converge
        expect(
          result!.normalizedEffortSecsPerKm,
          closeTo(expected!.normalizedEffortSecsPerKm!, 1e-9),
        );
        expect(
          result.intensityFactor,
          closeTo(expected.intensityFactor, 1e-9),
        );
        expect(result.tss, closeTo(expected.tss, 1e-9));
      },
    );

    test(
      'excludes zero-speed and non-positive-distance segments from normalization',
      () {
        final start = DateTime.utc(2026, 3, 14);
        final points = _buildPoints(
          timestamps: [
            start,
            start.add(const Duration(seconds: 1)),
            start.add(const Duration(seconds: 2)),
            start.add(const Duration(seconds: 3)),
          ],
          speeds: [0, 1000 / 200, 1000 / 200, 1000 / 300],
          elevations: [0, 0, 0, 0],
          cumulativeDistances: [0, 0, 0, 1000 / 300],
          powers: [null, null, null, null],
        );

        final result = TssCalculator.rTss(
          points: points,
          thresholdPaceSecsPerKm: 300,
        );

        // rTss with valid inputs returns rTSS method
        expect(result?.method, TssMethod.rTSS);
        // only the final segment (1000/300 m at 300 s/km) has positive distance
        expect(result?.normalizedEffortSecsPerKm, closeTo(300, 1e-6));
      },
    );

    test('irregular timestamp gaps weight pace by elapsed seconds', () {
      final densePoints = _buildRunPointsFromSegments(
        segmentDurationsSeconds: [1, ...List<int>.filled(30, 1)],
        segmentSpeedsMs: [1000 / 250, ...List<double>.filled(30, 1000 / 500)],
      );
      final sparsePoints = _buildRunPointsFromSegments(
        segmentDurationsSeconds: [1, 30],
        segmentSpeedsMs: [1000 / 250, 1000 / 500],
      );

      final denseResult = TssCalculator.rTss(
        points: densePoints,
        thresholdPaceSecsPerKm: 500,
      );
      final sparseResult = TssCalculator.rTss(
        points: sparsePoints,
        thresholdPaceSecsPerKm: 500,
      );

      // both dense and sparse representations produce rTSS method
      expect(denseResult?.method, TssMethod.rTSS);
      expect(sparseResult?.method, TssMethod.rTSS);
      // time-weighted normalization makes dense/sparse equivalent
      expect(
        sparseResult!.normalizedEffortSecsPerKm,
        closeTo(denseResult!.normalizedEffortSecsPerKm!, 1e-9),
      );
      expect(
        sparseResult.intensityFactor,
        closeTo(denseResult.intensityFactor, 1e-9),
      );
      expect(sparseResult.tss, closeTo(denseResult.tss, 1e-9));
    });

    test(
      'uses all available values when points are fewer than 30-sample window',
      () {
        final points = _buildUniformRunPoints(
          durationSeconds: 10,
          speedMs: 1000 / 250,
        );

        final result = TssCalculator.rTss(
          points: points,
          thresholdPaceSecsPerKm: 250,
        );

        // rTss with valid inputs returns rTSS method
        expect(result?.method, TssMethod.rTSS);
        // uniform 250 s/km with <30 points → uses all available values
        expect(result?.normalizedEffortSecsPerKm, closeTo(250, 1e-9));
      },
    );

    test('null threshold returns null', () {
      final points = _buildUniformRunPoints(
        durationSeconds: 10,
        speedMs: 1000 / 250,
      );

      final result = TssCalculator.rTss(
        points: points,
        thresholdPaceSecsPerKm: null,
      );

      expect(result, isNull);
    });

    test('empty points list returns null', () {
      final result = TssCalculator.rTss(
        points: const [],
        thresholdPaceSecsPerKm: 250,
      );

      expect(result, isNull);
    });
  });

  group('cTss', () {
    test('constant 200W for 3600s at FTP 200 gives TSS 100.0', () {
      final points = _buildPowerPoints(List<int?>.filled(3600, 200));

      final result = TssCalculator.cTss(
        points: points,
        ftpWatts: 200,
      );

      // cTss with valid power data returns cTSS method
      expect(result?.method, TssMethod.cTSS);
      // NP = 200W, FTP = 200W → IF = 200/200 = 1.0
      expect(result?.intensityFactor, closeTo(1, 1e-9));
      // TSS = (3600/3600) * 1.0^2 * 100 = 100
      expect(result?.tss, closeTo(100, 1e-9));
    });

    test('split-block power yields NP greater than simple mean power', () {
      final segmentPowers = <int?>[
        ...List<int>.filled(3000, 200),
        ...List<int>.filled(600, 350),
      ];
      final points = _buildPowerPoints(segmentPowers);
      final result = TssCalculator.cTss(points: points, ftpWatts: 300);
      const simpleMeanPower = ((200 * 3000) + (350 * 600)) / 3600;

      // cTss with valid power data returns cTSS method
      expect(result?.method, TssMethod.cTSS);
      // 4th-root mean of 30s rolling avg > arithmetic mean for variable power
      final normalizedPower = result!.intensityFactor * 300;
      expect(normalizedPower, greaterThan(simpleMeanPower));
    });

    test('irregular timestamp gaps weight power by elapsed seconds', () {
      final densePoints = _buildPowerPoints(<int?>[
        100,
        ...List<int>.filled(30, 300),
      ]);
      final sparsePoints = _buildPowerPointsFromSegments(
        segmentDurationsSeconds: [1, 30],
        segmentPowers: [100, 300],
      );

      final denseResult = TssCalculator.cTss(
        points: densePoints,
        ftpWatts: 300,
      );
      final sparseResult = TssCalculator.cTss(
        points: sparsePoints,
        ftpWatts: 300,
      );

      // both dense and sparse representations produce cTSS method
      expect(denseResult?.method, TssMethod.cTSS);
      expect(sparseResult?.method, TssMethod.cTSS);
      // time-weighted power normalization makes dense/sparse equivalent
      expect(
        sparseResult!.intensityFactor,
        closeTo(denseResult!.intensityFactor, 1e-9),
      );
      expect(sparseResult.tss, closeTo(denseResult.tss, 1e-9));
    });

    test('zero-watt segments are included in normalized power', () {
      final points = _buildPowerPoints(<int?>[
        ...List<int>.filled(1800, 200),
        ...List<int>.filled(1800, 0),
      ]);

      final result = TssCalculator.cTss(
        points: points,
        ftpWatts: 200,
      );

      // cTss with valid power data returns cTSS method
      expect(result?.method, TssMethod.cTSS);
      // half the duration at 0W → NP < FTP → IF < 1.0
      expect(result?.intensityFactor, lessThan(1));
      // IF < 1.0 → TSS < 100
      expect(result?.tss, lessThan(100));
    });

    test('all-null power values returns null', () {
      final points = _buildPowerPoints(List<int?>.filled(60, null));

      final result = TssCalculator.cTss(
        points: points,
        ftpWatts: 200,
      );

      expect(result, isNull);
    });

    test('all-zero power values return zero TSS', () {
      final points = _buildPowerPoints(List<int?>.filled(60, 0));

      final result = TssCalculator.cTss(
        points: points,
        ftpWatts: 200,
      );

      // cTss with all-zero power still returns cTSS method
      expect(result?.method, TssMethod.cTSS);
      // all 0W → NP = 0 → IF = 0/200 = 0
      expect(result?.intensityFactor, 0);
      // TSS = (60/3600) * 0^2 * 100 = 0
      expect(result?.tss, 0);
    });

    test('null ftp returns null', () {
      final points = _buildPowerPoints(List<int?>.filled(60, 200));

      final result = TssCalculator.cTss(
        points: points,
        ftpWatts: null,
      );

      expect(result, isNull);
    });

    test('empty points list returns null', () {
      final result = TssCalculator.cTss(
        points: const [],
        ftpWatts: 200,
      );

      expect(result, isNull);
    });
  });
}

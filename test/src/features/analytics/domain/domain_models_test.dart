import 'package:test/test.dart';
import 'package:uff/src/features/analytics/domain/analytics_point.dart';
import 'package:uff/src/features/analytics/domain/fitness_profile.dart';
import 'package:uff/src/features/analytics/domain/hr_zone.dart';
import 'package:uff/src/features/analytics/domain/interval_event.dart';
import 'package:uff/src/features/analytics/domain/pmc_day.dart';
import 'package:uff/src/features/analytics/domain/power_curve_point.dart';
import 'package:uff/src/features/analytics/domain/race_prediction.dart';
import 'package:uff/src/features/analytics/domain/sport_type.dart';
import 'package:uff/src/features/analytics/domain/training_stress.dart';

List<HrZone> _buildSevenZones() {
  return const [
    HrZone(number: 1, label: 'Z1', lowerBpm: 100, upperBpm: 119),
    HrZone(number: 2, label: 'Z2', lowerBpm: 120, upperBpm: 129),
    HrZone(number: 3, label: 'Z3', lowerBpm: 130, upperBpm: 139),
    HrZone(number: 4, label: 'Z4', lowerBpm: 140, upperBpm: 149),
    HrZone(number: 5, label: 'Z5a', lowerBpm: 150, upperBpm: 159),
    HrZone(number: 6, label: 'Z5b', lowerBpm: 160, upperBpm: 169),
    HrZone(number: 7, label: 'Z5c', lowerBpm: 170),
  ];
}

void main() {
  group('SportType', () {
    test('has exactly run and ride values', () {
      expect(SportType.values, [SportType.run, SportType.ride]);
    });
  });

  group('AnalyticsPoint', () {
    test('constructs with required and nullable optional fields', () {
      final point = AnalyticsPoint(
        timestamp: DateTime.utc(2026, 3, 14, 12, 30),
        latitude: 37.7749,
        longitude: -122.4194,
        elevationMeters: 15.25,
        speedMs: 3.45,
        heartRateBpm: 158,
        cadenceRpm: 174,
        powerWatts: 265,
        cumulativeDistanceMeters: 1234.5,
      );

      expect(point.timestamp, DateTime.utc(2026, 3, 14, 12, 30));
      expect(point.latitude, closeTo(37.7749, 1e-9));
      expect(point.longitude, closeTo(-122.4194, 1e-9));
      expect(point.elevationMeters, closeTo(15.25, 1e-9));
      expect(point.speedMs, closeTo(3.45, 1e-9));
      expect(point.heartRateBpm, 158);
      expect(point.cadenceRpm, 174);
      expect(point.powerWatts, 265);
      expect(point.cumulativeDistanceMeters, closeTo(1234.5, 1e-9));
    });

    test('leaves optional values null when omitted', () {
      final point = AnalyticsPoint(
        timestamp: DateTime.utc(2026, 3, 14, 12, 30),
        latitude: 37.7749,
        longitude: -122.4194,
      );

      expect(point.elevationMeters, isNull);
      expect(point.speedMs, isNull);
      expect(point.heartRateBpm, isNull);
      expect(point.cadenceRpm, isNull);
      expect(point.powerWatts, isNull);
      expect(point.cumulativeDistanceMeters, isNull);
    });
  });

  group('FitnessProfile', () {
    test('uses defaults for optional thresholds and sport settings', () {
      const profile = FitnessProfile();

      expect(profile.thresholdPaceSecsPerKm, isNull);
      expect(profile.lthr, isNull);
      expect(profile.ftpWatts, isNull);
      expect(profile.riegelExponent, closeTo(1.06, 1e-12));
      expect(profile.sport, SportType.run);
    });

    test('stores explicit values when provided', () {
      const profile = FitnessProfile(
        thresholdPaceSecsPerKm: 250,
        lthr: 172,
        ftpWatts: 285,
        riegelExponent: 1.07,
        sport: SportType.ride,
      );

      expect(profile.thresholdPaceSecsPerKm, closeTo(250, 1e-9));
      expect(profile.lthr, 172);
      expect(profile.ftpWatts, 285);
      expect(profile.riegelExponent, closeTo(1.07, 1e-12));
      expect(profile.sport, SportType.ride);
    });
  });

  group('TssMethod', () {
    test('has exactly three values', () {
      expect(TssMethod.values, [
        TssMethod.rTSS,
        TssMethod.cTSS,
        TssMethod.simpleTSS,
      ]);
    });
  });

  group('TrainingStressResult', () {
    test('round-trips fields and allows nullable normalized effort', () {
      const withNormalized = TrainingStressResult(
        tss: 82.5,
        intensityFactor: 0.91,
        method: TssMethod.rTSS,
        normalizedEffortSecsPerKm: 280.5,
      );
      const withoutNormalized = TrainingStressResult(
        tss: 68.2,
        intensityFactor: 0.83,
        method: TssMethod.simpleTSS,
      );

      expect(withNormalized.tss, closeTo(82.5, 1e-9));
      expect(withNormalized.intensityFactor, closeTo(0.91, 1e-9));
      expect(withNormalized.method, TssMethod.rTSS);
      expect(withNormalized.normalizedEffortSecsPerKm, closeTo(280.5, 1e-9));

      expect(withoutNormalized.tss, closeTo(68.2, 1e-9));
      expect(withoutNormalized.intensityFactor, closeTo(0.83, 1e-9));
      expect(withoutNormalized.method, TssMethod.simpleTSS);
      expect(withoutNormalized.normalizedEffortSecsPerKm, isNull);
    });
  });

  group('PmcDay', () {
    test('round-trips fields for UTC-midnight date input', () {
      final pmcDay = PmcDay(
        date: DateTime.utc(2026, 3, 14),
        ctl: 56.3,
        atl: 62.1,
        tsb: -5.8,
        tssOnDay: 74,
      );

      expect(pmcDay.date, DateTime.utc(2026, 3, 14));
      expect(pmcDay.ctl, closeTo(56.3, 1e-9));
      expect(pmcDay.atl, closeTo(62.1, 1e-9));
      expect(pmcDay.tsb, closeTo(-5.8, 1e-9));
      expect(pmcDay.tssOnDay, closeTo(74.0, 1e-9));
    });

    test('does not normalize dates in the model', () {
      final pmcDay = PmcDay(
        date: DateTime.utc(2026, 3, 14, 5, 45),
        ctl: 56.3,
        atl: 62.1,
        tsb: -5.8,
        tssOnDay: 74,
      );

      expect(pmcDay.date, DateTime.utc(2026, 3, 14, 5, 45));
    });
  });

  group('HrZone', () {
    test('supports manual equality and hashCode for identical values', () {
      const first = HrZone(
        number: 4,
        label: 'Z4',
        lowerBpm: 151,
        upperBpm: 161,
      );
      const second = HrZone(
        number: 4,
        label: 'Z4',
        lowerBpm: 151,
        upperBpm: 161,
      );
      const different = HrZone(
        number: 5,
        label: 'Z5a',
        lowerBpm: 162,
        upperBpm: 169,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(different));
    });
  });

  group('HrZones', () {
    test('holds lthr and exactly 7 zones', () {
      final zones = HrZones(lthr: 172, zones: _buildSevenZones());

      expect(zones.lthr, 172);
      expect(zones.zones, hasLength(7));
    });

    test('rejects non-7-zone input', () {
      final sixZones = _buildSevenZones().sublist(0, 6);

      expect(
        () => HrZones(lthr: 172, zones: sixZones),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('exposes an unmodifiable zone list', () {
      final zones = HrZones(lthr: 172, zones: _buildSevenZones());

      expect(
        () => zones.zones.add(
          const HrZone(number: 8, label: 'X', lowerBpm: 200),
        ),
        throwsUnsupportedError,
      );
    });

    test('defensively copies source zone list input', () {
      final sourceZones = _buildSevenZones().toList();
      final zones = HrZones(lthr: 172, zones: sourceZones);

      sourceZones[0] = const HrZone(
        number: 1,
        label: 'mutated',
        lowerBpm: 50,
        upperBpm: 99,
      );

      expect(
        zones.zones.first,
        const HrZone(number: 1, label: 'Z1', lowerBpm: 100, upperBpm: 119),
      );
    });
  });

  group('HrZoneBreakdown', () {
    test('sums total seconds from all zones', () {
      final breakdown = HrZoneBreakdown(
        secondsPerZone: const {1: 60.5, 2: 125.0, 3: 30.0},
      );

      expect(breakdown.totalSeconds, closeTo(215.5, 1e-9));
    });

    test('returns 0.0 total seconds for empty input', () {
      final breakdown = HrZoneBreakdown(secondsPerZone: const {});
      expect(breakdown.totalSeconds, closeTo(0, 1e-9));
    });

    test('exposes an unmodifiable seconds map', () {
      final breakdown = HrZoneBreakdown(secondsPerZone: const {1: 60.0});

      expect(
        () => breakdown.secondsPerZone[2] = 30.0,
        throwsUnsupportedError,
      );
    });

    test('defensively copies source seconds map input', () {
      final sourceSeconds = <int, double>{1: 60.0};
      final breakdown = HrZoneBreakdown(secondsPerZone: sourceSeconds);

      sourceSeconds[1] = 999.0;
      sourceSeconds[2] = 5.0;

      expect(breakdown.secondsPerZone, {1: 60.0});
      expect(breakdown.totalSeconds, closeTo(60.0, 1e-9));
    });
  });

  group('RaceResult', () {
    test('supports manual equality and hashCode for identical values', () {
      const first = RaceResult(
        distanceMeters: 10000,
        duration: Duration(minutes: 42),
      );
      const second = RaceResult(
        distanceMeters: 10000,
        duration: Duration(minutes: 42),
      );
      const different = RaceResult(
        distanceMeters: 5000,
        duration: Duration(minutes: 19),
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(different));
    });
  });

  group('RacePrediction', () {
    test('stores all fields', () {
      const prediction = RacePrediction(
        label: '10 km',
        distanceMeters: 10000,
        predictedTime: Duration(minutes: 41, seconds: 30),
        intensityFactor: 0.94,
      );

      expect(prediction.label, '10 km');
      expect(prediction.distanceMeters, closeTo(10000, 1e-9));
      expect(
        prediction.predictedTime,
        const Duration(minutes: 41, seconds: 30),
      );
      expect(prediction.intensityFactor, closeTo(0.94, 1e-9));
    });
  });

  group('StandardRaces', () {
    test('contains six standard races with expected labels and distances', () {
      expect(StandardRaces.all, hasLength(6));
      expect(
        StandardRaces.all,
        [
          (label: '5 km', distanceMeters: 5000.0),
          (label: '10 km', distanceMeters: 10000.0),
          (label: '15 km', distanceMeters: 15000.0),
          (label: 'Half Marathon', distanceMeters: 21097.5),
          (label: '30 km', distanceMeters: 30000.0),
          (label: 'Marathon', distanceMeters: 42195.0),
        ],
      );
    });
  });

  group('IntervalIntensity', () {
    test('has hard and easy values', () {
      expect(IntervalIntensity.values, [
        IntervalIntensity.hard,
        IntervalIntensity.easy,
      ]);
    });
  });

  group('IntervalEvent', () {
    test('supports manual equality and duration getter', () {
      final first = IntervalEvent(
        intensity: IntervalIntensity.hard,
        startTimestamp: DateTime.utc(2026, 3, 14, 6),
        endTimestamp: DateTime.utc(2026, 3, 14, 6, 4, 30),
        distanceMeters: 1200,
        avgPaceSecsPerKm: 225,
        avgHeartRateBpm: 172,
      );
      final second = IntervalEvent(
        intensity: IntervalIntensity.hard,
        startTimestamp: DateTime.utc(2026, 3, 14, 6),
        endTimestamp: DateTime.utc(2026, 3, 14, 6, 4, 30),
        distanceMeters: 1200,
        avgPaceSecsPerKm: 225,
        avgHeartRateBpm: 172,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.duration, const Duration(minutes: 4, seconds: 30));
    });
  });

  group('PowerCurvePoint', () {
    test('stores fields with avgWatts validated via closeTo', () {
      const point = PowerCurvePoint(
        duration: Duration(minutes: 20),
        avgWatts: 257.25,
      );

      expect(point.duration, const Duration(minutes: 20));
      expect(point.avgWatts, closeTo(257.25, 1e-9));
    });
  });
}

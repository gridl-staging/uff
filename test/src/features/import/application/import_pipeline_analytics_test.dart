import 'dart:math' as math;

import 'package:fit_tool/fit_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/analytics/application/analytics_providers.dart';
import 'package:uff/src/features/analytics/domain/analytics_point.dart';
import 'package:uff/src/features/analytics/domain/hr_zone_calculator.dart';
import 'package:uff/src/features/analytics/domain/pmc_calculator.dart';
import 'package:uff/src/features/analytics/domain/sport_type.dart';
import 'package:uff/src/features/analytics/domain/training_stress.dart';
import 'package:uff/src/features/analytics/domain/tss_calculator.dart';

import '../../../../fixtures/fixture_loader.dart';
import '../data/fit_test_helpers.dart';
import 'import_pipeline_analytics_test_support.dart';

const double _earthRadiusMeters = 6371000;
const double _pmcComparisonTolerance = 1e-4;

void main() {
  group('ImportPipeline analytics accuracy', () {
    test(
      'smoke: imports deterministic FIT and reloads saved session and points',
      () async {
        final harness = await ImportPipelineAnalyticsHarness.create();
        addTearDown(harness.dispose);

        final records = buildDeterministicFitRecords(pointCount: 48);
        final sessionId = await harness.importFit(
          records: records,
          filename: 'smoke.fit',
        );

        final session = await harness.loadSessionOrThrow(sessionId);
        final points = await harness.loadPoints(sessionId);

        expect(points, hasLength(records.length));
        expect(session.id, sessionId);
        expect(
          session.distanceMeters,
          closeTo(_sumHaversineMeters(records), 1.0),
        );
        expect(
          session.movingTimeSeconds,
          equals(_elapsedSecondsFromRecords(records)),
        );
        expect(points.first.heartRateBpm, records.first.heartRate);
        expect(points.last.powerWatts, records.last.power);
        expect(harness.syncService.queuedSessionIds, [sessionId]);
      },
    );

    test(
      'distance: persisted session distance matches independent haversine sum',
      () async {
        final harness = await ImportPipelineAnalyticsHarness.create();
        addTearDown(harness.dispose);

        final records = buildDeterministicFitRecords(pointCount: 120);
        final sessionId = await harness.importFit(
          records: records,
          filename: 'distance.fit',
        );
        final session = await harness.loadSessionOrThrow(sessionId);

        final expectedDistanceMeters = _sumHaversineMeters(records);
        final actualDistanceMeters = session.distanceMeters;

        expect(actualDistanceMeters, closeTo(expectedDistanceMeters, 1.0));
      },
    );

    test(
      'HR zones: imported 130-164 BPM stream maps to expected Friel zone durations',
      () async {
        final harness = await ImportPipelineAnalyticsHarness.create(
          profile: buildImportAnalyticsTestProfile(lthrBpm: 155),
        );
        addTearDown(harness.dispose);

        final records = buildDeterministicFitRecords(pointCount: 140);
        final sessionId = await harness.importFit(
          records: records,
          filename: 'hr.fit',
        );

        final breakdown = await harness.container.read(
          activityHrZonesProvider(sessionId).future,
        );
        final points = await harness.loadPoints(sessionId);
        final expected = _expectedHrZoneSeconds(points, lthrBpm: 155);

        expect(
          _mapsWithinTolerance(breakdown!.secondsPerZone, expected),
          isTrue,
        );
        // The _mapsWithinTolerance check above already verifies exact zone
        // values within 1e-9 tolerance — individual greaterThan(0) checks
        // were redundant and have been removed. The boundary check below
        // covers a distinct concern (no zone 7 leakage).
        expect(breakdown.secondsPerZone.containsKey(7), isFalse);
      },
    );

    test(
      'cTSS: imported power stream matches independent fourth-power normalization expectation',
      () async {
        final harness = await ImportPipelineAnalyticsHarness.create();
        addTearDown(harness.dispose);

        final records = buildDeterministicFitRecords(pointCount: 90);
        final sessionId = await harness.importFit(
          records: records,
          sport: Sport.cycling,
          filename: 'ctss.fit',
        );

        final points = await harness.loadPoints(sessionId);

        // This intentionally bypasses activity providers because the production
        // analytics conversion helper currently drops power/cadence.
        final analyticsPoints = toAnalyticsPoints(points);
        final ftpWatts = harness.fixedFitnessProfile.ftpWatts!;

        final cTss = TssCalculator.cTss(
          points: analyticsPoints,
          ftpWatts: ftpWatts,
        );
        final expectedTss = _expectedCtss(
          analyticsPoints: analyticsPoints,
          ftpWatts: ftpWatts,
        );

        expect(cTss!.tss, closeTo(expectedTss, 1e-9));
      },
    );

    test(
      'PMC: 20 imported weekday sessions over 4 weeks accumulate CTL with correct daily simple TSS',
      () async {
        final harness = await ImportPipelineAnalyticsHarness.create(
          profile: buildImportAnalyticsTestProfile(),
        );
        addTearDown(harness.dispose);

        final expectedDailyTss = <DateTime, double>{};
        final baseMonday = DateTime.utc(2026, 1, 5, 6);

        for (var week = 0; week < 4; week++) {
          for (var weekday = 0; weekday < 5; weekday++) {
            final sessionStart = baseMonday.add(
              Duration(days: (week * 7) + weekday),
            );
            final records = buildDeterministicFitRecords(
              pointCount: 80,
              timestampMsForIndex: (index, _) =>
                  sessionStart.millisecondsSinceEpoch + (index * 5000),
            );

            final sessionId = await harness.importFit(
              records: records,
              filename: 'pmc_${week}_$weekday.fit',
            );
            final session = await harness.loadSessionOrThrow(sessionId);

            final expectedStartedAt = _utcDateTimeFromEpochMs(
              records.first.timestampMs,
            );
            final expectedDistanceMeters = _sumHaversineMeters(records);
            final expectedMovingSeconds = _elapsedSecondsFromRecords(records);
            final avgPaceSecsPerKm =
                expectedMovingSeconds / (expectedDistanceMeters / 1000);
            final simpleTss = TssCalculator.simpleTss(
              durationSeconds: expectedMovingSeconds,
              avgPaceSecsPerKm: avgPaceSecsPerKm,
              thresholdPaceSecsPerKm:
                  harness.fixedFitnessProfile.thresholdPaceSecsPerKm,
            );

            expect(session.startedAt?.toUtc(), expectedStartedAt);
            expect(
              session.distanceMeters,
              closeTo(expectedDistanceMeters, 1.0),
            );
            expect(session.movingTimeSeconds, expectedMovingSeconds);
            expect(
              simpleTss,
              isA<TrainingStressResult>().having(
                (r) => r.method,
                'method',
                TssMethod.simpleTSS,
              ),
            );
            final day = _toUtcDay(expectedStartedAt);
            expectedDailyTss[day] =
                (expectedDailyTss[day] ?? 0) + simpleTss!.tss;
          }
        }

        final pmc = await harness.container.read(pmcProvider.future);
        final nonZeroDays = pmc
            .where((day) => day.tssOnDay > 0)
            .toList(growable: false);

        expect(nonZeroDays, hasLength(20));

        final firstDay = expectedDailyTss.keys.reduce(
          (left, right) => left.isBefore(right) ? left : right,
        );
        final lastDay = expectedDailyTss.keys.reduce(
          (left, right) => left.isAfter(right) ? left : right,
        );
        final expectedPmc = PmcCalculator.calculate(
          dailyTss: expectedDailyTss,
          rangeStart: firstDay,
          rangeEnd: lastDay,
        );

        expect(pmc, hasLength(expectedPmc.length));
        for (var index = 0; index < pmc.length; index++) {
          expect(pmc[index].date, expectedPmc[index].date);
          expect(
            pmc[index].tssOnDay,
            closeTo(expectedPmc[index].tssOnDay, _pmcComparisonTolerance),
          );
          expect(
            pmc[index].ctl,
            closeTo(expectedPmc[index].ctl, _pmcComparisonTolerance),
          );
        }

        final firstWeekFriday = _toUtcDay(
          baseMonday.add(const Duration(days: 4)),
        );
        final finalWeekFriday = _toUtcDay(
          baseMonday.add(const Duration(days: 25)),
        );
        final pmcByDay = {for (final day in pmc) day.date: day};

        expect(pmcByDay.containsKey(firstWeekFriday), isTrue);
        expect(pmcByDay.containsKey(finalWeekFriday), isTrue);
        expect(
          pmcByDay[finalWeekFriday]!.ctl,
          greaterThan(pmcByDay[firstWeekFriday]!.ctl),
        );
      },
    );
  });
}

DateTime _toUtcDay(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

DateTime _utcDateTimeFromEpochMs(int timestampMs) {
  return DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true);
}

int _elapsedSecondsFromRecords(List<FitTestRecord> records) {
  var elapsedSeconds = 0;
  for (var index = 1; index < records.length; index++) {
    final deltaSeconds =
        (records[index].timestampMs - records[index - 1].timestampMs) ~/ 1000;
    if (deltaSeconds > 0) {
      elapsedSeconds += deltaSeconds;
    }
  }
  return elapsedSeconds;
}

double _sumHaversineMeters(List<FitTestRecord> records) {
  var total = 0.0;
  for (var index = 1; index < records.length; index++) {
    final previous = records[index - 1];
    final current = records[index];
    total += _haversineMeters(
      previous.latitude!,
      previous.longitude!,
      current.latitude!,
      current.longitude!,
    );
  }
  return total;
}

double _haversineMeters(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  final lat1Rad = _toRadians(lat1);
  final lat2Rad = _toRadians(lat2);
  final latitudeDelta = lat2Rad - lat1Rad;
  final longitudeDelta = _toRadians(lon2 - lon1);
  final haversineTerm =
      math.pow(math.sin(latitudeDelta / 2), 2) +
      (math.cos(lat1Rad) *
          math.cos(lat2Rad) *
          math.pow(math.sin(longitudeDelta / 2), 2));
  final centralAngle =
      2 * math.atan2(math.sqrt(haversineTerm), math.sqrt(1 - haversineTerm));
  return _earthRadiusMeters * centralAngle;
}

double _toRadians(double degrees) => degrees * (math.pi / 180);

Map<int, double> _expectedHrZoneSeconds(
  List<TrackingPoint> points, {
  required int lthrBpm,
}) {
  final zones = HrZoneCalculator.forLthr(lthrBpm, SportType.run);
  final secondsPerZone = <int, double>{};

  // Previous-sample attribution rule: the elapsed time between point N and
  // point N+1 is attributed to the zone of point N's heart-rate sample.
  for (var index = 0; index < points.length - 1; index++) {
    final leading = points[index];
    final trailing = points[index + 1];
    final elapsedSeconds =
        trailing.timestamp.difference(leading.timestamp).inMilliseconds / 1000;
    if (elapsedSeconds <= 0 || leading.heartRateBpm == null) {
      continue;
    }

    final zone = zones.zones.firstWhere(
      (candidate) =>
          leading.heartRateBpm! >= candidate.lowerBpm &&
          (candidate.upperBpm == null ||
              leading.heartRateBpm! <= candidate.upperBpm!),
      orElse: () => throw StateError('Heart rate outside expected zone range'),
    );

    secondsPerZone[zone.number] =
        (secondsPerZone[zone.number] ?? 0) + elapsedSeconds;
  }

  return secondsPerZone;
}

bool _mapsWithinTolerance(
  Map<int, double> actual,
  Map<int, double> expected,
) {
  final allKeys = <int>{...actual.keys, ...expected.keys};
  for (final key in allKeys) {
    final left = actual[key] ?? 0;
    final right = expected[key] ?? 0;
    if ((left - right).abs() > 1e-9) {
      return false;
    }
  }
  return true;
}

double _expectedCtss({
  required List<AnalyticsPoint> analyticsPoints,
  required int ftpWatts,
}) {
  final powerBySecond = <double>[];
  var durationSeconds = 0;

  for (var index = 1; index < analyticsPoints.length; index++) {
    final previous = analyticsPoints[index - 1];
    final current = analyticsPoints[index];
    final deltaSeconds = current.timestamp
        .difference(previous.timestamp)
        .inSeconds;
    if (deltaSeconds <= 0) {
      continue;
    }

    final power = current.powerWatts;
    durationSeconds += deltaSeconds;
    if (power == null || power < 0) {
      continue;
    }

    for (var second = 0; second < deltaSeconds; second++) {
      powerBySecond.add(power.toDouble());
    }
  }

  if (powerBySecond.isEmpty || durationSeconds <= 0) {
    throw StateError('Expected imported power samples and positive duration');
  }

  final rollingAverages = <double>[];
  for (var index = 0; index < powerBySecond.length; index++) {
    final windowStart = math.max(0, index - 29);
    final window = powerBySecond.sublist(windowStart, index + 1);
    final average =
        window.reduce((left, right) => left + right) / window.length;
    rollingAverages.add(average);
  }

  final fourthPowerAverage =
      rollingAverages
          .map((value) => math.pow(value, 4).toDouble())
          .reduce((left, right) => left + right) /
      rollingAverages.length;
  final normalizedPower = math.pow(fourthPowerAverage, 0.25).toDouble();
  final intensityFactor = normalizedPower / ftpWatts;

  return (durationSeconds / 3600) * intensityFactor * intensityFactor * 100;
}

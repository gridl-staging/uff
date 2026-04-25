import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/analytics/domain/analytics_point.dart';
import 'package:uff/src/features/analytics/domain/fitness_profile.dart';
import 'package:uff/src/features/analytics/domain/hr_zone.dart';
import 'package:uff/src/features/analytics/domain/hr_zone_analyzer.dart';
import 'package:uff/src/features/analytics/domain/hr_zone_calculator.dart';
import 'package:uff/src/features/analytics/domain/interval_detector.dart';
import 'package:uff/src/features/analytics/domain/interval_event.dart';
import 'package:uff/src/features/analytics/domain/pmc_calculator.dart';
import 'package:uff/src/features/analytics/domain/pmc_day.dart';
import 'package:uff/src/features/analytics/domain/race_prediction.dart';
import 'package:uff/src/features/analytics/domain/race_predictor.dart';
import 'package:uff/src/features/analytics/domain/training_stress.dart';
import 'package:uff/src/features/analytics/domain/tss_calculator.dart';
import 'package:uff/src/features/analytics/domain/vdot_calculator.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';

// ---------------------------------------------------------------------------
// Conversion helper
// ---------------------------------------------------------------------------

/// Maps [TrackingPoint]s to [AnalyticsPoint]s at the feature boundary.
///
/// Leaves `cadenceRpm`, `powerWatts`, and `cumulativeDistanceMeters` null —
/// the domain calculators already handle null values via fallbacks.
List<AnalyticsPoint> _toAnalyticsPoints(List<TrackingPoint> points) {
  return [
    for (final p in points)
      AnalyticsPoint(
        timestamp: p.timestamp,
        latitude: p.coordinate.latitude,
        longitude: p.coordinate.longitude,
        elevationMeters: p.elevation,
        speedMs: p.speed,
        heartRateBpm: p.heartRateBpm,
      ),
  ];
}

Future<ActivityDetailData?> _watchActivityDetail(Ref ref, int sessionId) {
  return ref.watch(activityDetailProvider(sessionId).future);
}

Future<List<AnalyticsPoint>?> _watchActivityAnalyticsPoints(
  Ref ref,
  int sessionId,
) async {
  final detail = await _watchActivityDetail(ref, sessionId);
  if (detail == null) {
    return null;
  }

  return _toAnalyticsPoints(detail.cleanedPoints);
}

// ---------------------------------------------------------------------------
// Threshold estimation (single-sourced private helper)
// ---------------------------------------------------------------------------

/// Estimates threshold pace from saved sessions.
///
/// 1. Filters to sessions with non-null `distanceMeters` / `movingTimeSeconds`
///    and moving time between 40–70 minutes, within the last 180 days.
/// 2. Returns the lowest (fastest) pace in s/km from qualifying sessions.
/// 3. Falls back to the median pace of all valid sessions if none qualify.
/// 4. Returns null if no sessions have distance/time data.
double? _estimateThresholdPace(List<TrackingSessionRecord> sessions) {
  final now = DateTime.now();
  final cutoff = now.subtract(const Duration(days: 180));

  final validSessions = <_SessionPace>[];
  for (final session in sessions) {
    final distance = session.distanceMeters;
    final time = session.movingTimeSeconds;
    if (distance == null || distance <= 0 || time == null || time <= 0) {
      continue;
    }
    final paceSecsPerKm = time / (distance / 1000);
    validSessions.add(
      _SessionPace(
        paceSecsPerKm: paceSecsPerKm,
        movingTimeSeconds: time,
        startedAt: session.startedAt,
      ),
    );
  }

  if (validSessions.isEmpty) return null;

  // Qualifying: 40-70 min moving time, within last 180 days.
  final qualifying = validSessions.where((s) {
    if (s.movingTimeSeconds < 2400 || s.movingTimeSeconds > 4200) return false;
    final started = s.startedAt;
    if (started == null || started.isBefore(cutoff)) return false;
    return true;
  }).toList();

  if (qualifying.isNotEmpty) {
    // Best (lowest) pace among qualifying sessions.
    qualifying.sort((a, b) => a.paceSecsPerKm.compareTo(b.paceSecsPerKm));
    return qualifying.first.paceSecsPerKm;
  }

  // Fallback: median pace of all valid sessions.
  validSessions.sort((a, b) => a.paceSecsPerKm.compareTo(b.paceSecsPerKm));
  final mid = validSessions.length ~/ 2;
  if (validSessions.length.isOdd) {
    return validSessions[mid].paceSecsPerKm;
  }
  return (validSessions[mid - 1].paceSecsPerKm +
          validSessions[mid].paceSecsPerKm) /
      2;
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Auto-estimated fitness profile from saved activity metadata.
final FutureProvider<FitnessProfile> fitnessProfileProvider =
    FutureProvider.autoDispose<FitnessProfile>((ref) async {
      final profileState = ref.watch(profileProvider);
      final sessions = await ref.watch(savedActivitiesProvider.future);
      final thresholdPace = _estimateThresholdPace(sessions);
      final lthr = profileState.asData?.value?.lthrBpm;

      return FitnessProfile(
        thresholdPaceSecsPerKm: thresholdPace,
        lthr: lthr,
      );
    });

/// Per-activity rTSS computed from cleaned track points.
final FutureProviderFamily<TrainingStressResult?, int> activityTssProvider =
    FutureProvider.autoDispose.family<TrainingStressResult?, int>(
      (ref, int sessionId) async {
        final analyticsPoints = await _watchActivityAnalyticsPoints(
          ref,
          sessionId,
        );
        if (analyticsPoints == null) return null;

        final profile = await ref.watch(fitnessProfileProvider.future);

        return TssCalculator.rTss(
          points: analyticsPoints,
          thresholdPaceSecsPerKm: profile.thresholdPaceSecsPerKm,
        );
      },
    );

/// Aggregated interval metrics for one activity.
class ActivityIntervalSummary {
  const ActivityIntervalSummary({
    required this.totalIntervals,
    required this.hardIntervals,
    required this.easyIntervals,
    required this.averageHardPaceSecsPerKm,
    required this.averageEasyPaceSecsPerKm,
  });

  final int totalIntervals;
  final int hardIntervals;
  final int easyIntervals;
  final double? averageHardPaceSecsPerKm;
  final double? averageEasyPaceSecsPerKm;
}

ActivityIntervalSummary? _summarizeIntervals(List<IntervalEvent> intervals) {
  if (intervals.isEmpty) {
    return null;
  }

  var hardIntervals = 0;
  var easyIntervals = 0;
  var hardPaceSum = 0.0;
  var easyPaceSum = 0.0;

  for (final interval in intervals) {
    if (interval.intensity == IntervalIntensity.hard) {
      hardIntervals += 1;
      hardPaceSum += interval.avgPaceSecsPerKm;
      continue;
    }

    easyIntervals += 1;
    easyPaceSum += interval.avgPaceSecsPerKm;
  }

  return ActivityIntervalSummary(
    totalIntervals: intervals.length,
    hardIntervals: hardIntervals,
    easyIntervals: easyIntervals,
    averageHardPaceSecsPerKm: hardIntervals == 0
        ? null
        : hardPaceSum / hardIntervals,
    averageEasyPaceSecsPerKm: easyIntervals == 0
        ? null
        : easyPaceSum / easyIntervals,
  );
}

/// Per-activity interval summary derived from cleaned track points.
final FutureProviderFamily<ActivityIntervalSummary?, int>
activityIntervalSummaryProvider = FutureProvider.autoDispose
    .family<ActivityIntervalSummary?, int>(
      (ref, int sessionId) async {
        final analyticsPoints = await _watchActivityAnalyticsPoints(
          ref,
          sessionId,
        );
        if (analyticsPoints == null) return null;

        return _summarizeIntervals(
          IntervalDetector.detect(points: analyticsPoints),
        );
      },
    );

/// Per-activity HR zone breakdown.
final FutureProviderFamily<HrZoneBreakdown?, int> activityHrZonesProvider =
    FutureProvider.autoDispose.family<HrZoneBreakdown?, int>(
      (ref, int sessionId) async {
        final analyticsPoints = await _watchActivityAnalyticsPoints(
          ref,
          sessionId,
        );
        if (analyticsPoints == null) return null;

        final profile = await ref.watch(fitnessProfileProvider.future);
        final lthr = profile.lthr;
        if (lthr == null) return null;

        final zones = HrZoneCalculator.forLthr(lthr, profile.sport);

        return HrZoneAnalyzer.analyze(points: analyticsPoints, zones: zones);
      },
    );

// ---------------------------------------------------------------------------
// Best recent effort (single-sourced private helper)
// ---------------------------------------------------------------------------

/// Finds the best recent effort suitable for race predictions and VDOT.
///
/// Filters to sessions with `distanceMeters` >= 5000, non-null
/// `movingTimeSeconds`, and `startedAt` within the last 90 days.
/// Returns a [RaceResult] from the session with the best average speed,
/// or null if no sessions qualify.
RaceResult? _bestRecentEffort(List<TrackingSessionRecord> sessions) {
  final now = DateTime.now();
  final cutoff = now.subtract(const Duration(days: 90));

  TrackingSessionRecord? best;
  double bestSpeedMs = 0;

  for (final session in sessions) {
    final distance = session.distanceMeters;
    final time = session.movingTimeSeconds;
    final started = session.startedAt;

    if (distance == null || distance < 5000) continue;
    if (time == null || time <= 0) continue;
    if (started == null || started.isBefore(cutoff)) continue;

    final speedMs = distance / time;
    if (speedMs > bestSpeedMs) {
      bestSpeedMs = speedMs;
      best = session;
    }
  }

  if (best == null) return null;

  return RaceResult(
    distanceMeters: best.distanceMeters!,
    duration: Duration(seconds: best.movingTimeSeconds!),
  );
}

// ---------------------------------------------------------------------------
// Aggregate providers
// ---------------------------------------------------------------------------

/// Single-sourced best recent effort, shared by [racePredictionsProvider] and
/// [vdotEstimateProvider].
final FutureProvider<RaceResult?> _bestRecentEffortProvider =
    FutureProvider.autoDispose<RaceResult?>((ref) async {
      final sessions = await ref.watch(savedActivitiesProvider.future);
      return _bestRecentEffort(sessions);
    });

/// PMC (Performance Management Chart) computed from session metadata.
///
/// Uses [TssCalculator.simpleTss] per session (not rTSS) to avoid loading
/// all track points for every activity — a deliberate performance decision.
final FutureProvider<List<PmcDay>> pmcProvider =
    FutureProvider.autoDispose<List<PmcDay>>((ref) async {
      final sessions = await ref.watch(savedActivitiesProvider.future);
      final profile = await ref.watch(fitnessProfileProvider.future);

      final dailyTss = <DateTime, double>{};
      DateTime? earliest;
      DateTime? latest;

      for (final session in sessions) {
        final distance = session.distanceMeters;
        final time = session.movingTimeSeconds;
        if (distance == null || distance <= 0 || time == null || time <= 0) {
          continue;
        }

        final avgPaceSecsPerKm = time / (distance / 1000);
        final result = TssCalculator.simpleTss(
          durationSeconds: time,
          avgPaceSecsPerKm: avgPaceSecsPerKm,
          thresholdPaceSecsPerKm: profile.thresholdPaceSecsPerKm,
        );
        if (result == null) continue;

        final day = _toUtcDay(session.startedAt ?? session.createdAt);
        dailyTss[day] = (dailyTss[day] ?? 0) + result.tss;

        if (earliest == null || day.isBefore(earliest)) earliest = day;
        if (latest == null || day.isAfter(latest)) latest = day;
      }

      if (earliest == null || latest == null) return const [];

      return PmcCalculator.calculate(
        dailyTss: dailyTss,
        rangeStart: earliest,
        rangeEnd: latest,
      );
    });

/// Race predictions based on best recent effort >= 5 km.
final FutureProvider<List<RacePrediction>> racePredictionsProvider =
    FutureProvider.autoDispose<List<RacePrediction>>((ref) async {
      final bestEffort = await ref.watch(_bestRecentEffortProvider.future);
      if (bestEffort == null) return const [];

      final profile = await ref.watch(fitnessProfileProvider.future);

      return RacePredictor.predictStandardRaces(
        bestEffort,
        exponent: profile.riegelExponent,
      );
    });

/// VDOT estimate based on best recent effort >= 5 km.
final FutureProvider<double?> vdotEstimateProvider =
    FutureProvider.autoDispose<double?>((ref) async {
      final bestEffort = await ref.watch(_bestRecentEffortProvider.future);
      if (bestEffort == null) return null;

      return VdotCalculator.estimate(bestEffort);
    });

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

DateTime _toUtcDay(DateTime dt) {
  final utc = dt.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

class _SessionPace {
  const _SessionPace({
    required this.paceSecsPerKm,
    required this.movingTimeSeconds,
    required this.startedAt,
  });

  final double paceSecsPerKm;
  final int movingTimeSeconds;
  final DateTime? startedAt;
}

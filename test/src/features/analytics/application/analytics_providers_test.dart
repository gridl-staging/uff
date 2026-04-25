import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/analytics/application/analytics_providers.dart';
import 'package:uff/src/features/analytics/domain/analytics_point.dart';
import 'package:uff/src/features/analytics/domain/hr_zone_analyzer.dart';
import 'package:uff/src/features/analytics/domain/hr_zone_calculator.dart';
import 'package:uff/src/features/analytics/domain/interval_detector.dart';
import 'package:uff/src/features/analytics/domain/interval_event.dart';
import 'package:uff/src/features/analytics/domain/sport_type.dart';
import 'package:uff/src/features/analytics/domain/training_stress.dart';
import 'package:uff/src/features/analytics/domain/tss_calculator.dart';
import 'package:uff/src/features/profile/data/profile.dart';

import 'analytics_provider_test_support.dart';

/// ## Test Scenarios
// - [positive] Fitness profile derives threshold pace from saved sessions
// - [positive] Fitness profile maps profile lthr bpm into the derived state
// - [negative] Missing session id returns null from per-activity analytics
// - [isolation] New provider container does not reuse prior user analytics state
// - [edge] Empty saved sessions yield null fitness fields
// - [statemachine] Profile loading/error states preserve threshold fallback behavior

/// Mirrors the production _toAnalyticsPoints conversion so tests can derive
/// expected values from the same public calculators the provider uses.
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

void main() {
  _registerFitnessProfileProviderTests();
  _registerActivityTssProviderTests();
  _registerActivityIntervalSummaryProviderTests();
  _registerActivityHrZonesProviderTests();
}

const _profileWithLthr = Profile(
  userId: 'user-1',
  preferredUnits: 'metric',
  defaultActivityVisibility: 'private',
  onboardingCompleted: true,
  lthrBpm: 165,
);

void _registerFitnessProfileProviderTests() {
  group('fitnessProfileProvider', () {
    test(
      'returns best qualifying pace from 40-70 min sessions',
      _returnsBestQualifyingPace,
    );
    test(
      'falls back to median pace when no sessions in 40-70 min range',
      _fallsBackToMedianPace,
    );
    test(
      'maps settled profile lthrBpm into fitness profile using only saved-sessions aggregate',
      _mapsSettledProfileLthrIntoFitnessProfile,
    );
    test(
      'keeps estimated threshold pace and null lthr when settled profile is null',
      _keepsEstimatedThresholdWhenProfileNull,
    );
    test(
      'keeps estimated threshold pace and null lthr when profile is loading',
      _keepsEstimatedThresholdWhenProfileLoading,
    );
    test(
      'keeps estimated threshold pace and null lthr when profile has error',
      _keepsEstimatedThresholdWhenProfileError,
    );
    test(
      'does not reuse prior user fitness state in a new provider container',
      _doesNotReusePriorUserFitnessState,
    );
    test('returns null fields when session list is empty', _returnsNullFields);
  });
}

Future<void> _returnsBestQualifyingPace() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();

  repository.sessionsById[1] = savedSession(
    id: 1,
    startedAt: now.subtract(const Duration(days: 10)),
    distanceMeters: 10000,
    movingTimeSeconds: 3000,
  );
  repository.sessionsById[2] = savedSession(
    id: 2,
    startedAt: now.subtract(const Duration(days: 5)),
    distanceMeters: 10000,
    movingTimeSeconds: 2700,
  );
  repository.sessionsById[3] = savedSession(
    id: 3,
    startedAt: now.subtract(const Duration(days: 3)),
    distanceMeters: 5000,
    movingTimeSeconds: 1200,
  );

  final container = createContainer(repository);
  addTearDown(container.dispose);

  final profile = await container.read(fitnessProfileProvider.future);
  expect(profile.thresholdPaceSecsPerKm, 270);
}

Future<void> _fallsBackToMedianPace() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();

  repository.sessionsById[1] = savedSession(
    id: 1,
    startedAt: now.subtract(const Duration(days: 10)),
    distanceMeters: 5000,
    movingTimeSeconds: 1200,
  );
  repository.sessionsById[2] = savedSession(
    id: 2,
    startedAt: now.subtract(const Duration(days: 5)),
    distanceMeters: 8000,
    movingTimeSeconds: 1800,
  );
  repository.sessionsById[3] = savedSession(
    id: 3,
    startedAt: now.subtract(const Duration(days: 3)),
    distanceMeters: 4000,
    movingTimeSeconds: 900,
  );

  final container = createContainer(repository);
  addTearDown(container.dispose);

  final profile = await container.read(fitnessProfileProvider.future);
  expect(profile.thresholdPaceSecsPerKm, 225);
}

Future<void> _returnsNullFields() async {
  final repository = FakeTrackingRepository();
  final container = createContainer(repository);
  addTearDown(container.dispose);

  final profile = await container.read(fitnessProfileProvider.future);
  expect(profile.thresholdPaceSecsPerKm, isNull);
  expect(profile.lthr, isNull);
  expect(profile.ftpWatts, isNull);
}

Future<void> _mapsSettledProfileLthrIntoFitnessProfile() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();
  _seedSingleThresholdSession(repository, now);

  final container = createContainer(
    repository,
    profileState: const AsyncData<Profile?>(_profileWithLthr),
  );
  addTearDown(container.dispose);

  final profile = await container.read(fitnessProfileProvider.future);
  expect(profile.thresholdPaceSecsPerKm, 300);
  expect(profile.lthr, 165);
  expect(repository.loadSavedSessionsCallCount, 1);
  expect(repository.loadSessionCallCount, 0);
  expect(repository.loadPointsForSessionCallCount, 0);
}

/// Shared helper: verifies that a seeded threshold session yields
/// thresholdPaceSecsPerKm=300 and lthr=null under the given profile state.
Future<void> _assertKeepsEstimatedThreshold(
  AsyncValue<Profile?> profileState,
) async {
  final repository = FakeTrackingRepository();
  _seedSingleThresholdSession(repository, DateTime.now());

  final container = createContainer(repository, profileState: profileState);
  addTearDown(container.dispose);

  final profile = await container.read(fitnessProfileProvider.future);
  expect(profile.thresholdPaceSecsPerKm, 300);
  expect(profile.lthr, isNull);
}

Future<void> _keepsEstimatedThresholdWhenProfileNull() =>
    _assertKeepsEstimatedThreshold(const AsyncData<Profile?>(null));

Future<void> _keepsEstimatedThresholdWhenProfileLoading() =>
    _assertKeepsEstimatedThreshold(const AsyncLoading<Profile?>());

Future<void> _keepsEstimatedThresholdWhenProfileError() =>
    _assertKeepsEstimatedThreshold(
      AsyncError<Profile?>(StateError('boom'), StackTrace.empty),
    );

Future<void> _doesNotReusePriorUserFitnessState() async {
  final firstRepository = FakeTrackingRepository();
  final secondRepository = FakeTrackingRepository();
  final now = DateTime.now();
  _seedSingleThresholdSession(firstRepository, now);

  final firstContainer = createContainer(
    firstRepository,
    profileState: const AsyncData<Profile?>(_profileWithLthr),
  );
  addTearDown(firstContainer.dispose);

  final firstProfile = await firstContainer.read(fitnessProfileProvider.future);
  expect(firstProfile.thresholdPaceSecsPerKm, 300);
  expect(firstProfile.lthr, 165);
  expect(firstRepository.loadSavedSessionsCallCount, 1);

  final secondContainer = createContainer(secondRepository);
  addTearDown(secondContainer.dispose);

  final secondProfile = await secondContainer.read(
    fitnessProfileProvider.future,
  );
  expect(secondProfile.thresholdPaceSecsPerKm, isNull);
  expect(secondProfile.lthr, isNull);
  expect(secondProfile.ftpWatts, isNull);
  expect(secondRepository.loadSavedSessionsCallCount, 1);
}

void _seedSingleThresholdSession(
  FakeTrackingRepository repository,
  DateTime now,
) {
  repository.sessionsById[100] = savedSession(
    id: 100,
    startedAt: now.subtract(const Duration(days: 2)),
    distanceMeters: 10000,
    movingTimeSeconds: 3000,
  );
}

void _registerActivityTssProviderTests() {
  group('activityTssProvider', () {
    test(
      'returns rTSS for session with constant speed points and auto-estimated threshold',
      _returnsRtssForSavedSession,
    );
    test(
      'returns null for non-existent session',
      _returnsNullForMissingSession,
    );
    test(
      'returns null when all speed values are null',
      _returnsNullWhenPointsHaveNoSpeed,
    );
  });
}

void _registerActivityIntervalSummaryProviderTests() {
  group('activityIntervalSummaryProvider', () {
    test(
      'returns interval summary for alternating hard/easy segments',
      _returnsIntervalSummaryForAlternatingSegments,
    );
    test(
      'returns null for non-existent session',
      _returnsNullIntervalSummaryForMissingSession,
    );
    test(
      'returns null when points do not contain enough intervals',
      _returnsNullIntervalSummaryWhenNoIntervalsDetected,
    );
  });
}

Future<void> _returnsRtssForSavedSession() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();
  const sessionId = 10;

  repository.sessionsById[sessionId] = savedSession(
    id: sessionId,
    startedAt: now.subtract(const Duration(days: 1)),
    distanceMeters: 10000,
    movingTimeSeconds: 3000,
  );
  final fixturePoints = _constantSpeedPoints(
    sessionId: sessionId,
    start: now.subtract(const Duration(days: 1)),
  );
  repository.pointsBySessionId[sessionId] = fixturePoints;

  final container = createContainer(repository);
  addTearDown(container.dispose);

  final result = await container.read(activityTssProvider(sessionId).future);

  // Derive exact expected rTSS using the same public calculator with
  // the same fixture data and threshold (300 s/km from auto-estimation).
  final expected = TssCalculator.rTss(
    points: _toAnalyticsPoints(fixturePoints),
    thresholdPaceSecsPerKm: 300,
  );
  // provider returns rTSS method for valid session with points
  expect(result?.method, TssMethod.rTSS);
  // reference calculator also returns rTSS method
  expect(expected?.method, TssMethod.rTSS);
  // provider result matches direct calculator output
  expect(result?.tss, expected!.tss);
  expect(result?.intensityFactor, expected.intensityFactor);
}

List<TrackingPoint> _constantSpeedPoints({
  required int sessionId,
  required DateTime start,
}) {
  final points = <TrackingPoint>[];
  for (var i = 0; i <= 300; i++) {
    points.add(
      TrackingPoint(
        sessionId: sessionId,
        timestamp: start.add(Duration(seconds: i * 10)),
        coordinate: GeoCoordinate(
          latitude: 47 + (i * 0.0001),
          longitude: 8,
        ),
        speed: 3.33,
        elevation: 400,
      ),
    );
  }
  return points;
}

Future<void> _returnsNullForMissingSession() async {
  final repository = FakeTrackingRepository();
  final container = createContainer(repository);
  addTearDown(container.dispose);

  final result = await container.read(activityTssProvider(999).future);
  expect(result, isNull);
}

Future<void> _returnsNullWhenPointsHaveNoSpeed() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();
  const sessionId = 20;
  final baseTime = now.subtract(const Duration(days: 1));

  repository.sessionsById[sessionId] = savedSession(
    id: sessionId,
    startedAt: baseTime,
    distanceMeters: 10000,
    movingTimeSeconds: 3000,
  );
  repository.pointsBySessionId[sessionId] = [
    TrackingPoint(
      sessionId: sessionId,
      timestamp: baseTime,
      coordinate: const GeoCoordinate(latitude: 47, longitude: 8),
    ),
    TrackingPoint(
      sessionId: sessionId,
      timestamp: baseTime.add(const Duration(seconds: 10)),
      coordinate: const GeoCoordinate(latitude: 47.001, longitude: 8),
    ),
  ];

  final container = createContainer(repository);
  addTearDown(container.dispose);

  final result = await container.read(activityTssProvider(sessionId).future);
  expect(result, isNull);
}

Future<void> _returnsIntervalSummaryForAlternatingSegments() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();
  const sessionId = 25;
  final start = now.subtract(const Duration(days: 1));

  repository.sessionsById[sessionId] = savedSession(
    id: sessionId,
    startedAt: start,
    distanceMeters: 3000,
    movingTimeSeconds: 360,
  );
  final fixturePoints = _alternatingSpeedPoints(
    sessionId: sessionId,
    start: start,
    segmentDurationsSeconds: const [120, 120, 120],
    segmentSpeedsMs: const [5.0, 2.5, 5.0],
  );
  repository.pointsBySessionId[sessionId] = fixturePoints;

  final container = createContainer(repository);
  addTearDown(container.dispose);

  final result = await container.read(
    activityIntervalSummaryProvider(sessionId).future,
  );

  // Derive exact expected paces from the same IntervalDetector pipeline.
  final intervals = IntervalDetector.detect(
    points: _toAnalyticsPoints(fixturePoints),
  );
  var hardPaceSum = 0.0;
  var hardCount = 0;
  var easyPaceSum = 0.0;
  var easyCount = 0;
  for (final interval in intervals) {
    if (interval.intensity == IntervalIntensity.hard) {
      hardCount++;
      hardPaceSum += interval.avgPaceSecsPerKm;
    } else {
      easyCount++;
      easyPaceSum += interval.avgPaceSecsPerKm;
    }
  }

  // concrete interval counts prove result is non-null
  expect(result?.totalIntervals, 3);
  // 2 hard intervals from the alternating speed fixture
  expect(result?.hardIntervals, 2);
  // 1 easy interval from the alternating speed fixture
  expect(result?.easyIntervals, 1);
  expect(result?.averageHardPaceSecsPerKm, hardPaceSum / hardCount);
  expect(result?.averageEasyPaceSecsPerKm, easyPaceSum / easyCount);
}

Future<void> _returnsNullIntervalSummaryForMissingSession() async {
  final repository = FakeTrackingRepository();
  final container = createContainer(repository);
  addTearDown(container.dispose);

  final result = await container.read(
    activityIntervalSummaryProvider(999).future,
  );
  expect(result, isNull);
}

Future<void> _returnsNullIntervalSummaryWhenNoIntervalsDetected() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();
  const sessionId = 26;

  repository.sessionsById[sessionId] = savedSession(
    id: sessionId,
    startedAt: now.subtract(const Duration(days: 1)),
    distanceMeters: 10000,
    movingTimeSeconds: 3000,
  );
  repository.pointsBySessionId[sessionId] = _constantSpeedPoints(
    sessionId: sessionId,
    start: now.subtract(const Duration(days: 1)),
  );

  final container = createContainer(repository);
  addTearDown(container.dispose);

  final result = await container.read(
    activityIntervalSummaryProvider(sessionId).future,
  );
  expect(result, isNull);
}

List<TrackingPoint> _alternatingSpeedPoints({
  required int sessionId,
  required DateTime start,
  required List<int> segmentDurationsSeconds,
  required List<double> segmentSpeedsMs,
}) {
  final points = <TrackingPoint>[];
  var elapsedSeconds = 0;
  var latitude = 47.0;

  for (
    var segmentIndex = 0;
    segmentIndex < segmentDurationsSeconds.length;
    segmentIndex++
  ) {
    final segmentDuration = segmentDurationsSeconds[segmentIndex];
    final segmentSpeed = segmentSpeedsMs[segmentIndex];

    for (var second = 0; second < segmentDuration; second++) {
      points.add(
        TrackingPoint(
          sessionId: sessionId,
          timestamp: start.add(Duration(seconds: elapsedSeconds)),
          coordinate: GeoCoordinate(latitude: latitude, longitude: 8),
          speed: segmentSpeed,
        ),
      );
      elapsedSeconds += 1;
      latitude += 0.00001;
    }
  }

  return points;
}

void _registerActivityHrZonesProviderTests() {
  group('activityHrZonesProvider', () {
    test(
      'returns null when lthr is null in fitness profile',
      _returnsNullWhenLthrMissing,
    );
    test(
      'returns null for non-existent session',
      _returnsNullHrZonesForMissingSession,
    );
    test(
      'returns HrZoneBreakdown with zero total seconds when points have no HR data',
      _returnsZeroSecondHrBreakdown,
    );
    test(
      'returns positive total seconds when lthr and HR samples are present',
      _returnsPositiveHrBreakdownWithLthrAndHrSamples,
    );
  });
}

Future<void> _returnsNullWhenLthrMissing() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();
  const sessionId = 30;

  repository.sessionsById[sessionId] = savedSession(
    id: sessionId,
    startedAt: now.subtract(const Duration(days: 1)),
    distanceMeters: 10000,
    movingTimeSeconds: 3000,
  );
  repository.pointsBySessionId[sessionId] = [
    TrackingPoint(
      sessionId: sessionId,
      timestamp: now.subtract(const Duration(days: 1)),
      coordinate: const GeoCoordinate(latitude: 47, longitude: 8),
    ),
  ];

  final container = createContainer(repository);
  addTearDown(container.dispose);

  final result = await container.read(
    activityHrZonesProvider(sessionId).future,
  );
  expect(result, isNull);
}

Future<void> _returnsNullHrZonesForMissingSession() async {
  final repository = FakeTrackingRepository();
  final container = createContainer(repository);
  addTearDown(container.dispose);

  final result = await container.read(activityHrZonesProvider(999).future);
  expect(result, isNull);
}

Future<void> _returnsZeroSecondHrBreakdown() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();
  const sessionId = 40;
  final baseTime = now.subtract(const Duration(days: 1));

  repository.sessionsById[sessionId] = savedSession(
    id: sessionId,
    startedAt: baseTime,
    distanceMeters: 10000,
    movingTimeSeconds: 3000,
  );
  repository.pointsBySessionId[sessionId] = [
    TrackingPoint(
      sessionId: sessionId,
      timestamp: baseTime,
      coordinate: const GeoCoordinate(latitude: 47, longitude: 8),
      speed: 3.33,
    ),
    TrackingPoint(
      sessionId: sessionId,
      timestamp: baseTime.add(const Duration(seconds: 10)),
      coordinate: const GeoCoordinate(latitude: 47.001, longitude: 8),
      speed: 3.33,
    ),
  ];

  final container = createContainer(
    repository,
    profileState: const AsyncData<Profile?>(_profileWithLthr),
  );
  addTearDown(container.dispose);

  final result = await container.read(
    activityHrZonesProvider(sessionId).future,
  );
  // LTHR set but no HR samples → totalSeconds = 0 proves non-null
  expect(result?.totalSeconds, 0);
}

Future<void> _returnsPositiveHrBreakdownWithLthrAndHrSamples() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();
  const sessionId = 41;
  final baseTime = now.subtract(const Duration(days: 1));

  repository.sessionsById[sessionId] = savedSession(
    id: sessionId,
    startedAt: baseTime,
    distanceMeters: 10000,
    movingTimeSeconds: 3000,
  );
  final fixturePoints = [
    TrackingPoint(
      sessionId: sessionId,
      timestamp: baseTime,
      coordinate: const GeoCoordinate(latitude: 47, longitude: 8),
      speed: 3.33,
      heartRateBpm: 162,
    ),
    TrackingPoint(
      sessionId: sessionId,
      timestamp: baseTime.add(const Duration(seconds: 10)),
      coordinate: const GeoCoordinate(latitude: 47.001, longitude: 8),
      speed: 3.33,
      heartRateBpm: 170,
    ),
    TrackingPoint(
      sessionId: sessionId,
      timestamp: baseTime.add(const Duration(seconds: 20)),
      coordinate: const GeoCoordinate(latitude: 47.002, longitude: 8),
      speed: 3.33,
      heartRateBpm: 176,
    ),
  ];
  repository.pointsBySessionId[sessionId] = fixturePoints;

  final container = createContainer(
    repository,
    profileState: const AsyncData<Profile?>(_profileWithLthr),
  );
  addTearDown(container.dispose);

  final result = await container.read(
    activityHrZonesProvider(sessionId).future,
  );

  // Derive exact expected HR zone breakdown using the same public calculators.
  final zones = HrZoneCalculator.forLthr(165, SportType.run);
  final expected = HrZoneAnalyzer.analyze(
    points: _toAnalyticsPoints(fixturePoints),
    zones: zones,
  );
  // concrete zone comparison proves result non-null; matches reference analyzer
  expect(result?.totalSeconds, expected.totalSeconds);
  expect(result?.secondsPerZone, expected.secondsPerZone);
}

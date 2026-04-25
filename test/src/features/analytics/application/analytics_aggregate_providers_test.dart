import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/analytics/application/analytics_providers.dart';
import 'package:uff/src/features/analytics/domain/fitness_profile.dart';
import 'package:uff/src/features/analytics/domain/pmc_calculator.dart';
import 'package:uff/src/features/analytics/domain/race_prediction.dart';
import 'package:uff/src/features/analytics/domain/race_predictor.dart';
import 'package:uff/src/features/analytics/domain/training_stress.dart';
import 'package:uff/src/features/analytics/domain/tss_calculator.dart';
import 'package:uff/src/features/analytics/domain/vdot_calculator.dart';

import 'analytics_provider_test_support.dart';

/// ## Test Scenarios
/// - [positive] `pmcProvider` computes deterministic PMC output from saved sessions
/// - [positive] `racePredictionsProvider` returns exact standard-race predictions from best effort
/// - [negative] Sub-5k or invalid efforts yield empty race predictions
/// - [positive] `vdotEstimateProvider` mirrors `VdotCalculator` output for best effort
/// - [edge] Empty saved sessions yield empty/null aggregate analytics outputs

void main() {
  _registerPmcProviderTests();
  _registerRacePredictionsProviderTests();
  _registerVdotEstimateProviderTests();
}

void _registerPmcProviderTests() {
  group('pmcProvider', () {
    test(
      'produces PMC days with CTL carry-forward across days',
      _producesPmcDaysAcrossTwoDays,
    );
    test('returns empty list when no saved activities', _returnsEmptyPmcList);
  });
}

Future<void> _producesPmcDaysAcrossTwoDays() async {
  final repository = FakeTrackingRepository();
  final day1 = DateTime.utc(2026, 3, 1, 10);
  final day2 = DateTime.utc(2026, 3, 2, 10);

  repository.sessionsById[1] = savedSession(
    id: 1,
    startedAt: day1,
    distanceMeters: 10000,
    movingTimeSeconds: 3000,
  );
  repository.sessionsById[2] = savedSession(
    id: 2,
    startedAt: day2,
    distanceMeters: 8000,
    movingTimeSeconds: 2400,
  );

  final container = createContainer(repository);
  addTearDown(container.dispose);

  final pmcDays = await container.read(pmcProvider.future);
  expect(pmcDays.length, 2);
  expect(pmcDays.first.date, DateTime.utc(2026, 3));
  expect(pmcDays.last.date, DateTime.utc(2026, 3, 2));
  _expectSimpleTss(pmcDays.first.tssOnDay, 3000);
  _expectSimpleTss(pmcDays.last.tssOnDay, 2400);

  // Derive exact CTL expectation via PmcCalculator with the known TSS values.
  final tss1 = TssCalculator.simpleTss(
    durationSeconds: 3000,
    avgPaceSecsPerKm: 300,
    thresholdPaceSecsPerKm: 300,
  )!.tss;
  final tss2 = TssCalculator.simpleTss(
    durationSeconds: 2400,
    avgPaceSecsPerKm: 300,
    thresholdPaceSecsPerKm: 300,
  )!.tss;
  final expectedPmc = PmcCalculator.calculate(
    dailyTss: {
      DateTime.utc(2026, 3): tss1,
      DateTime.utc(2026, 3, 2): tss2,
    },
    rangeStart: DateTime.utc(2026, 3),
    rangeEnd: DateTime.utc(2026, 3, 2),
  );
  expect(pmcDays.last.ctl, expectedPmc.last.ctl);
}

void _expectSimpleTss(double actual, int durationSeconds) {
  final result = TssCalculator.simpleTss(
    durationSeconds: durationSeconds,
    avgPaceSecsPerKm: 300,
    thresholdPaceSecsPerKm: 300,
  );
  // simpleTss with valid inputs always returns simpleTSS method (proves non-null)
  expect(result?.method, TssMethod.simpleTSS);
  // method assertion above proves non-null; ! needed for closeTo's num parameter
  expect(actual, closeTo(result!.tss, 1e-9));
}

Future<void> _returnsEmptyPmcList() async {
  final repository = FakeTrackingRepository();
  final container = createContainer(repository);
  addTearDown(container.dispose);

  final pmcDays = await container.read(pmcProvider.future);
  expect(pmcDays, isEmpty);
}

void _registerRacePredictionsProviderTests() {
  group('racePredictionsProvider', () {
    test(
      'returns predictions for distances > 5 km from qualifying session',
      _returnsPredictionsForQualifyingSession,
    );
    test(
      'returns empty list when session distance < 5000 m',
      _returnsEmptyForShortSession,
    );
    test(
      'returns empty list when no sessions have valid distance/time',
      _returnsEmptyWithoutValidSessions,
    );
    test(
      'uses fitnessProfile.riegelExponent for prediction times',
      _usesFitnessProfileRiegelExponent,
    );
    test(
      'uses fastest recent effort and ignores older faster sessions',
      _usesFastestRecentEffortForPredictions,
    );
  });
}

Future<void> _returnsPredictionsForQualifyingSession() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();

  repository.sessionsById[1] = savedSession(
    id: 1,
    startedAt: now.subtract(const Duration(days: 5)),
    distanceMeters: 5000,
    movingTimeSeconds: 1200,
  );

  final container = createContainer(repository);
  addTearDown(container.dispose);

  final predictions = await container.read(racePredictionsProvider.future);
  final expected = RacePredictor.predictStandardRaces(
    const RaceResult(distanceMeters: 5000, duration: Duration(seconds: 1200)),
  );
  expect(predictions.length, expected.length);
  for (var i = 0; i < predictions.length; i++) {
    expect(predictions[i].distanceMeters, expected[i].distanceMeters);
    expect(predictions[i].predictedTime, expected[i].predictedTime);
  }
}

Future<void> _returnsEmptyForShortSession() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();

  repository.sessionsById[1] = savedSession(
    id: 1,
    startedAt: now.subtract(const Duration(days: 5)),
    distanceMeters: 3000,
    movingTimeSeconds: 900,
  );

  final container = createContainer(repository);
  addTearDown(container.dispose);

  final predictions = await container.read(racePredictionsProvider.future);
  expect(predictions, isEmpty);
}

Future<void> _returnsEmptyWithoutValidSessions() async {
  final repository = FakeTrackingRepository();
  final container = createContainer(repository);
  addTearDown(container.dispose);

  final predictions = await container.read(racePredictionsProvider.future);
  expect(predictions, isEmpty);
}

Future<void> _usesFitnessProfileRiegelExponent() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();
  const exponent = 1.2;

  repository.sessionsById[1] = savedSession(
    id: 1,
    startedAt: now.subtract(const Duration(days: 5)),
    distanceMeters: 5000,
    movingTimeSeconds: 1200,
  );

  final container = ProviderContainer(
    overrides: [
      trackingRepositoryProvider.overrideWithValue(repository),
      fitnessProfileProvider.overrideWith(
        (ref) async => const FitnessProfile(riegelExponent: exponent),
      ),
    ],
  );
  addTearDown(container.dispose);

  final predictions = await container.read(racePredictionsProvider.future);
  final expected = RacePredictor.predictStandardRaces(
    const RaceResult(distanceMeters: 5000, duration: Duration(seconds: 1200)),
    exponent: exponent,
  );

  expect(predictions.length, expected.length);
  for (var i = 0; i < predictions.length; i++) {
    expect(predictions[i].distanceMeters, expected[i].distanceMeters);
    expect(predictions[i].predictedTime, expected[i].predictedTime);
  }
}

Future<void> _usesFastestRecentEffortForPredictions() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();

  repository.sessionsById[1] = savedSession(
    id: 1,
    startedAt: now.subtract(const Duration(days: 10)),
    distanceMeters: 5000,
    movingTimeSeconds: 1250,
  );
  repository.sessionsById[2] = savedSession(
    id: 2,
    startedAt: now.subtract(const Duration(days: 5)),
    distanceMeters: 6000,
    movingTimeSeconds: 1200,
  );
  repository.sessionsById[3] = savedSession(
    id: 3,
    startedAt: now.subtract(const Duration(days: 120)),
    distanceMeters: 5000,
    movingTimeSeconds: 900,
  );

  final container = createContainer(repository);
  addTearDown(container.dispose);

  final predictions = await container.read(racePredictionsProvider.future);
  final expected = RacePredictor.predictStandardRaces(
    const RaceResult(distanceMeters: 6000, duration: Duration(seconds: 1200)),
  );

  expect(predictions.length, expected.length);
  for (var i = 0; i < predictions.length; i++) {
    expect(predictions[i].distanceMeters, expected[i].distanceMeters);
    expect(predictions[i].predictedTime, expected[i].predictedTime);
  }
}

void _registerVdotEstimateProviderTests() {
  group('vdotEstimateProvider', () {
    test(
      'returns VDOT close to 49.8 for 5000 m / 20 min effort',
      _returnsExpectedVdotEstimate,
    );
    test(
      'returns null when no valid sessions',
      _returnsNullWithoutValidSessions,
    );
    test(
      'uses fastest recent effort and ignores older faster sessions',
      _usesFastestRecentEffortForVdot,
    );
  });
}

Future<void> _returnsExpectedVdotEstimate() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();

  repository.sessionsById[1] = savedSession(
    id: 1,
    startedAt: now.subtract(const Duration(days: 5)),
    distanceMeters: 5000,
    movingTimeSeconds: 1200,
  );

  final container = createContainer(repository);
  addTearDown(container.dispose);

  final vdot = await container.read(vdotEstimateProvider.future);
  final expected = VdotCalculator.estimate(
    const RaceResult(distanceMeters: 5000, duration: Duration(seconds: 1200)),
  );
  // closeTo proves non-null; VDOT from 5km in 1200s via VdotCalculator.estimate
  expect(vdot, closeTo(expected, 1e-12));
}

Future<void> _returnsNullWithoutValidSessions() async {
  final repository = FakeTrackingRepository();
  final container = createContainer(repository);
  addTearDown(container.dispose);

  final vdot = await container.read(vdotEstimateProvider.future);
  expect(vdot, isNull);
}

Future<void> _usesFastestRecentEffortForVdot() async {
  final repository = FakeTrackingRepository();
  final now = DateTime.now();

  repository.sessionsById[1] = savedSession(
    id: 1,
    startedAt: now.subtract(const Duration(days: 10)),
    distanceMeters: 5000,
    movingTimeSeconds: 1250,
  );
  repository.sessionsById[2] = savedSession(
    id: 2,
    startedAt: now.subtract(const Duration(days: 5)),
    distanceMeters: 6000,
    movingTimeSeconds: 1200,
  );
  repository.sessionsById[3] = savedSession(
    id: 3,
    startedAt: now.subtract(const Duration(days: 120)),
    distanceMeters: 5000,
    movingTimeSeconds: 900,
  );

  final container = createContainer(repository);
  addTearDown(container.dispose);

  final vdot = await container.read(vdotEstimateProvider.future);
  final expected = VdotCalculator.estimate(
    const RaceResult(distanceMeters: 6000, duration: Duration(seconds: 1200)),
  );

  // closeTo proves non-null; fastest recent = 6km/1200s (session 2)
  expect(vdot, closeTo(expected, 1e-12));
}

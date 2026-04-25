import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/analytics/application/analytics_providers.dart';
import 'package:uff/src/features/analytics/domain/pmc_day.dart';
import 'package:uff/src/features/analytics/domain/race_prediction.dart';
import 'package:uff/src/features/analytics/presentation/analytics_screen.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/settings/presentation/settings_routes.dart';

const expectedAnalyticsEmptyStateMessage =
    'Record some activities to see your training analytics';
const expectedTrainingLoadEmptyStateMessage =
    'No training load data yet. Record your first run.';
const expectedPmcChartEmptyStateMessage =
    'Not enough data to display the chart.';
const expectedRacePredictionsLoadingMessage = 'Loading race predictions...';
const expectedVdotLoadingMessage = 'Loading VDOT estimate...';
const expectedRacePredictionsErrorMessage = 'Unable to load race predictions.';
const expectedVdotErrorMessage = 'Unable to load VDOT estimate.';
const expectedRacePredictionsUnavailableMessage =
    'Race predictions are unavailable right now.';
const expectedNoPredictionsOrVdotMessage =
    'No race prediction data yet. Complete a recent run of at least 5 km.';
const expectedNoPredictionsWithVdotMessage =
    'This effort is already at or beyond the longest standard race distance we predict.';
const String expectedHrZonesRoutePath = SettingsRoutes.hrZonesPath;

enum AnalyticsProfileState { missingLthr, configuredLthr, loading, error }

Finder findHrZonesSetupCta({bool skipOffstage = false}) {
  return find.byKey(
    AnalyticsScreen.hrZonesSetupCtaKey,
    skipOffstage: skipOffstage,
  );
}

void expectHrZonesSetupCtaPresent({bool skipOffstage = false}) {
  expect(findHrZonesSetupCta(skipOffstage: skipOffstage), findsOneWidget);
}

void expectHrZonesSetupCtaAbsent({bool skipOffstage = false}) {
  expect(findHrZonesSetupCta(skipOffstage: skipOffstage), findsNothing);
}

AsyncValue<Profile?> profileStateFor(AnalyticsProfileState state) {
  return switch (state) {
    AnalyticsProfileState.missingLthr => AsyncData<Profile?>(
      _testProfile(lthrBpm: null),
    ),
    AnalyticsProfileState.configuredLthr => AsyncData<Profile?>(
      _testProfile(lthrBpm: 170),
    ),
    AnalyticsProfileState.loading => const AsyncLoading<Profile?>(),
    AnalyticsProfileState.error => AsyncError<Profile?>(
      StateError('profile failed'),
      StackTrace.empty,
    ),
  };
}

List<Override> successfulAnalyticsScreenOverrides({
  AnalyticsProfileState profileState = AnalyticsProfileState.missingLthr,
}) {
  return [
    pmcProvider.overrideWith((ref) async => pmcSampleDays()),
    racePredictionsProvider.overrideWith((ref) async => samplePredictions()),
    vdotEstimateProvider.overrideWith((ref) async => 50.0),
    profileProvider.overrideWith(
      () => FakeAnalyticsProfileNotifier(profileStateFor(profileState)),
    ),
  ];
}

/// Verifies that the AnalyticsScreen widget tree rendered. The AppBar with
/// title "Analytics" is now provided by HomeShellScreen, not AnalyticsScreen
/// itself (double-AppBar fix), so we verify the screen widget exists instead.
void expectAnalyticsScreenRendered(WidgetTester tester) {
  expect(find.byType(AnalyticsScreen), findsOneWidget);
}

List<PmcDay> pmcSampleDays() => [
  PmcDay(date: DateTime(2025), ctl: 50, atl: 60, tsb: -10, tssOnDay: 80),
  PmcDay(date: DateTime(2025, 1, 2), ctl: 51, atl: 58, tsb: -7, tssOnDay: 40),
];

List<RacePrediction> samplePredictions() => const [
  RacePrediction(
    label: '10 km',
    distanceMeters: 10000,
    predictedTime: Duration(minutes: 43, seconds: 10),
    intensityFactor: 1,
  ),
  RacePrediction(
    label: 'Marathon',
    distanceMeters: 42195,
    predictedTime: Duration(hours: 3, minutes: 18, seconds: 6),
    intensityFactor: 1,
  ),
];

Future<void> bringIntoView(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> dragToRefresh(WidgetTester tester, Finder dragTarget) async {
  await tester.drag(dragTarget, const Offset(0, 300));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

List<TrackingSessionRecord> savedActivitiesSample() => [
  TrackingSessionRecord(
    id: 1,
    status: TrackingSessionStatus.saved,
    createdAt: DateTime.utc(2025, 1, 1, 8),
    updatedAt: DateTime.utc(2025, 1, 1, 8, 30),
    startedAt: DateTime.utc(2025, 1, 1, 8),
    distanceMeters: 6200,
    movingTimeSeconds: 1740,
  ),
];

Profile _testProfile({required int? lthrBpm}) {
  return Profile(
    userId: 'analytics-user',
    preferredUnits: 'metric',
    defaultActivityVisibility: 'private',
    onboardingCompleted: true,
    lthrBpm: lthrBpm,
  );
}

class FakeAnalyticsProfileNotifier extends ProfileNotifier {
  FakeAnalyticsProfileNotifier(this.profileState);

  final AsyncValue<Profile?> profileState;

  @override
  FutureOr<Profile?> build() {
    return profileState.when(
      data: (profile) => profile,
      loading: () => Completer<Profile?>().future,
      error: Error.throwWithStackTrace,
    );
  }
}

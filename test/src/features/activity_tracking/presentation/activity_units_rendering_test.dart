import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_controller.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_history_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/recording_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';

import 'activity_detail_screen_test_support.dart';

const _imperialProfile = Profile(
  userId: 'user-1',
  preferredUnits: 'imperial',
  defaultActivityVisibility: 'private',
  onboardingCompleted: true,
);

class _StaticProfileNotifier extends ProfileNotifier {
  _StaticProfileNotifier(this.profile);

  final Profile? profile;

  @override
  FutureOr<Profile?> build() => profile;
}

class _StaticRecordingController extends RecordingController {
  _StaticRecordingController(this.stateForBuild);

  final RecordingControllerState stateForBuild;

  @override
  RecordingControllerState build() => stateForBuild;
}

void main() {
  configureActivityDetailScreenTests();

  testWidgets('recording screen respects imperial distance and pace', (
    tester,
  ) async {
    final points = [
      TrackingPoint(
        sessionId: 1,
        timestamp: DateTime(2025, 1, 1, 12),
        coordinate: const GeoCoordinate(latitude: 0, longitude: 0),
      ),
      TrackingPoint(
        sessionId: 1,
        timestamp: DateTime(2025, 1, 1, 12, 25),
        coordinate: const GeoCoordinate(latitude: 0, longitude: 0.045),
      ),
    ];
    const elapsed = Duration(minutes: 25);
    final distanceMeters = calculateTrackDistanceMeters(points);
    final expectedDistance = formatDistance(
      distanceMeters,
      preferredUnits: 'imperial',
    );
    final expectedPace = formatPaceForPreferredUnits(
      pacePerKilometer: calculatePacePerKilometer(
        distanceMeters: distanceMeters,
        elapsedTime: elapsed,
      ),
      pacePerMile: calculatePacePerMile(
        distanceMeters: distanceMeters,
        elapsedTime: elapsed,
      ),
      preferredUnits: 'imperial',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith(
            () => _StaticProfileNotifier(_imperialProfile),
          ),
          recordingControllerProvider.overrideWith(
            () => _StaticRecordingController(
              RecordingControllerState(
                status: TrackingSessionStatus.paused,
                session: TrackingSessionRecord(
                  id: 1,
                  status: TrackingSessionStatus.paused,
                  createdAt: DateTime(2025, 1, 1, 12),
                  updatedAt: DateTime(2025, 1, 1, 12, 25),
                ),
                points: points,
                timeline: const RecordingTimeline(
                  activeDuration: Duration(minutes: 25),
                ),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: RecordingScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Distance: $expectedDistance'), findsOneWidget);
    expect(find.text('Pace: $expectedPace'), findsOneWidget);
  });

  testWidgets('activity history respects imperial distance and pace', (
    tester,
  ) async {
    final session = TrackingSessionRecord(
      id: 10,
      status: TrackingSessionStatus.saved,
      createdAt: DateTime(2025, 1, 5, 8),
      updatedAt: DateTime(2025, 1, 5, 8, 25),
      startedAt: DateTime(2025, 1, 5, 8),
      distanceMeters: 5000,
      movingTimeSeconds: 1500,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith(
            () => _StaticProfileNotifier(_imperialProfile),
          ),
          savedActivitiesProvider.overrideWith((ref) async => [session]),
        ],
        child: const MaterialApp(home: ActivityHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3.11 mi'), findsOneWidget);
    expect(find.text('Avg pace: 08:02 /mi'), findsOneWidget);
  });

  testWidgets('activity detail respects imperial distance and pace', (
    tester,
  ) async {
    await pumpActivityDetailScreen(
      tester,
      overrides: [
        profileProvider.overrideWith(
          () => _StaticProfileNotifier(_imperialProfile),
        ),
        activityDetailProvider(activityId).overrideWith(
          (_) async => buildTestActivityDetailData(activityId: activityId),
        ),
      ],
    );

    expect(find.text('2.13 mi'), findsOneWidget);
    expect(find.text('15:12 /mi'), findsOneWidget);
  });
}

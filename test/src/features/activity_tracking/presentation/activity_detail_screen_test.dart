import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart';

import 'activity_detail_screen_test_support.dart';

/// ## Test Scenarios
/// - `[positive]` Detail metadata, metrics, and splits render persisted values correctly in read-only mode.
/// - `[positive]` Overflow menu exposes Edit and Delete, and Edit reveals metadata controls on demand.
/// - `[statemachine]` Map gesture boundaries preserve parent-scroll state transitions.
/// - `[statemachine]` Simplified map-owned gesture contract: scroll physics remains constant during map interaction lifecycle.
/// - `[error]` Load and save failures show sanitized retryable copy.
/// - `[edge]` Back-navigation guards respect clean, dirty, and failed-save states.
/// - `[positive]` Delete actions run through overflow-menu confirmation and local/remote cleanup paths.

void main() {
  configureActivityDetailScreenTests();

  testWidgets(
    'renders summary metrics splits and read-only metadata by default',
    (tester) async {
      final detailLoader = MockActivityDetailLoader();
      final detailData = ActivityDetailData(
        session: TrackingSessionRecord(
          id: activityId,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2025, 1, 10, 7, 30),
          updatedAt: DateTime(2025, 1, 10, 8, 2),
          startedAt: DateTime(2025, 1, 10, 7, 30),
          stoppedAt: DateTime(2025, 1, 10, 8, 2),
          title: 'Morning Tempo',
          description: 'Steady effort with final push.',
        ),
        cleanedPoints: [
          TrackingPoint(
            sessionId: activityId,
            timestamp: DateTime(2025, 1, 10, 7, 30),
            coordinate: const GeoCoordinate(
              latitude: 40.7128,
              longitude: -74.0060,
            ),
          ),
          TrackingPoint(
            sessionId: activityId,
            timestamp: DateTime(2025, 1, 10, 7, 46),
            coordinate: const GeoCoordinate(
              latitude: 40.7198,
              longitude: -73.9980,
            ),
          ),
          TrackingPoint(
            sessionId: activityId,
            timestamp: DateTime(2025, 1, 10, 8, 2),
            coordinate: const GeoCoordinate(
              latitude: 40.7268,
              longitude: -73.9900,
            ),
          ),
        ],
        processedMetrics: ProcessedActivityMetrics(
          session: TrackingSessionRecord(
            id: activityId,
            status: TrackingSessionStatus.saved,
            createdAt: DateTime(2025, 1, 10, 7, 30),
            updatedAt: DateTime(2025, 1, 10, 8, 2),
            title: 'Morning Tempo',
            description: 'Steady effort with final push.',
          ),
          trackSummary: const TrackSummary(
            distanceMeters: 3420,
            movingTime: Duration(minutes: 32, seconds: 15),
            averagePace: ActivityPace(
              perKilometer: Duration(minutes: 9, seconds: 26),
              perMile: Duration(minutes: 15, seconds: 12),
            ),
            elevationGainMeters: 88.4,
          ),
          splits: const [
            ActivitySplit(
              index: 1,
              unit: SplitUnit.kilometer,
              splitDuration: Duration(minutes: 9, seconds: 45),
              cumulativeDuration: Duration(minutes: 9, seconds: 45),
              cumulativeDistanceMeters: 1000,
              pace: Duration(minutes: 9, seconds: 45),
            ),
            ActivitySplit(
              index: 2,
              unit: SplitUnit.kilometer,
              splitDuration: Duration(minutes: 9, seconds: 35),
              cumulativeDuration: Duration(minutes: 19, seconds: 20),
              cumulativeDistanceMeters: 2000,
              pace: Duration(minutes: 9, seconds: 35),
            ),
          ],
          autoPause: const AutoPauseResult(
            windows: [],
            totalMovingDuration: Duration(minutes: 32, seconds: 15),
          ),
        ),
      );

      when(detailLoader.call).thenAnswer((_) async => detailData);

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
        ],
      );

      // Metadata card is now above the summary card in the layout, so the
      // summary metrics are below the initial viewport. Use scrollUntilVisible
      // to incrementally scroll the main ListView until the summary section
      // is built and visible. Specify the scrollable to avoid ambiguity with
      // the horizontal splits table scroll view.
      await tester.scrollUntilVisible(
        find.byKey(ActivityDetailScreen.distanceValueTextKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(ActivityDetailScreen.distanceValueTextKey),
        findsOneWidget,
      );
      expect(
        find.byKey(ActivityDetailScreen.durationValueTextKey),
        findsOneWidget,
      );
      expect(find.byKey(ActivityDetailScreen.paceValueTextKey), findsOneWidget);
      expect(
        find.byKey(ActivityDetailScreen.elevationValueTextKey),
        findsOneWidget,
      );
      expect(find.text('3.42 km'), findsOneWidget);
      expect(find.text('00:32:15'), findsOneWidget);
      expect(find.text('09:26 /km'), findsOneWidget);
      // Elevation is now rounded to whole numbers (formatElevation).
      expect(find.text('88 m'), findsOneWidget);

      expect(find.text('Morning Tempo'), findsWidgets);
      expect(find.text('Steady effort with final push.'), findsOneWidget);
      expect(find.byKey(ActivityDetailScreen.titleFieldKey), findsNothing);
      expect(
        find.byKey(ActivityDetailScreen.descriptionFieldKey),
        findsNothing,
      );
      expect(find.byKey(ActivityDetailScreen.saveButtonKey), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await scrollToActivityDetailKey(
        tester,
        ActivityDetailScreen.splitsTableKey,
      );

      final splitsTable = tester.widget<DataTable>(
        find.byKey(ActivityDetailScreen.splitsTableKey),
      );
      expect(splitsTable.rows, hasLength(2));
    },
  );

  testWidgets(
    'edit mode is entered from the overflow menu and reveals metadata controls',
    (tester) async {
      final detailData = buildTestActivityDetailData(activityId: activityId);

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) async => detailData),
        ],
      );

      expect(find.byKey(ActivityDetailScreen.titleFieldKey), findsNothing);
      expect(
        find.byKey(ActivityDetailScreen.visibilitySegmentedButtonKey),
        findsNothing,
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.byKey(ActivityDetailScreen.titleFieldKey), findsOneWidget);
      expect(
        find.byKey(ActivityDetailScreen.descriptionFieldKey),
        findsOneWidget,
      );
      expect(
        find.byKey(ActivityDetailScreen.visibilitySegmentedButtonKey),
        findsOneWidget,
      );
      await scrollToSaveButton(tester);
      expect(find.byKey(ActivityDetailScreen.saveButtonKey), findsOneWidget);
    },
  );

  testWidgets('view mode hides empty photo and gear sections', (tester) async {
    final detailData = buildTestActivityDetailData(
      activityId: activityId,
      remoteId: 'remote-activity-empty-sections',
    );

    await pumpActivityDetailScreen(
      tester,
      overrides: [
        activityDetailProvider(
          activityId,
        ).overrideWith((_) async => detailData),
        activityDetailGearProvider(activityId).overrideWith(
          (_) async => const ActivityDetailGearState.editable(
            remoteActivityId: 'remote-activity-empty-sections',
            selectableGear: [],
            selectedGearId: null,
            hasStaleAssignedGear: false,
          ),
        ),
        activityPhotoListProvider(
          'remote-activity-empty-sections',
        ).overrideWith((_) async => const []),
      ],
    );

    expect(find.byKey(ActivityDetailScreen.photoSectionKey), findsNothing);
    expect(find.byKey(ActivityDetailScreen.gearDropdownKey), findsNothing);
    expect(find.text('Gear'), findsNothing);
  });

  testWidgets('renders not found state when detail provider returns null', (
    tester,
  ) async {
    final detailLoader = MockActivityDetailLoader();
    when(detailLoader.call).thenAnswer((_) async => null);

    await pumpActivityDetailScreen(
      tester,
      overrides: [
        activityDetailProvider(activityId).overrideWith((_) => detailLoader()),
      ],
    );

    expect(find.text('Activity not found.'), findsOneWidget);
  });

  testWidgets(
    'map-started drags keep the page fixed without rewriting parent scroll physics',
    (tester) async {
      final detailLoader = MockActivityDetailLoader();
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        remoteId: 'remote-map-scroll-1',
      );
      when(detailLoader.call).thenAnswer((_) async => detailData);

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          activityPhotoListProvider('remote-map-scroll-1').overrideWith(
            (_) async => [
              buildTestActivityPhoto(
                id: 'photo-map-scroll-1',
                activityId: 'remote-map-scroll-1',
              ),
            ],
          ),
        ],
      );

      expect(activityDetailRouteMapRegionFinder(), findsOneWidget);
      expect(readActivityDetailScrollOffset(tester), closeTo(0, 0.01));
      final initialPhysicsType = readActivityDetailScrollPhysics(
        tester,
      )?.runtimeType;
      expect(initialPhysicsType, AlwaysScrollableScrollPhysics);
      final mapGestureRecognizers = tester
          .widget<MapWidget>(find.byType(MapWidget))
          .gestureRecognizers;
      final equivalentMapGestureRecognizers =
          <Factory<OneSequenceGestureRecognizer>>{
            const Factory<OneSequenceGestureRecognizer>(
              EagerGestureRecognizer.new,
            ),
          };
      expect(
        collectGestureRecognizerRuntimeTypes(mapGestureRecognizers),
        equals(<Object>{EagerGestureRecognizer}),
        reason:
            'Saved detail should let the platform map claim gestures directly '
            'instead of mutating the parent ListView scroll physics.',
      );
      expect(
        collectGestureRecognizerRuntimeTypes(mapGestureRecognizers),
        equals(
          collectGestureRecognizerRuntimeTypes(equivalentMapGestureRecognizers),
        ),
        reason:
            'Saved detail should validate the map gesture contract by recognizer '
            'behavior, not by requiring one exact Set instance identity.',
      );

      final mapGesture = await tester.startGesture(mapCenterDragStart(tester));
      await tester.pump();
      expectActivityDetailScrollPhysicsType(tester, initialPhysicsType);
      await mapGesture.moveBy(const Offset(0, -180));
      await tester.pump();
      expect(readActivityDetailScrollOffset(tester), closeTo(0, 0.01));
      expectActivityDetailScrollPhysicsType(tester, initialPhysicsType);
      await mapGesture.up();
      await tester.pumpAndSettle();
      expect(readActivityDetailScrollOffset(tester), closeTo(0, 0.01));
      expectActivityDetailScrollPhysicsType(tester, initialPhysicsType);

      final detailScrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ActivityDetailScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      detailScrollable.position.jumpTo(0);
      await tester.pumpAndSettle();

      await dragFromOffset(
        tester,
        start: mapBelowDragStart(tester),
        delta: const Offset(0, -180),
      );
      expect(readActivityDetailScrollOffset(tester), closeTo(180, 0.01));
      expectActivityDetailScrollPhysicsType(tester, initialPhysicsType);
    },
  );

  testWidgets(
    'canceling a map-started gesture leaves parent scroll physics unchanged',
    (tester) async {
      final detailLoader = MockActivityDetailLoader();
      final detailData = buildTestActivityDetailData(activityId: activityId);
      when(detailLoader.call).thenAnswer((_) async => detailData);

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
        ],
      );

      final initialPhysicsType = readActivityDetailScrollPhysics(
        tester,
      )?.runtimeType;
      final mapGesture = await tester.startGesture(mapCenterDragStart(tester));
      await tester.pump();
      expectActivityDetailScrollPhysicsType(tester, initialPhysicsType);

      await mapGesture.cancel();
      await tester.pumpAndSettle();

      expectActivityDetailScrollPhysicsType(tester, initialPhysicsType);
    },
  );

  testWidgets(
    'not-found state offers a reload action that retries detail loading',
    (tester) async {
      var loadAttempts = 0;
      final detailData = buildTestActivityDetailData(activityId: activityId);

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(activityId).overrideWith((_) async {
            loadAttempts += 1;
            if (loadAttempts == 1) {
              return null;
            }
            return detailData;
          }),
        ],
      );

      expect(find.text('Activity not found.'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Try again'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Try again'));
      await tester.pumpAndSettle();

      expect(loadAttempts, 2);
      expect(find.text('Activity not found.'), findsNothing);
      expect(find.text('Morning Tempo'), findsOneWidget);
    },
  );

  testWidgets('renders a generic error when detail loading fails', (
    tester,
  ) async {
    final detailLoader = MockActivityDetailLoader();
    when(
      detailLoader.call,
    ).thenThrow(StateError('Failed to load session 77 from storage backend.'));

    await pumpActivityDetailScreen(
      tester,
      overrides: [
        activityDetailProvider(activityId).overrideWith((_) => detailLoader()),
      ],
    );

    expect(
      find.text('Unable to load activity detail. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('storage backend'), findsNothing);
  });

  testWidgets('load error state offers retry and reloads detail content', (
    tester,
  ) async {
    var loadAttempts = 0;
    final detailData = buildTestActivityDetailData(activityId: activityId);

    await pumpActivityDetailScreen(
      tester,
      overrides: [
        activityDetailProvider(activityId).overrideWith((_) async {
          loadAttempts += 1;
          if (loadAttempts == 1) {
            throw StateError('load failed');
          }
          return detailData;
        }),
      ],
    );

    expect(
      find.text('Unable to load activity detail. Please try again.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ElevatedButton, 'Try again'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Try again'));
    await tester.pumpAndSettle();

    expect(loadAttempts, 2);
    expect(
      find.text('Unable to load activity detail. Please try again.'),
      findsNothing,
    );
    expect(find.text('Morning Tempo'), findsOneWidget);
  });

  testWidgets('restores the save action and shows an error when saving fails', (
    tester,
  ) async {
    final detailLoader = MockActivityDetailLoader();
    final repository = SaveAttemptTrackingRepository();
    final detailData = ActivityDetailData(
      session: TrackingSessionRecord(
        id: activityId,
        status: TrackingSessionStatus.saved,
        createdAt: DateTime(2025, 1, 10, 7, 30),
        updatedAt: DateTime(2025, 1, 10, 8, 2),
        startedAt: DateTime(2025, 1, 10, 7, 30),
      ),
      cleanedPoints: [
        TrackingPoint(
          sessionId: activityId,
          timestamp: DateTime(2025, 1, 10, 7, 30),
          coordinate: const GeoCoordinate(
            latitude: 40.7128,
            longitude: -74.0060,
          ),
        ),
        TrackingPoint(
          sessionId: activityId,
          timestamp: DateTime(2025, 1, 10, 7, 46),
          coordinate: const GeoCoordinate(
            latitude: 40.7198,
            longitude: -73.9980,
          ),
        ),
      ],
      processedMetrics: ProcessedActivityMetrics(
        session: TrackingSessionRecord(
          id: activityId,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime(2025, 1, 10, 7, 30),
          updatedAt: DateTime(2025, 1, 10, 8, 2),
        ),
        trackSummary: const TrackSummary(
          distanceMeters: 1500,
          movingTime: Duration(minutes: 9),
          averagePace: ActivityPace(
            perKilometer: Duration(minutes: 6),
            perMile: Duration(minutes: 9, seconds: 39),
          ),
          elevationGainMeters: 12,
        ),
        splits: const [],
        autoPause: const AutoPauseResult(
          windows: [],
          totalMovingDuration: Duration(minutes: 9),
        ),
      ),
    );

    when(detailLoader.call).thenAnswer((_) async => detailData);

    await pumpActivityDetailScreen(
      tester,
      overrides: [
        activityDetailProvider(activityId).overrideWith((_) => detailLoader()),
        trackingRepositoryProvider.overrideWithValue(repository),
      ],
    );

    await enterActivityDetailEditMode(tester);
    await scrollToTitleField(tester);
    await tester.enterText(
      find.byKey(ActivityDetailScreen.titleFieldKey),
      'Updated title',
    );
    await tester.pump();

    final saveButton = find.byKey(ActivityDetailScreen.saveButtonKey);
    await scrollToSaveButton(tester);
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repository.saveAttemptCount, 1);
    expect(
      find.text('Unable to save activity details. Please try again.'),
      findsOneWidget,
    );
    expect(tester.widget<ElevatedButton>(saveButton).enabled, isTrue);
    expect(find.text('Not enough distance to compute splits.'), findsOneWidget);
    expect(find.byKey(ActivityDetailScreen.splitsTableKey), findsNothing);
  });
}

Set<Object> collectGestureRecognizerRuntimeTypes(
  Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
) {
  return gestureRecognizers?.map((factory) {
        final recognizer = factory.constructor();
        final runtimeType = recognizer.runtimeType;
        recognizer.dispose();
        return runtimeType;
      }).toSet() ??
      <Object>{};
}

void expectActivityDetailScrollPhysicsType(
  WidgetTester tester,
  Object? expectedRuntimeType,
) {
  expect(
    readActivityDetailScrollPhysics(tester)?.runtimeType,
    expectedRuntimeType,
  );
}

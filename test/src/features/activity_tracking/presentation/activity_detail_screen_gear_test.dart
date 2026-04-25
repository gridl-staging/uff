import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/gear/application/gear_providers.dart';

import '../application/tracking_controller_test_support.dart';
import '../../../test_helpers/gear_test_support.dart';
import 'activity_detail_screen_test_support.dart';

/// ## Test Scenarios
/// - `[positive]` Synced activities load and persist gear selections through the dropdown.
/// - `[edge]` Unsynced activities show a read-only gear state and helper copy.
/// - `[error]` Gear assignment load/save failures surface retry-safe error messaging.
/// - `[statemachine]` In-flight gear updates disable repeated dropdown mutations.
void main() {
  configureActivityDetailScreenTests();

  testWidgets(
    'renders gear dropdown with current selection for synced activity',
    (
      tester,
    ) async {
      final assignmentRepository = RecordingActivityGearAssignmentRepository(
        assignedGearByRemoteActivityId: {
          'remote-activity-1': testShoeGear.id,
        },
      );
      final gearRepository = RecordingGearRepository(
        itemsToReturn: [testShoeGear, testBikeGear, testRetiredComponentGear],
      );
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: 'remote-activity-1',
        ),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          activityGearAssignmentRepositoryProvider.overrideWithValue(
            assignmentRepository,
          ),
          gearRepositoryProvider.overrideWithValue(gearRepository),
        ],
      );

      await scrollToGearDropdown(tester);
      expect(find.text('Gear'), findsOneWidget);
      expect(find.byKey(ActivityDetailScreen.gearDropdownKey), findsOneWidget);
      expect(find.text('Daily Trainer'), findsOneWidget);
    },
  );

  testWidgets(
    'shows non-editable sync message for unsynced activity gear section',
    (tester) async {
      final assignmentRepository = RecordingActivityGearAssignmentRepository();
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(activityId: activityId),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          activityGearAssignmentRepositoryProvider.overrideWithValue(
            assignmentRepository,
          ),
          gearRepositoryProvider.overrideWithValue(RecordingGearRepository()),
        ],
      );

      await tester.scrollUntilVisible(
        find.text('Gear can be assigned after this activity syncs.'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(ActivityDetailScreen.gearDropdownKey), findsNothing);
      expect(
        find.text('Gear can be assigned after this activity syncs.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'shows safe empty state when no active shoes or bikes are available',
    (tester) async {
      final assignmentRepository = RecordingActivityGearAssignmentRepository(
        assignedGearByRemoteActivityId: {'remote-activity-2': null},
      );
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: 'remote-activity-2',
        ),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          activityGearAssignmentRepositoryProvider.overrideWithValue(
            assignmentRepository,
          ),
          gearRepositoryProvider.overrideWithValue(
            RecordingGearRepository(
              itemsToReturn: const [testRetiredComponentGear],
            ),
          ),
        ],
      );

      await scrollToGearDropdown(tester);
      expect(find.byKey(ActivityDetailScreen.gearDropdownKey), findsOneWidget);
      expect(find.text('No active shoes or bikes available.'), findsOneWidget);
    },
  );

  testWidgets('gear load error exposes retry action and can recover', (
    tester,
  ) async {
    var gearLoadAttempts = 0;
    final detailLoader = CountingActivityDetailLoader(
      buildTestActivityDetailData(
        activityId: activityId,
        remoteId: 'remote-activity-retry-1',
      ),
    );

    await pumpActivityDetailScreen(
      tester,
      overrides: [
        activityDetailProvider(
          activityId,
        ).overrideWith((_) => detailLoader()),
        activityDetailGearProvider(activityId).overrideWith((_) async {
          gearLoadAttempts += 1;
          if (gearLoadAttempts == 1) {
            throw StateError('failed to load gear');
          }
          return ActivityDetailGearState.editable(
            remoteActivityId: 'remote-activity-retry-1',
            selectableGear: const [testShoeGear, testBikeGear],
            selectedGearId: testShoeGear.id,
            hasStaleAssignedGear: false,
          );
        }),
      ],
    );

    await tester.scrollUntilVisible(
      find.text('Unable to load gear options right now.'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Unable to load gear options right now.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Try again'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Try again'));
    await tester.pumpAndSettle();

    expect(gearLoadAttempts, 2);
    expect(find.byKey(ActivityDetailScreen.gearDropdownKey), findsOneWidget);
  });

  testWidgets(
    'changing gear saves by remote id, disables repeated changes, and invalidates providers',
    (tester) async {
      final assignmentRepository = RecordingActivityGearAssignmentRepository(
        assignedGearByRemoteActivityId: {
          'remote-activity-3': testShoeGear.id,
        },
      );
      final updateCompleter = Completer<void>();
      assignmentRepository.updateCompleter = updateCompleter;
      final gearRepository = RecordingGearRepository(
        itemsToReturn: [testShoeGear, testBikeGear],
      );
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: 'remote-activity-3',
        ),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          activityGearAssignmentRepositoryProvider.overrideWithValue(
            assignmentRepository,
          ),
          gearRepositoryProvider.overrideWithValue(gearRepository),
        ],
      );

      await scrollToGearDropdown(tester);
      expect(detailLoader.callCount, 1);
      expect(gearRepository.loadGearCallCount, 1);

      await selectGearOption(tester, 'Road Bike');
      expect(assignmentRepository.updateCallCount, 1);
      expect(
        assignmentRepository.lastUpdatedRemoteActivityId,
        'remote-activity-3',
      );
      expect(assignmentRepository.lastUpdatedGearId, testBikeGear.id);

      final dropdown = tester.widget<DropdownButtonFormField<String?>>(
        find.byKey(ActivityDetailScreen.gearDropdownKey),
      );
      expect(dropdown.onChanged, isNull);

      await scrollToGearDropdown(tester);
      await tester.ensureVisible(
        find.byKey(ActivityDetailScreen.gearDropdownKey),
      );
      await tester.tap(find.byKey(ActivityDetailScreen.gearDropdownKey));
      await tester.pump();
      expect(assignmentRepository.updateCallCount, 1);

      updateCompleter.complete();
      await tester.pumpAndSettle();

      expect(detailLoader.callCount, greaterThan(1));
      expect(gearRepository.loadGearCallCount, greaterThan(1));
      expect(find.text('Gear assignment updated.'), findsOneWidget);
    },
  );

  testWidgets(
    'back navigation is blocked while gear assignment save is in flight',
    (tester) async {
      final repository = FakeTrackingRepository();
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        remoteId: 'remote-activity-gear-pop-guard',
      );
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      final assignmentRepository = RecordingActivityGearAssignmentRepository(
        assignedGearByRemoteActivityId: {
          'remote-activity-gear-pop-guard': testShoeGear.id,
        },
      );
      final updateCompleter = Completer<void>();
      assignmentRepository.updateCompleter = updateCompleter;

      await tester.pumpWidget(
        buildPoppableActivityDetailScreen(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
            activityGearAssignmentRepositoryProvider.overrideWithValue(
              assignmentRepository,
            ),
            gearRepositoryProvider.overrideWithValue(
              RecordingGearRepository(
                itemsToReturn: [testShoeGear, testBikeGear],
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await scrollToGearDropdown(tester);
      await selectGearOption(tester, 'Road Bike');

      expect(assignmentRepository.updateCallCount, 1);

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();

      expect(find.byType(ActivityDetailScreen), findsOneWidget);
      expect(find.text(activityDetailExitRouteText), findsNothing);

      updateCompleter.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'rejects gear assignment values that are not in selectable gear',
    (tester) async {
      final assignmentRepository = RecordingActivityGearAssignmentRepository(
        assignedGearByRemoteActivityId: {
          'remote-activity-3b': testShoeGear.id,
        },
      );
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: 'remote-activity-3b',
        ),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          activityGearAssignmentRepositoryProvider.overrideWithValue(
            assignmentRepository,
          ),
          gearRepositoryProvider.overrideWithValue(
            RecordingGearRepository(
              itemsToReturn: [testShoeGear, testBikeGear],
            ),
          ),
        ],
      );

      final dropdownFinder = find.byKey(ActivityDetailScreen.gearDropdownKey);
      await scrollToGearDropdown(tester);

      tester
          .widget<DropdownButtonFormField<String?>>(dropdownFinder)
          .onChanged
          ?.call('gear-other-user');
      await tester.pumpAndSettle();

      expect(assignmentRepository.updateCallCount, 0);
      expect(
        find.text('Unable to save gear assignment. Please try again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('shows recoverable error feedback when gear save fails', (
    tester,
  ) async {
    final assignmentRepository = RecordingActivityGearAssignmentRepository(
      assignedGearByRemoteActivityId: {
        'remote-activity-4': testShoeGear.id,
      },
      updateError: Exception('write failed'),
    );
    final detailLoader = CountingActivityDetailLoader(
      buildTestActivityDetailData(
        activityId: activityId,
        remoteId: 'remote-activity-4',
      ),
    );

    await pumpActivityDetailScreen(
      tester,
      overrides: [
        activityDetailProvider(
          activityId,
        ).overrideWith((_) => detailLoader()),
        activityGearAssignmentRepositoryProvider.overrideWithValue(
          assignmentRepository,
        ),
        gearRepositoryProvider.overrideWithValue(
          RecordingGearRepository(
            itemsToReturn: [testShoeGear, testBikeGear],
          ),
        ),
      ],
    );

    await scrollToGearDropdown(tester);
    await selectGearOption(tester, 'Road Bike');
    await tester.pumpAndSettle();

    expect(assignmentRepository.updateCallCount, 1);
    expect(
      find.text('Unable to save gear assignment. Please try again.'),
      findsOneWidget,
    );
    final dropdown = tester.widget<DropdownButtonFormField<String?>>(
      find.byKey(ActivityDetailScreen.gearDropdownKey),
    );
    expect(dropdown.enabled, isTrue);
  });
}

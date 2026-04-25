import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';

import '../application/tracking_controller_test_support.dart';
import 'activity_detail_screen_test_support.dart';

/// ## Test Scenarios
/// - `[edge]` Back navigation exits immediately for clean details and prompts for dirty details.
/// - `[error]` Failed metadata saves keep back-navigation discard guards active.
/// - `[positive]` Delete controls open confirmation and execute local/remote cleanup.
void main() {
  configureActivityDetailScreenTests();
  testWidgets('clean activity detail exits immediately on back', (
    tester,
  ) async {
    final repository = FakeTrackingRepository();
    final detailData = buildTestActivityDetailData(activityId: activityId);
    repository.sessionsById[activityId] = detailData.session;
    repository.points.addAll(detailData.cleanedPoints);

    await tester.pumpWidget(
      buildPoppableActivityDetailScreen(
        overrides: [
          trackingRepositoryProvider.overrideWithValue(repository),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text(activityDetailExitRouteText), findsOneWidget);
    expect(find.byType(ActivityDetailScreen), findsNothing);
  });

  testWidgets(
    'whitespace-padded saved metadata does not trigger a dirty guard on load',
    (tester) async {
      final repository = FakeTrackingRepository();
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        title: '  Morning Tempo  ',
        description: '  Steady effort with final push.  ',
      );
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await tester.pumpWidget(
        buildPoppableActivityDetailScreen(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ActivityDetailScreen.saveButtonKey), findsNothing);
      expect(
        find.byKey(ActivityDetailScreen.visibilityBadgeKey),
        findsOneWidget,
      );
      expect(find.text('Steady effort with final push.'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text(activityDetailExitRouteText), findsOneWidget);
      expect(find.text('Discard changes?'), findsNothing);
    },
  );

  testWidgets('dirty title edit shows discard prompt and stay keeps edits', (
    tester,
  ) async {
    final repository = FakeTrackingRepository();
    final detailData = buildTestActivityDetailData(activityId: activityId);
    repository.sessionsById[activityId] = detailData.session;
    repository.points.addAll(detailData.cleanedPoints);

    await tester.pumpWidget(
      buildPoppableActivityDetailScreen(
        overrides: [
          trackingRepositoryProvider.overrideWithValue(repository),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await enterActivityDetailEditMode(tester);
    await scrollToTitleField(tester);
    await tester.enterText(
      find.byKey(ActivityDetailScreen.titleFieldKey),
      'Draft title',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.text('You have unsaved changes.'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();

    final titleField = tester.widget<TextField>(
      find.byKey(ActivityDetailScreen.titleFieldKey),
    );
    expect(titleField.controller?.text, 'Draft title');
    expect(find.byType(ActivityDetailScreen), findsOneWidget);
    expect(find.text(activityDetailExitRouteText), findsNothing);
  });

  testWidgets('failed metadata save keeps back guard active for description', (
    tester,
  ) async {
    final repository = SaveAttemptTrackingRepository();
    final detailData = buildTestActivityDetailData(activityId: activityId);
    repository.sessionsById[activityId] = detailData.session;
    repository.points.addAll(detailData.cleanedPoints);

    await tester.pumpWidget(
      buildPoppableActivityDetailScreen(
        overrides: [
          trackingRepositoryProvider.overrideWithValue(repository),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await enterActivityDetailEditMode(tester);
    await scrollToTitleField(tester);
    await tester.enterText(
      find.byKey(ActivityDetailScreen.descriptionFieldKey),
      'Draft notes that fail to save.',
    );
    await tester.pump();

    await scrollToSaveButton(tester);
    await tester.ensureVisible(find.byKey(ActivityDetailScreen.saveButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityDetailScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(repository.saveAttemptCount, 1);
    expect(
      find.text('Unable to save activity details. Please try again.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.byType(ActivityDetailScreen), findsOneWidget);
    expect(find.text(activityDetailExitRouteText), findsNothing);
  });

  testWidgets(
    'saved detail keeps delete behind the overflow menu instead of inline metadata controls',
    (tester) async {
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(activityId: activityId),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
        ],
      );

      expect(find.byKey(ActivityDetailScreen.deleteButtonKey), findsNothing);
      await openDeleteConfirmationDialog(tester);

      expect(
        find.byKey(ActivityDetailScreen.deleteConfirmDialogKey),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping overflow delete opens confirmation dialog with permanent warning',
    (tester) async {
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(activityId: activityId),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
        ],
      );

      await openDeleteConfirmationDialog(tester);

      expect(
        find.byKey(ActivityDetailScreen.deleteConfirmDialogKey),
        findsOneWidget,
      );
      expect(find.text('Delete activity?'), findsOneWidget);
      expect(find.textContaining('permanent'), findsOneWidget);
      expect(
        find.byKey(ActivityDetailScreen.deleteConfirmButtonKey),
        findsOneWidget,
      );
      expect(
        find.byKey(ActivityDetailScreen.deleteCancelButtonKey),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'canceling deletion dialog dismisses it and keeps detail screen intact',
    (tester) async {
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(activityId: activityId),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
        ],
      );

      await openDeleteConfirmationDialog(tester);
      await tester.tap(find.byKey(ActivityDetailScreen.deleteCancelButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ActivityDetailScreen.deleteConfirmDialogKey),
        findsNothing,
      );
      expect(find.byType(ActivityDetailScreen), findsOneWidget);
    },
  );

  testWidgets(
    'confirming delete calls local deleteActivity and navigates away',
    (tester) async {
      final repository = FakeTrackingRepository();
      final syncService = FakeSyncService();
      final detailData = buildTestActivityDetailData(activityId: activityId);
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await tester.pumpWidget(
        buildPoppableDeleteTestScreen(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
            syncServiceProvider.overrideWithValue(syncService),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await confirmDeleteActivity(tester);
      await tester.pumpAndSettle();

      expect(repository.sessionsById.containsKey(activityId), isFalse);
      expect(syncService.deletedRemoteActivityIds, isEmpty);
      expect(find.text(activityDetailExitRouteText), findsOneWidget);
      expect(find.byType(ActivityDetailScreen), findsNothing);
    },
  );

  testWidgets(
    'confirming delete also calls deleteRemoteActivity when remoteId exists',
    (tester) async {
      final repository = FakeTrackingRepository();
      final syncService = FakeSyncService();
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        remoteId: 'remote-abc-123',
      );
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await tester.pumpWidget(
        buildPoppableDeleteTestScreen(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
            syncServiceProvider.overrideWithValue(syncService),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await confirmDeleteActivity(tester);
      await tester.pumpAndSettle();

      expect(syncService.deletedRemoteActivityIds, ['remote-abc-123']);
      expect(repository.sessionsById.containsKey(activityId), isFalse);
      expect(find.text(activityDetailExitRouteText), findsOneWidget);
      expect(find.byType(ActivityDetailScreen), findsNothing);
    },
  );

  testWidgets(
    'successful delete invalidates savedActivitiesProvider before navigating away',
    (tester) async {
      final repository = FakeTrackingRepository();
      final syncService = FakeSyncService();
      final detailData = buildTestActivityDetailData(activityId: activityId);
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);
      var savedActivitiesLoadCount = 0;

      await tester.pumpWidget(
        buildPoppableDeleteTestScreen(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
            syncServiceProvider.overrideWithValue(syncService),
            savedActivitiesProvider.overrideWith((ref) async {
              savedActivitiesLoadCount += 1;
              return repository.loadSavedSessions();
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final initialLoadCount = savedActivitiesLoadCount;

      await confirmDeleteActivity(tester);
      await tester.pumpAndSettle();

      expect(savedActivitiesLoadCount, initialLoadCount + 1);
      expect(find.text(activityDetailExitRouteText), findsOneWidget);
      expect(find.byType(ActivityDetailScreen), findsNothing);
    },
  );

  testWidgets(
    'delete progress is shown, repeat delete attempts are blocked, and back navigation stays blocked while deleting',
    (tester) async {
      final repository = FakeTrackingRepository();
      final slowSyncService = SlowSyncService();
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        remoteId: 'remote-slow-1',
      );
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await tester.pumpWidget(
        buildPoppableDeleteTestScreen(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
            syncServiceProvider.overrideWithValue(slowSyncService),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await confirmDeleteActivity(tester);
      await tester.pump();

      expect(slowSyncService.deletedRemoteActivityIds, ['remote-slow-1']);
      expect(
        find.byKey(ActivityDetailScreen.deleteProgressIndicatorKey),
        findsOneWidget,
      );
      await openActivityDetailOverflowMenu(tester);
      await tester.tap(find.byKey(ActivityDetailScreen.deleteButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(ActivityDetailScreen.deleteConfirmDialogKey),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();

      expect(find.byType(ActivityDetailScreen), findsOneWidget);
      expect(find.text(activityDetailExitRouteText), findsNothing);

      slowSyncService.completeDelete();
      await tester.pumpAndSettle();
      expect(find.text(activityDetailExitRouteText), findsOneWidget);
      expect(find.byType(ActivityDetailScreen), findsNothing);
    },
  );

  testWidgets(
    'delete failure shows snackbar and keeps the detail screen visible',
    (tester) async {
      final repository = FakeTrackingRepository();
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        remoteId: 'remote-fail-1',
      );
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);
      final throwingSyncService = ThrowingSyncService();

      await tester.pumpWidget(
        buildPoppableDeleteTestScreen(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
            syncServiceProvider.overrideWithValue(throwingSyncService),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await confirmDeleteActivity(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to delete activity. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(ActivityDetailScreen), findsOneWidget);
      expect(find.text(activityDetailExitRouteText), findsNothing);
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';

import '../application/tracking_controller_test_support.dart';
import 'activity_detail_screen_test_support.dart';

void main() {
  configureActivityDetailScreenTests();

  testWidgets(
    'local delete failure after remote delete shows snackbar and keeps detail screen visible',
    (tester) async {
      final repository = ThrowingDeleteTrackingRepository();
      final syncService = FakeSyncService();
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        remoteId: 'remote-local-failure-1',
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

      expect(syncService.deletedRemoteActivityIds, ['remote-local-failure-1']);
      expect(
        find.text('Unable to delete activity. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(ActivityDetailScreen), findsOneWidget);
      expect(find.text(activityDetailExitRouteText), findsNothing);
    },
  );

  testWidgets(
    'local delete failure without remoteId does not call remote delete and keeps detail screen visible',
    (tester) async {
      final repository = ThrowingDeleteTrackingRepository();
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

      expect(syncService.deletedRemoteActivityIds, isEmpty);
      expect(
        find.text('Unable to delete activity. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(ActivityDetailScreen), findsOneWidget);
      expect(find.text(activityDetailExitRouteText), findsNothing);
    },
  );
}

class ThrowingDeleteTrackingRepository extends FakeTrackingRepository {
  @override
  Future<void> deleteActivity(int sessionId) async {
    throw StateError('Local delete failed for session $sessionId');
  }
}

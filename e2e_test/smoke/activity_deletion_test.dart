import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_history_screen.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

// ## Test Scenarios
// - [positive] Deleting a seeded activity from detail returns to history and
//   removes the deleted activity card.
// - [edge] Deleting the last local activity reveals the history empty-state
//   message.
// - [isolation] Deleted owner activity does not appear for a viewer account
//   after relaunch (multi-account deletion cleanup, not privacy isolation).
void main() {
  patrolTest(
    'deleting an activity from detail screen removes it from history',
    ($) async {
      await launchAuthenticatedApp($);
      registerAuthCleanup($);

      // Seed a single local-only activity.
      final startedAt = DateTime.utc(2026, 1, 20, 8);
      final sessionId = await seedStraightLineActivity(
        $,
        distanceMeters: 3000,
        startedAt: startedAt,
        duration: const Duration(minutes: 20),
        segmentCount: 2,
      );

      // Navigate to the Activity tab so the card is visible.
      await waitForHomeActivityHistoryLoaded($);

      // Tap the activity card to open the detail screen.
      final activityCardFinder = find.byKey(
        ActivityHistoryScreen.activityCardKey(sessionId),
      );
      await $(activityCardFinder).waitUntilVisible();
      await $(activityCardFinder).tap();

      // Scroll down to reveal the delete button near the bottom of the detail
      // screen. The control sits below summary, splits, and comments content.
      await revealActivityDetailDeleteButton($);

      // Tap the delete button.
      final deleteButtonFinder = find.byKey(
        ActivityDetailScreen.deleteButtonKey,
      );
      await $(deleteButtonFinder).waitUntilVisible();
      await $(deleteButtonFinder).tap();

      // Assert the confirmation dialog appears and confirm deletion.
      final confirmDialogFinder = find.byKey(
        ActivityDetailScreen.deleteConfirmDialogKey,
      );
      await $(confirmDialogFinder).waitUntilVisible();
      final confirmButtonFinder = find.byKey(
        ActivityDetailScreen.deleteConfirmButtonKey,
      );
      await $(confirmButtonFinder).waitUntilVisible();
      await $(confirmButtonFinder).tap();

      // Assert: navigation returns to activity history.
      await $(find.text('Activities')).waitUntilVisible();

      // The deleted activity card should no longer be in the widget tree.
      expect(activityCardFinder, findsNothing);

      // With no remaining activities, the empty-state message should appear.
      await $(find.text(emptyHistoryMessage)).waitUntilVisible();
    },
  );

  patrolTest(
    'deleted owner activity does not appear for viewer after relaunch',
    ($) async {
      // Supabase must be initialized before creating owner/viewer accounts,
      // because ensureOwnerViewerAccounts calls Supabase.instance internally.
      await initializeTestServices();
      final accounts = await ensureOwnerViewerAccounts(namespace: 'deletion');

      await launchAuthenticatedApp(
        $,
        email: accounts.owner.email,
        password: accounts.owner.password,
      );
      registerAuthCleanup($);

      // Seed a single activity as owner.
      final sessionId = await seedStraightLineActivity(
        $,
        distanceMeters: 3000,
        startedAt: DateTime.utc(2026, 1, 20, 8),
        duration: const Duration(minutes: 20),
        segmentCount: 2,
      );

      await waitForHomeActivityHistoryLoaded($);

      // Open the activity detail and delete through the UI flow.
      final activityCardFinder = find.byKey(
        ActivityHistoryScreen.activityCardKey(sessionId),
      );
      await $(activityCardFinder).waitUntilVisible();
      await $(activityCardFinder).tap();

      // Scroll to reveal the delete button, then tap it.
      await revealActivityDetailDeleteButton($);
      await $(
        find.byKey(ActivityDetailScreen.deleteButtonKey),
      ).waitUntilVisible();
      await $(find.byKey(ActivityDetailScreen.deleteButtonKey)).tap();

      // Confirm deletion.
      await $(
        find.byKey(ActivityDetailScreen.deleteConfirmDialogKey),
      ).waitUntilVisible();
      await $(
        find.byKey(ActivityDetailScreen.deleteConfirmButtonKey),
      ).waitUntilVisible();
      await $(find.byKey(ActivityDetailScreen.deleteConfirmButtonKey)).tap();

      // Verify deletion completed for owner.
      await $(find.text('Activities')).waitUntilVisible();
      expect(activityCardFinder, findsNothing);
      await $(find.text(emptyHistoryMessage)).waitUntilVisible();

      // Relaunch as viewer without cleaning local data, so any cross-account
      // leakage from cached owner state would be visible.
      await unmountTestApp($);
      await launchAuthenticatedApp(
        $,
        email: accounts.viewer.email,
        password: accounts.viewer.password,
        cleanupLocalData: false,
      );

      await waitForHomeActivityHistoryLoaded($);
      await $(find.text(emptyHistoryMessage)).waitUntilVisible();

      // The deleted owner activity must not appear for the viewer.
      expect(activityCardFinder, findsNothing);
      expect(find.text('Activity #$sessionId'), findsNothing);
    },
  );
}

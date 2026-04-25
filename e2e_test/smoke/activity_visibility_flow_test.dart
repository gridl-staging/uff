import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_history_screen.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

// ## Test Scenarios
// - [positive] Pre-authenticated owner can change and save visibility from the
//   activity detail metadata section.
// - [statemachine] Visibility selection transitions public -> followers ->
//   private and persists across detail reopen cycles.
// - [negative] A second authenticated viewer does not see the owner activity
//   after relaunch when the owner persisted private visibility.
// - [isolation] Viewer relaunch starts from a clean local slate and still
//   keeps owner metadata isolated from the second account.
void main() {
  patrolTest(
    'pre-authenticated user can persist activity visibility changes from detail',
    ($) async {
      await initializeTestServices();
      final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
      final account = E2eTestUserCredentials(
        email: 'visibility-positive-$uniqueSuffix@example.com',
        password: 'VisibilityPass!$uniqueSuffix',
      );
      await ensureTestUser(email: account.email, password: account.password);
      await launchAuthenticatedApp(
        $,
        email: account.email,
        password: account.password,
      );
      registerAuthCleanup($);

      final startedAt = DateTime.utc(2026, 1, 21, 6, 30);
      final activityId = await seedStraightLineActivity(
        $,
        distanceMeters: 3200,
        startedAt: startedAt,
        duration: const Duration(minutes: 24),
        visibility: publicTrackingSessionVisibility,
      );

      await waitForHomeActivityHistoryLoaded($);

      final activityCardFinder = find.byKey(
        ActivityHistoryScreen.activityCardKey(activityId),
      );
      await $(activityCardFinder).waitUntilVisible();
      await $(activityCardFinder).tap();

      final visibilitySegmentedFinder = find.byKey(
        ActivityDetailScreen.visibilitySegmentedButtonKey,
      );
      final saveButtonFinder = find.byKey(ActivityDetailScreen.saveButtonKey);

      await revealActivityDetailMetadataSection($);
      expect(
        $.tester
            .widget<SegmentedButton<String>>(visibilitySegmentedFinder)
            .selected,
        {publicTrackingSessionVisibility},
      );

      await $(
        find.descendant(
          of: visibilitySegmentedFinder,
          matching: find.text('Followers'),
        ),
      ).tap();
      expect(
        $.tester
            .widget<SegmentedButton<String>>(visibilitySegmentedFinder)
            .selected,
        {followersTrackingSessionVisibility},
      );
      await revealActivityDetailSaveButton($);
      await $(saveButtonFinder).tap();
      await waitForActivityDetailSaveCompletion($);

      await returnToHomeActivityHistory(
        $,
        activityCardFinder: activityCardFinder,
      );
      await $(activityCardFinder).tap();
      await revealActivityDetailMetadataSection($);
      expect(
        $.tester
            .widget<SegmentedButton<String>>(visibilitySegmentedFinder)
            .selected,
        {followersTrackingSessionVisibility},
      );
    },
  );

  patrolTest(
    'owner saved visibility persists and viewer relaunch cannot see owner card',
    ($) async {
      // Supabase must be initialized before creating owner/viewer accounts,
      // because ensureOwnerViewerAccounts calls Supabase.instance internally.
      await initializeTestServices();
      final accounts = await ensureOwnerViewerAccounts(namespace: 'visibility');

      await launchAuthenticatedApp(
        $,
        email: accounts.owner.email,
        password: accounts.owner.password,
      );
      registerAuthCleanup($);

      final startedAt = DateTime.utc(2026, 1, 22, 6, 45);
      final activityId = await seedStraightLineActivity(
        $,
        distanceMeters: 2800,
        startedAt: startedAt,
        duration: const Duration(minutes: 21),
        visibility: publicTrackingSessionVisibility,
      );

      await waitForHomeActivityHistoryLoaded($);
      final ownerActivityCardFinder = find.byKey(
        ActivityHistoryScreen.activityCardKey(activityId),
      );
      await $(ownerActivityCardFinder).waitUntilVisible();
      await $(ownerActivityCardFinder).tap();

      final visibilitySegmentedFinder = find.byKey(
        ActivityDetailScreen.visibilitySegmentedButtonKey,
      );
      final saveButtonFinder = find.byKey(ActivityDetailScreen.saveButtonKey);

      await revealActivityDetailMetadataSection($);
      expect(
        $.tester
            .widget<SegmentedButton<String>>(visibilitySegmentedFinder)
            .selected,
        {publicTrackingSessionVisibility},
      );

      await $(
        find.descendant(
          of: visibilitySegmentedFinder,
          matching: find.text('Followers'),
        ),
      ).tap();
      expect(
        $.tester
            .widget<SegmentedButton<String>>(visibilitySegmentedFinder)
            .selected,
        {followersTrackingSessionVisibility},
      );
      await revealActivityDetailSaveButton($);
      await $(saveButtonFinder).tap();
      await waitForActivityDetailSaveCompletion($);

      await returnToHomeActivityHistory(
        $,
        activityCardFinder: ownerActivityCardFinder,
      );
      await $(ownerActivityCardFinder).tap();
      await revealActivityDetailMetadataSection($);
      expect(
        $.tester
            .widget<SegmentedButton<String>>(visibilitySegmentedFinder)
            .selected,
        {followersTrackingSessionVisibility},
      );

      await $(
        find.descendant(
          of: visibilitySegmentedFinder,
          matching: find.text('Private'),
        ),
      ).tap();
      expect(
        $.tester
            .widget<SegmentedButton<String>>(visibilitySegmentedFinder)
            .selected,
        {privateTrackingSessionVisibility},
      );
      await revealActivityDetailSaveButton($);
      await $(saveButtonFinder).tap();
      await waitForActivityDetailSaveCompletion($);

      await returnToHomeActivityHistory(
        $,
        activityCardFinder: ownerActivityCardFinder,
      );
      await unmountTestApp($);
      await launchAuthenticatedApp(
        $,
        email: accounts.viewer.email,
        password: accounts.viewer.password,
      );

      await waitForHomeActivityHistoryLoaded($);
      await $(find.text(emptyHistoryMessage)).waitUntilVisible();
      expect(ownerActivityCardFinder, findsNothing);
      expect(find.text('Activity #$activityId'), findsNothing);
    },
  );
}

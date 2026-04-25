import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_history_screen.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

const _seededDistanceMeters = 2500.0;
const _seededDuration = Duration(minutes: 25);

// ## Test Scenarios
// - [positive] Owner opens a seeded activity and reads exact distance,
//   duration, pace, elevation, and split rows.
// - [negative] Viewer account does not see owner-seeded history cards or
//   detail values after relaunch.
// - [isolation] Fresh launch with a second account does not retain the first
//   user's detail-loaded state.
void main() {
  patrolTest(
    'pre-authenticated user sees seeded activity detail metrics and splits',
    ($) async {
      await launchAuthenticatedApp($);
      registerAuthCleanup($);

      final startedAt = DateTime.utc(2026, 1, 20, 6, 30);
      final activityId = await seedStraightLineActivity(
        $,
        distanceMeters: _seededDistanceMeters,
        startedAt: startedAt,
        duration: _seededDuration,
        segmentCount: 4,
        elevationStepMeters: 5,
      );

      await waitForHomeActivityHistoryLoaded($);

      final activityCardFinder = find.byKey(
        ActivityHistoryScreen.activityCardKey(activityId),
      );
      await $(activityCardFinder).waitUntilVisible();
      await $(activityCardFinder).tap();

      await _expectTextValue(
        $,
        find.byKey(ActivityDetailScreen.distanceValueTextKey),
        '2.50 km',
      );
      await _expectTextValue(
        $,
        find.byKey(ActivityDetailScreen.durationValueTextKey),
        '00:25:00',
      );
      await _expectTextValueIn(
        $,
        find.byKey(ActivityDetailScreen.paceValueTextKey),
        const {'09:59 /km', '10:00 /km'},
      );
      await _expectTextValue(
        $,
        find.byKey(ActivityDetailScreen.elevationValueTextKey),
        '20 m',
      );
      await revealActivityDetailSplitsSection($);
      final splitRowCount = await readActivityDetailSplitRowCount($);
      expect(splitRowCount, 2);
    },
  );

  patrolTest(
    'fresh launch prevents viewer from reading owner seeded detail values',
    ($) async {
      // Supabase must be initialized before creating owner/viewer accounts,
      // because ensureOwnerViewerAccounts calls Supabase.instance internally.
      await initializeTestServices();
      final accounts = await ensureOwnerViewerAccounts(namespace: 'detail');

      await launchAuthenticatedApp(
        $,
        email: accounts.owner.email,
        password: accounts.owner.password,
      );
      registerAuthCleanup($);

      const ownerDistanceLabel = '2.50 km';
      const ownerDurationLabel = '00:25:00';
      final startedAt = DateTime.utc(2026, 1, 23, 6, 30);
      final activityId = await seedStraightLineActivity(
        $,
        distanceMeters: _seededDistanceMeters,
        startedAt: startedAt,
        duration: _seededDuration,
        segmentCount: 4,
        elevationStepMeters: 5,
      );

      await waitForHomeActivityHistoryLoaded($);

      final ownerActivityCardFinder = find.byKey(
        ActivityHistoryScreen.activityCardKey(activityId),
      );
      await $(ownerActivityCardFinder).waitUntilVisible();
      await $(ownerActivityCardFinder).tap();

      await _expectTextValue(
        $,
        find.byKey(ActivityDetailScreen.distanceValueTextKey),
        ownerDistanceLabel,
      );
      await _expectTextValue(
        $,
        find.byKey(ActivityDetailScreen.durationValueTextKey),
        ownerDurationLabel,
      );

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
      await $(find.text(emptyHistoryMessage)).waitUntilVisible(
        timeout: const Duration(seconds: 30),
      );

      expect(ownerActivityCardFinder, findsNothing);
      expect(find.text('Activity #$activityId'), findsNothing);
      expect(find.text(ownerDistanceLabel), findsNothing);
      expect(find.text(ownerDurationLabel), findsNothing);
    },
  );
}

Future<void> _expectTextValue(
  PatrolIntegrationTester $,
  Finder finder,
  String expected,
) async {
  await $(finder).waitUntilVisible();
  final textWidget = $.tester.widget<Text>(finder);
  expect(textWidget.data, expected);
}

Future<void> _expectTextValueIn(
  PatrolIntegrationTester $,
  Finder finder,
  Set<String> expectedValues,
) async {
  await $(finder).waitUntilVisible();
  final textWidget = $.tester.widget<Text>(finder);
  expect(expectedValues, contains(textWidget.data));
}

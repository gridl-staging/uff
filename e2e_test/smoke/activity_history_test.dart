import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_history_screen.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

const _seededRouteDuration = Duration(minutes: 30);

// ## Test Scenarios
// - [positive] Pre-authenticated user sees newest-first seeded history and
//   matching detail distance for the opened card.
// - [negative] A different authenticated user does not see owner-seeded cards
//   or labels after relaunch.
// - [isolation] Fresh app relaunch with a second account shows empty history
//   instead of retained owner state.
void main() {
  patrolTest(
    'pre-authenticated user sees newest-first history and detail distance',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();
      // Pre-authenticate BEFORE pumping the widget to avoid rapid router
      // redirect cycles that cause duplicate GlobalKey errors in
      // go_router's StatefulShellRoute.
      await preAuthenticate();
      await $.pumpWidget(await buildTestApp(trackingOverrides: false));
      await cleanupTestData($);

      registerAuthCleanup($);

      await waitForHomeActivityHistoryLoaded($);

      const oldestDistanceMeters = 1500.0;
      const middleDistanceMeters = 4200.0;
      const newestDistanceMeters = 9876.0;

      const oldestDistanceLabel = '1.50 km';
      const middleDistanceLabel = '4.20 km';
      const newestDistanceLabel = '9.88 km';

      final oldestSessionId = await seedStraightLineActivity(
        $,
        distanceMeters: oldestDistanceMeters,
        startedAt: DateTime.utc(2026, 1, 1, 9),
        duration: _seededRouteDuration,
      );
      final middleSessionId = await seedStraightLineActivity(
        $,
        distanceMeters: middleDistanceMeters,
        startedAt: DateTime.utc(2026, 1, 1, 10),
        duration: _seededRouteDuration,
      );
      final newestSessionId = await seedStraightLineActivity(
        $,
        distanceMeters: newestDistanceMeters,
        startedAt: DateTime.utc(2026, 1, 1, 11),
        duration: _seededRouteDuration,
      );

      final newestCardFinder = find.byKey(
        ActivityHistoryScreen.activityCardKey(newestSessionId),
      );
      final middleCardFinder = find.byKey(
        ActivityHistoryScreen.activityCardKey(middleSessionId),
      );
      final oldestCardFinder = find.byKey(
        ActivityHistoryScreen.activityCardKey(oldestSessionId),
      );

      await $(newestCardFinder).waitUntilVisible();
      await $(middleCardFinder).waitUntilVisible();
      await $(oldestCardFinder).waitUntilVisible();

      await $(
        find.descendant(
          of: newestCardFinder,
          matching: find.textContaining('Run'),
        ),
      ).waitUntilVisible();
      await $(
        find.descendant(
          of: middleCardFinder,
          matching: find.textContaining('Run'),
        ),
      ).waitUntilVisible();
      await $(
        find.descendant(
          of: oldestCardFinder,
          matching: find.textContaining('Run'),
        ),
      ).waitUntilVisible();

      await $(find.text(newestDistanceLabel)).waitUntilVisible();
      await $(find.text(middleDistanceLabel)).waitUntilVisible();
      await $(find.text(oldestDistanceLabel)).waitUntilVisible();

      final newestCardTop = $.tester.getTopLeft(newestCardFinder).dy;
      final middleCardTop = $.tester.getTopLeft(middleCardFinder).dy;
      final oldestCardTop = $.tester.getTopLeft(oldestCardFinder).dy;

      expect(newestCardTop, lessThan(middleCardTop));
      expect(middleCardTop, lessThan(oldestCardTop));

      await $(newestCardFinder).tap();

      final detailDistanceFinder = find.byKey(
        ActivityDetailScreen.distanceValueTextKey,
      );
      await $(detailDistanceFinder).waitUntilVisible();

      final detailDistanceText = $.tester.widget<Text>(detailDistanceFinder);
      expect(detailDistanceText.data, newestDistanceLabel);

      // Leave the Mapbox-backed detail route before teardown to avoid plugin
      // channel exceptions during app shutdown on emulator runs.
      final detailBackButtonFinder = find.byTooltip('Back');
      await $(detailBackButtonFinder).waitUntilVisible();
      await $(detailBackButtonFinder).tap();
      await $(newestCardFinder).waitUntilVisible();
    },
  );

  patrolTest(
    'fresh launch keeps owner history hidden from a second authenticated user',
    ($) async {
      // Supabase must be initialized before creating owner/viewer accounts,
      // because ensureOwnerViewerAccounts calls Supabase.instance internally.
      await initializeTestServices();
      final accounts = await ensureOwnerViewerAccounts(namespace: 'history');

      await launchAuthenticatedApp(
        $,
        email: accounts.owner.email,
        password: accounts.owner.password,
      );
      registerAuthCleanup($);

      await waitForHomeActivityHistoryLoaded($);

      const ownerFirstDistanceMeters = 1100.0;
      const ownerSecondDistanceMeters = 6400.0;
      const ownerFirstDistanceLabel = '1.10 km';
      const ownerSecondDistanceLabel = '6.40 km';

      final ownerFirstSessionId = await seedStraightLineActivity(
        $,
        distanceMeters: ownerFirstDistanceMeters,
        startedAt: DateTime.utc(2026, 1, 22, 9),
        duration: _seededRouteDuration,
      );
      final ownerSecondSessionId = await seedStraightLineActivity(
        $,
        distanceMeters: ownerSecondDistanceMeters,
        startedAt: DateTime.utc(2026, 1, 22, 10),
        duration: _seededRouteDuration,
      );

      await $(
        find.byKey(ActivityHistoryScreen.activityCardKey(ownerFirstSessionId)),
      ).waitUntilVisible();
      await $(
        find.byKey(ActivityHistoryScreen.activityCardKey(ownerSecondSessionId)),
      ).waitUntilVisible();
      await $(find.text(ownerFirstDistanceLabel)).waitUntilVisible();
      await $(find.text(ownerSecondDistanceLabel)).waitUntilVisible();

      await unmountTestApp($);
      await launchAuthenticatedApp(
        $,
        email: accounts.viewer.email,
        password: accounts.viewer.password,
      );

      await waitForHomeActivityHistoryLoaded($);
      await $(find.text(emptyHistoryMessage)).waitUntilVisible();

      expect(
        find.byKey(ActivityHistoryScreen.activityCardKey(ownerFirstSessionId)),
        findsNothing,
      );
      expect(
        find.byKey(ActivityHistoryScreen.activityCardKey(ownerSecondSessionId)),
        findsNothing,
      );
      expect(find.text('Activity #$ownerFirstSessionId'), findsNothing);
      expect(find.text('Activity #$ownerSecondSessionId'), findsNothing);
      expect(find.text(ownerFirstDistanceLabel), findsNothing);
      expect(find.text(ownerSecondDistanceLabel), findsNothing);
    },
  );
}

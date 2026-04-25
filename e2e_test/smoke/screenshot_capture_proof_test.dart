import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_history_screen.dart';

import '../fixtures.dart';

const _seededDistanceMeters = 2500.0;
const _seededDuration = Duration(minutes: 25);

// ## Test Scenarios
// - [positive] Pre-authenticated owner lands on one seeded Activity Detail
//   screen and holds the frame for deterministic simulator screenshot capture.
void main() {
  patrolTest(
    'proof: seeded activity detail stays visible for screenshot',
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

      // Keep Activity Detail stable while wrapper scripts call
      // `xcrun simctl io <udid> screenshot <path>`.
      await Future<void>.delayed(const Duration(seconds: 30));
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

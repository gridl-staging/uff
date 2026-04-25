import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_analytics_section.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/analytics/application/analytics_providers.dart';
import 'package:uff/src/features/analytics/domain/training_stress.dart';

import 'activity_detail_screen_test_support.dart';

// ## Test Scenarios
// - [positive] Compact saved-detail layouts require scrolling before the analytics card mounts.
// - [positive] Once the analytics card is revealed, the exact TSS label becomes readable.
void main() {
  configureActivityDetailScreenTests();

  testWidgets(
    'compact detail view mounts analytics only after scrolling to the below-fold card',
    (tester) async {
      final originalPhysicalSize = tester.view.physicalSize;
      final originalDevicePixelRatio = tester.view.devicePixelRatio;
      tester.view
        ..physicalSize = const Size(390, 640)
        ..devicePixelRatio = 1;
      addTearDown(() {
        tester.view
          ..physicalSize = originalPhysicalSize
          ..devicePixelRatio = originalDevicePixelRatio;
      });

      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(activityId: activityId),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Keep the photo/sync branch hermetic so this contract test only
            // exercises the detail ListView build order and analytics section.
            activitySyncEntryProvider(
              activityId,
            ).overrideWith((_) async => null),
            activityDetailProvider(
              activityId,
            ).overrideWith((_) => detailLoader()),
            activityTssProvider(activityId).overrideWith(
              (_) async => const TrainingStressResult(
                tss: 82.4,
                intensityFactor: 0.91,
                method: TssMethod.rTSS,
              ),
            ),
            activityIntervalSummaryProvider(
              activityId,
            ).overrideWith((_) async => null),
          ],
          child: const MaterialApp(
            home: ActivityDetailScreen(activityId: activityId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The hosted failures happen after a successful save on a compact
      // simulator. Reproduce that contract locally: the exact analytics label
      // is absent until the detail ListView reveals the below-fold card.
      expect(find.text('rTSS'), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(ActivityAnalyticsSection.cardKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ActivityAnalyticsSection.cardKey), findsOneWidget);
      expect(find.text('rTSS'), findsOneWidget);
    },
  );
}

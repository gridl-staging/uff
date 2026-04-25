import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/import/presentation/import_screen.dart';
import 'package:uff/src/routing/app_router.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

void main() {
  patrolTest('zip import shows progress and summary, then refreshes history', (
    $,
  ) async {
    await launchAuthenticatedApp($);
    await waitForHomeActivityHistoryLoaded($);

    _registerImportFlowTearDown($);

    final openImportFinder = find.byKey(HomeShellScreen.openImportButtonKey);
    await $(openImportFinder).waitUntilVisible();
    await $(openImportFinder).tap();
    await $(find.byKey(ImportScreen.pickFileButtonKey)).waitUntilVisible();

    // 8 activities: enough to exercise ZIP progress display + summary count,
    // without the volume overhead of 120 (which caused 120s+ import times and
    // history-refresh timeouts in baseline runs).
    const activityCount = 8;
    setNextPickedImportFile(
      name: 'strava_export.zip',
      bytes: buildTestZipBytes(activityCount: activityCount),
    );

    await $(find.byKey(ImportScreen.pickFileButtonKey)).tap(
      settlePolicy: SettlePolicy.noSettle,
    );
    // "Importing" text appears as soon as parse starts (<1s measured).
    await $(
      find.textContaining('Importing '),
    ).waitUntilVisible(timeout: const Duration(seconds: 15));
    // 8-activity ZIP import completes in <5s locally; 30s ceiling for CI.
    await $(find.byKey(ImportScreen.zipSuccessSummaryKey)).waitUntilVisible(
      timeout: const Duration(seconds: 30),
    );
    await $(find.text('ZIP Import Complete')).waitUntilVisible();
    await $(
      find.text('Imported $activityCount of $activityCount activities.'),
    ).waitUntilVisible();

    await $(find.text('Import Another')).tap();
    await $(find.byKey(ImportScreen.pickFileButtonKey)).waitUntilVisible();

    await $(find.byKey(ImportScreen.backButtonKey)).tap();
    // History refresh with 8 activities completes in <5s; 30s catches hangs
    // without the 120s ceiling that masked the baseline timeout failure. The
    // expected row title comes from the deterministic FIT fixture timestamp
    // plus the shared activity-title formatter, which keeps this assertion
    // exact without baking in a timezone assumption.
    await $(
      find.text(expectedImportedRunTitleForTesting()),
    ).waitUntilVisible(
      timeout: const Duration(seconds: 30),
    );
  });

  patrolTest('single-file import via picker still refreshes history', (
    $,
  ) async {
    await launchAuthenticatedApp($);
    await waitForHomeActivityHistoryLoaded($);

    _registerImportFlowTearDown($);

    final openImportFinder = find.byKey(HomeShellScreen.openImportButtonKey);
    await $(openImportFinder).waitUntilVisible();
    await $(openImportFinder).tap();
    await $(find.byKey(ImportScreen.pickFileButtonKey)).waitUntilVisible();

    setNextPickedImportFile(
      name: 'single.fit',
      bytes: buildTestFitBytes(),
    );

    await $(find.byKey(ImportScreen.pickFileButtonKey)).tap();
    // Single FIT import completes in <2s; 15s ceiling is generous.
    await $(find.byKey(ImportScreen.successSummaryKey)).waitUntilVisible(
      timeout: const Duration(seconds: 15),
    );

    await $(find.byKey(ImportScreen.backButtonKey)).tap();
    // Single-activity history refresh is near-instant; 15s catches real hangs.
    await $(
      find.text(expectedImportedRunTitleForTesting()),
    ).waitUntilVisible(
      timeout: const Duration(seconds: 15),
    );
  });
}

void _registerImportFlowTearDown(PatrolIntegrationTester $) {
  addTearDown(() async {
    restoreFilePickerPlatform();
    await cleanupTestData($);
    await unmountTestApp($);
    await clearAuthSession();
  });
}

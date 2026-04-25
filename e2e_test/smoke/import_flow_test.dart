import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/import/presentation/import_screen.dart';
import 'package:uff/src/routing/app_router.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

void main() {
  patrolTest(
    'pre-authenticated user imports FIT activity and sees it in history',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();
      // Pre-authenticate BEFORE pumping the widget to avoid rapid router
      // redirect cycles that cause duplicate GlobalKey errors in
      // go_router's StatefulShellRoute.
      await preAuthenticate();
      await $.pumpWidget(await buildTestApp(trackingOverrides: false));
      await cleanupTestData($);

      addTearDown(() async {
        await unmountTestApp($);
        await cleanupTestData($);
        await clearAuthSession();
      });

      final openImportFinder = find.byKey(HomeShellScreen.openImportButtonKey);
      await $(openImportFinder).waitUntilVisible();
      await $(openImportFinder).tap();
      await runTestImport($, buildTestFitBytes(), 'test.fit');
      await $(find.byKey(ImportScreen.successSummaryKey)).waitUntilVisible();

      final backButtonFinder = find.byKey(ImportScreen.backButtonKey);
      await $(backButtonFinder).waitUntilVisible();
      await $(backButtonFinder).tap();

      // Navigate to Activity tab — the app defaults to the Feed tab after
      // returning from the import screen.
      await waitForHomeActivityHistoryLoaded($);

      final emptyHistoryFinder = find.text(emptyHistoryMessage);
      // Derive the exact expected title from the deterministic FIT fixture so
      // this test proves the imported row rendered, not merely that some
      // unrelated widget on screen contains the word "Run".
      final activityTitleFinder = find.text(
        expectedImportedRunTitleForTesting(),
      );

      await $(activityTitleFinder).waitUntilVisible();
      expect(emptyHistoryFinder, findsNothing);
      expect(activityTitleFinder, findsOneWidget);
    },
  );

  patrolTest(
    'pre-authenticated user sees corrupt FIT error and recovers with Try Again',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();
      // Pre-authenticate BEFORE pumping the widget to avoid rapid router
      // redirect cycles that cause duplicate GlobalKey errors in
      // go_router's StatefulShellRoute.
      await preAuthenticate();
      await $.pumpWidget(await buildTestApp(trackingOverrides: false));
      await cleanupTestData($);

      addTearDown(() async {
        restoreFilePickerPlatform();
        await unmountTestApp($);
        await cleanupTestData($);
        await clearAuthSession();
      });

      final openImportFinder = find.byKey(HomeShellScreen.openImportButtonKey);
      await $(openImportFinder).waitUntilVisible();
      await $(openImportFinder).tap();

      setNextPickedImportFile(
        name: 'corrupt.fit',
        bytes: Uint8List.fromList(const [
          0x43,
          0x4f,
          0x52,
          0x52,
          0x55,
          0x50,
          0x54,
        ]),
      );

      final pickFileFinder = find.byKey(ImportScreen.pickFileButtonKey);
      await $(pickFileFinder).waitUntilVisible();
      await $(pickFileFinder).tap();

      final errorFinder = find.byKey(ImportScreen.errorMessageKey);
      await $(errorFinder).waitUntilVisible();
      expect(errorFinder, findsOneWidget);
      expect(find.text('Unrecognized file format'), findsOneWidget);

      await $(find.text('Try Again')).waitUntilVisible();
      await $(find.text('Try Again')).tap();
      await $(pickFileFinder).waitUntilVisible();
      expect(errorFinder, findsNothing);
    },
  );
}

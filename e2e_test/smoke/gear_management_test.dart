/// ## Test Scenarios
/// - [positive] Pre-authenticated user creates first gear item from profile manage gear flow

import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/gear/presentation/gear_form_screen.dart';
import 'package:uff/src/features/gear/presentation/gear_list_screen.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

const _emptyGearMessage = 'No gear yet. Add your first shoe or bike.';

void main() {
  patrolTest(
    'pre-authenticated user creates first gear from profile manage gear flow',
    ($) async {
      await initializeTestServices();
      await clearAuthSession();
      // Pre-authenticate BEFORE pumping the widget to avoid rapid router
      // redirect cycles that cause duplicate GlobalKey errors in
      // go_router's StatefulShellRoute.
      await preAuthenticate();
      await $.pumpWidget(
        await buildTestApp(trackingOverrides: false),
      );
      await cleanupTestData($);
      await cleanupGearItems();

      addTearDown(() async {
        await unmountTestApp($);
        await cleanupGearItems();
        await cleanupTestData($);
        await unmountTestApp($);
        await clearAuthSession();
      });

      final uniqueTimestamp = DateTime.now().microsecondsSinceEpoch;
      final gearName = 'Smoke Test Gear $uniqueTimestamp';

      final profileTabFinder = find.text('Profile');
      await $(profileTabFinder).waitUntilVisible();
      await $(profileTabFinder).tap();

      final manageGearFinder = find.text('Manage Gear');
      await $(manageGearFinder).scrollTo();
      await $(manageGearFinder).waitUntilVisible();
      await $(manageGearFinder).tap();

      final emptyStateFinder = find.byKey(GearListScreen.emptyStateKey);
      final addGearFinder = find.byKey(GearListScreen.addButtonKey);
      await $(emptyStateFinder).waitUntilVisible();
      await $(find.text(_emptyGearMessage)).waitUntilVisible();
      expect(find.text(gearName), findsNothing);

      await $(addGearFinder).waitUntilVisible();
      await $(addGearFinder).tap();

      final nameFieldFinder = find.byKey(GearFormScreen.nameFieldKey);
      final saveButtonFinder = find.byKey(GearFormScreen.saveButtonKey);
      await $(nameFieldFinder).waitUntilVisible();
      await $(nameFieldFinder).enterText(gearName);
      await $(saveButtonFinder).waitUntilVisible();
      await $(saveButtonFinder).tap();

      await $(addGearFinder).waitUntilVisible();
      await $(find.text(gearName)).waitUntilVisible();
      await $(find.text('Shoe · 0.00 km')).waitUntilVisible();
      expect(emptyStateFinder, findsNothing);
    },
  );
}

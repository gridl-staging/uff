// Scenario tags use markdown-style brackets (for example [positive]) that are
// parsed as references by this lint, so we ignore it for the file header block.
// ignore_for_file: comment_references

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/profile/presentation/privacy_zone_form_screen.dart';
import 'package:uff/src/features/profile/presentation/privacy_zones_screen.dart';
import 'package:uff/src/features/profile/presentation/profile_screen.dart';
import 'package:uff/src/routing/app_router.dart';

import '../auth_setup.dart';
import '../fixtures.dart';

/// ## Test Scenarios
/// - [positive] User creates a privacy zone with label, coordinates, and radius via UI
/// - [positive] User edits an existing privacy zone's label and radius
/// - [positive] User deletes a privacy zone after confirming the delete dialog
/// - [edge] Delete cancel keeps the zone and returns to edit form
/// NOTE: Single-account only. No cross-user negative or masking RPC coverage.
void main() {
  patrolTest(
    'user can create, edit, and delete a privacy zone via visible UI',
    (
      $,
    ) async {
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
      await cleanupPrivacyZones();

      addTearDown(() async {
        await unmountTestApp($);
        await cleanupPrivacyZones();
        await cleanupTestData($);
        await clearAuthSession();
      });

      const createdLabel = 'Home Base';
      const updatedLabel = 'Home Base Updated';

      await waitForHomeActivityHistoryLoaded($);
      await navigateToHomeShellDestination($, HomeShellDestinationId.profile);
      await revealProfileSignOutButton($);
      await $(
        find.byKey(ProfileScreen.privacyZonesButtonKey),
      ).waitUntilVisible();
      await $(find.byKey(ProfileScreen.privacyZonesButtonKey)).tap();

      await $(
        find.byKey(PrivacyZonesScreen.explanationCardKey),
      ).waitUntilVisible();
      await $(
        find.text(PrivacyZonesScreen.explanationCardMessage),
      ).waitUntilVisible();
      await $(find.byKey(PrivacyZonesScreen.addPrivacyZoneButtonKey)).tap();

      // Create mode uses the same app-bar copy as the widget contract:
      // "New Privacy Zone". The previous "Create Privacy Zone" expectation
      // was stale and timed out even though the form routed correctly.
      await $(find.text('New Privacy Zone')).waitUntilVisible();
      await _enterVisibleFormField(
        $,
        PrivacyZoneFormScreen.labelFieldKey,
        createdLabel,
      );
      await _enterVisibleFormField(
        $,
        PrivacyZoneFormScreen.latitudeFieldKey,
        '37.7749',
      );
      await _enterVisibleFormField(
        $,
        PrivacyZoneFormScreen.longitudeFieldKey,
        '-122.4194',
      );
      await _enterVisibleFormField(
        $,
        PrivacyZoneFormScreen.radiusFieldKey,
        '250',
      );
      await $(find.byKey(PrivacyZoneFormScreen.saveButtonKey)).tap();

      await $(
        find.byKey(PrivacyZonesScreen.explanationCardKey),
      ).waitUntilVisible();
      await $(find.text(createdLabel)).waitUntilVisible();
      await $(find.text('250 m')).waitUntilVisible();

      await $(find.text(createdLabel)).tap();
      await $(find.text('Edit Privacy Zone')).waitUntilVisible();

      await _enterVisibleFormField(
        $,
        PrivacyZoneFormScreen.labelFieldKey,
        updatedLabel,
      );
      await _enterVisibleFormField(
        $,
        PrivacyZoneFormScreen.radiusFieldKey,
        '300',
      );
      await $(find.byKey(PrivacyZoneFormScreen.saveButtonKey)).tap();

      await $(
        find.byKey(PrivacyZonesScreen.explanationCardKey),
      ).waitUntilVisible();
      await $(find.text(updatedLabel)).waitUntilVisible();
      await $(find.text('300 m')).waitUntilVisible();

      await $(find.text(updatedLabel)).tap();
      await _scrollToAndWaitForKey($, PrivacyZoneFormScreen.deleteButtonKey);
      await $(find.byKey(PrivacyZoneFormScreen.deleteButtonKey)).tap();
      await $(
        find.byKey(PrivacyZoneFormScreen.deleteConfirmButtonKey),
      ).waitUntilVisible();
      await $(find.byKey(PrivacyZoneFormScreen.deleteCancelButtonKey)).tap();

      await $(
        find.byKey(PrivacyZoneFormScreen.deleteButtonKey),
      ).waitUntilVisible();
      await $(find.byKey(PrivacyZoneFormScreen.deleteButtonKey)).tap();
      await $(find.byKey(PrivacyZoneFormScreen.deleteConfirmButtonKey)).tap();

      await $(
        find.byKey(PrivacyZonesScreen.explanationCardKey),
      ).waitUntilVisible();
      await $(find.byKey(PrivacyZonesScreen.emptyStateKey)).waitUntilVisible();
      expect(find.text(updatedLabel), findsNothing);
    },
  );
}

Future<void> _enterVisibleFormField(
  PatrolIntegrationTester $,
  Key fieldKey,
  String text,
) async {
  final finder = find.byKey(fieldKey);
  await $(finder).scrollTo();
  await $(finder).enterText(text);
}

Future<void> _scrollToAndWaitForKey(
  PatrolIntegrationTester $,
  Key fieldKey,
) async {
  final finder = find.byKey(fieldKey);
  await $(finder).scrollTo();
  await $(finder).waitUntilVisible();
}

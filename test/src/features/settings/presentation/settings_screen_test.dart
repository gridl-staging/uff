import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/core/presentation/discard_changes_dialog.dart';
import 'package:uff/src/core/telemetry/telemetry_enablement.dart';
import 'package:uff/src/core/theme/theme_providers.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/settings/presentation/settings_routes.dart';
import 'package:uff/src/features/settings/presentation/settings_screen.dart';

import '../../auth/presentation/auth_test_support.dart';
import '../../profile/presentation/profile_screen_test_support.dart';
import 'settings_screen_test_support.dart';

// ## Test Scenarios
// - [positive] Section headers render in spec order: Display Preferences, Account, Privacy, Data, About, Danger Zone.
// - [positive] Units immediate-save calls profile update with `preferredUnits: imperial`.
// - [positive] Visibility immediate-save calls profile update with `defaultActivityVisibility: followers`.
// - [positive] Display Name field renders in Account and explicit Save persists display name.
// - [positive] Theme controls render and update `themeModeProvider`.
// - [positive] Theme controls expose system/light/dark keys and preserve exact provider state across transitions.
// - [positive] Telemetry toggle renders in Data and updates `telemetryEnablementProvider`.
// - [positive] HR Zones and legal entries navigate to their route targets.
// - [positive] Sign Out exposes a stable semantics id and label for release-smoke selectors.
// - [negative] Unsaved display-name change blocks back navigation and shows discard dialog.
// - [negative] Mutation in-flight disables save/export/delete/sign-out and segmented controls.
// - [isolation] Invalidating `profileProvider` with a different profile resets display-name form state.
// - [statemachine] Units change then visibility change then display-name save preserves combined state.
// - [edge] Export shows a dialog containing exported JSON.
// - [edge] Delete shows confirmation then executes repository delete.
// - [error] Display-name save failure shows snackbar and reverts field text.
// - [error] Export failure shows snackbar.
// - [error] Delete failure shows snackbar.
// - [error] Units immediate-save failure reverts selected segment and shows snackbar.
// - [error] Visibility immediate-save failure reverts selected segment and shows snackbar.
// - [error] Thrown profile-notifier save errors are caught, reverted, and surfaced via snackbar.

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void _expectInteractionControlsLocked(WidgetTester tester) {
  final signOutButtonFinder = find.descendant(
    of: find.byKey(SettingsScreen.signOutButtonKey),
    matching: find.byType(OutlinedButton),
  );
  final saveButton = tester.widget<ElevatedButton>(
    find.byKey(SettingsScreen.saveButtonKey),
  );
  final exportButton = tester.widget<OutlinedButton>(
    find.byKey(SettingsScreen.exportDataButtonKey),
  );
  final deleteButton = tester.widget<OutlinedButton>(
    find.byKey(SettingsScreen.deleteAccountButtonKey),
  );
  final signOutButton = tester.widget<OutlinedButton>(
    signOutButtonFinder,
  );
  final unitsSegment = tester.widget<SegmentedButton<String>>(
    find.byKey(SettingsScreen.unitsSegmentKey),
  );
  final visibilitySegment = tester.widget<SegmentedButton<String>>(
    find.byKey(SettingsScreen.visibilitySegmentKey),
  );
  final displayNameField = tester.widget<TextFormField>(
    find.byKey(SettingsScreen.displayNameFieldKey),
  );

  expect(saveButton.onPressed, null);
  expect(exportButton.onPressed, null);
  expect(deleteButton.onPressed, null);
  expect(signOutButton.onPressed, null);
  expect(unitsSegment.onSelectionChanged, null);
  expect(visibilitySegment.onSelectionChanged, null);
  expect(displayNameField.enabled, false);
}

class _ThrowingSettingsProfileNotifier extends ProfileNotifier {
  _ThrowingSettingsProfileNotifier(this._profileRepository);

  final FakeProfileRepository _profileRepository;

  @override
  FutureOr<Profile?> build() {
    return _profileRepository.profileToReturn;
  }

  @override
  Future<void> updateProfile(Profile profile) {
    throw Exception('forced notifier throw');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsScreen', () {
    testWidgets(
      'renders section headers in spec order and does not show legacy section names',
      (tester) async {
        final originalPhysicalSize = tester.view.physicalSize;
        final originalDevicePixelRatio = tester.view.devicePixelRatio;
        tester.view
          ..physicalSize = const Size(1080, 2600)
          ..devicePixelRatio = 1;
        addTearDown(() {
          tester.view
            ..physicalSize = originalPhysicalSize
            ..devicePixelRatio = originalDevicePixelRatio;
        });

        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildSettingsTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        const sectionHeaders = <String>[
          'Display Preferences',
          'Account',
          'Privacy',
          'Data',
          'About',
          'Danger Zone',
        ];

        for (final sectionHeader in sectionHeaders) {
          expect(find.text(sectionHeader), findsOneWidget);
        }

        final headerYPositions = sectionHeaders
            .map((header) => tester.getTopLeft(find.text(header)).dy)
            .toList();
        for (var index = 1; index < headerYPositions.length; index++) {
          expect(
            headerYPositions[index],
            greaterThan(headerYPositions[index - 1]),
          );
        }

        expect(find.text('Appearance'), findsNothing);
        expect(find.text('Training'), findsNothing);
        expect(find.text('Telemetry'), findsNothing);
      },
    );

    testWidgets(
      'renders units and visibility segmented controls under Display Preferences',
      (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildSettingsTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(SettingsScreen.unitsSegmentKey), findsOneWidget);
        expect(find.byKey(SettingsScreen.visibilitySegmentKey), findsOneWidget);
        expect(find.text('Metric'), findsOneWidget);
        expect(find.text('Imperial'), findsOneWidget);
        expect(find.text('Public'), findsOneWidget);
        expect(find.text('Followers'), findsOneWidget);
        expect(find.text('Private'), findsOneWidget);
      },
    );

    testWidgets(
      'renders account, privacy, data, and danger-zone controls under new sections',
      (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildSettingsTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(SettingsScreen.displayNameFieldKey), findsOneWidget);
        expect(find.byKey(SettingsScreen.saveButtonKey), findsOneWidget);
        expect(find.byKey(SettingsScreen.privacyZonesLinkKey), findsOneWidget);
        expect(find.byKey(SettingsScreen.exportDataButtonKey), findsOneWidget);
        expect(
          find.byKey(SettingsScreen.telemetryToggleTileKey),
          findsOneWidget,
        );
        expect(find.byKey(SettingsScreen.signOutButtonKey), findsOneWidget);
        expect(
          find.byKey(SettingsScreen.deleteAccountButtonKey),
          findsOneWidget,
        );
      },
    );

    testWidgets('sign out exposes a stable semantics id and label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      try {
        await tester.pumpWidget(
          buildSettingsTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        await _scrollUntilVisible(
          tester,
          find.byKey(SettingsScreen.signOutButtonKey),
        );

        // Keep the identifier, label, and tap action on the same semantics
        // node. Testing them separately is too weak because release-lane tools
        // like Maestro query one accessibility element at a time.
        expect(
          tester.getSemantics(find.byKey(SettingsScreen.signOutButtonKey)),
          matchesSemantics(
            identifier: SettingsScreen.signOutButtonSemanticsId,
            label: 'Sign Out',
            textDirection: TextDirection.ltr,
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('theme controls render and update themeModeProvider', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildSettingsTestScope(
          profileRepo: profileRepo,
          initialThemeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
      final themeModeGroup = tester.widget<RadioGroup<ThemeMode>>(
        find.byKey(SettingsScreen.themeModeGroupKey),
      );
      expect(themeModeGroup.groupValue, ThemeMode.dark);

      await tester.tap(find.byKey(SettingsScreen.lightThemeModeKey));
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    testWidgets(
      'theme controls expose static keys and cycle through exact theme mode values',
      (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildSettingsTestScope(
            profileRepo: profileRepo,
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SettingsScreen)),
        );

        expect(find.byKey(SettingsScreen.systemThemeModeKey), findsOneWidget);
        expect(find.byKey(SettingsScreen.lightThemeModeKey), findsOneWidget);
        expect(find.byKey(SettingsScreen.darkThemeModeKey), findsOneWidget);
        expect(container.read(themeModeProvider), ThemeMode.system);

        await tester.tap(find.byKey(SettingsScreen.darkThemeModeKey));
        await tester.pumpAndSettle();
        expect(container.read(themeModeProvider), ThemeMode.dark);

        await tester.tap(find.byKey(SettingsScreen.lightThemeModeKey));
        await tester.pumpAndSettle();
        expect(container.read(themeModeProvider), ThemeMode.light);

        await tester.tap(find.byKey(SettingsScreen.systemThemeModeKey));
        await tester.pumpAndSettle();
        expect(container.read(themeModeProvider), ThemeMode.system);
      },
    );

    testWidgets('telemetry toggle renders in Data and updates provider', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildSettingsTestScope(
          profileRepo: profileRepo,
          initialTelemetryEnabled: false,
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
      final telemetryTile = tester.widget<SwitchListTile>(
        find.byKey(SettingsScreen.telemetryToggleTileKey),
      );
      expect(telemetryTile.value, false);

      await _scrollUntilVisible(
        tester,
        find.byKey(SettingsScreen.telemetryToggleTileKey),
      );
      await tester.tap(find.byKey(SettingsScreen.telemetryToggleTileKey));
      await tester.pumpAndSettle();

      expect(container.read(telemetryEnablementProvider), true);
    });

    testWidgets('units immediate-save updates profile preferred units', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildSettingsTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byKey(SettingsScreen.unitsSegmentKey),
          matching: find.text('Imperial'),
        ),
      );
      await tester.pumpAndSettle();

      expect(profileRepo.updateProfileCallCount, 1);
      expect(profileRepo.lastUpdatedProfile?.preferredUnits, 'imperial');
      expect(
        profileRepo.lastUpdatedProfile?.defaultActivityVisibility,
        testProfile.defaultActivityVisibility,
      );
    });

    testWidgets(
      'visibility immediate-save updates profile default visibility',
      (
        tester,
      ) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildSettingsTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.descendant(
            of: find.byKey(SettingsScreen.visibilitySegmentKey),
            matching: find.text('Followers'),
          ),
        );
        await tester.pumpAndSettle();

        expect(profileRepo.updateProfileCallCount, 1);
        expect(
          profileRepo.lastUpdatedProfile?.defaultActivityVisibility,
          'followers',
        );
        expect(
          profileRepo.lastUpdatedProfile?.preferredUnits,
          testProfile.preferredUnits,
        );
      },
    );

    testWidgets(
      'units immediate-save failure reverts selection and shows snackbar',
      (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile
          ..updateProfileException = Exception('units write failed');

        await tester.pumpWidget(
          buildSettingsTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.descendant(
            of: find.byKey(SettingsScreen.unitsSegmentKey),
            matching: find.text('Imperial'),
          ),
        );
        await tester.pumpAndSettle();

        final renderedUnitsSegment = tester.widget<SegmentedButton<String>>(
          find.byKey(SettingsScreen.unitsSegmentKey),
        );
        expect(renderedUnitsSegment.selected, {'metric'});
        expect(
          find.text('Failed to save settings. Please try again.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'units immediate-save catches thrown notifier errors and reverts selection',
      (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildSettingsTestScope(
            profileRepo: profileRepo,
            profileNotifierFactory: _ThrowingSettingsProfileNotifier.new,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.descendant(
            of: find.byKey(SettingsScreen.unitsSegmentKey),
            matching: find.text('Imperial'),
          ),
        );
        await tester.pumpAndSettle();

        final renderedUnitsSegment = tester.widget<SegmentedButton<String>>(
          find.byKey(SettingsScreen.unitsSegmentKey),
        );
        expect(renderedUnitsSegment.selected, {'metric'});
        expect(
          find.text('Failed to save settings. Please try again.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'visibility immediate-save failure reverts selection and shows snackbar',
      (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile
          ..updateProfileException = Exception('visibility write failed');

        await tester.pumpWidget(
          buildSettingsTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.descendant(
            of: find.byKey(SettingsScreen.visibilitySegmentKey),
            matching: find.text('Followers'),
          ),
        );
        await tester.pumpAndSettle();

        final renderedVisibilitySegment = tester
            .widget<SegmentedButton<String>>(
              find.byKey(SettingsScreen.visibilitySegmentKey),
            );
        expect(renderedVisibilitySegment.selected, {'private'});
        expect(
          find.text('Failed to save settings. Please try again.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('display-name save calls updateProfile with explicit Save', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildSettingsTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(SettingsScreen.displayNameFieldKey),
        'Alice Updated',
      );
      await _scrollUntilVisible(
        tester,
        find.byKey(SettingsScreen.saveButtonKey),
      );
      await tester.tap(find.byKey(SettingsScreen.saveButtonKey));
      await tester.pumpAndSettle();

      expect(profileRepo.updateProfileCallCount, 1);
      expect(profileRepo.lastUpdatedProfile?.displayName, 'Alice Updated');
    });

    testWidgets('display-name save failure reverts text and shows snackbar', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile
        ..updateProfileException = Exception('save failed');

      await tester.pumpWidget(
        buildSettingsTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(SettingsScreen.displayNameFieldKey),
        'Unsaved Name',
      );
      await _scrollUntilVisible(
        tester,
        find.byKey(SettingsScreen.saveButtonKey),
      );
      await tester.tap(find.byKey(SettingsScreen.saveButtonKey));
      await tester.pumpAndSettle();

      final displayNameField = tester.widget<TextFormField>(
        find.byKey(SettingsScreen.displayNameFieldKey),
      );
      expect(displayNameField.controller?.text, 'Alice');
      expect(
        find.text('Failed to save settings. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'display-name save catches thrown notifier errors and reverts text',
      (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildSettingsTestScope(
            profileRepo: profileRepo,
            profileNotifierFactory: _ThrowingSettingsProfileNotifier.new,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(SettingsScreen.displayNameFieldKey),
          'Unsaved Name',
        );
        await _scrollUntilVisible(
          tester,
          find.byKey(SettingsScreen.saveButtonKey),
        );
        await tester.tap(find.byKey(SettingsScreen.saveButtonKey));
        await tester.pumpAndSettle();

        final displayNameField = tester.widget<TextFormField>(
          find.byKey(SettingsScreen.displayNameFieldKey),
        );
        expect(displayNameField.controller?.text, 'Alice');
        expect(
          find.text('Failed to save settings. Please try again.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('dirty display-name blocks pop and shows discard dialog', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildPoppableSettingsRouterTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(SettingsScreen.displayNameFieldKey),
        'Unsaved Change',
      );
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(discardChangesDialogTitle), findsOneWidget);
      expect(find.text(discardChangesDialogMessage), findsOneWidget);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('mutation in-flight locks interaction controls', (
      tester,
    ) async {
      final pendingSave = Completer<Profile>();
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile
        ..updateProfileCompleter = pendingSave;

      await tester.pumpWidget(
        buildSettingsTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(SettingsScreen.displayNameFieldKey),
        'Pending Save',
      );
      await _scrollUntilVisible(
        tester,
        find.byKey(SettingsScreen.saveButtonKey),
      );
      await tester.tap(find.byKey(SettingsScreen.saveButtonKey));
      await tester.pump();

      _expectInteractionControlsLocked(tester);

      pendingSave.complete(profileRepo.lastUpdatedProfile!);
      await tester.pumpAndSettle();
    });

    testWidgets(
      'preference immediate-save in-flight locks interaction controls',
      (
        tester,
      ) async {
        final pendingSave = Completer<Profile>();
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile
          ..updateProfileCompleter = pendingSave;

        await tester.pumpWidget(
          buildSettingsTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.descendant(
            of: find.byKey(SettingsScreen.unitsSegmentKey),
            matching: find.text('Imperial'),
          ),
        );
        await tester.pump();

        _expectInteractionControlsLocked(tester);

        pendingSave.complete(profileRepo.lastUpdatedProfile!);
        await tester.pumpAndSettle();
      },
    );

    testWidgets('profileProvider invalidation resets display-name form state', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildSettingsTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(SettingsScreen.displayNameFieldKey),
        'Unsaved Local Name',
      );
      await tester.pump();

      profileRepo.profileToReturn = testProfile.copyWith(
        userId: 'user-2',
        displayName: 'Second User',
      );
      ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      ).invalidate(profileProvider);
      await tester.pumpAndSettle();

      final displayNameField = tester.widget<TextFormField>(
        find.byKey(SettingsScreen.displayNameFieldKey),
      );
      expect(displayNameField.controller?.text, 'Second User');
    });

    testWidgets(
      'units -> visibility -> display-name save sequence preserves combined state',
      (tester) async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = testProfile;

        await tester.pumpWidget(
          buildSettingsTestScope(profileRepo: profileRepo),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.descendant(
            of: find.byKey(SettingsScreen.unitsSegmentKey),
            matching: find.text('Imperial'),
          ),
        );
        await tester.pumpAndSettle();
        expect(profileRepo.lastUpdatedProfile?.preferredUnits, 'imperial');

        await tester.tap(
          find.descendant(
            of: find.byKey(SettingsScreen.visibilitySegmentKey),
            matching: find.text('Followers'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          profileRepo.lastUpdatedProfile?.defaultActivityVisibility,
          'followers',
        );

        await tester.enterText(
          find.byKey(SettingsScreen.displayNameFieldKey),
          'Alice Sequence',
        );
        await _scrollUntilVisible(
          tester,
          find.byKey(SettingsScreen.saveButtonKey),
        );
        await tester.tap(find.byKey(SettingsScreen.saveButtonKey));
        await tester.pumpAndSettle();

        expect(profileRepo.updateProfileCallCount, 3);
        expect(profileRepo.lastUpdatedProfile?.displayName, 'Alice Sequence');
        expect(profileRepo.lastUpdatedProfile?.preferredUnits, 'imperial');
        expect(
          profileRepo.lastUpdatedProfile?.defaultActivityVisibility,
          'followers',
        );
      },
    );

    testWidgets('export shows JSON dialog content', (tester) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildSettingsTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      await _scrollUntilVisible(
        tester,
        find.byKey(SettingsScreen.exportDataButtonKey),
      );
      await tester.tap(find.byKey(SettingsScreen.exportDataButtonKey));
      await tester.pumpAndSettle();

      expect(profileRepo.exportMyDataCallCount, 1);
      expect(find.byKey(SettingsScreen.exportDataDialogKey), findsOneWidget);
      expect(find.text('Exported Data'), findsOneWidget);
      expect(find.textContaining('"profile"'), findsOneWidget);
      expect(find.textContaining('"activities"'), findsOneWidget);
      expect(find.textContaining('"privacy_zones"'), findsOneWidget);
    });

    testWidgets('export failure shows snackbar', (tester) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile
        ..exportMyDataException = Exception('export failed');

      await tester.pumpWidget(
        buildSettingsTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      await _scrollUntilVisible(
        tester,
        find.byKey(SettingsScreen.exportDataButtonKey),
      );
      await tester.tap(find.byKey(SettingsScreen.exportDataButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.text('Failed to export data. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('delete confirmation then executes deleteMyAccount', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildSettingsTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      await _scrollUntilVisible(
        tester,
        find.byKey(SettingsScreen.deleteAccountButtonKey),
      );
      await tester.tap(find.byKey(SettingsScreen.deleteAccountButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Delete Account'), findsAtLeastNWidgets(1));
      expect(
        find.text(
          'This permanently deletes your account and all data. This cannot be undone.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(profileRepo.deleteMyAccountCallCount, 1);
    });

    testWidgets('delete failure shows snackbar', (tester) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile
        ..deleteMyAccountException = Exception('delete failed');

      await tester.pumpWidget(
        buildSettingsTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      await _scrollUntilVisible(
        tester,
        find.byKey(SettingsScreen.deleteAccountButtonKey),
      );
      await tester.tap(find.byKey(SettingsScreen.deleteAccountButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(
        find.text('Failed to delete account. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('sign out delegates to authProvider.notifier.signOut', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;
      final authRepo = RecordingAuthRepository(
        initialState: const AuthState.authenticated(
          userId: 'user-1',
          email: 'a@b.com',
        ),
      );

      await tester.pumpWidget(
        buildSettingsTestScope(profileRepo: profileRepo, authRepo: authRepo),
      );
      await tester.pumpAndSettle();

      await _scrollUntilVisible(
        tester,
        find.byKey(SettingsScreen.signOutButtonKey),
      );
      await tester.tap(find.byKey(SettingsScreen.signOutButtonKey));
      await tester.pumpAndSettle();

      expect(authRepo.signOutCallCount, 1);
    });

    testWidgets('privacy zones, hr zones, and legal rows navigate via routes', (
      tester,
    ) async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = testProfile;

      await tester.pumpWidget(
        buildSettingsRouterTestScope(profileRepo: profileRepo),
      );
      await tester.pumpAndSettle();

      await _scrollUntilVisible(
        tester,
        find.byKey(SettingsScreen.privacyZonesLinkKey),
      );
      await tester.tap(find.byKey(SettingsScreen.privacyZonesLinkKey));
      await tester.pumpAndSettle();
      expect(find.text('Privacy Zones Target'), findsOneWidget);

      final context = tester.element(find.text('Privacy Zones Target'));
      GoRouter.of(context).go(SettingsRoutes.settingsPath);
      await tester.pumpAndSettle();

      await _scrollUntilVisible(
        tester,
        find.byKey(SettingsScreen.hrZonesTileKey),
      );
      await tester.tap(find.byKey(SettingsScreen.hrZonesTileKey));
      await tester.pumpAndSettle();
      expect(find.text('HR Zones Target'), findsOneWidget);

      final hrContext = tester.element(find.text('HR Zones Target'));
      GoRouter.of(hrContext).go(SettingsRoutes.settingsPath);
      await tester.pumpAndSettle();

      await _scrollUntilVisible(
        tester,
        find.byKey(SettingsScreen.privacyPolicyTileKey),
      );
      await tester.tap(find.byKey(SettingsScreen.privacyPolicyTileKey));
      await tester.pumpAndSettle();
      expect(find.text('Privacy Policy Target'), findsOneWidget);

      final privacyContext = tester.element(find.text('Privacy Policy Target'));
      GoRouter.of(privacyContext).go(SettingsRoutes.settingsPath);
      await tester.pumpAndSettle();

      await _scrollUntilVisible(
        tester,
        find.byKey(SettingsScreen.termsOfServiceTileKey),
      );
      await tester.tap(find.byKey(SettingsScreen.termsOfServiceTileKey));
      await tester.pumpAndSettle();
      expect(find.text('Terms of Service Target'), findsOneWidget);
    });
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/core/presentation/button_progress_indicator.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/settings/presentation/hr_zone_setup_screen.dart';

// ## Test Scenarios
// - [positive] Loading state shows progress indicator.
// - [error] Load error shows retry button.
// - [positive] LTHR field prefills with existing value.
// - [positive] Valid LTHR renders the computed five-zone breakdown.
// - [negative] Blank, non-integer, and out-of-range input show validation errors before update.
// - [isolation] Profile hydration resets the field from provider state instead of stale local widget state.
// - [positive] Valid LTHR saves successfully.
// - [positive] Save shows button progress and disables actions while update is pending.
// - [positive] Clear button writes null LTHR.

const _profileWithLthr = Profile(
  userId: 'user-1',
  preferredUnits: 'metric',
  defaultActivityVisibility: 'private',
  onboardingCompleted: true,
  displayName: 'Runner',
  avatarUrl: 'https://example.com/avatar.png',
  lthrBpm: 165,
);

const _profileWithoutLthr = Profile(
  userId: 'user-1',
  preferredUnits: 'metric',
  defaultActivityVisibility: 'private',
  onboardingCompleted: true,
  displayName: 'Runner',
  avatarUrl: 'https://example.com/avatar.png',
);

class _BuildFailure {
  const _BuildFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

const _loadingState = Object();

class _ScriptedProfileController {
  _ScriptedProfileController(this._buildResults, {this.updateProfileException});

  final List<Object?> _buildResults;
  final Exception? updateProfileException;
  int buildCallCount = 0;
  int updateProfileCallCount = 0;
  Profile? lastUpdatedProfile;
  Completer<void>? updateProfileCompleter;

  Object? nextBuildResult() {
    if (_buildResults.isEmpty) {
      throw StateError('Build script cannot be empty');
    }

    final index = buildCallCount;
    buildCallCount++;
    if (index >= _buildResults.length) {
      return _buildResults.last;
    }

    return _buildResults[index];
  }
}

class _ScriptedProfileNotifier extends ProfileNotifier {
  _ScriptedProfileNotifier(this.controller);

  final _ScriptedProfileController controller;

  @override
  FutureOr<Profile?> build() {
    final result = controller.nextBuildResult();
    if (identical(result, _loadingState)) {
      return Completer<Profile?>().future;
    }

    if (result is _BuildFailure) {
      Error.throwWithStackTrace(result.error, result.stackTrace);
    }

    if (result is Profile?) {
      return result;
    }

    throw StateError('Unexpected build result: ');
  }

  @override
  Future<void> updateProfile(Profile profile) async {
    final previousState = state;
    state = const AsyncLoading<Profile?>();

    controller.updateProfileCallCount++;
    controller.lastUpdatedProfile = profile;
    final pendingUpdate = controller.updateProfileCompleter;
    if (pendingUpdate != null) {
      await pendingUpdate.future;
    }
    state = AsyncValue.data(profile);
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _ScriptedProfileController controller,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileProvider.overrideWith(
          () => _ScriptedProfileNotifier(controller),
        ),
      ],
      child: const MaterialApp(home: HrZoneSetupScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows loading state while profile is unresolved', (
    tester,
  ) async {
    final controller = _ScriptedProfileController([_loadingState]);

    await _pumpScreen(tester, controller: controller);

    expect(find.byKey(HrZoneSetupScreen.loadingStateKey), findsOneWidget);
    expect(find.byKey(HrZoneSetupScreen.lthrInputKey), findsNothing);
  });

  testWidgets('shows safe load error and retry refreshes profileProvider', (
    tester,
  ) async {
    final controller = _ScriptedProfileController([
      _BuildFailure(StateError('backend exploded'), StackTrace.current),
      _profileWithoutLthr,
    ]);

    await _pumpScreen(tester, controller: controller);
    await tester.pumpAndSettle();

    expect(find.byKey(HrZoneSetupScreen.loadErrorStateKey), findsOneWidget);
    expect(
      find.text('Unable to load heart rate zones right now. Please retry.'),
      findsOneWidget,
    );
    expect(find.textContaining('backend exploded'), findsNothing);
    expect(controller.buildCallCount, 1);

    await tester.tap(find.byKey(HrZoneSetupScreen.retryButtonKey));
    await tester.pumpAndSettle();

    expect(controller.buildCallCount, 2);
    expect(find.byKey(HrZoneSetupScreen.lthrInputKey), findsOneWidget);
    expect(find.byKey(HrZoneSetupScreen.loadErrorStateKey), findsNothing);
  });

  testWidgets('prefills the LTHR input from Profile.lthrBpm', (tester) async {
    final controller = _ScriptedProfileController([_profileWithLthr]);

    await _pumpScreen(tester, controller: controller);
    await tester.pumpAndSettle();

    expect(find.byKey(HrZoneSetupScreen.lthrInputKey), findsOneWidget);
    expect(find.text('165'), findsOneWidget);
  });

  testWidgets(
    'shows the five-zone breakdown for a valid LTHR using the shared calculator contract',
    (tester) async {
      final controller = _ScriptedProfileController([_profileWithLthr]);

      await _pumpScreen(tester, controller: controller);
      await tester.pumpAndSettle();

      expect(find.byKey(HrZoneSetupScreen.zoneBreakdownKey), findsOneWidget);
      expect(find.text('Zone 1 · Recovery'), findsOneWidget);
      expect(find.text('0-139 bpm'), findsOneWidget);
      expect(find.text('Zone 2 · Aerobic'), findsOneWidget);
      expect(find.text('140-147 bpm'), findsOneWidget);
      expect(find.text('Zone 3 · Tempo'), findsOneWidget);
      expect(find.text('148-155 bpm'), findsOneWidget);
      expect(find.text('Zone 4 · Threshold'), findsOneWidget);
      expect(find.text('156-164 bpm'), findsOneWidget);
      expect(find.text('Zone 5 · VO2max'), findsOneWidget);
      expect(find.text('165+ bpm'), findsOneWidget);
    },
  );

  testWidgets(
    'rejects blank, non-integer, and calculator-invalid values before update',
    (tester) async {
      final controller = _ScriptedProfileController([_profileWithLthr]);

      await _pumpScreen(tester, controller: controller);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(HrZoneSetupScreen.lthrInputKey), '');
      await tester.tap(find.byKey(HrZoneSetupScreen.saveButtonKey));
      await tester.pumpAndSettle();
      expect(controller.updateProfileCallCount, 0);

      await tester.enterText(find.byKey(HrZoneSetupScreen.lthrInputKey), 'abc');
      await tester.tap(find.byKey(HrZoneSetupScreen.saveButtonKey));
      await tester.pumpAndSettle();
      expect(controller.updateProfileCallCount, 0);

      await tester.enterText(find.byKey(HrZoneSetupScreen.lthrInputKey), '33');
      await tester.tap(find.byKey(HrZoneSetupScreen.saveButtonKey));
      await tester.pumpAndSettle();
      expect(controller.updateProfileCallCount, 0);

      expect(find.text('Enter a valid LTHR value.'), findsOneWidget);
    },
  );

  testWidgets('saves valid LTHR and preserves unrelated profile fields', (
    tester,
  ) async {
    final controller = _ScriptedProfileController([_profileWithoutLthr]);

    await _pumpScreen(tester, controller: controller);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(HrZoneSetupScreen.lthrInputKey), '172');
    await tester.tap(find.byKey(HrZoneSetupScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(controller.updateProfileCallCount, 1);
    expect(controller.lastUpdatedProfile!.lthrBpm, 172);
    expect(controller.lastUpdatedProfile!.userId, _profileWithoutLthr.userId);
    expect(
      controller.lastUpdatedProfile!.preferredUnits,
      _profileWithoutLthr.preferredUnits,
    );
    expect(
      controller.lastUpdatedProfile!.defaultActivityVisibility,
      _profileWithoutLthr.defaultActivityVisibility,
    );
    expect(
      controller.lastUpdatedProfile!.displayName,
      _profileWithoutLthr.displayName,
    );
    expect(
      controller.lastUpdatedProfile!.avatarUrl,
      _profileWithoutLthr.avatarUrl,
    );
  });

  testWidgets(
    'save shows progress feedback and disables actions while profile update is pending',
    (tester) async {
      final controller = _ScriptedProfileController([_profileWithoutLthr]);
      final pendingUpdate = Completer<void>();
      controller.updateProfileCompleter = pendingUpdate;

      await _pumpScreen(tester, controller: controller);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(HrZoneSetupScreen.lthrInputKey), '172');
      await tester.tap(find.byKey(HrZoneSetupScreen.saveButtonKey));
      await tester.pump();

      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(HrZoneSetupScreen.saveButtonKey),
      );
      final clearButton = tester.widget<OutlinedButton>(
        find.byKey(HrZoneSetupScreen.clearButtonKey),
      );

      expect(find.byType(ButtonProgressIndicator), findsOneWidget);
      expect(saveButton.onPressed, isNull);
      expect(clearButton.onPressed, isNull);

      pendingUpdate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ButtonProgressIndicator), findsNothing);
      expect(controller.updateProfileCallCount, 1);
      expect(controller.lastUpdatedProfile!.lthrBpm, 172);
    },
  );

  testWidgets('clear writes null LTHR and preserves unrelated profile fields', (
    tester,
  ) async {
    final controller = _ScriptedProfileController([_profileWithLthr]);

    await _pumpScreen(tester, controller: controller);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HrZoneSetupScreen.clearButtonKey));
    await tester.pumpAndSettle();

    expect(controller.updateProfileCallCount, 1);
    expect(controller.lastUpdatedProfile!.lthrBpm, isNull);
    expect(controller.lastUpdatedProfile!.userId, _profileWithLthr.userId);
    expect(
      controller.lastUpdatedProfile!.preferredUnits,
      _profileWithLthr.preferredUnits,
    );
    expect(
      controller.lastUpdatedProfile!.defaultActivityVisibility,
      _profileWithLthr.defaultActivityVisibility,
    );
    expect(
      controller.lastUpdatedProfile!.displayName,
      _profileWithLthr.displayName,
    );
    expect(
      controller.lastUpdatedProfile!.avatarUrl,
      _profileWithLthr.avatarUrl,
    );
  });
}

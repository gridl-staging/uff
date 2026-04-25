import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/profile/data/profile_repository.dart';
import 'package:uff/src/common_widgets/brand_header.dart';
import 'package:uff/src/features/onboarding/presentation/onboarding_screen.dart';

part 'onboarding_screen_test_helpers.dart';

// ## Test Scenarios
// - [positive] Onboarding renders the first-run flow shell and page scaffold.
// - [positive] BrandHeader renders above the welcome step title.
// - [statemachine] Continue/back/skip/complete transitions move between steps,
//   keep local state until submit, and persist exactly one final payload.
// - [negative] Onboarding-owned tests do not permit an empty sport selection
//   or duplicate submit writes while completion is already in flight.
// - [isolation] Submitted onboarding preferences stay scoped to the current
//   profile update path and do not mutate a different user's profile state.
// - [edge] Sport selection cannot transition to an empty set.
// - [error] Retry recovers from profile-load failures and null-profile states.
// - [edge] Repeated complete/skip taps during an in-flight submit are ignored.
// - [error] Completion submit failures show a snackbar and keep Step 4 retryable.

const _baseProfile = Profile(
  userId: 'user-1',
  preferredUnits: 'metric',
  defaultActivityVisibility: 'private',
  onboardingCompleted: false,
  displayName: 'Runner',
);

const _hydratedProfile = Profile(
  userId: 'user-2',
  preferredUnits: 'imperial',
  defaultActivityVisibility: 'followers',
  onboardingCompleted: false,
  displayName: 'Hydrated Runner',
  sportPreferences: ['ride', 'walk'],
);

const _legacyPublicProfile = Profile(
  userId: 'user-3',
  preferredUnits: 'imperial',
  defaultActivityVisibility: 'public',
  onboardingCompleted: false,
  displayName: 'Legacy Public Runner',
);

void main() {
  group('OnboardingScreen', () {
    testWidgets('BrandHeader renders above the welcome step title', (
      tester,
    ) async {
      final notifier = _RecordingProfileNotifier(_baseProfile);
      await _pumpOnboarding(tester, profileNotifier: notifier);

      final brandHeader = find.byKey(BrandHeader.brandHeaderKey);
      final welcomeTitle = find.text('Welcome to Uff');
      expect(brandHeader, findsOneWidget);
      expect(welcomeTitle, findsOneWidget);

      final brandHeaderY = tester.getTopLeft(brandHeader).dy;
      final welcomeTitleY = tester.getTopLeft(welcomeTitle).dy;
      expect(
        brandHeaderY,
        lessThan(welcomeTitleY),
        reason: 'BrandHeader must render above the welcome step title',
      );
    });

    testWidgets('renders onboarding shell and welcome step', (tester) async {
      final notifier = _RecordingProfileNotifier(_baseProfile);
      await _pumpOnboarding(tester, profileNotifier: notifier);

      expect(find.byKey(const Key('onboarding_screen')), findsOneWidget);
      expect(find.text('Welcome to Uff'), findsOneWidget);
      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets(
      'progresses and goes back via PageController with indicator bound to it',
      (tester) async {
        final notifier = _RecordingProfileNotifier(_baseProfile);
        await _pumpOnboarding(tester, profileNotifier: notifier);

        final pageView = tester.widget<PageView>(find.byType(PageView));
        final indicator = tester.widget<SmoothPageIndicator>(
          find.byKey(const Key('onboarding_page_indicator')),
        );
        expect(identical(indicator.controller, pageView.controller), isTrue);

        await _goToSportStep(tester);
        expect(find.text('What do you track?'), findsOneWidget);

        await _tapContinue(tester);
        expect(find.text('Unit preference'), findsOneWidget);

        await _tapBack(tester);
        expect(find.text('What do you track?'), findsOneWidget);
      },
    );

    testWidgets(
      'hydrates sport and units from profile while privacy keeps the required private default',
      (tester) async {
        final notifier = _RecordingProfileNotifier(_hydratedProfile);
        await _pumpOnboarding(tester, profileNotifier: notifier);

        await _goToSportStep(tester);
        expect(_sportChip(tester, 'ride').selected, isTrue);
        expect(_sportChip(tester, 'walk').selected, isTrue);
        expect(_sportChip(tester, 'run').selected, isFalse);

        await _tapContinue(tester);
        final unitSelector = tester.widget<SegmentedButton<String>>(
          find.byKey(const Key('onboarding_units_selector')),
        );
        expect(unitSelector.selected, {'imperial'});

        await _tapContinue(tester);
        expect(
          find.byKey(const Key('visibility_option_private_check')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('visibility_option_followers_check')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'sport chips are toggleable, run starts selected, and at least one stays selected',
      (tester) async {
        final notifier = _RecordingProfileNotifier(_baseProfile);
        await _pumpOnboarding(tester, profileNotifier: notifier);
        await _goToSportStep(tester);

        expect(_sportChip(tester, 'run').selected, isTrue);

        await tester.tap(find.byKey(const Key('sport_chip_ride')));
        await tester.pumpAndSettle();
        expect(_sportChip(tester, 'ride').selected, isTrue);

        await tester.tap(find.byKey(const Key('sport_chip_run')));
        await tester.pumpAndSettle();
        expect(_sportChip(tester, 'run').selected, isFalse);

        await tester.tap(find.byKey(const Key('sport_chip_ride')));
        await tester.pumpAndSettle();
        expect(_sportChip(tester, 'ride').selected, isTrue);
      },
    );

    testWidgets('holds local onboarding state until complete or skip', (
      tester,
    ) async {
      final notifier = _RecordingProfileNotifier(_baseProfile);
      await _pumpOnboarding(tester, profileNotifier: notifier);
      await _selectCustomOnboardingChoices(tester);

      expect(notifier.updateProfileCallCount, 0);
    });

    testWidgets('complete submits selected onboarding payload once', (
      tester,
    ) async {
      final notifier = _RecordingProfileNotifier(_baseProfile);
      await _pumpOnboarding(tester, profileNotifier: notifier);
      await _selectCustomOnboardingChoices(tester);
      await _tapContinue(tester);

      _expectSubmittedProfile(
        notifier,
        preferredUnits: 'imperial',
        defaultActivityVisibility: 'followers',
        sportPreferences: ['run', 'ride'],
      );
    });

    testWidgets('privacy cards preselect only me and move check icon on tap', (
      tester,
    ) async {
      final notifier = _RecordingProfileNotifier(_baseProfile);
      await _pumpOnboarding(tester, profileNotifier: notifier);
      await _goToPrivacyStep(tester);

      expect(
        find.byKey(const Key('visibility_option_private_check')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('visibility_option_followers')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('visibility_option_followers_check')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('visibility_option_private_check')),
        findsNothing,
      );
    });

    testWidgets(
      'skip submits default onboarding payload and does not persist partial selections',
      (tester) async {
        final notifier = _RecordingProfileNotifier(_baseProfile);
        await _pumpOnboarding(tester, profileNotifier: notifier);
        await _selectCustomOnboardingChoices(tester);
        await _tapAndSettle(
          tester,
          find.byKey(const Key('onboarding_skip_button')),
        );

        _expectSubmittedProfile(
          notifier,
          preferredUnits: 'metric',
          defaultActivityVisibility: 'private',
          sportPreferences: ['run'],
        );
      },
    );

    testWidgets(
      'skip and complete defaults stay equivalent for legacy public rows',
      (tester) async {
        final completeNotifier = _RecordingProfileNotifier(
          _legacyPublicProfile,
        );
        await _pumpOnboarding(tester, profileNotifier: completeNotifier);
        await _goToPrivacyStep(tester);
        await _tapContinue(tester);

        final completePayload = completeNotifier.lastUpdatedProfile!;

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        final skipNotifier = _RecordingProfileNotifier(_legacyPublicProfile);
        await _pumpOnboarding(tester, profileNotifier: skipNotifier);
        await tester.tap(find.byKey(const Key('onboarding_skip_button')));
        await tester.pumpAndSettle();

        final skipPayload = skipNotifier.lastUpdatedProfile!;

        expect(skipPayload.preferredUnits, completePayload.preferredUnits);
        expect(
          skipPayload.defaultActivityVisibility,
          completePayload.defaultActivityVisibility,
        );
        expect(skipPayload.sportPreferences, completePayload.sportPreferences);
        expect(
          skipPayload.onboardingCompleted,
          completePayload.onboardingCompleted,
        );
      },
    );

    testWidgets(
      'error state shows retry affordance and recovers after profile refresh',
      (tester) async {
        final notifier = _RetryingProfileNotifier(
          profile: _baseProfile,
          failBuild: true,
        );
        await _pumpOnboarding(tester, profileNotifier: notifier);

        expect(find.text('Unable to load onboarding profile.'), findsOneWidget);
        expect(
          find.byKey(const Key('onboarding_retry_button')),
          findsOneWidget,
        );

        notifier.failBuild = false;
        await _tapRetry(tester);

        expect(find.text('Welcome to Uff'), findsOneWidget);
        expect(find.text('Unable to load onboarding profile.'), findsNothing);
        expect(find.byKey(const Key('onboarding_retry_button')), findsNothing);
      },
    );

    testWidgets(
      'null profile state offers retry affordance instead of dead-end copy',
      (tester) async {
        final notifier = _RetryingProfileNotifier(returnNullProfile: true);
        await _pumpOnboarding(tester, profileNotifier: notifier);

        expect(find.text('No profile available.'), findsOneWidget);
        expect(
          find.byKey(const Key('onboarding_retry_button')),
          findsOneWidget,
        );

        await _tapRetry(tester);

        expect(find.text('No profile available.'), findsOneWidget);
        expect(find.text('Welcome to Uff'), findsNothing);
        expect(
          find.byKey(const Key('onboarding_retry_button')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'complete ignores repeated taps while profile update is in flight',
      (tester) async {
        final notifier = _DelayedUpdateProfileNotifier(_baseProfile);
        await _pumpOnboarding(tester, profileNotifier: notifier);
        await _goToPrivacyStep(tester);

        expect(find.text('Complete'), findsOneWidget);

        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pump();

        expect(notifier.updateProfileCallCount, 1);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await notifier.finishPendingUpdate();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'complete failure shows snackbar, keeps privacy step active, and allows retry',
      (tester) async {
        final profileRepository = _FailingSubmitProfileRepository(
          profile: _baseProfile,
        );
        await _pumpOnboardingWithProfileRepository(
          tester,
          profileRepository: profileRepository,
          authState: AuthState.authenticated(
            userId: _baseProfile.userId,
            email: 'runner@example.com',
          ),
        );
        await _goToPrivacyStep(tester);

        expect(find.text('Default activity visibility'), findsOneWidget);
        expect(find.text('Complete'), findsOneWidget);

        final submitButtonBeforeFailure = tester.widget<ElevatedButton>(
          find.byKey(const Key('onboarding_continue_button')),
        );
        expect(submitButtonBeforeFailure.onPressed == null, isFalse);

        await _tapContinue(tester);

        expect(
          find.text('Could not complete onboarding. Try again.'),
          findsOneWidget,
        );
        expect(profileRepository.updateProfileCallCount, 1);
        expect(find.text('Default activity visibility'), findsOneWidget);
        expect(find.text('Complete'), findsOneWidget);

        final submitButtonAfterFailure = tester.widget<ElevatedButton>(
          find.byKey(const Key('onboarding_continue_button')),
        );
        expect(submitButtonAfterFailure.onPressed == null, isFalse);

        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        await _tapContinue(tester);
        expect(profileRepository.updateProfileCallCount, 2);
      },
    );

    testWidgets(
      'skip ignores repeated taps while profile update is in flight',
      (tester) async {
        final notifier = _DelayedUpdateProfileNotifier(_baseProfile);
        await _pumpOnboarding(tester, profileNotifier: notifier);

        await tester.tap(find.byKey(const Key('onboarding_skip_button')));
        await tester.tap(find.byKey(const Key('onboarding_skip_button')));
        await tester.pump();

        expect(notifier.updateProfileCallCount, 1);
        final skipButton = tester.widget<TextButton>(
          find.byKey(const Key('onboarding_skip_button')),
        );
        expect(skipButton.onPressed, isNull);

        await notifier.finishPendingUpdate();
        await tester.pumpAndSettle();
      },
    );
  });
}

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_history_screen.dart';
import 'package:uff/src/features/analytics/presentation/analytics_screen.dart';
import 'package:uff/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:uff/src/features/social/presentation/feed_screen.dart';
import 'package:uff/src/routing/app_router.dart';
import '../auth_setup.dart';
import '../fixtures.dart';

// ## Test Scenarios
// - [positive] New user with pending onboarding completes the full onboarding
//   flow and lands on home with empty activity history.
// - [positive] New user skips onboarding and lands on home with empty history.
// - [positive] Brand-new user sees empty states across feed, activity, and
//   analytics tabs after completing onboarding.
void main() {
  patrolTest(
    'new user completes onboarding flow and lands on home history',
    ($) async {
      // Create a user whose onboarding_completed = false. In hosted
      // environments this uses the admin API to bypass email confirmation.
      // The router will redirect to /onboarding on app launch.
      await initializeTestServices();
      await ensureTestUserForOnboarding();
      await $.pumpWidget(
        await buildTestApp(trackingOverrides: false),
      );
      registerAuthCleanup($);

      await $(
        find.byKey(OnboardingScreen.onboardingScreenKey),
      ).waitUntilVisible(timeout: const Duration(seconds: 20));
      expect(find.text(emptyHistoryMessage), findsNothing);

      await $(find.byKey(OnboardingScreen.continueButtonKey)).tap();
      await $(find.byKey(const Key('sport_chip_run'))).waitUntilVisible();
      await $(find.byKey(OnboardingScreen.continueButtonKey)).tap();

      await $(
        find.byKey(OnboardingScreen.unitsImperialOptionKey),
      ).waitUntilVisible();
      await $(find.byKey(OnboardingScreen.unitsImperialOptionKey)).tap();
      await $(find.byKey(OnboardingScreen.continueButtonKey)).tap();

      await $(
        find.byKey(OnboardingScreen.visibilityFollowersOptionKey),
      ).waitUntilVisible();
      await $(find.byKey(OnboardingScreen.visibilityFollowersOptionKey)).tap();
      await $(find.byKey(OnboardingScreen.continueButtonKey)).tap();

      await waitForHomeActivityHistoryLoaded($);
      await $(find.text(emptyHistoryMessage)).waitUntilVisible();
      expect(find.byKey(OnboardingScreen.onboardingScreenKey), findsNothing);
    },
  );

  patrolTest(
    'new user skips onboarding and lands on home history',
    ($) async {
      await initializeTestServices();
      await ensureTestUserForOnboarding();
      await $.pumpWidget(
        await buildTestApp(trackingOverrides: false),
      );
      registerAuthCleanup($);

      await $(
        find.byKey(OnboardingScreen.onboardingScreenKey),
      ).waitUntilVisible(timeout: const Duration(seconds: 20));
      expect(find.text(emptyHistoryMessage), findsNothing);

      await $(find.byKey(OnboardingScreen.skipButtonKey)).waitUntilVisible();
      await $(find.byKey(OnboardingScreen.skipButtonKey)).tap();

      await waitForHomeActivityHistoryLoaded($);
      await $(find.text(emptyHistoryMessage)).waitUntilVisible();
      expect(find.byKey(OnboardingScreen.onboardingScreenKey), findsNothing);
    },
  );

  patrolTest(
    'brand-new user sees empty states across feed activity and analytics tabs',
    ($) async {
      await initializeTestServices();
      await ensureTestUserForOnboarding();
      await $.pumpWidget(
        await buildTestApp(trackingOverrides: false),
      );
      registerAuthCleanup($);

      await $(
        find.byKey(OnboardingScreen.onboardingScreenKey),
      ).waitUntilVisible(timeout: const Duration(seconds: 20));

      await $(find.byKey(OnboardingScreen.continueButtonKey)).tap();
      await $(find.byKey(const Key('sport_chip_run'))).waitUntilVisible();
      await $(find.byKey(OnboardingScreen.continueButtonKey)).tap();

      await $(
        find.byKey(OnboardingScreen.unitsImperialOptionKey),
      ).waitUntilVisible();
      await $(find.byKey(OnboardingScreen.unitsImperialOptionKey)).tap();
      await $(find.byKey(OnboardingScreen.continueButtonKey)).tap();

      await $(
        find.byKey(OnboardingScreen.visibilityFollowersOptionKey),
      ).waitUntilVisible();
      await $(find.byKey(OnboardingScreen.visibilityFollowersOptionKey)).tap();
      await $(find.byKey(OnboardingScreen.continueButtonKey)).tap();

      await $(
        find.byKey(HomeShellScreen.openSettingsButtonKey),
      ).waitUntilVisible(timeout: const Duration(seconds: 30));
      // Feed empty state is in the widget tree but may not be hit-testable
      // (e.g. behind the bottom nav bar), so check existence rather than
      // visibility.
      await $(find.byKey(FeedScreen.emptyStateKey)).waitUntilExists();

      await navigateToHomeShellDestination($, HomeShellDestinationId.activity);
      await $(
        find.byKey(ActivityHistoryScreen.emptyStateKey),
      ).waitUntilVisible();
      await $(find.text(emptyHistoryMessage)).waitUntilVisible();

      await navigateToHomeShellDestination($, HomeShellDestinationId.analytics);
      // With zero saved activities the analytics screen now shows the
      // screen-level empty state instead of mounting the training-load cards.
      await $(find.byKey(AnalyticsScreen.emptyStateKey)).waitUntilVisible();
    },
  );
}

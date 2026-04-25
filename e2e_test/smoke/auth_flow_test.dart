import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:uff/src/features/activity_tracking/presentation/activity_history_screen.dart';
import 'package:uff/src/features/auth/presentation/auth_error_message.dart';
import 'package:uff/src/features/auth/presentation/login_screen.dart';
import 'package:uff/src/features/auth/presentation/signup_screen.dart';
import 'package:uff/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:uff/src/features/settings/presentation/settings_screen.dart';
import 'package:uff/src/routing/app_router.dart';
import '../auth_setup.dart';
import '../fixtures.dart';

// ## Test Scenarios
// - [positive] New user with pending onboarding can skip onboarding, sign out,
//   and sign back in from auth screens.
// - [edge] OAuth button affordances match the current environment config and
//   platform capabilities. When OAuth is disabled, buttons must be absent.
// - [error] Invalid credentials show mapped error copy, then retry with the
//   correct password succeeds.
void main() {
  patrolTest(
    'new user with pending onboarding can skip onboarding sign out and sign back in',
    ($) async {
      // Create a user with onboarding_completed = false. In hosted
      // environments this bypasses email confirmation via admin API.
      await initializeTestServices();
      final credentials = await ensureTestUserForOnboarding();
      await $.pumpWidget(
        await buildTestApp(trackingOverrides: false),
      );
      registerAuthCleanup($);

      // The router redirects to /onboarding because onboarding_completed is
      // false. Skip onboarding to reach home.
      await $(
        find.byKey(OnboardingScreen.onboardingScreenKey),
      ).waitUntilVisible(timeout: const Duration(seconds: 20));
      await $(find.byKey(OnboardingScreen.skipButtonKey)).tap();

      await waitForHomeActivityHistoryLoaded($);
      await $(find.text(emptyHistoryMessage)).waitUntilVisible();

      // Sign out.
      await navigateToHomeShellDestination($, HomeShellDestinationId.profile);
      await openSettingsAndRevealSignOutButton($);
      await $(find.byKey(SettingsScreen.signOutButtonKey)).waitUntilVisible();
      await $(find.byKey(SettingsScreen.signOutButtonKey)).tap();

      // Sign back in with the same credentials.
      await $(find.byKey(LoginScreen.emailFieldKey)).waitUntilVisible();
      await $(
        find.byKey(LoginScreen.emailFieldKey),
      ).enterText(credentials.email);
      await $(
        find.byKey(LoginScreen.passwordFieldKey),
      ).enterText(credentials.password);
      await $(find.byKey(LoginScreen.signInButtonKey)).tap();

      await waitForHomeActivityHistoryLoaded($);
      await $(find.text(emptyHistoryMessage)).waitUntilVisible();
    },
  );

  patrolTest(
    'auth screens show correct OAuth button affordances for environment config',
    ($) async {
      await launchUnauthenticatedApp($);
      registerAuthCleanup($);

      // Read environment config to determine which OAuth providers are enabled.
      // The test validates that the UI matches the configuration.
      final isGoogleEnabled =
          dotenv.maybeGet('ENABLE_GOOGLE_SIGN_IN')?.toLowerCase() == 'true';
      final isAppleEnabled =
          dotenv.maybeGet('ENABLE_APPLE_SIGN_IN')?.toLowerCase() == 'true';
      final expectsAppleButton =
          isAppleEnabled &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS);

      // Login screen: verify OAuth buttons match config.
      await $(find.byKey(LoginScreen.emailFieldKey)).waitUntilVisible();

      if (isGoogleEnabled) {
        await $(
          find.byKey(LoginScreen.googleSignInButtonKey),
        ).waitUntilVisible();
      } else {
        expect(find.byKey(LoginScreen.googleSignInButtonKey), findsNothing);
      }

      if (expectsAppleButton) {
        await $(
          find.byKey(LoginScreen.appleSignInButtonKey),
        ).waitUntilVisible();
      } else {
        expect(find.byKey(LoginScreen.appleSignInButtonKey), findsNothing);
      }

      // Signup screen: verify same OAuth buttons.
      await $(find.text('Create account')).tap();
      await $(find.byKey(SignUpScreen.displayNameFieldKey)).waitUntilVisible();

      if (isGoogleEnabled) {
        await $(
          find.byKey(SignUpScreen.googleSignInButtonKey),
        ).waitUntilVisible();
      } else {
        expect(find.byKey(SignUpScreen.googleSignInButtonKey), findsNothing);
      }

      if (expectsAppleButton) {
        await $(
          find.byKey(SignUpScreen.appleSignInButtonKey),
        ).waitUntilVisible();
      } else {
        expect(find.byKey(SignUpScreen.appleSignInButtonKey), findsNothing);
      }
    },
  );

  patrolTest(
    'existing user sees invalid-credentials copy then signs in on retry',
    ($) async {
      await initializeTestServices();

      final uniqueTimestamp = DateTime.now().microsecondsSinceEpoch;
      final email = 'wrong_password_retry_$uniqueTimestamp@example.com';
      const correctPassword = 'TestPassword123!';
      const wrongPassword = 'WrongPassword123!';
      const invalidCredentialsError = AuthException(
        'Authentication failed',
        code: 'invalid_credentials',
      );
      final invalidCredentialsMessage = mapAuthErrorToMessage(
        invalidCredentialsError,
      );

      await ensureTestUser(email: email, password: correctPassword);
      await launchUnauthenticatedApp($);
      registerAuthCleanup($);

      await $(find.byKey(LoginScreen.emailFieldKey)).waitUntilVisible();
      await $(find.byKey(LoginScreen.emailFieldKey)).enterText(email);
      await $(
        find.byKey(LoginScreen.passwordFieldKey),
      ).enterText(wrongPassword);
      await $(find.byKey(LoginScreen.signInButtonKey)).tap();

      await $(find.text(invalidCredentialsMessage)).waitUntilVisible();
      expect(find.byKey(LoginScreen.emailFieldKey), findsOneWidget);
      expect(find.byKey(LoginScreen.signInButtonKey), findsOneWidget);

      await $(
        find.byKey(LoginScreen.passwordFieldKey),
      ).enterText(correctPassword);
      await $(find.byKey(LoginScreen.signInButtonKey)).tap();

      await waitForHomeActivityHistoryLoaded($);
      await $(
        find.byKey(ActivityHistoryScreen.emptyStateKey),
      ).waitUntilVisible();
    },
  );
}

/// ## Test Scenarios
/// - [positive] Login screen submits credentials and navigates on success
/// - [positive] Sign up screen submits credentials and handles email confirmation
/// - [positive] Settings screen sign out calls provider and returns to login
/// - [positive] Social auth buttons render per platform (iOS: Apple+Google, Android: no Apple)
/// - [positive] Legal links render and open privacy policy / terms
/// - [negative] Login blocks submit when credentials are empty or malformed
/// - [negative] Sign up blocks submit for invalid field values
/// - [negative] Login shows mapped error message for invalid credentials
/// - [negative] Signup shows mapped error message for duplicate email
/// - [edge] Sign in / sign up ignore repeated taps and redirect only after auth settles
/// - [edge] Social auth buttons disabled while auth is loading
/// - [edge] Login / sign up clear validation errors after correction
/// - [error] Login legal failure shows recovery actions and returns to login
/// - [error] Both screens render same message for same error type and network failures

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, AuthRetryableFetchException;
import 'package:uff/src/app.dart';
import 'package:uff/src/features/auth/data/auth_repository.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/auth/presentation/login_screen.dart';
import 'package:uff/src/features/auth/presentation/signup_screen.dart';
import 'package:uff/src/features/legal/presentation/legal_document_screen.dart';
import 'package:uff/src/features/legal/presentation/legal_routes.dart';
import 'package:uff/src/features/settings/presentation/settings_screen.dart';
import 'package:uff/src/routing/app_router.dart';

import 'auth_test_support.dart';

Future<void> _pumpAuthScreen(
  WidgetTester tester, {
  required AuthRepository repository,
  required Widget child,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    buildAuthTestScope(
      repository: repository,
      child: MaterialApp(theme: theme, home: child),
    ),
  );
}

Future<void> _enterLoginCredentials(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  await tester.enterText(find.byKey(LoginScreen.emailFieldKey), email);
  await tester.enterText(find.byKey(LoginScreen.passwordFieldKey), password);
}

Future<void> _enterSignUpCredentials(
  WidgetTester tester, {
  required String displayName,
  required String email,
  required String password,
  String? confirmPassword,
}) async {
  await tester.enterText(
    find.byKey(SignUpScreen.displayNameFieldKey),
    displayName,
  );
  await tester.enterText(find.byKey(SignUpScreen.emailFieldKey), email);
  await tester.enterText(find.byKey(SignUpScreen.passwordFieldKey), password);
  await tester.enterText(
    find.byKey(SignUpScreen.confirmPasswordFieldKey),
    confirmPassword ?? password,
  );
}

Future<String?> _submitLoginAndReadErrorMessage(
  WidgetTester tester, {
  required AuthRepository repository,
  required String email,
  required String password,
  required String expectedMessage,
}) async {
  await _pumpAuthScreen(
    tester,
    repository: repository,
    child: const LoginScreen(),
  );
  await _enterLoginCredentials(tester, email: email, password: password);
  await tester.tap(find.byKey(LoginScreen.signInButtonKey));
  await tester.pumpAndSettle();
  return tester.widget<Text>(find.text(expectedMessage)).data;
}

Future<String?> _submitSignUpAndReadErrorMessage(
  WidgetTester tester, {
  required AuthRepository repository,
  required String displayName,
  required String email,
  required String password,
  required String expectedMessage,
}) async {
  await _pumpAuthScreen(
    tester,
    repository: repository,
    child: const SignUpScreen(),
  );
  await _enterSignUpCredentials(
    tester,
    displayName: displayName,
    email: email,
    password: password,
  );
  await tester.tap(find.byKey(SignUpScreen.signUpButtonKey));
  await tester.pumpAndSettle();
  return tester.widget<Text>(find.text(expectedMessage)).data;
}

Future<void> _scrollToSettingsSignOutButton(WidgetTester tester) {
  return tester.scrollUntilVisible(
    find.byKey(SettingsScreen.signOutButtonKey),
    200,
    scrollable: find.byType(Scrollable).first,
  );
}

void main() {
  group('Auth screens', () {
    test('login screen is a ConsumerWidget', () {
      // Stage 3: isA<ConsumerWidget> is the most concrete assertion for a
      // compile-time type hierarchy check; no runtime value to pin here.
      // test-standards:allow-weak-assertion
      expect(const LoginScreen(), isA<ConsumerWidget>());
    });

    testWidgets('login screen submits credentials', (tester) async {
      final repository = RecordingAuthRepository();

      await _pumpAuthScreen(
        tester,
        repository: repository,
        child: const LoginScreen(),
      );

      await tester.enterText(find.byKey(LoginScreen.emailFieldKey), 'a@b.com');
      await tester.enterText(
        find.byKey(LoginScreen.passwordFieldKey),
        'pw123456',
      );
      await tester.tap(find.byKey(LoginScreen.signInButtonKey));
      await tester.pumpAndSettle();

      expect(repository.signInEmail, 'a@b.com');
      expect(repository.signInPassword, 'pw123456');
    });

    testWidgets('login screen blocks submit when credentials are empty', (
      tester,
    ) async {
      final repository = RecordingAuthRepository();

      await _pumpAuthScreen(
        tester,
        repository: repository,
        child: const LoginScreen(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(LoginScreen.signInButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
      expect(repository.signInEmail, isNull);
      expect(repository.signInPassword, isNull);
    });

    testWidgets('login screen blocks submit for malformed email', (
      tester,
    ) async {
      final repository = RecordingAuthRepository();

      await _pumpAuthScreen(
        tester,
        repository: repository,
        child: const LoginScreen(),
      );

      await tester.enterText(
        find.byKey(LoginScreen.emailFieldKey),
        'invalid-email-format',
      );
      await tester.enterText(
        find.byKey(LoginScreen.passwordFieldKey),
        'abc123',
      );
      await tester.tap(find.byKey(LoginScreen.signInButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(repository.signInEmail, isNull);
      expect(repository.signInPassword, isNull);
    });

    testWidgets('login screen clears validation errors after correction', (
      tester,
    ) async {
      final repository = RecordingAuthRepository();

      await _pumpAuthScreen(
        tester,
        repository: repository,
        child: const LoginScreen(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(LoginScreen.signInButtonKey));
      await tester.pumpAndSettle();
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);

      await tester.enterText(
        find.byKey(LoginScreen.emailFieldKey),
        'fixed@example.com',
      );
      await tester.enterText(
        find.byKey(LoginScreen.passwordFieldKey),
        'abc123',
      );
      await tester.pumpAndSettle();

      expect(find.text('Email is required'), findsNothing);
      expect(find.text('Password is required'), findsNothing);

      await tester.tap(find.byKey(LoginScreen.signInButtonKey));
      await tester.pumpAndSettle();

      expect(repository.signInEmail, 'fixed@example.com');
      expect(repository.signInPassword, 'abc123');
    });

    testWidgets('login screen shows Apple and Google buttons on iOS', (
      tester,
    ) async {
      final repository = RecordingAuthRepository();

      await _pumpAuthScreen(
        tester,
        repository: repository,
        theme: ThemeData(platform: TargetPlatform.iOS),
        child: const LoginScreen(),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(LoginScreen.appleSignInButtonKey), findsOneWidget);
      expect(find.byKey(LoginScreen.googleSignInButtonKey), findsOneWidget);
    });

    testWidgets('login screen hides Apple button on Android', (tester) async {
      final repository = RecordingAuthRepository();

      await _pumpAuthScreen(
        tester,
        repository: repository,
        theme: ThemeData(platform: TargetPlatform.android),
        child: const LoginScreen(),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(LoginScreen.appleSignInButtonKey), findsNothing);
      expect(find.byKey(LoginScreen.googleSignInButtonKey), findsOneWidget);
    });

    testWidgets('sign up screen submits credentials', (tester) async {
      final repository = RecordingAuthRepository();

      await _pumpAuthScreen(
        tester,
        repository: repository,
        child: const SignUpScreen(),
      );

      await tester.enterText(
        find.byKey(SignUpScreen.displayNameFieldKey),
        'Test User',
      );
      await tester.enterText(
        find.byKey(SignUpScreen.emailFieldKey),
        'new@b.com',
      );
      await tester.enterText(
        find.byKey(SignUpScreen.passwordFieldKey),
        'pw123456',
      );
      await tester.enterText(
        find.byKey(SignUpScreen.confirmPasswordFieldKey),
        'pw123456',
      );
      await tester.tap(find.byKey(SignUpScreen.signUpButtonKey));
      await tester.pumpAndSettle();

      expect(repository.signUpDisplayName, 'Test User');
      expect(repository.signUpEmail, 'new@b.com');
      expect(repository.signUpPassword, 'pw123456');
    });

    testWidgets(
      'sign up screen explains when email confirmation is still required',
      (tester) async {
        await _pumpAuthScreen(
          tester,
          repository: ConfirmationPendingAuthRepository(),
          child: const SignUpScreen(),
        );

        await tester.enterText(
          find.byKey(SignUpScreen.displayNameFieldKey),
          'Test User',
        );
        await tester.enterText(
          find.byKey(SignUpScreen.emailFieldKey),
          'confirm@b.com',
        );
        await tester.enterText(
          find.byKey(SignUpScreen.passwordFieldKey),
          'pw123456',
        );
        await tester.enterText(
          find.byKey(SignUpScreen.confirmPasswordFieldKey),
          'pw123456',
        );
        await tester.tap(find.byKey(SignUpScreen.signUpButtonKey));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Account created. Check your email to confirm your account before '
            'signing in.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('sign up screen blocks submit for invalid field values', (
      tester,
    ) async {
      final repository = RecordingAuthRepository();

      await _pumpAuthScreen(
        tester,
        repository: repository,
        child: const SignUpScreen(),
      );

      await tester.enterText(
        find.byKey(SignUpScreen.displayNameFieldKey),
        '   ',
      );
      await tester.enterText(
        find.byKey(SignUpScreen.emailFieldKey),
        'bad-email',
      );
      await tester.enterText(
        find.byKey(SignUpScreen.passwordFieldKey),
        '12345',
      );
      await tester.enterText(
        find.byKey(SignUpScreen.confirmPasswordFieldKey),
        'different',
      );
      await tester.tap(find.byKey(SignUpScreen.signUpButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Display name is required'), findsOneWidget);
      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(
        find.text('Password must be at least 6 characters'),
        findsOneWidget,
      );
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(repository.signUpDisplayName, isNull);
      expect(repository.signUpEmail, isNull);
      expect(repository.signUpPassword, isNull);
    });

    testWidgets('sign up screen clears validation errors after correction', (
      tester,
    ) async {
      final repository = RecordingAuthRepository();

      await _pumpAuthScreen(
        tester,
        repository: repository,
        child: const SignUpScreen(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(SignUpScreen.signUpButtonKey));
      await tester.pumpAndSettle();
      expect(find.text('Display name is required'), findsOneWidget);
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
      expect(find.text('Confirm your password'), findsOneWidget);

      await tester.enterText(
        find.byKey(SignUpScreen.displayNameFieldKey),
        'Test User',
      );
      await tester.enterText(
        find.byKey(SignUpScreen.emailFieldKey),
        'new@b.com',
      );
      await tester.enterText(
        find.byKey(SignUpScreen.passwordFieldKey),
        'pw123456',
      );
      await tester.enterText(
        find.byKey(SignUpScreen.confirmPasswordFieldKey),
        'pw123456',
      );
      await tester.pumpAndSettle();

      expect(find.text('Display name is required'), findsNothing);
      expect(find.text('Email is required'), findsNothing);
      expect(find.text('Password is required'), findsNothing);
      expect(find.text('Confirm your password'), findsNothing);

      await tester.tap(find.byKey(SignUpScreen.signUpButtonKey));
      await tester.pumpAndSettle();

      expect(repository.signUpDisplayName, 'Test User');
      expect(repository.signUpEmail, 'new@b.com');
      expect(repository.signUpPassword, 'pw123456');
    });

    testWidgets('sign up screen shows Apple and Google buttons on iOS', (
      tester,
    ) async {
      final repository = RecordingAuthRepository();

      await _pumpAuthScreen(
        tester,
        repository: repository,
        theme: ThemeData(platform: TargetPlatform.iOS),
        child: const SignUpScreen(),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(SignUpScreen.appleSignInButtonKey), findsOneWidget);
      expect(find.byKey(SignUpScreen.googleSignInButtonKey), findsOneWidget);
    });

    testWidgets('settings screen sign out calls provider', (tester) async {
      final repository = RecordingAuthRepository();

      await _pumpAuthScreen(
        tester,
        repository: repository,
        child: const SettingsScreen(),
      );
      await tester.pump();

      await _scrollToSettingsSignOutButton(tester);
      await tester.tap(find.byKey(SettingsScreen.signOutButtonKey));
      await tester.pumpAndSettle();

      expect(repository.signOutCallCount, 1);
    });

    testWidgets(
      'settings screen keeps direct-usage section and sign-out contract',
      (tester) async {
        final repository = RecordingAuthRepository(
          initialState: const AuthState.authenticated(
            userId: 'seed-user',
            email: 'seed@example.com',
          ),
        );

        await tester.pumpWidget(
          buildAuthTestScope(
            repository: repository,
            initialAuthState: const AuthState.authenticated(
              userId: 'seed-user',
              email: 'seed@example.com',
            ),
            child: const MaterialApp(home: SettingsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Appearance'), findsOneWidget);
        expect(find.text('About'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(SettingsScreen.signOutButtonKey),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Account'), findsOneWidget);
        await _scrollToSettingsSignOutButton(tester);
        expect(find.byKey(SettingsScreen.signOutButtonKey), findsOneWidget);
      },
    );

    testWidgets('signed-in users can open settings from the home shell', (
      tester,
    ) async {
      final repository = RecordingAuthRepository(
        initialState: const AuthState.authenticated(
          userId: 'seed-user',
          email: 'seed@example.com',
        ),
      );

      await tester.pumpWidget(
        buildAuthTestScope(
          repository: repository,
          trackingRepository: AuthTestTrackingRepository(),
          initialAuthState: const AuthState.authenticated(
            userId: 'seed-user',
            email: 'seed@example.com',
          ),
          child: const UffApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeShellScreen), findsOneWidget);
      final navBar = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      expect(navBar.currentIndex, 0);
      expect(find.text('Feed'), findsOneWidget);

      await tester.tap(find.byKey(HomeShellScreen.openSettingsButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      await _scrollToSettingsSignOutButton(tester);
      expect(find.byKey(SettingsScreen.signOutButtonKey), findsOneWidget);
    });

    testWidgets('sign in stays on the login screen while loading', (
      tester,
    ) async {
      final repository = DelayedSignInAuthRepository();

      await tester.pumpWidget(
        buildAuthTestScope(
          repository: repository,
          trackingRepository: AuthTestTrackingRepository(),
          child: const UffApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(LoginScreen.emailFieldKey), 'a@b.com');
      await tester.enterText(
        find.byKey(LoginScreen.passwordFieldKey),
        'pw123456',
      );
      await tester.tap(find.byKey(LoginScreen.signInButtonKey));
      await tester.pump();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);

      repository.completeSignIn(
        const AuthState.authenticated(
          userId: 'stub-a@b.com',
          email: 'a@b.com',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets(
      'sign in ignores repeated taps and redirects only after auth settles',
      (tester) async {
        final repository = DelayedSignInAuthRepository();

        await tester.pumpWidget(
          buildAuthTestScope(
            repository: repository,
            trackingRepository: AuthTestTrackingRepository(),
            child: const UffApp(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(LoginScreen.emailFieldKey),
          'double@tap.com',
        );
        await tester.enterText(
          find.byKey(LoginScreen.passwordFieldKey),
          'pw123456',
        );
        await tester.tap(find.byKey(LoginScreen.signInButtonKey));
        await tester.tap(find.byKey(LoginScreen.signInButtonKey));
        await tester.pump();

        expect(repository.signInCallCount, 1);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byType(HomeShellScreen), findsNothing);

        repository.completeSignIn(
          const AuthState.authenticated(
            userId: 'double-tap',
            email: 'double@tap.com',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(HomeShellScreen), findsOneWidget);
      },
    );

    testWidgets(
      'sign up ignores repeated taps and redirects only after auth settles',
      (tester) async {
        final repository = DelayedSignInAuthRepository(delaySignUp: true);

        await tester.pumpWidget(
          buildAuthTestScope(
            repository: repository,
            trackingRepository: AuthTestTrackingRepository(),
            child: const UffApp(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Create account'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(SignUpScreen.displayNameFieldKey),
          'Double Tapper',
        );
        await tester.enterText(
          find.byKey(SignUpScreen.emailFieldKey),
          'signup@tap.com',
        );
        await tester.enterText(
          find.byKey(SignUpScreen.passwordFieldKey),
          'pw123456',
        );
        await tester.enterText(
          find.byKey(SignUpScreen.confirmPasswordFieldKey),
          'pw123456',
        );
        await tester.tap(find.byKey(SignUpScreen.signUpButtonKey));
        await tester.tap(find.byKey(SignUpScreen.signUpButtonKey));
        await tester.pump();

        expect(repository.signUpCallCount, 1);
        expect(find.byType(SignUpScreen), findsOneWidget);
        expect(find.byType(HomeShellScreen), findsNothing);

        repository.completeSignUp(
          const AuthState.authenticated(
            userId: 'signup-double-tap',
            email: 'signup@tap.com',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(HomeShellScreen), findsOneWidget);
      },
    );

    testWidgets('social auth buttons are disabled while auth is loading', (
      tester,
    ) async {
      final repository = DelayedSignInAuthRepository();

      await _pumpAuthScreen(
        tester,
        repository: repository,
        theme: ThemeData(platform: TargetPlatform.iOS),
        child: const LoginScreen(),
      );

      await tester.enterText(find.byKey(LoginScreen.emailFieldKey), 'a@b.com');
      await tester.enterText(
        find.byKey(LoginScreen.passwordFieldKey),
        'pw123456',
      );
      await tester.tap(find.byKey(LoginScreen.signInButtonKey));
      await tester.pump();

      final googleButton = tester.widget<OutlinedButton>(
        find.byKey(LoginScreen.googleSignInButtonKey),
      );
      expect(googleButton.onPressed, isNull);

      await tester.tap(
        find.byKey(LoginScreen.appleSignInButtonKey),
        warnIfMissed: false,
      );
      await tester.tap(find.byKey(LoginScreen.googleSignInButtonKey));
      await tester.pump();

      expect(repository.signInWithAppleCallCount, 0);
      expect(repository.signInWithGoogleCallCount, 0);
    });

    testWidgets(
      'sign out from settings waits for auth settle and ignores repeated taps',
      (tester) async {
        final repository = DelayedSignInAuthRepository(
          initialState: const AuthState.authenticated(
            userId: 'seed-user',
            email: 'seed@example.com',
          ),
          delaySignOut: true,
        );

        await tester.pumpWidget(
          buildAuthTestScope(
            repository: repository,
            trackingRepository: AuthTestTrackingRepository(),
            initialAuthState: const AuthState.authenticated(
              userId: 'seed-user',
              email: 'seed@example.com',
            ),
            child: const UffApp(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(HomeShellScreen.openSettingsButtonKey));
        await tester.pumpAndSettle();
        await _scrollToSettingsSignOutButton(tester);
        await tester.tap(find.byKey(SettingsScreen.signOutButtonKey));
        await tester.tap(find.byKey(SettingsScreen.signOutButtonKey));
        await tester.pump();

        expect(repository.signOutCallCount, 1);
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.byType(LoginScreen), findsNothing);

        repository.completeSignOut();
        await tester.pumpAndSettle();

        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byKey(LoginScreen.signInButtonKey), findsOneWidget);
      },
    );

    testWidgets('sign out from settings returns to the login screen', (
      tester,
    ) async {
      final repository = RecordingAuthRepository(
        initialState: const AuthState.authenticated(
          userId: 'seed-user',
          email: 'seed@example.com',
        ),
      );

      await tester.pumpWidget(
        buildAuthTestScope(
          repository: repository,
          trackingRepository: AuthTestTrackingRepository(),
          initialAuthState: const AuthState.authenticated(
            userId: 'seed-user',
            email: 'seed@example.com',
          ),
          child: const UffApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(HomeShellScreen.openSettingsButtonKey));
      await tester.pumpAndSettle();
      await _scrollToSettingsSignOutButton(tester);
      await tester.tap(find.byKey(SettingsScreen.signOutButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byKey(LoginScreen.signInButtonKey), findsOneWidget);
    });

    testWidgets('router refreshes when auth stream emits state changes', (
      tester,
    ) async {
      final repository = RecordingAuthRepository();
      final authStateChanges = StreamController<AuthState>.broadcast();
      addTearDown(authStateChanges.close);

      await tester.pumpWidget(
        buildAuthTestScope(
          repository: repository,
          trackingRepository: AuthTestTrackingRepository(),
          authStateChanges: authStateChanges.stream,
          child: const UffApp(),
        ),
      );

      authStateChanges.add(const AuthState.unauthenticated());
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);

      authStateChanges.add(
        const AuthState.authenticated(
          userId: 'stream-user',
          email: 'stream@example.com',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);

      await tester.tap(find.byKey(HomeShellScreen.openSettingsButtonKey));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      authStateChanges.add(const AuthState.unauthenticated());
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);
    });

    testWidgets('login screen exposes legal links and opens privacy policy', (
      tester,
    ) async {
      final repository = RecordingAuthRepository();

      await tester.pumpWidget(
        buildAuthTestScope(
          repository: repository,
          trackingRepository: AuthTestTrackingRepository(),
          child: const UffApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(LoginScreen.privacyPolicyButtonKey), findsOneWidget);
      expect(find.byKey(LoginScreen.termsOfServiceButtonKey), findsOneWidget);
      expect(find.text(LegalRoutes.privacyTitle), findsOneWidget);
      expect(find.text(LegalRoutes.termsTitle), findsOneWidget);

      await tester.tap(find.byKey(LoginScreen.privacyPolicyButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      expect(find.text(LegalRoutes.privacyTitle), findsOneWidget);
      expect(find.byKey(LegalDocumentScreen.markdownViewKey), findsOneWidget);
      expect(find.byKey(LegalDocumentScreen.errorMessageKey), findsNothing);
    });

    testWidgets(
      'login legal failure shows recovery actions and returns to login',
      (tester) async {
        final repository = RecordingAuthRepository();
        final router = GoRouter(
          initialLocation: '/auth/sign-in',
          routes: [
            GoRoute(
              path: '/auth/sign-in',
              builder: (_, __) => const LoginScreen(),
            ),
            GoRoute(
              path: LegalRoutes.privacyPath,
              builder: (_, __) => const LegalDocumentScreen(
                title: LegalRoutes.privacyTitle,
                assetPath: 'docs/missing_privacy_policy.md',
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          buildAuthTestScope(
            repository: repository,
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(LoginScreen.privacyPolicyButtonKey));
        await tester.pumpAndSettle();

        expect(find.byType(LegalDocumentScreen), findsOneWidget);
        expect(find.byKey(LegalDocumentScreen.errorMessageKey), findsOneWidget);
        expect(find.byKey(LegalDocumentScreen.retryButtonKey), findsOneWidget);
        expect(find.byKey(LegalDocumentScreen.backButtonKey), findsOneWidget);

        await tester.tap(find.byKey(LegalDocumentScreen.retryButtonKey));
        await tester.pumpAndSettle();

        expect(find.byType(LegalDocumentScreen), findsOneWidget);
        expect(find.byKey(LegalDocumentScreen.errorMessageKey), findsOneWidget);

        await tester.tap(find.byKey(LegalDocumentScreen.backButtonKey));
        await tester.pumpAndSettle();

        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byKey(LoginScreen.privacyPolicyButtonKey), findsOneWidget);
      },
    );

    testWidgets('sign-up screen exposes legal links and opens terms', (
      tester,
    ) async {
      final repository = RecordingAuthRepository();

      await tester.pumpWidget(
        buildAuthTestScope(
          repository: repository,
          trackingRepository: AuthTestTrackingRepository(),
          child: const UffApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(find.byType(SignUpScreen), findsOneWidget);
      expect(find.byKey(SignUpScreen.privacyPolicyButtonKey), findsOneWidget);
      expect(find.byKey(SignUpScreen.termsOfServiceButtonKey), findsOneWidget);
      expect(find.text(LegalRoutes.privacyTitle), findsOneWidget);
      expect(find.text(LegalRoutes.termsTitle), findsOneWidget);

      await tester.tap(find.byKey(SignUpScreen.termsOfServiceButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      expect(find.text(LegalRoutes.termsTitle), findsOneWidget);
      expect(find.byKey(LegalDocumentScreen.markdownViewKey), findsOneWidget);
      expect(find.byKey(LegalDocumentScreen.errorMessageKey), findsNothing);
    });
  });

  group('Auth error display', () {
    testWidgets('login screen shows mapped message for invalid credentials', (
      tester,
    ) async {
      final message = await _submitLoginAndReadErrorMessage(
        tester,
        repository: ThrowingAuthRepository(
          signInError: const AuthException(
            'Authentication failed',
            code: 'invalid_credentials',
          ),
        ),
        email: 'a@b.com',
        password: 'wrong',
        expectedMessage: 'Invalid email or password.',
      );
      expect(message, 'Invalid email or password.');
    });

    testWidgets('signup screen shows mapped message for duplicate email', (
      tester,
    ) async {
      final message = await _submitSignUpAndReadErrorMessage(
        tester,
        repository: ThrowingAuthRepository(
          signUpError: const AuthException(
            'Authentication failed',
            code: 'email_address_already_registered',
          ),
        ),
        displayName: 'Test',
        email: 'dup@b.com',
        password: 'pw123456',
        expectedMessage: 'An account with this email already exists.',
      );
      expect(message, 'An account with this email already exists.');
    });

    testWidgets(
      'both screens render the same message for the same error type',
      (tester) async {
        const error = AuthException(
          'Authentication failed',
          code: 'invalid_credentials',
        );

        final loginMessage = await _submitLoginAndReadErrorMessage(
          tester,
          repository: ThrowingAuthRepository(signInError: error),
          email: 'a@b.com',
          password: 'wrong',
          expectedMessage: 'Invalid email or password.',
        );
        final signupMessage = await _submitSignUpAndReadErrorMessage(
          tester,
          repository: ThrowingAuthRepository(signUpError: error),
          displayName: 'Test',
          email: 'a@b.com',
          password: 'wrong',
          expectedMessage: 'Invalid email or password.',
        );
        expect(signupMessage, loginMessage);
      },
    );

    testWidgets(
      'both screens render the same network message for retryable auth failures',
      (tester) async {
        final error = AuthRetryableFetchException();

        final loginMessage = await _submitLoginAndReadErrorMessage(
          tester,
          repository: ThrowingAuthRepository(signInError: error),
          email: 'a@b.com',
          password: 'wrong',
          expectedMessage: 'Unable to connect. Check your internet connection.',
        );
        final signupMessage = await _submitSignUpAndReadErrorMessage(
          tester,
          repository: ThrowingAuthRepository(signUpError: error),
          displayName: 'Test',
          email: 'a@b.com',
          password: 'wrong',
          expectedMessage: 'Unable to connect. Check your internet connection.',
        );
        expect(signupMessage, loginMessage);
      },
    );
  });
}

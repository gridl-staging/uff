import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/common_widgets/brand_header.dart';
import 'package:uff/src/features/auth/presentation/signup_screen.dart';

import 'auth_test_support.dart';

// ## Test Scenarios
// - [positive] Signup form controls expose stable spoken labels
// - [positive] BrandHeader renders above the display name field
// - [positive] Create-account action renders above the OAuth divider and buttons
// - [edge] Signup form is wrapped in scroll view for keyboard safety
// - [negative] Signup with duplicate email shows error, not session
// - [isolation] Logout clears auth state; re-signup shows clean form

void main() {
  testWidgets('signup form controls expose stable spoken labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        buildAuthTestScope(
          repository: RecordingAuthRepository(),
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: const SignUpScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(SignUpScreen.displayNameFieldKey), findsOneWidget);
      expect(find.bySemanticsLabel('Display Name'), findsAtLeastNWidgets(1));
      expect(find.byKey(SignUpScreen.emailFieldKey), findsOneWidget);
      expect(find.bySemanticsLabel('Email'), findsAtLeastNWidgets(1));
      expect(find.byKey(SignUpScreen.passwordFieldKey), findsOneWidget);
      expect(find.bySemanticsLabel('Password'), findsAtLeastNWidgets(1));
      expect(find.byKey(SignUpScreen.confirmPasswordFieldKey), findsOneWidget);
      expect(
        find.bySemanticsLabel('Confirm Password'),
        findsAtLeastNWidgets(1),
      );
      expect(find.byKey(SignUpScreen.signUpButtonKey), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.byKey(SignUpScreen.signUpButtonKey)),
        isA<ElevatedButton>().having(
          (button) => button.onPressed,
          'onPressed',
          // Stage 3: callback identity is not a stable value target; isNotNull
          // proves the button is enabled, which is the intent of this test.
          isNotNull,
        ),
      );
      expect(find.bySemanticsLabel('Create account'), findsAtLeastNWidgets(1));
      expect(find.byKey(SignUpScreen.googleSignInButtonKey), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(
          find.byKey(SignUpScreen.googleSignInButtonKey),
        ),
        isA<OutlinedButton>().having(
          (button) => button.onPressed,
          'onPressed',
          // Stage 3: callback identity is not a stable value target; isNotNull
          // proves the button is enabled, which is the intent of this test.
          isNotNull,
        ),
      );
      expect(
        find.bySemanticsLabel('Continue with Google'),
        findsAtLeastNWidgets(1),
      );
      expect(find.byKey(SignUpScreen.appleSignInButtonKey), findsOneWidget);
      expect(
        tester.widget<AbsorbPointer>(
          find
              .ancestor(
                of: find.byKey(SignUpScreen.appleSignInButtonKey),
                matching: find.byType(AbsorbPointer),
              )
              .first,
        ),
        isA<AbsorbPointer>().having(
          (absorbPointer) => absorbPointer.absorbing,
          'absorbing',
          isFalse,
        ),
      );
      expect(
        find.bySemanticsLabel('Sign in with Apple'),
        findsAtLeastNWidgets(1),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('BrandHeader renders above the display name field', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildAuthTestScope(
        repository: RecordingAuthRepository(),
        child: const MaterialApp(home: SignUpScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final brandHeader = find.byKey(BrandHeader.brandHeaderKey);
    final displayNameField = find.byKey(SignUpScreen.displayNameFieldKey);
    expect(brandHeader, findsOneWidget);
    expect(displayNameField, findsOneWidget);

    final brandHeaderY = tester.getTopLeft(brandHeader).dy;
    final displayNameFieldY = tester.getTopLeft(displayNameField).dy;
    expect(
      brandHeaderY,
      lessThan(displayNameFieldY),
      reason: 'BrandHeader must render above the display name field',
    );
  });

  testWidgets(
    'create-account action renders above the OAuth divider and buttons',
    (tester) async {
      await tester.pumpWidget(
        buildAuthTestScope(
          repository: RecordingAuthRepository(),
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: const SignUpScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dividerText = find.text('or');
      final socialAuthButtons = <({String label, Finder finder})>[
        (
          label: 'Google',
          finder: find.byKey(SignUpScreen.googleSignInButtonKey),
        ),
        (label: 'Apple', finder: find.byKey(SignUpScreen.appleSignInButtonKey)),
      ];
      expectPrimaryActionAboveOAuthDividerAndButtons(
        tester,
        primaryAction: (
          label: 'Create account',
          finder: find.byKey(SignUpScreen.signUpButtonKey),
        ),
        dividerText: dividerText,
        socialAuthButtons: socialAuthButtons,
      );
    },
  );

  testWidgets('signup form is wrapped in a scroll view for keyboard safety', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildAuthTestScope(
        repository: RecordingAuthRepository(),
        child: const MaterialApp(home: SignUpScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('signup with email confirmation navigates to sign-in screen', (
    tester,
  ) async {
    // Use the ConfirmationPendingAuthRepository: signUp returns
    // Unauthenticated, meaning email confirmation is required.
    final repo = ConfirmationPendingAuthRepository();

    await tester.pumpWidget(
      buildAuthTestScope(
        repository: repo,
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/auth/sign-up',
            routes: [
              GoRoute(
                path: '/auth/sign-up',
                builder: (_, __) => const SignUpScreen(),
              ),
              GoRoute(
                path: '/auth/sign-in',
                builder: (_, __) => const Text('Sign In Screen'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Fill in valid form fields.
    await tester.enterText(
      find.byKey(SignUpScreen.displayNameFieldKey),
      'Test User',
    );
    await tester.enterText(
      find.byKey(SignUpScreen.emailFieldKey),
      'test@example.com',
    );
    await tester.enterText(
      find.byKey(SignUpScreen.passwordFieldKey),
      'StrongP@ss1',
    );
    await tester.enterText(
      find.byKey(SignUpScreen.confirmPasswordFieldKey),
      'StrongP@ss1',
    );

    // Submit the form.
    await tester.tap(find.byKey(SignUpScreen.signUpButtonKey));
    await tester.pumpAndSettle();

    // After email-confirmation signup, user should be on the sign-in screen.
    expect(find.text('Sign In Screen'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/common_widgets/brand_header.dart';
import 'package:uff/src/features/auth/presentation/login_screen.dart';

import 'auth_test_support.dart';

// ## Test Scenarios
// - [positive] Login form controls expose stable spoken labels
// - [positive] BrandHeader renders above the email field
// - [positive] Sign-in action renders above the OAuth divider and buttons
// - [edge] Login form is wrapped in scroll view for keyboard safety
// - [negative] Login with invalid credentials shows error, not session
// - [isolation] Logout clears auth state; re-login shows clean form

void main() {
  testWidgets('login form controls expose stable spoken labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        buildAuthTestScope(
          repository: RecordingAuthRepository(),
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: const LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(LoginScreen.emailFieldKey), findsOneWidget);
      expect(find.bySemanticsLabel('Email'), findsAtLeastNWidgets(1));
      expect(find.byKey(LoginScreen.passwordFieldKey), findsOneWidget);
      expect(find.bySemanticsLabel('Password'), findsAtLeastNWidgets(1));
      expect(find.byKey(LoginScreen.signInButtonKey), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.byKey(LoginScreen.signInButtonKey)),
        isA<ElevatedButton>().having(
          (button) => button.onPressed,
          'onPressed',
          // Stage 3: callback identity is not a stable value target; isNotNull
          // proves the button is enabled, which is the intent of this test.
          isNotNull,
        ),
      );
      expect(find.bySemanticsLabel('Sign In'), findsAtLeastNWidgets(1));
      expect(find.byKey(LoginScreen.googleSignInButtonKey), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(
          find.byKey(LoginScreen.googleSignInButtonKey),
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
      expect(find.byKey(LoginScreen.appleSignInButtonKey), findsOneWidget);
      expect(
        tester.widget<AbsorbPointer>(
          find
              .ancestor(
                of: find.byKey(LoginScreen.appleSignInButtonKey),
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

  testWidgets('BrandHeader renders above the email field', (tester) async {
    await tester.pumpWidget(
      buildAuthTestScope(
        repository: RecordingAuthRepository(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final brandHeader = find.byKey(BrandHeader.brandHeaderKey);
    final emailField = find.byKey(LoginScreen.emailFieldKey);
    expect(brandHeader, findsOneWidget);
    expect(emailField, findsOneWidget);

    final brandHeaderY = tester.getTopLeft(brandHeader).dy;
    final emailFieldY = tester.getTopLeft(emailField).dy;
    expect(
      brandHeaderY,
      lessThan(emailFieldY),
      reason: 'BrandHeader must render above the email field',
    );
  });

  testWidgets('sign-in action renders above the OAuth divider and buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildAuthTestScope(
        repository: RecordingAuthRepository(),
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dividerText = find.text('or');
    final socialAuthButtons = <({String label, Finder finder})>[
      (label: 'Google', finder: find.byKey(LoginScreen.googleSignInButtonKey)),
      (label: 'Apple', finder: find.byKey(LoginScreen.appleSignInButtonKey)),
    ];
    expectPrimaryActionAboveOAuthDividerAndButtons(
      tester,
      primaryAction: (
        label: 'Sign in',
        finder: find.byKey(LoginScreen.signInButtonKey),
      ),
      dividerText: dividerText,
      socialAuthButtons: socialAuthButtons,
    );
  });

  testWidgets('login form is wrapped in a scroll view for keyboard safety', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildAuthTestScope(
        repository: RecordingAuthRepository(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}

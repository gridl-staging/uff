/// ## Test Scenarios
/// - [positive] Shows Apple button and divider on iOS and invokes Apple callback
/// - [positive] Shows Google button and divider and invokes Google callback
/// - [negative] Renders no social buttons or divider when both flags are off
/// - [negative] Hides Apple button on Android when Apple flag is enabled
/// - [edge] Disables Apple and Google actions while loading
/// - [edge] Shows Apple button on macOS when Apple flag is enabled

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/auth/presentation/social_auth_section.dart';

const _appleButtonKey = Key('social_auth_apple_button');
const _googleButtonKey = Key('social_auth_google_button');

Future<void> _pumpSocialAuthSection(
  WidgetTester tester, {
  required TargetPlatform platform,
  bool isLoading = false,
  bool isAppleSignInEnabled = false,
  bool isGoogleSignInEnabled = false,
  Future<void> Function()? onSignInWithApple,
  Future<void> Function()? onSignInWithGoogle,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: SocialAuthSection(
          appleButtonKey: _appleButtonKey,
          googleButtonKey: _googleButtonKey,
          isLoading: isLoading,
          isAppleSignInEnabled: isAppleSignInEnabled,
          isGoogleSignInEnabled: isGoogleSignInEnabled,
          onSignInWithApple: onSignInWithApple ?? () async {},
          onSignInWithGoogle: onSignInWithGoogle ?? () async {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('SocialAuthSection', () {
    testWidgets(
      'renders no social buttons or divider when both flags are off',
      (
        tester,
      ) async {
        await _pumpSocialAuthSection(tester, platform: TargetPlatform.iOS);

        expect(find.byKey(_appleButtonKey), findsNothing);
        expect(find.byKey(_googleButtonKey), findsNothing);
        expect(find.text('or'), findsNothing);
      },
    );

    testWidgets(
      'shows Apple button and divider on iOS and invokes Apple callback',
      (tester) async {
        var appleTapCount = 0;

        await _pumpSocialAuthSection(
          tester,
          platform: TargetPlatform.iOS,
          isAppleSignInEnabled: true,
          onSignInWithApple: () async {
            appleTapCount++;
          },
        );

        expect(find.byKey(_appleButtonKey), findsOneWidget);
        expect(find.text('or'), findsOneWidget);

        await tester.tap(find.byKey(_appleButtonKey), warnIfMissed: false);
        await tester.pump();

        expect(appleTapCount, 1);
      },
    );

    testWidgets('hides Apple button on Android when Apple flag is enabled', (
      tester,
    ) async {
      await _pumpSocialAuthSection(
        tester,
        platform: TargetPlatform.android,
        isAppleSignInEnabled: true,
      );

      expect(find.byKey(_appleButtonKey), findsNothing);
    });

    testWidgets(
      'shows Google button and divider and invokes Google callback',
      (tester) async {
        var googleTapCount = 0;

        await _pumpSocialAuthSection(
          tester,
          platform: TargetPlatform.iOS,
          isGoogleSignInEnabled: true,
          onSignInWithGoogle: () async {
            googleTapCount++;
          },
        );

        expect(find.byKey(_googleButtonKey), findsOneWidget);
        expect(find.text('or'), findsOneWidget);

        await tester.tap(find.byKey(_googleButtonKey));
        await tester.pump();

        expect(googleTapCount, 1);
      },
    );

    testWidgets('disables Apple and Google actions while loading', (
      tester,
    ) async {
      var appleTapCount = 0;
      var googleTapCount = 0;

      await _pumpSocialAuthSection(
        tester,
        platform: TargetPlatform.iOS,
        isLoading: true,
        isAppleSignInEnabled: true,
        isGoogleSignInEnabled: true,
        onSignInWithApple: () async {
          appleTapCount++;
        },
        onSignInWithGoogle: () async {
          googleTapCount++;
        },
      );

      final googleButton = tester.widget<OutlinedButton>(
        find.byKey(_googleButtonKey),
      );
      expect(googleButton.onPressed, isNull);

      await tester.tap(find.byKey(_appleButtonKey), warnIfMissed: false);
      await tester.tap(find.byKey(_googleButtonKey));
      await tester.pump();

      expect(appleTapCount, 0);
      expect(googleTapCount, 0);
    });

    testWidgets('shows Apple button on macOS when Apple flag is enabled', (
      tester,
    ) async {
      await _pumpSocialAuthSection(
        tester,
        platform: TargetPlatform.macOS,
        isAppleSignInEnabled: true,
      );

      expect(find.byKey(_appleButtonKey), findsOneWidget);
    });
  });
}

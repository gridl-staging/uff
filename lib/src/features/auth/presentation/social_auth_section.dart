import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

// TODO(uff): Document SocialAuthSection.
/// TODO: Document SocialAuthSection.
class SocialAuthSection extends StatelessWidget {
  const SocialAuthSection({
    required this.appleButtonKey,
    required this.googleButtonKey,
    required this.isLoading,
    required this.isAppleSignInEnabled,
    required this.isGoogleSignInEnabled,
    required this.onSignInWithApple,
    required this.onSignInWithGoogle,
    super.key,
  });

  final Key appleButtonKey;
  final Key googleButtonKey;
  final bool isLoading;
  final bool isAppleSignInEnabled;
  final bool isGoogleSignInEnabled;
  final Future<void> Function() onSignInWithApple;
  final Future<void> Function() onSignInWithGoogle;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final showAppleButton =
        isAppleSignInEnabled &&
        (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS);
    final showGoogleButton = isGoogleSignInEnabled;
    final showDivider = showAppleButton || showGoogleButton;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDivider) ...[
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('or'),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (showAppleButton) ...[
          AbsorbPointer(
            absorbing: isLoading,
            child: Opacity(
              opacity: isLoading ? 0.6 : 1,
              child: SignInWithAppleButton(
                key: appleButtonKey,
                onPressed: onSignInWithApple,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (showGoogleButton) ...[
          OutlinedButton(
            key: googleButtonKey,
            onPressed: isLoading ? null : onSignInWithGoogle,
            child: const Text('Continue with Google'),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

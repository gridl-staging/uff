import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/core/presentation/button_progress_indicator.dart';
import 'package:uff/src/core/validators.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/auth/presentation/auth_legal_links.dart';
import 'package:uff/src/features/auth/presentation/auth_error_message.dart';
import 'package:uff/src/common_widgets/brand_header.dart';
import 'package:uff/src/features/auth/presentation/social_auth_section.dart';

// TODO(uff): Document SignUpScreen.
/// TODO: Document SignUpScreen.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  static const displayNameFieldKey = Key('signup_display_name_field');
  static const emailFieldKey = Key('signup_email_field');
  static const passwordFieldKey = Key('signup_password_field');
  static const confirmPasswordFieldKey = Key('signup_confirm_password_field');
  static const appleSignInButtonKey = Key('signup_apple_sign_in_button');
  static const googleSignInButtonKey = Key('signup_google_sign_in_button');
  static const signUpButtonKey = Key('signup_create_account_button');
  static const privacyPolicyButtonKey = Key('signup_privacy_policy_button');
  static const termsOfServiceButtonKey = Key('signup_terms_of_service_button');

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

// TODO(uff): Document _SignUpScreenState.
/// TODO: Document _SignUpScreenState.
class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _hasSubmitted = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final authController = ref.read(authProvider.notifier);
    final authOAuthConfig = ref.watch(authOAuthConfigProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign Up')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          // Keep initial load clean; switch to live validation after first submit.
          autovalidateMode: _hasSubmitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BrandHeader(),
              if (authState.hasError)
                Text(
                  mapAuthErrorToMessage(authState.error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              TextFormField(
                key: SignUpScreen.displayNameFieldKey,
                controller: _displayNameController,
                decoration: const InputDecoration(labelText: 'Display Name'),
                validator: (value) {
                  return AuthValidators.validateRequired(
                    value: value,
                    fieldName: 'Display name',
                  );
                },
              ),
              TextFormField(
                key: SignUpScreen.emailFieldKey,
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: AuthValidators.validateEmail,
              ),
              TextFormField(
                key: SignUpScreen.passwordFieldKey,
                controller: _passwordController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: AuthValidators.validateSignUpPassword,
              ),
              TextFormField(
                key: SignUpScreen.confirmPasswordFieldKey,
                controller: _confirmPasswordController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                ),
                validator: (value) {
                  return AuthValidators.validatePasswordConfirmation(
                    value: value,
                    password: _passwordController.text,
                  );
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                key: SignUpScreen.signUpButtonKey,
                onPressed: isLoading
                    ? null
                    : () async {
                        if (!_hasSubmitted) {
                          setState(() => _hasSubmitted = true);
                        }

                        final isValid =
                            _formKey.currentState?.validate() ?? false;
                        if (!isValid) {
                          return;
                        }

                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        await authController.signUp(
                          AuthValidators.normalizeEmail(_emailController.text),
                          _passwordController.text,
                          AuthValidators.normalizeDisplayName(
                            _displayNameController.text,
                          ),
                        );
                        if (!mounted) {
                          return;
                        }

                        final nextState = ref.read(authProvider);
                        if (nextState.hasError) {
                          return;
                        }

                        final authData = nextState.asData?.value;
                        final requiresEmailConfirmation = switch (authData) {
                          Unauthenticated() => true,
                          Authenticated() => false,
                          null => false,
                        };
                        if (requiresEmailConfirmation == true) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Account created. Check your email to confirm '
                                'your account before signing in.',
                              ),
                              duration: Duration(seconds: 6),
                            ),
                          );
                          // Navigate to sign-in so the user knows where to go
                          // after confirming their email.
                          if (context.mounted) {
                            GoRouter.maybeOf(context)?.go('/auth/sign-in');
                          }
                        }
                      },
                child: isLoading
                    ? const ButtonProgressIndicator()
                    : const Text('Create account'),
              ),
              SocialAuthSection(
                appleButtonKey: SignUpScreen.appleSignInButtonKey,
                googleButtonKey: SignUpScreen.googleSignInButtonKey,
                isLoading: isLoading,
                isAppleSignInEnabled: authOAuthConfig.isAppleSignInEnabled,
                isGoogleSignInEnabled: authOAuthConfig.isGoogleSignInEnabled,
                onSignInWithApple: authController.signInWithApple,
                onSignInWithGoogle: authController.signInWithGoogle,
              ),
              TextButton(
                onPressed: isLoading ? null : () => context.go('/auth/sign-in'),
                child: const Text('Already have an account?'),
              ),
              const SizedBox(height: 8),
              AuthLegalLinks(
                privacyPolicyButtonKey: SignUpScreen.privacyPolicyButtonKey,
                termsOfServiceButtonKey: SignUpScreen.termsOfServiceButtonKey,
                isLoading: isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

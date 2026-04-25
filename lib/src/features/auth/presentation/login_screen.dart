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

typedef LoginSubmitCallback =
    Future<void> Function(String email, String password);

// TODO(uff): Document LoginScreen.
/// TODO: Document LoginScreen.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  static const emailFieldKey = Key('login_email_field');
  static const passwordFieldKey = Key('login_password_field');
  static const appleSignInButtonKey = Key('login_apple_sign_in_button');
  static const googleSignInButtonKey = Key('login_google_sign_in_button');
  static const signInButtonKey = Key('login_sign_in_button');
  static const privacyPolicyButtonKey = Key('login_privacy_policy_button');
  static const termsOfServiceButtonKey = Key('login_terms_of_service_button');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final authController = ref.read(authProvider.notifier);
    final authOAuthConfig = ref.watch(authOAuthConfigProvider);
    return _LoginForm(
      authState: authState,
      isAppleSignInEnabled: authOAuthConfig.isAppleSignInEnabled,
      isGoogleSignInEnabled: authOAuthConfig.isGoogleSignInEnabled,
      onSignIn: authController.signIn,
      onSignInWithApple: authController.signInWithApple,
      onSignInWithGoogle: authController.signInWithGoogle,
      onCreateAccount: () => context.go('/auth/sign-up'),
    );
  }
}

// TODO(uff): Document _LoginForm.
/// TODO: Document _LoginForm.
class _LoginForm extends StatefulWidget {
  const _LoginForm({
    required this.authState,
    required this.isAppleSignInEnabled,
    required this.isGoogleSignInEnabled,
    required this.onSignIn,
    required this.onSignInWithApple,
    required this.onSignInWithGoogle,
    required this.onCreateAccount,
  });

  final AsyncValue<AuthState> authState;
  final bool isAppleSignInEnabled;
  final bool isGoogleSignInEnabled;
  final LoginSubmitCallback onSignIn;
  final Future<void> Function() onSignInWithApple;
  final Future<void> Function() onSignInWithGoogle;
  final VoidCallback onCreateAccount;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

// TODO(uff): Document _LoginFormState.
/// TODO: Document _LoginFormState.
class _LoginFormState extends State<_LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _hasSubmitted = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (widget.authState.isLoading) return;

    if (!_hasSubmitted) {
      setState(() => _hasSubmitted = true);
    }

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    await widget.onSignIn(
      AuthValidators.normalizeEmail(_emailController.text),
      _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = widget.authState.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign In')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          // Only start live-validation after the first submit attempt.
          autovalidateMode: _hasSubmitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BrandHeader(),
              if (widget.authState.hasError)
                Text(
                  mapAuthErrorToMessage(widget.authState.error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              TextFormField(
                key: LoginScreen.emailFieldKey,
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: AuthValidators.validateEmail,
              ),
              TextFormField(
                key: LoginScreen.passwordFieldKey,
                controller: _passwordController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: TextInputAction.go,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: AuthValidators.validateLoginPassword,
                onFieldSubmitted: (_) => _submitForm(),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                key: LoginScreen.signInButtonKey,
                onPressed: isLoading ? null : _submitForm,
                child: isLoading
                    ? const ButtonProgressIndicator()
                    : const Text('Sign In'),
              ),
              SocialAuthSection(
                appleButtonKey: LoginScreen.appleSignInButtonKey,
                googleButtonKey: LoginScreen.googleSignInButtonKey,
                isLoading: isLoading,
                isAppleSignInEnabled: widget.isAppleSignInEnabled,
                isGoogleSignInEnabled: widget.isGoogleSignInEnabled,
                onSignInWithApple: widget.onSignInWithApple,
                onSignInWithGoogle: widget.onSignInWithGoogle,
              ),
              TextButton(
                onPressed: isLoading ? null : widget.onCreateAccount,
                child: const Text('Create account'),
              ),
              const SizedBox(height: 8),
              AuthLegalLinks(
                privacyPolicyButtonKey: LoginScreen.privacyPolicyButtonKey,
                termsOfServiceButtonKey: LoginScreen.termsOfServiceButtonKey,
                isLoading: isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

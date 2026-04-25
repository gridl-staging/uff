import 'package:uff/src/utils/app_environment.dart';

class AuthOAuthConfig {
  const AuthOAuthConfig({
    required this.googleWebClientId,
    required this.googleIosClientId,
    required this.isAppleSignInEnabled,
    required this.isGoogleSignInEnabled,
  });

  final String googleWebClientId;
  final String googleIosClientId;
  final bool isAppleSignInEnabled;
  final bool isGoogleSignInEnabled;
}

// TODO(uff): Document AuthOAuthConfigInitializer.
/// TODO: Document AuthOAuthConfigInitializer.
class AuthOAuthConfigInitializer {
  const AuthOAuthConfigInitializer();

  static const enableAppleSignInKey = 'ENABLE_APPLE_SIGN_IN';
  static const enableGoogleSignInKey = 'ENABLE_GOOGLE_SIGN_IN';
  static const googleWebClientIdKey = 'GOOGLE_WEB_CLIENT_ID';
  static const googleIosClientIdKey = 'GOOGLE_IOS_CLIENT_ID';

  AuthOAuthConfig initialize({required Map<String, String> environment}) {
    final isAppleSignInEnabled = _readBooleanEnvironmentValue(
      environment: environment,
      key: enableAppleSignInKey,
    );
    final isGoogleSignInEnabled = _readBooleanEnvironmentValue(
      environment: environment,
      key: enableGoogleSignInKey,
    );
    final googleWebClientId = _readEnvironmentValue(
      environment: environment,
      key: googleWebClientIdKey,
      requiredForRuntime: isGoogleSignInEnabled,
    );
    final googleIosClientId = _readEnvironmentValue(
      environment: environment,
      key: googleIosClientIdKey,
      requiredForRuntime: isGoogleSignInEnabled,
    );

    return AuthOAuthConfig(
      googleWebClientId: googleWebClientId,
      googleIosClientId: googleIosClientId,
      isAppleSignInEnabled: isAppleSignInEnabled,
      isGoogleSignInEnabled: isGoogleSignInEnabled,
    );
  }

  String _readEnvironmentValue({
    required Map<String, String> environment,
    required String key,
    required bool requiredForRuntime,
  }) {
    final value = environment[key]?.trim() ?? '';
    if (requiredForRuntime) {
      final requiredValue = requireEnvironmentValue(
        environment: environment,
        key: key,
      );
      if (_looksLikePlaceholder(requiredValue)) {
        throw StateError(
          'Replace placeholder $key before enabling that auth provider. '
          '$runtimeEnvironmentSetupGuidance',
        );
      }
      return requiredValue;
    }
    return value;
  }

  bool _readBooleanEnvironmentValue({
    required Map<String, String> environment,
    required String key,
  }) {
    final normalizedValue = environment[key]?.trim().toLowerCase() ?? '';
    return normalizedValue == 'true' ||
        normalizedValue == '1' ||
        normalizedValue == 'yes';
  }

  bool _looksLikePlaceholder(String value) {
    return value.startsWith('<') && value.endsWith('>');
  }
}

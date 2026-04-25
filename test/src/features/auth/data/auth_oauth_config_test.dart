/// ## Test Scenarios
/// - [positive] Defaults both social providers to disabled
/// - [positive] Returns parsed runtime config when values are present
/// - [negative] Throws when GOOGLE_WEB_CLIENT_ID is missing for enabled Google auth
/// - [negative] Throws when GOOGLE_IOS_CLIENT_ID is blank for enabled Google auth
/// - [negative] Throws when enabled Google auth uses checked-in placeholders
/// - [edge] Does not require APPLE_SERVICE_ID for runtime initialization

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/auth/data/auth_oauth_config.dart';
import 'package:uff/src/utils/app_environment.dart';

void main() {
  group('AuthOAuthConfigInitializer', () {
    test('defaults both social providers to disabled', () {
      final config = const AuthOAuthConfigInitializer().initialize(
        environment: const {},
      );

      expect(config.isAppleSignInEnabled, isFalse);
      expect(config.isGoogleSignInEnabled, isFalse);
      expect(config.googleWebClientId, isEmpty);
      expect(config.googleIosClientId, isEmpty);
    });

    test(
      'throws when GOOGLE_WEB_CLIENT_ID is missing for enabled Google auth',
      () {
        expect(
          () => const AuthOAuthConfigInitializer().initialize(
            environment: const {
              'ENABLE_GOOGLE_SIGN_IN': 'true',
              'GOOGLE_IOS_CLIENT_ID': 'ios-client-id',
            },
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('Missing required GOOGLE_WEB_CLIENT_ID.'),
                contains(runtimeEnvironmentSetupGuidance),
              ),
            ),
          ),
        );
      },
    );

    test(
      'throws when GOOGLE_IOS_CLIENT_ID is blank for enabled Google auth',
      () {
        expect(
          () => const AuthOAuthConfigInitializer().initialize(
            environment: const {
              'ENABLE_GOOGLE_SIGN_IN': 'true',
              'GOOGLE_WEB_CLIENT_ID': 'web-client-id',
              'GOOGLE_IOS_CLIENT_ID': ' ',
            },
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('Missing required GOOGLE_IOS_CLIENT_ID.'),
                contains(runtimeEnvironmentSetupGuidance),
              ),
            ),
          ),
        );
      },
    );

    test(
      'throws when enabled Google auth still uses checked-in placeholders',
      () {
        expect(
          () => const AuthOAuthConfigInitializer().initialize(
            environment: const {
              'ENABLE_GOOGLE_SIGN_IN': 'true',
              'GOOGLE_WEB_CLIENT_ID': '<google-oauth-web-client-id>',
              'GOOGLE_IOS_CLIENT_ID': '<google-oauth-ios-client-id>',
            },
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('Replace placeholder GOOGLE_WEB_CLIENT_ID'),
                contains(runtimeEnvironmentSetupGuidance),
              ),
            ),
          ),
        );
      },
    );

    test('does not require APPLE_SERVICE_ID for runtime initialization', () {
      final config = const AuthOAuthConfigInitializer().initialize(
        environment: const {
          'ENABLE_APPLE_SIGN_IN': 'true',
          'GOOGLE_WEB_CLIENT_ID': 'web-client-id',
          'GOOGLE_IOS_CLIENT_ID': 'ios-client-id',
        },
      );

      expect(config.isAppleSignInEnabled, isTrue);
      expect(config.isGoogleSignInEnabled, isFalse);
      expect(config.googleWebClientId, 'web-client-id');
      expect(config.googleIosClientId, 'ios-client-id');
    });

    test('returns parsed runtime config when values are present', () {
      final config = const AuthOAuthConfigInitializer().initialize(
        environment: const {
          'ENABLE_APPLE_SIGN_IN': 'true',
          'ENABLE_GOOGLE_SIGN_IN': 'true',
          'GOOGLE_WEB_CLIENT_ID': 'web-client-id',
          'GOOGLE_IOS_CLIENT_ID': 'ios-client-id',
        },
      );

      expect(config.isAppleSignInEnabled, isTrue);
      expect(config.isGoogleSignInEnabled, isTrue);
      expect(config.googleWebClientId, 'web-client-id');
      expect(config.googleIosClientId, 'ios-client-id');
    });
  });
}

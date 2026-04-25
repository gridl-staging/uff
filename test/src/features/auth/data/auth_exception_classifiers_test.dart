/// ## Test Scenarios
/// - [positive] isDuplicateUserAuthException returns true for known codes and fallback message
/// - [positive] isEmailNotConfirmedAuthException returns true for known shapes
/// - [positive] isAuthRateLimitException returns true for known shapes
/// - [positive] isUnauthorizedEmailAuthException returns true for exact message
/// - [negative] isDuplicateUserAuthException returns false for non-duplicate codes and near-miss messages

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:uff/src/features/auth/data/auth_exception_classifiers.dart';

void main() {
  group('isDuplicateUserAuthException', () {
    test('returns true for known duplicate-user auth codes', () {
      for (final code in const [
        'email_address_already_registered',
        'email_exists',
        'user_already_exists',
      ]) {
        final error = AuthException('msg', code: code);
        expect(isDuplicateUserAuthException(error), isTrue);
      }
    });

    test('returns true for exact duplicate-user fallback message', () {
      const error = AuthException('User already registered');
      expect(isDuplicateUserAuthException(error), isTrue);
    });

    test('returns false for non-duplicate codes and near-miss messages', () {
      const invalidCredentials = AuthException(
        'msg',
        code: 'invalid_credentials',
      );
      const emptyCode = AuthException('msg', code: '');
      const nearMissMessage = AuthException('User already registered!');
      const unrelatedMessage = AuthException('Something else');

      expect(isDuplicateUserAuthException(invalidCredentials), isFalse);
      expect(isDuplicateUserAuthException(emptyCode), isFalse);
      expect(isDuplicateUserAuthException(nearMissMessage), isFalse);
      expect(isDuplicateUserAuthException(unrelatedMessage), isFalse);
    });
  });

  group('isEmailNotConfirmedAuthException', () {
    test('returns true for known email-not-confirmed auth shapes', () {
      const withCode = AuthException(
        'Authentication failed',
        code: 'email_not_confirmed',
      );
      const withMessage = AuthException('Email not confirmed');

      expect(isEmailNotConfirmedAuthException(withCode), isTrue);
      expect(isEmailNotConfirmedAuthException(withMessage), isTrue);
    });
  });

  group('isAuthRateLimitException', () {
    test('returns true for known rate-limit auth shapes', () {
      const withCode = AuthException(
        'Authentication failed',
        code: 'over_email_send_rate_limit',
      );
      const withMessage = AuthException(
        'For security purposes, you can only request this after 60 seconds.',
      );
      const tooManyRequests = AuthException('Too many requests');

      expect(isAuthRateLimitException(withCode), isTrue);
      expect(isAuthRateLimitException(withMessage), isTrue);
      expect(isAuthRateLimitException(tooManyRequests), isTrue);
    });
  });

  group('isUnauthorizedEmailAuthException', () {
    test('returns true for exact unauthorized-email message', () {
      const error = AuthException('Email address not authorized');
      expect(isUnauthorizedEmailAuthException(error), isTrue);
    });
  });
}

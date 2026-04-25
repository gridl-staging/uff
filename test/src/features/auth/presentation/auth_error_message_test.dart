/// ## Test Scenarios
/// - [positive] Maps known auth error codes to user-friendly messages (invalid credentials, duplicate email, rate limit, etc.)
/// - [positive] Maps social sign-in failures (cancelled, missing token, provider unavailable)
/// - [positive] Maps network failures (SocketException, retryable fetch) to network error message
/// - [negative] Maps unknown AuthException to generic auth message
/// - [negative] Maps unknown exception to generic fallback

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, AuthRetryableFetchException;
import 'package:uff/src/features/auth/data/supabase_auth_repository.dart';
import 'package:uff/src/features/auth/presentation/auth_error_message.dart';

void main() {
  group('mapAuthErrorToMessage', () {
    test('maps invalid_credentials code to user-friendly message', () {
      const error = AuthException(
        'Authentication failed',
        code: 'invalid_credentials',
      );
      expect(
        mapAuthErrorToMessage(error),
        'Invalid email or password.',
      );
    });

    test('maps invalid credentials to user-friendly message', () {
      const error = AuthException('Invalid login credentials');
      expect(
        mapAuthErrorToMessage(error),
        'Invalid email or password.',
      );
    });

    for (final code in const [
      'email_address_already_registered',
      'email_exists',
      'user_already_exists',
    ]) {
      test('maps $code code to duplicate email message', () {
        final error = AuthException(
          'Authentication failed',
          code: code,
        );
        expect(
          mapAuthErrorToMessage(error),
          'An account with this email already exists.',
        );
      });
    }

    test('maps duplicate email to user-friendly message', () {
      const error = AuthException('User already registered');
      expect(
        mapAuthErrorToMessage(error),
        'An account with this email already exists.',
      );
    });

    test('maps email-not-confirmed to user-friendly message', () {
      const error = AuthException(
        'Authentication failed',
        code: 'email_not_confirmed',
      );
      expect(
        mapAuthErrorToMessage(error),
        'Check your email and confirm your account before signing in.',
      );
    });

    test('maps unauthorized email delivery to user-friendly message', () {
      const error = AuthException('Email address not authorized');
      expect(
        mapAuthErrorToMessage(error),
        'Email delivery is not configured for that address yet. Please use '
        'a confirmed test account or ask us to enable auth email sending.',
      );
    });

    test('maps auth rate-limit failures to user-friendly message', () {
      const error = AuthException(
        'For security purposes, you can only request this after 60 seconds.',
      );
      expect(
        mapAuthErrorToMessage(error),
        'Too many auth attempts right now. Please wait a bit and try again.',
      );
    });

    test('maps retryable auth fetch failures to network error message', () {
      final error = AuthRetryableFetchException(message: 'SocketException');
      expect(
        mapAuthErrorToMessage(error),
        'Unable to connect. Check your internet connection.',
      );
    });

    test('maps cancelled native social sign-in to cancellation message', () {
      const error = NativeAuthTokenException('Google sign-in was cancelled.');
      expect(
        mapAuthErrorToMessage(error),
        'Sign-in was cancelled.',
      );
    });

    test('maps missing native token errors to social auth fallback', () {
      const error = NativeAuthTokenException(
        'Apple sign-in did not return an id token.',
      );
      expect(
        mapAuthErrorToMessage(error),
        'Unable to complete social sign-in. Please try again.',
      );
    });

    test('maps cancelled Apple authorization exception', () {
      const error = SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.canceled,
        message: 'canceled by user',
      );
      expect(
        mapAuthErrorToMessage(error),
        'Sign-in was cancelled.',
      );
    });

    test('maps Apple provider unavailable platform error', () {
      final error = PlatformException(code: 'apple-sign-in-not-supported');
      expect(
        mapAuthErrorToMessage(error),
        'This sign-in method is not available on this device.',
      );
    });

    test('maps SocketException to network error message', () {
      const error = SocketException('Connection refused');
      expect(
        mapAuthErrorToMessage(error),
        'Unable to connect. Check your internet connection.',
      );
    });

    test('maps unknown AuthException to generic auth message', () {
      const error = AuthException('some_unknown_error');
      expect(
        mapAuthErrorToMessage(error),
        'Authentication failed. Please try again.',
      );
    });

    test('maps unknown exception to generic fallback', () {
      const error = FormatException('bad format');
      expect(
        mapAuthErrorToMessage(error),
        'Something went wrong. Please try again.',
      );
    });
  });
}

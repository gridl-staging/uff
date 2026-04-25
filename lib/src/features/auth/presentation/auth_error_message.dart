import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, AuthRetryableFetchException;
import 'package:uff/src/features/auth/data/auth_exception_classifiers.dart';
import 'package:uff/src/features/auth/data/supabase_auth_repository.dart';

/// Maps auth-related exceptions to user-facing error messages.
///
/// Used by both `LoginScreen` and `SignUpScreen` to ensure consistent
/// and security-safe error copy across all auth surfaces.
String mapAuthErrorToMessage(Object error) {
  if (error is NativeAuthTokenException) {
    if (error.message.contains('cancelled')) {
      return 'Sign-in was cancelled.';
    }
    return 'Unable to complete social sign-in. Please try again.';
  }
  if (error is SignInWithAppleAuthorizationException) {
    if (error.code == AuthorizationErrorCode.canceled) {
      return 'Sign-in was cancelled.';
    }
    return 'Unable to use Apple Sign-In right now.';
  }
  if (error is PlatformException) {
    if (_isCancelledSignInCode(error.code)) {
      return 'Sign-in was cancelled.';
    }
    if (_isProviderUnavailableCode(error.code)) {
      return 'This sign-in method is not available on this device.';
    }
  }
  if (error is AuthRetryableFetchException || error is SocketException) {
    return 'Unable to connect. Check your internet connection.';
  }
  if (error is AuthException) {
    return _mapAuthException(error);
  }
  return 'Something went wrong. Please try again.';
}

String _mapAuthException(AuthException error) {
  switch (error.code) {
    case 'invalid_credentials':
      return 'Invalid email or password.';
  }

  if (isDuplicateUserAuthException(error)) {
    return 'An account with this email already exists.';
  }
  if (isEmailNotConfirmedAuthException(error)) {
    return 'Check your email and confirm your account before signing in.';
  }
  if (isUnauthorizedEmailAuthException(error)) {
    return 'Email delivery is not configured for that address yet. Please use '
        'a confirmed test account or ask us to enable auth email sending.';
  }
  if (isAuthRateLimitException(error)) {
    return 'Too many auth attempts right now. Please wait a bit and try again.';
  }

  switch (error.message) {
    case 'Invalid login credentials':
      return 'Invalid email or password.';
  }

  return 'Authentication failed. Please try again.';
}

bool _isCancelledSignInCode(String code) {
  return switch (code) {
    'canceled' => true,
    'CANCELED' => true,
    'sign_in_canceled' => true,
    'sign_in_cancelled' => true,
    _ => false,
  };
}

bool _isProviderUnavailableCode(String code) {
  return switch (code) {
    'not-supported' => true,
    'sign_in_failed' => true,
    'apple-sign-in-not-supported' => true,
    _ => false,
  };
}

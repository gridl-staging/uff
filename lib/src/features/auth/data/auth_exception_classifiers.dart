import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

bool isDuplicateUserAuthException(AuthException error) {
  switch (error.code) {
    case 'email_address_already_registered':
    case 'email_exists':
    case 'user_already_exists':
      return true;
  }

  return error.message == 'User already registered';
}

bool isEmailNotConfirmedAuthException(AuthException error) {
  if (error.code == 'email_not_confirmed') {
    return true;
  }

  return error.message == 'Email not confirmed';
}

bool isAuthRateLimitException(AuthException error) {
  final code = (error.code ?? '').toLowerCase();
  final message = error.message.toLowerCase();

  return code.contains('rate_limit') ||
      code.contains('too_many_requests') ||
      message.contains('rate limit') ||
      message.contains('too many requests') ||
      message.contains('for security purposes') ||
      message.contains('after 60 seconds');
}

bool isUnauthorizedEmailAuthException(AuthException error) {
  return error.message == 'Email address not authorized';
}

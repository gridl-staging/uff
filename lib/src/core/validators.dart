// TODO(uff): Document AuthValidators.
/// TODO: Document AuthValidators.
class AuthValidators {
  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static const emailRequiredMessage = 'Email is required';
  static const invalidEmailMessage = 'Enter a valid email';
  static const passwordRequiredMessage = 'Password is required';
  static const confirmPasswordRequiredMessage = 'Confirm your password';
  static const signUpPasswordMinLengthMessage =
      'Password must be at least 6 characters';
  static const passwordsDoNotMatchMessage = 'Passwords do not match';

  static String normalizeEmail(String value) => value.trim();

  static String normalizeDisplayName(String value) => value.trim();

  static String? validateRequired({
    required String? value,
    required String fieldName,
  }) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    final requiredError = validateRequired(value: value, fieldName: 'Email');
    if (requiredError != null) {
      return emailRequiredMessage;
    }

    final normalizedEmail = normalizeEmail(value!);
    if (!_emailRegex.hasMatch(normalizedEmail)) {
      return invalidEmailMessage;
    }
    return null;
  }

  static String? validateLoginPassword(String? value) {
    return validateRequired(value: value, fieldName: 'Password');
  }

  static String? validateSignUpPassword(String? value) {
    final requiredError = validateRequired(value: value, fieldName: 'Password');
    if (requiredError != null) {
      return passwordRequiredMessage;
    }

    if (value!.length < 6) {
      return signUpPasswordMinLengthMessage;
    }
    return null;
  }

  static String? validatePasswordConfirmation({
    required String? value,
    required String password,
  }) {
    final normalizedValue = value ?? '';
    if (normalizedValue.isEmpty) {
      return confirmPasswordRequiredMessage;
    }

    if (normalizedValue != password) {
      return passwordsDoNotMatchMessage;
    }

    return null;
  }
}

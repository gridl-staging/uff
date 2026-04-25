import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/core/validators.dart';

void main() {
  group('AuthValidators', () {
    test('validateRequired trims whitespace before empty check', () {
      expect(
        AuthValidators.validateRequired(
          value: '   ',
          fieldName: 'Display name',
        ),
        'Display name is required',
      );
      expect(
        AuthValidators.validateRequired(
          value: ' Runner ',
          fieldName: 'Display name',
        ),
        isNull,
      );
    });

    test('validateEmail rejects malformed email and accepts trimmed email', () {
      expect(
        AuthValidators.validateEmail('not-an-email'),
        'Enter a valid email',
      );
      expect(AuthValidators.validateEmail('  valid@example.com  '), isNull);
    });

    test('password validators enforce login and signup rules', () {
      expect(
        AuthValidators.validateLoginPassword(''),
        'Password is required',
      );
      expect(AuthValidators.validateLoginPassword('a'), isNull);

      expect(
        AuthValidators.validateSignUpPassword('12345'),
        'Password must be at least 6 characters',
      );
      expect(AuthValidators.validateSignUpPassword('123456'), isNull);
    });
  });
}

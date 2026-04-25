import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../e2e_test/auth_setup.dart';

class MockGoTrueClient extends Mock implements supabase.GoTrueClient {}

supabase.User _testUser({
  String id = 'e2e-user-id',
  String email = 'e2e@example.com',
}) {
  return supabase.User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00.000Z',
    email: email,
  );
}

supabase.Session _testSession({required supabase.User user}) {
  return supabase.Session(
    accessToken: 'test-access-token',
    tokenType: 'bearer',
    user: user,
  );
}

void main() {
  late MockGoTrueClient authClient;

  setUp(() {
    authClient = MockGoTrueClient();
  });

  test(
    'preAuthenticateWithClient re-authenticates after onboarding update',
    () async {
      final user = _testUser(email: 'runner@example.com');
      final session = _testSession(user: user);
      when(
        () => authClient.signInWithPassword(
          email: 'runner@example.com',
          password: 'password123',
        ),
      ).thenAnswer(
        (_) async => supabase.AuthResponse(session: session, user: user),
      );
      when(() => authClient.signOut()).thenAnswer((_) async {});

      await preAuthenticateWithClient(
        authClient,
        email: 'runner@example.com',
        password: 'password123',
        markOnboardingCompleted: (_) async {},
      );

      verify(
        () => authClient.signInWithPassword(
          email: 'runner@example.com',
          password: 'password123',
        ),
      ).called(2);
      verify(() => authClient.signOut()).called(1);
    },
  );

  test(
    'preAuthenticateWithClient marks onboarding completed for signed-in user',
    () async {
      final user = _testUser(id: 'runner-id', email: 'runner@example.com');
      final session = _testSession(user: user);
      String? updatedUserId;
      when(
        () => authClient.signInWithPassword(
          email: 'runner@example.com',
          password: 'password123',
        ),
      ).thenAnswer(
        (_) async => supabase.AuthResponse(session: session, user: user),
      );
      when(() => authClient.signOut()).thenAnswer((_) async {});

      await preAuthenticateWithClient(
        authClient,
        email: 'runner@example.com',
        password: 'password123',
        markOnboardingCompleted: (userId) async {
          updatedUserId = userId;
        },
      );

      expect(updatedUserId, 'runner-id');
      verify(() => authClient.signOut()).called(1);
    },
  );

  test(
    'preAuthenticateWithClient throws when sign-in has no user',
    () async {
      var markCalled = false;
      when(
        () => authClient.signInWithPassword(
          email: 'runner@example.com',
          password: 'password123',
        ),
      ).thenAnswer((_) async => supabase.AuthResponse());

      await expectLater(
        () => preAuthenticateWithClient(
          authClient,
          email: 'runner@example.com',
          password: 'password123',
          markOnboardingCompleted: (_) async {
            markCalled = true;
          },
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Expected Supabase sign-in to return a user id'),
          ),
        ),
      );
      expect(markCalled, isFalse);
    },
  );

  test('clearAuthSessionWithClient delegates to signOut', () async {
    when(() => authClient.signOut()).thenAnswer((_) async {});

    await clearAuthSessionWithClient(authClient);

    verify(() => authClient.signOut()).called(1);
  });

  test(
    'clearAuthSessionWithClient ignores missing-session signOut errors',
    () async {
      when(() => authClient.signOut()).thenThrow(
        const supabase.AuthException(
          'Auth session missing!',
          code: 'session_not_found',
        ),
      );

      await expectLater(
        () => clearAuthSessionWithClient(authClient),
        returnsNormally,
      );
      verify(() => authClient.signOut()).called(1);
    },
  );

  test(
    'clearAuthSessionWithClient ignores session_missing signOut errors',
    () async {
      when(() => authClient.signOut()).thenThrow(
        const supabase.AuthException(
          'No active session',
          code: 'session_missing',
        ),
      );

      await expectLater(
        () => clearAuthSessionWithClient(authClient),
        returnsNormally,
      );
      verify(() => authClient.signOut()).called(1);
    },
  );

  test(
    'clearAuthSessionWithClient rethrows non-session signOut errors',
    () async {
      when(() => authClient.signOut()).thenThrow(
        const supabase.AuthException(
          'Network timeout',
          code: 'unexpected_failure',
        ),
      );

      await expectLater(
        () => clearAuthSessionWithClient(authClient),
        throwsA(
          isA<supabase.AuthException>().having(
            (e) => e.code,
            'code',
            'unexpected_failure',
          ),
        ),
      );
      verify(() => authClient.signOut()).called(1);
    },
  );

  test('ensureTestUserWithClient signs in after successful sign up', () async {
    final user = _testUser(email: 'new-user@example.com');
    final session = _testSession(user: user);
    when(
      () => authClient.signUp(
        email: 'new-user@example.com',
        password: 'password123',
      ),
    ).thenAnswer(
      (_) async => supabase.AuthResponse(session: session, user: user),
    );
    when(
      () => authClient.signInWithPassword(
        email: 'new-user@example.com',
        password: 'password123',
      ),
    ).thenAnswer(
      (_) async => supabase.AuthResponse(session: session, user: user),
    );
    when(() => authClient.signOut()).thenAnswer((_) async {});

    await ensureTestUserWithClient(
      authClient,
      email: 'new-user@example.com',
      password: 'password123',
      markOnboardingCompleted: (_) async {},
    );

    verify(
      () => authClient.signUp(
        email: 'new-user@example.com',
        password: 'password123',
      ),
    ).called(1);
    verify(
      () => authClient.signInWithPassword(
        email: 'new-user@example.com',
        password: 'password123',
      ),
    ).called(2);
    verify(() => authClient.signOut()).called(1);
  });

  test(
    'ensureTestUserWithClient ignores duplicate-user signup errors',
    () async {
      final user = _testUser(email: 'existing-user@example.com');
      final session = _testSession(user: user);
      when(
        () => authClient.signUp(
          email: 'existing-user@example.com',
          password: 'password123',
        ),
      ).thenThrow(
        const supabase.AuthException(
          'User already registered',
          code: 'user_already_exists',
        ),
      );
      when(
        () => authClient.signInWithPassword(
          email: 'existing-user@example.com',
          password: 'password123',
        ),
      ).thenAnswer(
        (_) async => supabase.AuthResponse(session: session, user: user),
      );
      when(() => authClient.signOut()).thenAnswer((_) async {});

      await ensureTestUserWithClient(
        authClient,
        email: 'existing-user@example.com',
        password: 'password123',
        markOnboardingCompleted: (_) async {},
      );

      verify(
        () => authClient.signInWithPassword(
          email: 'existing-user@example.com',
          password: 'password123',
        ),
      ).called(2);
      verify(() => authClient.signOut()).called(1);
    },
  );

  test(
    'ensureTestUserWithClient rethrows non-duplicate signup errors',
    () async {
      when(
        () => authClient.signUp(
          email: 'broken@example.com',
          password: 'password123',
        ),
      ).thenThrow(
        const supabase.AuthException(
          'Email signups are disabled',
          code: 'signup_disabled',
        ),
      );

      await expectLater(
        () => ensureTestUserWithClient(
          authClient,
          email: 'broken@example.com',
          password: 'password123',
          markOnboardingCompleted: (_) async {},
        ),
        throwsA(
          isA<supabase.AuthException>().having(
            (e) => e.code,
            'code',
            'signup_disabled',
          ),
        ),
      );
      verifyNever(
        () => authClient.signInWithPassword(
          email: 'broken@example.com',
          password: 'password123',
        ),
      );
    },
  );
}

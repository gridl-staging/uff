/// ## Test Scenarios
/// - [positive] getCurrentSession returns authenticated when session exists
/// - [positive] signIn calls signInWithPassword and returns authenticated
/// - [positive] signUp with display_name metadata returns authenticated
/// - [positive] signOut delegates to GoTrueClient
/// - [positive] Social sign-in (Apple, Google) maps returned session to AuthState
/// - [negative] getCurrentSession returns unauthenticated when no session exists
/// - [negative] signIn propagates SDK exceptions without mapping
/// - [negative] signUp returns unauthenticated when session is null (email confirmation)
/// - [negative] Apple sign-in throws when native sign-in returns no id token
/// - [negative] Google sign-in throws when native sign-in returns no id or access token

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/auth/data/supabase_auth_repository.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_repository.dart';

class MockGoTrueClient extends Mock implements supabase.GoTrueClient {}

class MockAppleNativeSignInClient extends Mock
    implements AppleNativeSignInClient {}

class MockGoogleNativeSignInClient extends Mock
    implements GoogleNativeSignInClient {}

class MockProfileRepository extends Mock implements ProfileRepository {}

supabase.User _testUser({
  String id = 'test-user-id',
  String email = 'test@example.com',
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
  late MockGoTrueClient mockAuth;
  late MockAppleNativeSignInClient mockAppleNativeSignInClient;
  late MockGoogleNativeSignInClient mockGoogleNativeSignInClient;
  late MockProfileRepository mockProfileRepository;
  late SupabaseAuthRepository repository;

  setUpAll(() {
    registerFallbackValue(_testProfile(userId: 'fallback-user-id'));
  });

  setUp(() {
    mockAuth = MockGoTrueClient();
    mockAppleNativeSignInClient = MockAppleNativeSignInClient();
    mockGoogleNativeSignInClient = MockGoogleNativeSignInClient();
    mockProfileRepository = MockProfileRepository();
    repository = SupabaseAuthRepository(
      mockAuth,
      appleSignInClient: mockAppleNativeSignInClient,
      googleSignInClient: mockGoogleNativeSignInClient,
      profileRepository: mockProfileRepository,
      nonceGenerator: () => 'test-apple-nonce',
    );
  });

  group('getCurrentSession', () {
    test('returns authenticated when a session exists', () async {
      final user = _testUser();
      final session = _testSession(user: user);
      when(() => mockAuth.currentSession).thenReturn(session);

      final result = await repository.getCurrentSession();

      expect(
        result,
        const AuthState.authenticated(
          userId: 'test-user-id',
          email: 'test@example.com',
        ),
      );
    });

    test('returns unauthenticated when no session exists', () async {
      when(() => mockAuth.currentSession).thenReturn(null);

      final result = await repository.getCurrentSession();

      expect(result, const AuthState.unauthenticated());
    });
  });

  group('signIn', () {
    test('calls signInWithPassword and returns authenticated', () async {
      final user = _testUser(id: 'signin-id', email: 'a@b.com');
      final session = _testSession(user: user);
      when(
        () => mockAuth.signInWithPassword(
          email: 'a@b.com',
          password: 'pw123456',
        ),
      ).thenAnswer(
        (_) async => supabase.AuthResponse(session: session, user: user),
      );

      final result = await repository.signIn(
        email: 'a@b.com',
        password: 'pw123456',
      );

      expect(
        result,
        const AuthState.authenticated(userId: 'signin-id', email: 'a@b.com'),
      );
      verify(
        () => mockAuth.signInWithPassword(
          email: 'a@b.com',
          password: 'pw123456',
        ),
      ).called(1);
    });

    test('propagates SDK exceptions without mapping', () async {
      when(
        () => mockAuth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(
        const supabase.AuthException('Invalid login credentials'),
      );

      expect(
        () => repository.signIn(email: 'a@b.com', password: 'wrong'),
        throwsA(
          isA<supabase.AuthException>().having(
            (e) => e.message,
            'message',
            'Invalid login credentials',
          ),
        ),
      );
    });
  });

  group('signUp', () {
    test(
      'calls signUp with display_name metadata and returns authenticated',
      () async {
        final user = _testUser(id: 'new-id', email: 'new@b.com');
        final session = _testSession(user: user);
        when(
          () => mockAuth.signUp(
            email: 'new@b.com',
            password: 'pw123456',
            data: {'display_name': 'New User'},
          ),
        ).thenAnswer(
          (_) async => supabase.AuthResponse(session: session, user: user),
        );

        final result = await repository.signUp(
          email: 'new@b.com',
          password: 'pw123456',
          displayName: 'New User',
        );

        expect(
          result,
          const AuthState.authenticated(
            userId: 'new-id',
            email: 'new@b.com',
          ),
        );
        verify(
          () => mockAuth.signUp(
            email: 'new@b.com',
            password: 'pw123456',
            data: {'display_name': 'New User'},
          ),
        ).called(1);
      },
    );

    test(
      'returns unauthenticated when session is null (email confirmation)',
      () async {
        final user = _testUser(id: 'unconfirmed-id', email: 'new@b.com');
        when(
          () => mockAuth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            data: any(named: 'data'),
          ),
        ).thenAnswer(
          (_) async => supabase.AuthResponse(user: user),
        );

        final result = await repository.signUp(
          email: 'new@b.com',
          password: 'pw123456',
          displayName: 'New User',
        );

        expect(result, const AuthState.unauthenticated());
      },
    );
  });

  group('signOut', () {
    test('delegates to GoTrueClient.signOut', () async {
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      await repository.signOut();

      verify(() => mockAuth.signOut()).called(1);
    });
  });

  group('signInWithApple', () {
    test(
      'calls signInWithIdToken and maps the returned session to AuthState',
      () async {
        const nonce = 'test-apple-nonce';
        final hashedNonce = sha256.convert(utf8.encode(nonce)).toString();
        final user = _testUser(id: 'apple-user-id', email: 'apple@b.com');
        final session = _testSession(user: user);
        when(
          () => mockAppleNativeSignInClient.signIn(
            rawNonce: nonce,
            hashedNonce: hashedNonce,
          ),
        ).thenAnswer(
          (_) async => const AppleNativeSignInResult(
            idToken: 'apple-id-token',
            givenName: 'Alice',
            familyName: 'Runner',
          ),
        );
        when(
          () => mockAuth.signInWithIdToken(
            provider: supabase.OAuthProvider.apple,
            idToken: 'apple-id-token',
            nonce: nonce,
          ),
        ).thenAnswer(
          (_) async => supabase.AuthResponse(session: session, user: user),
        );
        when(
          () => mockProfileRepository.getProfile('apple-user-id'),
        ).thenAnswer(
          (_) async => _testProfile(userId: 'apple-user-id'),
        );
        when(
          () => mockProfileRepository.updateProfile(any()),
        ).thenAnswer(
          (invocation) async => invocation.positionalArguments.first as Profile,
        );

        final result = await repository.signInWithApple();

        expect(
          result,
          const AuthState.authenticated(
            userId: 'apple-user-id',
            email: 'apple@b.com',
          ),
        );
        verify(
          () => mockAuth.signInWithIdToken(
            provider: supabase.OAuthProvider.apple,
            idToken: 'apple-id-token',
            nonce: nonce,
          ),
        ).called(1);
        verify(
          () => mockProfileRepository.getProfile('apple-user-id'),
        ).called(1);
        final capturedProfile =
            verify(
                  () => mockProfileRepository.updateProfile(captureAny()),
                ).captured.single
                as Profile;
        expect(capturedProfile.displayName, 'Alice Runner');
      },
    );

    test(
      'throws when Apple native sign-in does not return an id token',
      () async {
        when(
          () => mockAppleNativeSignInClient.signIn(
            rawNonce: any(named: 'rawNonce'),
            hashedNonce: any(named: 'hashedNonce'),
          ),
        ).thenAnswer(
          (_) async => const AppleNativeSignInResult(),
        );

        expect(
          repository.signInWithApple,
          throwsA(
            isA<NativeAuthTokenException>().having(
              (e) => e.message,
              'message',
              contains('id token'),
            ),
          ),
        );
        verifyNever(
          () => mockAuth.signInWithIdToken(
            provider: supabase.OAuthProvider.apple,
            idToken: any(named: 'idToken'),
            nonce: any(named: 'nonce'),
          ),
        );
      },
    );
  });

  group('signInWithGoogle', () {
    test(
      'calls signInWithIdToken and maps the returned session to AuthState',
      () async {
        final user = _testUser(id: 'google-user-id', email: 'google@b.com');
        final session = _testSession(user: user);
        when(
          () => mockGoogleNativeSignInClient.signIn(),
        ).thenAnswer(
          (_) async => const GoogleNativeSignInResult(
            idToken: 'google-id-token',
            accessToken: 'google-access-token',
          ),
        );
        when(
          () => mockAuth.signInWithIdToken(
            provider: supabase.OAuthProvider.google,
            idToken: 'google-id-token',
            accessToken: 'google-access-token',
          ),
        ).thenAnswer(
          (_) async => supabase.AuthResponse(session: session, user: user),
        );

        final result = await repository.signInWithGoogle();

        expect(
          result,
          const AuthState.authenticated(
            userId: 'google-user-id',
            email: 'google@b.com',
          ),
        );
        verify(
          () => mockAuth.signInWithIdToken(
            provider: supabase.OAuthProvider.google,
            idToken: 'google-id-token',
            accessToken: 'google-access-token',
          ),
        ).called(1);
      },
    );

    test(
      'throws when Google native sign-in does not return an id token',
      () async {
        when(
          () => mockGoogleNativeSignInClient.signIn(),
        ).thenAnswer(
          (_) async => const GoogleNativeSignInResult(),
        );

        expect(
          repository.signInWithGoogle,
          throwsA(
            isA<NativeAuthTokenException>().having(
              (e) => e.message,
              'message',
              contains('id token'),
            ),
          ),
        );
        verifyNever(
          () => mockAuth.signInWithIdToken(
            provider: supabase.OAuthProvider.google,
            idToken: any(named: 'idToken'),
          ),
        );
      },
    );

    test(
      'throws when Google native sign-in does not return an access token',
      () async {
        when(
          () => mockGoogleNativeSignInClient.signIn(),
        ).thenAnswer(
          (_) async => const GoogleNativeSignInResult(
            idToken: 'google-id-token',
          ),
        );

        expect(
          repository.signInWithGoogle,
          throwsA(
            isA<NativeAuthTokenException>().having(
              (e) => e.message,
              'message',
              contains('access token'),
            ),
          ),
        );
        verifyNever(
          () => mockAuth.signInWithIdToken(
            provider: supabase.OAuthProvider.google,
            idToken: any(named: 'idToken'),
            accessToken: any(named: 'accessToken'),
          ),
        );
      },
    );
  });
}

Profile _testProfile({required String userId, String? displayName}) {
  return Profile(
    userId: userId,
    preferredUnits: 'metric',
    defaultActivityVisibility: 'private',
    onboardingCompleted: false,
    displayName: displayName,
  );
}

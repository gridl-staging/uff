import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart'
    show localDataCleanupProvider;
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_repository.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/core/telemetry/telemetry_enablement.dart';
import 'package:uff/src/features/notifications/application/notification_providers.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/profile/data/profile_repository.dart';
import 'package:uff/src/utils/app_logger.dart';

import '../data/fake_notification_token_service.dart';

/// ## Test Scenarios
/// - `[positive]` Authenticated transition syncs the current token once.
/// - `[isolation]` Unauthenticated transition cancels refresh persistence.
/// - `[isolation]` Re-authentication re-establishes refresh persistence for only the active session.
/// - `[negative]` Stale refresh tokens after sign-out do not persist to the backend.
/// - `[isolation]` Account switch persists only user B tokens after re-auth (no stale user-A writes).
/// - `[error]` Authenticated sync failures surface as provider AsyncError without token persistence.

class _FakeProfileRepository implements ProfileRepository {
  final List<String?> persistedTokens = <String?>[];

  @override
  Future<void> updateFcmToken(String? token) async {
    persistedTokens.add(token);
  }

  // No-op: backend token cleanup is auth-provider-owned (auth_provider.dart:300).
  @override
  Future<void> clearFcmToken() async {}

  @override
  Future<void> deleteMyAccount() {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> exportMyData() {
    throw UnimplementedError();
  }

  @override
  Future<Profile> getProfile(String userId) {
    throw UnimplementedError();
  }

  @override
  Future<Profile> updateProfile(Profile profile) {
    throw UnimplementedError();
  }

  @override
  Future<String> uploadAvatar(String userId, Uint8List bytes, String fileName) {
    throw UnimplementedError();
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  AuthState getCurrentSessionSync() => const AuthState.unauthenticated();

  @override
  Future<AuthState> getCurrentSession() async => getCurrentSessionSync();

  @override
  Future<AuthState> signIn({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<AuthState> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async => throw UnimplementedError();

  @override
  Future<AuthState> signInWithApple() async => throw UnimplementedError();

  @override
  Future<AuthState> signInWithGoogle() async => throw UnimplementedError();

  @override
  Future<void> signOut() async => throw UnimplementedError();

  // Notification-provider tests do not exercise password updates.
  @override
  Future<void> updatePassword(String newPassword) async =>
      throw UnimplementedError();

  // Notification-provider tests do not exercise connected auth providers.
  @override
  Future<List<String>> connectedProviders() async => throw UnimplementedError();

  // Notification-provider tests do not exercise account-age metadata lookups.
  @override
  DateTime? memberSince() => throw UnimplementedError();
}

ProviderContainer _createContainer({
  required StreamController<AuthState> authStateChanges,
  required FakeNotificationTokenService tokenService,
  required _FakeProfileRepository profileRepository,
}) {
  return ProviderContainer(
    overrides: [
      authStateChangesProvider.overrideWith((ref) => authStateChanges.stream),
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
      localDataCleanupProvider.overrideWithValue(() async {}),
      appLoggerProvider.overrideWithValue(AppLogger()),
      telemetryBreadcrumbRecorderProvider.overrideWithValue(
        noopTelemetryBreadcrumbRecorder,
      ),
      notificationTokenServiceProvider.overrideWithValue(tokenService),
      profileRepositoryProvider.overrideWithValue(profileRepository),
    ],
  );
}

Future<void> _flushAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('notificationRegistrarProvider', () {
    test('syncs the current token after an authenticated auth event', () async {
      final authStateChanges = StreamController<AuthState>();
      final tokenService = FakeNotificationTokenService()
        ..tokenToReturn = 'token-a';
      final profileRepository = _FakeProfileRepository();
      final container = _createContainer(
        authStateChanges: authStateChanges,
        tokenService: tokenService,
        profileRepository: profileRepository,
      );
      addTearDown(() async {
        container.dispose();
        await authStateChanges.close();
        await tokenService.dispose();
      });

      final registrarSubscription = container.listen(
        notificationRegistrarProvider,
        (_, __) {},
      );
      addTearDown(registrarSubscription.close);

      authStateChanges.add(
        const AuthState.authenticated(
          userId: 'user-1',
          email: 'user@example.com',
        ),
      );
      await container.read(authProvider.future);
      await _flushAsyncWork();

      expect(profileRepository.persistedTokens, <String?>['token-a']);
      expect(tokenService.refreshListenerCount, 1);
    });

    test(
      'reports async error when authenticated requestPermission throws',
      () async {
        final authStateChanges = StreamController<AuthState>();
        final tokenService = FakeNotificationTokenService()
          ..throwOnRequestPermissionError = StateError('permission denied');
        final profileRepository = _FakeProfileRepository();
        final container = _createContainer(
          authStateChanges: authStateChanges,
          tokenService: tokenService,
          profileRepository: profileRepository,
        );
        addTearDown(() async {
          container.dispose();
          await authStateChanges.close();
          await tokenService.dispose();
        });

        final registrarSubscription = container.listen(
          notificationRegistrarProvider,
          (_, __) {},
        );
        addTearDown(registrarSubscription.close);

        authStateChanges.add(
          const AuthState.authenticated(
            userId: 'user-1',
            email: 'user@example.com',
          ),
        );
        await container.read(authProvider.future);
        await _flushAsyncWork();

        final registrarState = container.read(notificationRegistrarProvider);
        expect(registrarState.hasError, true);
        expect(registrarState.isLoading, false);
        expect(registrarState.error.toString(), 'Bad state: permission denied');
        expect(tokenService.requestPermissionCallCount, 1);
        expect(profileRepository.persistedTokens, <String?>[]);
      },
    );

    test(
      'stops refresh persistence after auth becomes unauthenticated',
      () async {
        final authStateChanges = StreamController<AuthState>();
        final tokenService = FakeNotificationTokenService()
          ..tokenToReturn = 'token-a';
        final profileRepository = _FakeProfileRepository();
        final container = _createContainer(
          authStateChanges: authStateChanges,
          tokenService: tokenService,
          profileRepository: profileRepository,
        );
        addTearDown(() async {
          container.dispose();
          await authStateChanges.close();
          await tokenService.dispose();
        });

        final registrarSubscription = container.listen(
          notificationRegistrarProvider,
          (_, __) {},
        );
        addTearDown(registrarSubscription.close);

        authStateChanges.add(
          const AuthState.authenticated(
            userId: 'user-1',
            email: 'user@example.com',
          ),
        );
        await container.read(authProvider.future);
        await _flushAsyncWork();

        authStateChanges.add(const AuthState.unauthenticated());
        await _flushAsyncWork();
        tokenService.emitRefreshToken('token-after-sign-out');
        await _flushAsyncWork();

        expect(profileRepository.persistedTokens, <String?>['token-a']);
        expect(tokenService.refreshCancelCount, 1);
      },
    );

    test(
      're-authentication re-establishes refresh persistence for the next session only',
      () async {
        final authStateChanges = StreamController<AuthState>();
        final tokenService = FakeNotificationTokenService()
          ..tokenToReturn = 'token-a';
        final profileRepository = _FakeProfileRepository();
        final container = _createContainer(
          authStateChanges: authStateChanges,
          tokenService: tokenService,
          profileRepository: profileRepository,
        );
        addTearDown(() async {
          container.dispose();
          await authStateChanges.close();
          await tokenService.dispose();
        });

        final registrarSubscription = container.listen(
          notificationRegistrarProvider,
          (_, __) {},
        );
        addTearDown(registrarSubscription.close);

        authStateChanges.add(
          const AuthState.authenticated(
            userId: 'user-1',
            email: 'user@example.com',
          ),
        );
        await container.read(authProvider.future);
        await _flushAsyncWork();

        authStateChanges.add(const AuthState.unauthenticated());
        await _flushAsyncWork();
        tokenService.emitRefreshToken('token-after-sign-out');
        await _flushAsyncWork();

        tokenService.tokenToReturn = 'token-b';
        authStateChanges.add(
          const AuthState.authenticated(
            userId: 'user-2',
            email: 'user2@example.com',
          ),
        );
        await _flushAsyncWork();

        tokenService.emitRefreshToken('token-c');
        await _flushAsyncWork();

        expect(profileRepository.persistedTokens, <String?>[
          'token-a',
          'token-b',
          'token-c',
        ]);
        expect(tokenService.refreshCancelCount, 1);
        expect(tokenService.refreshListenerCount, 2);
      },
    );

    test('account switch persists only user B tokens after re-auth', () async {
      final authStateChanges = StreamController<AuthState>();
      final tokenService = FakeNotificationTokenService()
        ..tokenToReturn = 'token-user-a';
      final profileRepository = _FakeProfileRepository();
      final container = _createContainer(
        authStateChanges: authStateChanges,
        tokenService: tokenService,
        profileRepository: profileRepository,
      );
      addTearDown(() async {
        container.dispose();
        await authStateChanges.close();
        await tokenService.dispose();
      });

      final registrarSubscription = container.listen(
        notificationRegistrarProvider,
        (_, __) {},
      );
      addTearDown(registrarSubscription.close);

      // User A authenticates, token persisted.
      authStateChanges.add(
        const AuthState.authenticated(userId: 'user-a', email: 'a@example.com'),
      );
      await container.read(authProvider.future);
      await _flushAsyncWork();

      // User A gets a refresh.
      tokenService.emitRefreshToken('token-user-a-refresh');
      await _flushAsyncWork();

      expect(profileRepository.persistedTokens, <String?>[
        'token-user-a',
        'token-user-a-refresh',
      ]);

      // Sign out user A.
      authStateChanges.add(const AuthState.unauthenticated());
      await _flushAsyncWork();

      // Stale refresh arrives after sign-out — must NOT persist.
      tokenService.emitRefreshToken('token-stale-should-not-persist');
      await _flushAsyncWork();

      expect(profileRepository.persistedTokens, <String?>[
        'token-user-a',
        'token-user-a-refresh',
      ]);

      // User B authenticates.
      tokenService.tokenToReturn = 'token-user-b';
      authStateChanges.add(
        const AuthState.authenticated(userId: 'user-b', email: 'b@example.com'),
      );
      await _flushAsyncWork();

      // User B gets a refresh.
      tokenService.emitRefreshToken('token-user-b-refresh');
      await _flushAsyncWork();

      // Full sequence: user A tokens, then user B tokens, no stale writes.
      expect(profileRepository.persistedTokens, <String?>[
        'token-user-a',
        'token-user-a-refresh',
        'token-user-b',
        'token-user-b-refresh',
      ]);
      expect(tokenService.refreshCancelCount, 1);
      expect(tokenService.refreshListenerCount, 2);
    });
  });
}

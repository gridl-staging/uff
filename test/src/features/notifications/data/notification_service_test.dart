import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/notifications/data/notification_service.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_repository.dart';

import 'fake_notification_token_service.dart';

/// ## Test Scenarios
/// - `[positive]` Authenticated sync persists the current token and refresh updates.
/// - `[isolation]` Unauthenticated transitions stop refresh writes immediately.
/// - `[positive]` Permission and token read ordering stays deterministic.
/// - `[isolation]` Overlapping sync generations only persist the newest session token.
/// - `[isolation]` In-flight sync cancellation suppresses stale token persistence.
/// - `[negative]` In-flight asyncMap refresh write persists despite subscription cancellation (accepted race).
/// - `[error]` Refresh-persistence failures propagate through the configured error callback.

class _FakeProfileRepository implements ProfileRepository {
  final List<String?> persistedTokens = <String?>[];
  int updateFcmTokenCallCount = 0;
  int? failOnUpdateCall;
  Object? updateFcmTokenError;
  Completer<void>? pendingUpdateCompleter;

  @override
  Future<void> updateFcmToken(String? token) async {
    updateFcmTokenCallCount++;
    if (failOnUpdateCall == updateFcmTokenCallCount &&
        updateFcmTokenError != null) {
      _throwConfiguredError(updateFcmTokenError!);
    }
    final completer = pendingUpdateCompleter;
    if (completer != null) {
      pendingUpdateCompleter = null;
      await completer.future;
    }
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

Never _throwConfiguredError(Object error) {
  if (error is Error) {
    throw error;
  }
  if (error is Exception) {
    throw error;
  }
  throw StateError(
    'Configured fake error for notification service tests must be Exception '
    'or Error, got ${error.runtimeType}.',
  );
}

void main() {
  group('NotificationService', () {
    test('persists current token during authenticated sync', () async {
      final tokenService = FakeNotificationTokenService()
        ..tokenToReturn = 'token-a';
      final profileRepository = _FakeProfileRepository();
      final notificationService = NotificationService(
        notificationTokenService: tokenService,
        profileRepository: profileRepository,
      );

      await notificationService.syncAuthenticatedSession();

      expect(tokenService.requestPermissionCallCount, 1);
      expect(tokenService.getTokenCallCount, 1);
      expect(profileRepository.persistedTokens, <String?>['token-a']);

      await notificationService.dispose();
      await tokenService.dispose();
    });

    test(
      'stops refresh persistence on unauthenticated transition without profile write',
      () async {
        final tokenService = FakeNotificationTokenService()
          ..tokenToReturn = 'token-a';
        final profileRepository = _FakeProfileRepository();
        final notificationService = NotificationService(
          notificationTokenService: tokenService,
          profileRepository: profileRepository,
        );

        await notificationService.syncAuthenticatedSession();
        await notificationService.stopForUnauthenticatedSession();
        tokenService.emitRefreshToken('token-after-signout');
        await Future<void>.delayed(Duration.zero);

        expect(profileRepository.persistedTokens, <String?>['token-a']);

        await notificationService.dispose();
        await tokenService.dispose();
      },
    );

    test('re-persists refreshed token after authenticated sync', () async {
      final tokenService = FakeNotificationTokenService()
        ..tokenToReturn = 'token-a';
      final profileRepository = _FakeProfileRepository();
      final notificationService = NotificationService(
        notificationTokenService: tokenService,
        profileRepository: profileRepository,
      );

      await notificationService.syncAuthenticatedSession();
      tokenService.emitRefreshToken('token-b');
      await Future<void>.delayed(Duration.zero);

      expect(profileRepository.persistedTokens, <String?>[
        'token-a',
        'token-b',
      ]);

      await notificationService.dispose();
      await tokenService.dispose();
    });

    test('requests permission before reading current token', () async {
      final tokenService = FakeNotificationTokenService()
        ..tokenToReturn = 'token-a';
      final profileRepository = _FakeProfileRepository();
      final notificationService = NotificationService(
        notificationTokenService: tokenService,
        profileRepository: profileRepository,
      );

      await notificationService.syncAuthenticatedSession();

      expect(tokenService.callOrder, <String>['requestPermission', 'getToken']);

      await notificationService.dispose();
      await tokenService.dispose();
    });

    test(
      'cancels an in-flight authenticated sync before token persistence',
      () async {
        final tokenCompleter = Completer<String?>();
        final tokenService = FakeNotificationTokenService()
          ..pendingTokenCompleter = tokenCompleter;
        final profileRepository = _FakeProfileRepository();
        final notificationService = NotificationService(
          notificationTokenService: tokenService,
          profileRepository: profileRepository,
        );

        final syncFuture = notificationService.syncAuthenticatedSession();
        await Future<void>.delayed(Duration.zero);

        await notificationService.stopForUnauthenticatedSession();
        tokenCompleter.complete('token-after-stop');
        await syncFuture;

        expect(profileRepository.persistedTokens, isEmpty);
        expect(tokenService.refreshListenerCount, 0);

        await notificationService.dispose();
        await tokenService.dispose();
      },
    );

    test(
      'overlapping sync generations persist only the newest session token',
      () async {
        final firstTokenCompleter = Completer<String?>();
        final tokenService = FakeNotificationTokenService()
          ..pendingTokenCompleter = firstTokenCompleter
          ..tokenToReturn = 'token-second';
        final profileRepository = _FakeProfileRepository();
        final notificationService = NotificationService(
          notificationTokenService: tokenService,
          profileRepository: profileRepository,
        );

        final firstSync = notificationService.syncAuthenticatedSession();
        await Future<void>.delayed(Duration.zero);

        tokenService.pendingTokenCompleter = null;
        final secondSync = notificationService.syncAuthenticatedSession();
        firstTokenCompleter.complete('token-first-stale');

        await firstSync;
        await secondSync;

        expect(tokenService.requestPermissionCallCount, 2);
        expect(tokenService.getTokenCallCount, 2);
        expect(profileRepository.persistedTokens, <String?>['token-second']);
        expect(tokenService.refreshListenerCount, 1);
        expect(tokenService.refreshCancelCount, 0);

        await notificationService.dispose();
        await tokenService.dispose();
      },
    );

    test(
      'in-flight refresh write completes despite subscription cancellation',
      () async {
        // This test proves a known race: if asyncMap is mid-execution when the
        // subscription is cancelled, the in-flight write still completes.
        // Dart stream subscription cancellation does NOT abort in-flight
        // asyncMap work. This is accepted behavior because:
        // (1) auth_provider.dart:300 calls clearFcmToken() on sign-out,
        // (2) the next sign-in overwrites with the new user's token.
        final updateCompleter = Completer<void>();
        final tokenService = FakeNotificationTokenService()
          ..tokenToReturn = 'token-a';
        final profileRepository = _FakeProfileRepository();
        final notificationService = NotificationService(
          notificationTokenService: tokenService,
          profileRepository: profileRepository,
        );

        await notificationService.syncAuthenticatedSession();
        expect(profileRepository.persistedTokens, <String?>['token-a']);

        // Make the next updateFcmToken call block on the completer.
        profileRepository.pendingUpdateCompleter = updateCompleter;
        tokenService.emitRefreshToken('token-refresh-in-flight');
        await Future<void>.delayed(Duration.zero);

        // updateFcmToken is now in flight (awaiting the completer).
        // Cancel the subscription by stopping the service.
        await notificationService.stopForUnauthenticatedSession();

        // Complete the in-flight write — it will persist despite cancellation.
        updateCompleter.complete();
        await Future<void>.delayed(Duration.zero);

        // The in-flight write persisted (this is the accepted race behavior).
        expect(profileRepository.persistedTokens, <String?>[
          'token-a',
          'token-refresh-in-flight',
        ]);

        await notificationService.dispose();
        await tokenService.dispose();
      },
    );

    test(
      'reports refresh persistence failures to the configured error handler',
      () async {
        final tokenService = FakeNotificationTokenService()
          ..tokenToReturn = 'token-a';
        final profileRepository = _FakeProfileRepository()
          ..failOnUpdateCall = 2
          ..updateFcmTokenError = StateError('refresh persist failed');
        Object? reportedError;
        StackTrace? reportedStackTrace;
        final notificationService = NotificationService(
          notificationTokenService: tokenService,
          profileRepository: profileRepository,
          onRefreshSyncError: (error, stackTrace) {
            reportedError = error;
            reportedStackTrace = stackTrace;
          },
        );

        await notificationService.syncAuthenticatedSession();
        tokenService.emitRefreshToken('token-b');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(profileRepository.persistedTokens, <String?>['token-a']);
        expect(reportedError.toString(), 'Bad state: refresh persist failed');
        // test-standards:allow-weak-assertion - refresh callback stack traces
        // are runtime-generated by async scheduling and have no stable text.
        expect(reportedStackTrace, isNotNull);

        await notificationService.dispose();
        await tokenService.dispose();
      },
    );
  });
}

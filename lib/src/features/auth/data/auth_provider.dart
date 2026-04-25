import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as flutter_riverpod;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart'
    show localDataCleanupProvider;
import 'package:uff/src/core/telemetry/telemetry_enablement.dart';
import 'package:uff/src/features/auth/data/auth_oauth_config.dart';
import 'package:uff/src/features/auth/data/auth_repository.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/auth/data/supabase_auth_repository.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/profile/data/supabase_profile_repository.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/utils/app_logger.dart';

part 'auth_provider.g.dart';

final authOAuthConfigProvider = flutter_riverpod.Provider<AuthOAuthConfig>((
  ref,
) {
  return const AuthOAuthConfigInitializer().initialize(environment: dotenv.env);
});

final appLoggerProvider = flutter_riverpod.Provider<AppLogger>(
  (ref) => AppLogger(),
);

@riverpod
AuthRepository authRepository(Ref ref) {
  final authOAuthConfig = ref.watch(authOAuthConfigProvider);
  return SupabaseAuthRepository(
    Supabase.instance.client.auth,
    googleSignInClient: GoogleSignInNativeSignInClient.withClientIds(
      googleWebClientId: authOAuthConfig.googleWebClientId,
      googleIosClientId: authOAuthConfig.googleIosClientId,
    ),
    profileRepository: SupabaseProfileRepository(Supabase.instance.client),
  );
}

final flutter_riverpod.FutureProvider<List<String>> connectedProvidersProvider =
    flutter_riverpod.FutureProvider.autoDispose<List<String>>(
      (ref) => ref.watch(authRepositoryProvider).connectedProviders(),
    );

final flutter_riverpod.Provider<DateTime?> memberSinceProvider =
    flutter_riverpod.Provider<DateTime?>(
      (ref) => ref.watch(authRepositoryProvider).memberSince(),
    );

@Riverpod(keepAlive: true)
Stream<AuthState> authStateChanges(Ref ref) {
  final auth = Supabase.instance.client.auth;
  // Use a replay-style controller that emits the current session state
  // synchronously, then forwards all subsequent auth state changes.
  // This avoids the async* generator race where the first yield is deferred
  // and the auth state stays AsyncLoading indefinitely.
  final controller = StreamController<AuthState>();

  // Emit the current session state synchronously when first listened.
  controller.onListen = () {
    controller.add(mapSessionToAuthState(auth.currentSession));
  };

  // Forward subsequent auth state changes from Supabase.
  final subscription = auth.onAuthStateChange.listen(
    (event) => controller.add(mapSessionToAuthState(event.session)),
    onError: controller.addError,
  );

  // Clean up when the provider is disposed.
  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });

  return controller.stream;
}

// TODO(stuart): Document Auth.
/// TODO: Document Auth.
@riverpod
class Auth extends _$Auth {
  bool _hasRunUnauthenticatedCleanup = false;

  @override
  FutureOr<AuthState> build() {
    _recordBoundaryBreadcrumb(message: 'auth.build', operation: 'build');

    // Listen to Supabase auth stream for ongoing state changes
    // (e.g. token refresh, sign-out from another tab).
    ref.listen<AsyncValue<AuthState>>(authStateChangesProvider, (_, next) {
      if (next is AsyncData<AuthState>) {
        final nextState = next.value;
        final isUnauthenticated =
            nextState == const AuthState.unauthenticated();
        if (isUnauthenticated) {
          if (!_hasRunUnauthenticatedCleanup) {
            _hasRunUnauthenticatedCleanup = true;
            _clearLocalDataAndInvalidateProviders();
          }
        } else {
          _hasRunUnauthenticatedCleanup = false;
        }
        ref
            .read(appLoggerProvider)
            .logEvent(
              eventType: 'auth.state.transition',
              outcome: 'received',
              identifiers: {'state': _authStateName(nextState)},
            );
        state = next;
      }
    });

    // Read the current session synchronously through the repository instead
    // of accessing Supabase.instance directly. This keeps the provider
    // testable (the repository is overridden in unit tests) while avoiding
    // the async gap that would leave the auth state in AsyncLoading.
    return ref.read(authRepositoryProvider).getCurrentSessionSync();
  }

  Future<void> signIn(String email, String password) async {
    if (state.isLoading) {
      return;
    }
    _recordBoundaryBreadcrumb(
      message: 'auth.sign_in',
      operation: 'sign_in_password',
      provider: 'password',
    );
    final logger = ref.read(appLoggerProvider)
      ..logEvent(
        eventType: 'auth.sign_in.password',
        outcome: 'start',
        identifiers: const {'provider': 'password'},
      );
    state = const AsyncLoading<AuthState>();
    state = await AsyncValue.guard(() {
      return logger.runWithTiming(
        eventType: 'auth.sign_in.password',
        successOutcome: 'success',
        failureOutcome: 'failure',
        identifiers: const {'provider': 'password'},
        operation: () {
          return ref
              .read(authRepositoryProvider)
              .signIn(email: email, password: password);
        },
      );
    });
  }

  Future<void> signUp(String email, String password, String displayName) async {
    if (state.isLoading) {
      return;
    }
    _recordBoundaryBreadcrumb(
      message: 'auth.sign_up',
      operation: 'sign_up_password',
      provider: 'password',
    );
    final logger = ref.read(appLoggerProvider)
      ..logEvent(
        eventType: 'auth.sign_up.password',
        outcome: 'start',
        identifiers: const {'provider': 'password'},
      );
    state = const AsyncLoading<AuthState>();
    state = await AsyncValue.guard(() {
      return logger.runWithTiming(
        eventType: 'auth.sign_up.password',
        successOutcome: 'success',
        failureOutcome: 'failure',
        identifiers: const {'provider': 'password'},
        operation: () {
          return ref
              .read(authRepositoryProvider)
              .signUp(
                email: email,
                password: password,
                displayName: displayName,
              );
        },
      );
    });
  }

  Future<void> signOut() async {
    if (state.isLoading) {
      return;
    }
    _recordBoundaryBreadcrumb(message: 'auth.sign_out', operation: 'sign_out');
    final logger = ref.read(appLoggerProvider)
      ..logEvent(eventType: 'auth.sign_out', outcome: 'start');
    state = const AsyncLoading<AuthState>();
    state = await AsyncValue.guard(() async {
      return logger.runWithTiming(
        eventType: 'auth.sign_out',
        successOutcome: 'success',
        failureOutcome: 'failure',
        operation: () async {
          await ref.read(authRepositoryProvider).signOut();
          return const AuthState.unauthenticated();
        },
      );
    });
  }

  Future<void> updatePassword(String newPassword) async {
    _recordBoundaryBreadcrumb(
      message: 'auth.update_password',
      operation: 'update_password',
      provider: 'password',
    );
    final logger = ref.read(appLoggerProvider)
      ..logEvent(
        eventType: 'auth.update_password',
        outcome: 'start',
        identifiers: const {'provider': 'password'},
      );
    await logger.runWithTiming(
      eventType: 'auth.update_password',
      successOutcome: 'success',
      failureOutcome: 'failure',
      identifiers: const {'provider': 'password'},
      operation: () {
        return ref.read(authRepositoryProvider).updatePassword(newPassword);
      },
    );
  }

  Future<void> signInWithApple() async {
    if (state.isLoading) {
      return;
    }
    _recordBoundaryBreadcrumb(
      message: 'auth.sign_in_apple',
      operation: 'sign_in_apple',
      provider: 'apple',
    );
    final logger = ref.read(appLoggerProvider)
      ..logEvent(
        eventType: 'auth.sign_in.apple',
        outcome: 'start',
        identifiers: const {'provider': 'apple'},
      );
    state = const AsyncLoading<AuthState>();
    state = await AsyncValue.guard(() {
      return logger.runWithTiming(
        eventType: 'auth.sign_in.apple',
        successOutcome: 'success',
        failureOutcome: 'failure',
        identifiers: const {'provider': 'apple'},
        operation: () => ref.read(authRepositoryProvider).signInWithApple(),
      );
    });
  }

  Future<void> signInWithGoogle() async {
    if (state.isLoading) {
      return;
    }
    _recordBoundaryBreadcrumb(
      message: 'auth.sign_in_google',
      operation: 'sign_in_google',
      provider: 'google',
    );
    final logger = ref.read(appLoggerProvider)
      ..logEvent(
        eventType: 'auth.sign_in.google',
        outcome: 'start',
        identifiers: const {'provider': 'google'},
      );
    state = const AsyncLoading<AuthState>();
    state = await AsyncValue.guard(() {
      return logger.runWithTiming(
        eventType: 'auth.sign_in.google',
        successOutcome: 'success',
        failureOutcome: 'failure',
        identifiers: const {'provider': 'google'},
        operation: () => ref.read(authRepositoryProvider).signInWithGoogle(),
      );
    });
  }

  String _authStateName(AuthState authState) {
    return authState.map(
      authenticated: (_) => 'authenticated',
      unauthenticated: (_) => 'unauthenticated',
    );
  }

  void _recordBoundaryBreadcrumb({
    required String message,
    required String operation,
    String? provider,
  }) {
    recordBoundaryTelemetryBreadcrumb(
      ref.read(telemetryBreadcrumbRecorderProvider),
      boundary: 'auth',
      operation: operation,
      message: message,
      metadata: <String, Object?>{if (provider != null) 'provider': provider},
    );
  }

  /// Clears local data and invalidates user-scoped providers on sign-out.
  ///
  /// The local Drift database doesn't scope by user_id, so switching users
  /// without clearing would expose the previous user's cached activities,
  /// track points, and sessions. This is a critical data isolation boundary.
  Future<void> _clearLocalDataAndInvalidateProviders() async {
    // Clear the FCM token from the backend profile so push notifications
    // intended for user A don't route to user B's device after an in-app
    // account switch. This must happen before we invalidate providers.
    // Wrapped in try/catch because the session may already be gone by the
    // time this cleanup runs (e.g. server-side session revocation), and
    // a failed token clear must not block the rest of the cleanup.
    try {
      await ref.read(profileRepositoryProvider).clearFcmToken();
    } on Object catch (_) {
      // Best-effort: if the session is already invalid, the token will
      // become stale on the backend anyway (the next sign-in will
      // overwrite it). Swallow the error to avoid blocking local cleanup.
    }

    // Clear the local Drift database so the next user starts with a
    // clean slate. Without this, locally-cached activities from user A
    // would be visible to user B after an in-app account switch.
    final cleanupLocal = ref.read(localDataCleanupProvider);
    await cleanupLocal();

    ref
      ..invalidate(savedActivitiesProvider)
      ..invalidate(activityDetailProvider)
      ..invalidate(socialFeedProvider)
      ..invalidate(viewedUserActivityListProvider)
      ..invalidate(remoteActivityDetailProvider)
      // These settings providers read auth-account state, not local activity
      // rows, but they still belong to the same account-switch boundary. If a
      // settings screen keeps them listened to across sign-out, invalidation
      // prevents user B from seeing user A's connected-provider badges.
      ..invalidate(connectedProvidersProvider)
      ..invalidate(memberSinceProvider);
  }
}

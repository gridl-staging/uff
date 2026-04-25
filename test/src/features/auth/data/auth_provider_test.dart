import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_repository.dart';
import 'package:uff/src/core/telemetry/telemetry_enablement.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_repository.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/profile/data/profile_repository.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/data/social_activity_repository.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/social_activity_detail.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/utils/app_logger.dart';

// ## Test Scenarios
// - [positive] Sign in / sign up updates async state to authenticated
// - [positive] Sign out updates async state to unauthenticated
// - [positive] Social sign-in (Apple, Google) maps session to authenticated
// - [positive] Structured logs emitted for auth boundary methods
// - [positive] Stream event updates auth state after initial hydration
// - [negative] Social sign-in exposes repository errors
// - [negative] Failed social sign-in emits structured failure log
// - [isolation] Unauthenticated transition invalidates cached savedActivities
// - [isolation] Unauthenticated transition invalidates cached activityDetail
// - [isolation] Unauthenticated transition invalidates cached socialFeedProvider
// - [isolation] Unauthenticated transition invalidates cached remoteActivityDetailProvider
// - [edge] Auth loading state maintained while social sign-in request is pending
// - [edge] Synchronous breadcrumb recorder failure does not block sign-in
// - [isolation] Unauthenticated transition clears FCM token from backend profile

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    AuthState initialState = const AuthState.unauthenticated(),
    this.signInWithAppleError,
    this.signInWithGoogleError,
  }) : _session = initialState;

  AuthState _session;
  final Exception? signInWithAppleError;
  final Exception? signInWithGoogleError;
  int getCurrentSessionCallCount = 0;
  int signInCallCount = 0;
  int signUpCallCount = 0;
  int signInWithAppleCallCount = 0;
  int signInWithGoogleCallCount = 0;
  int signOutCallCount = 0;
  int connectedProvidersCallCount = 0;
  List<String> connectedProvidersValue = const <String>[];

  @override
  Future<AuthState> getCurrentSession() async {
    getCurrentSessionCallCount++;
    return _session;
  }

  @override
  AuthState getCurrentSessionSync() {
    getCurrentSessionCallCount++;
    return _session;
  }

  @override
  Future<AuthState> signIn({
    required String email,
    required String password,
  }) async {
    signInCallCount++;
    _session = AuthState.authenticated(userId: 'fake-$email', email: email);
    return _session;
  }

  @override
  Future<AuthState> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    signUpCallCount++;
    _session = AuthState.authenticated(userId: 'fake-$email', email: email);
    return _session;
  }

  @override
  Future<AuthState> signInWithApple() async {
    signInWithAppleCallCount++;
    if (signInWithAppleError != null) {
      throw signInWithAppleError!;
    }
    _session = const AuthState.authenticated(
      userId: 'fake-apple-user',
      email: 'apple@example.com',
    );
    return _session;
  }

  @override
  Future<AuthState> signInWithGoogle() async {
    signInWithGoogleCallCount++;
    if (signInWithGoogleError != null) {
      throw signInWithGoogleError!;
    }
    _session = const AuthState.authenticated(
      userId: 'fake-google-user',
      email: 'google@example.com',
    );
    return _session;
  }

  @override
  Future<void> signOut() async {
    signOutCallCount++;
    _session = const AuthState.unauthenticated();
  }

  @override
  Future<void> updatePassword(String newPassword) async {}

  @override
  Future<List<String>> connectedProviders() async {
    connectedProvidersCallCount++;
    return connectedProvidersValue;
  }

  @override
  DateTime? memberSince() => null;
}

/// Fake profile repository that records clearFcmToken calls for
/// verifying FCM token cleanup on sign-out.
class _FakeProfileRepository implements ProfileRepository {
  int clearFcmTokenCallCount = 0;

  @override
  Future<void> clearFcmToken() async {
    clearFcmTokenCallCount++;
  }

  @override
  Future<Profile> getProfile(String userId) async {
    throw UnimplementedError('Not needed for auth provider tests');
  }

  @override
  Future<Profile> updateProfile(Profile profile) async {
    throw UnimplementedError('Not needed for auth provider tests');
  }

  @override
  Future<void> updateFcmToken(String? token) async {}

  @override
  Future<String> uploadAvatar(
    String userId,
    dynamic bytes,
    String fileName,
  ) async {
    throw UnimplementedError('Not needed for auth provider tests');
  }

  @override
  Future<Map<String, dynamic>> exportMyData() async {
    throw UnimplementedError('Not needed for auth provider tests');
  }

  @override
  Future<void> deleteMyAccount() async {
    throw UnimplementedError('Not needed for auth provider tests');
  }
}

/// Stub that short-circuits the real Supabase-backed profile fetch so
/// activityDetailProvider can resolve in a pure-unit context.
class _StubProfileNotifier extends ProfileNotifier {
  @override
  FutureOr<Profile?> build() => null;
}

ProviderContainer _createContainer({
  required AuthRepository repository,
  StreamController<AuthState>? streamController,
  AppLogger? logger,
  TelemetryBreadcrumbRecorder? breadcrumbRecorder,
}) {
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      // Override with no-op: unit tests don't have a real Drift database.
      localDataCleanupProvider.overrideWithValue(() async {}),
      if (logger != null) appLoggerProvider.overrideWithValue(logger),
      if (breadcrumbRecorder != null)
        telemetryBreadcrumbRecorderProvider.overrideWithValue(
          breadcrumbRecorder,
        ),
      if (streamController != null)
        authStateChangesProvider.overrideWith((ref) => streamController.stream),
    ],
  );
}

Future<AuthState> _hydrateFromAuthStream({
  required ProviderContainer container,
  required StreamController<AuthState> streamController,
  required AuthState initialAuthState,
}) async {
  final subscription = container.listen(authProvider, (_, __) {});
  try {
    final authFuture = container.read(authProvider.future);
    streamController.add(initialAuthState);
    return await authFuture;
  } finally {
    subscription.close();
  }
}

/// Creates a hydrated [FakeAuthRepository] + [ProviderContainer] test fixture.
/// Registers teardowns for the container and stream controller automatically.
Future<({FakeAuthRepository repository, ProviderContainer container})>
_createHydratedFixture({
  FakeAuthRepository? repository,
  AppLogger? logger,
  TelemetryBreadcrumbRecorder? breadcrumbRecorder,
  AuthState initialAuthState = const AuthState.unauthenticated(),
}) async {
  // Auth.build() reads getCurrentSessionSync() from the repository to get
  // the initial auth state synchronously (avoiding an async gap). Pass the
  // initial auth state through to the repository so the synchronous read
  // returns the expected value.
  final repo = repository ?? FakeAuthRepository(initialState: initialAuthState);
  final streamController = StreamController<AuthState>();
  final container = _createContainer(
    repository: repo,
    streamController: streamController,
    logger: logger,
    breadcrumbRecorder: breadcrumbRecorder,
  );
  addTearDown(() {
    container.dispose();
    streamController.close();
  });
  await _hydrateFromAuthStream(
    container: container,
    streamController: streamController,
    initialAuthState: initialAuthState,
  );
  return (repository: repo, container: container);
}

class DelayedAppleSignInAuthRepository implements AuthRepository {
  DelayedAppleSignInAuthRepository({
    AuthState initialState = const AuthState.unauthenticated(),
  }) : _session = initialState;

  final Completer<AuthState> _appleSignInCompleter = Completer<AuthState>();
  AuthState _session;

  void completeAppleSignIn(AuthState nextState) {
    if (!_appleSignInCompleter.isCompleted) {
      _session = nextState;
      _appleSignInCompleter.complete(nextState);
    }
  }

  @override
  Future<AuthState> getCurrentSession() async => _session;

  @override
  AuthState getCurrentSessionSync() => _session;

  @override
  Future<AuthState> signIn({
    required String email,
    required String password,
  }) async {
    return AuthState.authenticated(userId: 'fake-$email', email: email);
  }

  @override
  Future<AuthState> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    return AuthState.authenticated(userId: 'fake-$email', email: email);
  }

  @override
  Future<AuthState> signInWithApple() {
    return _appleSignInCompleter.future;
  }

  @override
  Future<AuthState> signInWithGoogle() async {
    return const AuthState.authenticated(
      userId: 'fake-google-user',
      email: 'google@example.com',
    );
  }

  @override
  Future<void> signOut() async {
    _session = const AuthState.unauthenticated();
  }

  @override
  Future<void> updatePassword(String newPassword) async {}

  @override
  Future<List<String>> connectedProviders() async => const <String>[];

  @override
  DateTime? memberSince() => null;
}

class AuthScopedSavedActivitiesRepository implements TrackingRepository {
  AuthScopedSavedActivitiesRepository({
    required this.savedSessionsByUserId,
    this.sessionDetailsByUserId = const {},
  });

  final Map<String, List<TrackingSessionRecord>> savedSessionsByUserId;

  /// Maps userId → (sessionId → session) for activityDetailProvider testing.
  final Map<String, Map<int, TrackingSessionRecord>> sessionDetailsByUserId;
  String? currentUserId;
  int loadSavedSessionsCallCount = 0;
  int loadSessionCallCount = 0;

  @override
  Future<List<TrackingSessionRecord>> loadSavedSessions() async {
    loadSavedSessionsCallCount++;
    final userId = currentUserId;
    if (userId == null) {
      return const <TrackingSessionRecord>[];
    }
    return savedSessionsByUserId[userId] ?? const <TrackingSessionRecord>[];
  }

  @override
  Future<TrackingSessionRecord?> loadSession(int sessionId) async {
    loadSessionCallCount++;
    final userId = currentUserId;
    if (userId == null) {
      return null;
    }
    return sessionDetailsByUserId[userId]?[sessionId];
  }

  @override
  Future<List<TrackingPoint>> loadPointsForSession(int sessionId) async {
    // Return empty points — sufficient for proving invalidation behavior.
    return const <TrackingPoint>[];
  }

  @override
  Future<void> appendPointBatch(List<TrackingPoint> points) async =>
      throw UnimplementedError();

  @override
  Future<TrackingSessionRecord> createSession() async =>
      throw UnimplementedError();

  @override
  Future<void> deleteActivity(int sessionId) async =>
      throw UnimplementedError();

  @override
  Future<void> discardSession(int sessionId) async =>
      throw UnimplementedError();

  @override
  Future<void> finalizeSession(int sessionId) async =>
      throw UnimplementedError();

  @override
  Future<TrackingSessionRecord?> loadActiveSession() async =>
      throw UnimplementedError();

  @override
  Future<List<SyncQueueEntry>> loadPendingSyncQueueEntries() async =>
      throw UnimplementedError();

  @override
  Future<SyncQueueEntry?> loadSyncQueueEntry(int sessionId) async =>
      throw UnimplementedError();

  @override
  Future<void> saveSession(TrackingSessionRecord session) async =>
      throw UnimplementedError();

  @override
  Future<int> saveImportedSession(
    TrackingSessionRecord session,
    List<TrackingPoint> points,
  ) async => throw UnimplementedError();

  @override
  Future<void> updateSessionRemoteId(int sessionId, String remoteId) async =>
      throw UnimplementedError();

  @override
  Future<void> updateSessionStatus(
    int sessionId,
    TrackingSessionStatus status,
    DateTime at,
  ) async => throw UnimplementedError();

  @override
  Future<void> updateSyncQueueEntryStatus({
    required int sessionId,
    required SyncQueueEntryStatus status,
    int? retryCount,
    String? lastError,
  }) async => throw UnimplementedError();

  @override
  Future<void> upsertSyncQueueEntry({
    required int sessionId,
    required SyncQueueEntryStatus status,
    required DateTime queuedAt,
    int retryCount = 0,
    String? lastError,
  }) async => throw UnimplementedError();
}

TrackingSessionRecord _savedSession({
  required int id,
  required String remoteId,
}) {
  return TrackingSessionRecord(
    id: id,
    status: TrackingSessionStatus.saved,
    createdAt: DateTime.utc(2026, 3, 26, 9),
    updatedAt: DateTime.utc(2026, 3, 26, 9),
    startedAt: DateTime.utc(2026, 3, 26, 9),
    stoppedAt: DateTime.utc(2026, 3, 26, 9, 30),
    distanceMeters: 5000,
    movingTimeSeconds: 1800,
    remoteId: remoteId,
    visibility: 'private',
  );
}

void main() {
  group('authProvider', () {
    test('build hydrates from auth stream initial event', () async {
      final fixture = await _createHydratedFixture(
        initialAuthState: const AuthState.authenticated(
          userId: 'stream-user',
          email: 'stream@example.com',
        ),
      );

      expect(
        fixture.container.read(authProvider).value,
        const AuthState.authenticated(
          userId: 'stream-user',
          email: 'stream@example.com',
        ),
      );
      // Auth.build() reads getCurrentSessionSync() once during initialization.
      expect(fixture.repository.getCurrentSessionCallCount, 1);
    });

    test('build loads initial session from the auth stream', () async {
      final fixture = await _createHydratedFixture(
        repository: FakeAuthRepository(
          initialState: const AuthState.authenticated(
            userId: 'seed-user',
            email: 'seed@example.com',
          ),
        ),
        initialAuthState: const AuthState.authenticated(
          userId: 'seed-user',
          email: 'seed@example.com',
        ),
      );

      expect(
        fixture.container.read(authProvider).value,
        const AuthState.authenticated(
          userId: 'seed-user',
          email: 'seed@example.com',
        ),
      );
    });

    test('sign in updates async state to authenticated', () async {
      final fixture = await _createHydratedFixture();

      await fixture.container
          .read(authProvider.notifier)
          .signIn('a@b.com', 'password123');

      expect(fixture.repository.signInCallCount, 1);
      expect(
        fixture.container.read(authProvider).value,
        const AuthState.authenticated(userId: 'fake-a@b.com', email: 'a@b.com'),
      );
    });

    test('sign up updates async state to authenticated', () async {
      final fixture = await _createHydratedFixture();

      await fixture.container
          .read(authProvider.notifier)
          .signUp('new@b.com', 'password123', 'New User');

      expect(fixture.repository.signUpCallCount, 1);
      expect(
        fixture.container.read(authProvider).value,
        const AuthState.authenticated(
          userId: 'fake-new@b.com',
          email: 'new@b.com',
        ),
      );
    });

    test('sign out updates async state to unauthenticated', () async {
      final fixture = await _createHydratedFixture(
        repository: FakeAuthRepository(
          initialState: const AuthState.authenticated(
            userId: 'seed-user',
            email: 'seed@example.com',
          ),
        ),
        initialAuthState: const AuthState.authenticated(
          userId: 'seed-user',
          email: 'seed@example.com',
        ),
      );

      await fixture.container.read(authProvider.notifier).signOut();

      expect(fixture.repository.signOutCallCount, 1);
      expect(
        fixture.container.read(authProvider).value,
        const AuthState.unauthenticated(),
      );
    });

    test('sign in with Apple updates async state to authenticated', () async {
      final fixture = await _createHydratedFixture();

      await fixture.container.read(authProvider.notifier).signInWithApple();

      expect(fixture.repository.signInWithAppleCallCount, 1);
      expect(
        fixture.container.read(authProvider).value,
        const AuthState.authenticated(
          userId: 'fake-apple-user',
          email: 'apple@example.com',
        ),
      );
    });

    test('sign in with Google updates async state to authenticated', () async {
      final fixture = await _createHydratedFixture();

      await fixture.container.read(authProvider.notifier).signInWithGoogle();

      expect(fixture.repository.signInWithGoogleCallCount, 1);
      expect(
        fixture.container.read(authProvider).value,
        const AuthState.authenticated(
          userId: 'fake-google-user',
          email: 'google@example.com',
        ),
      );
    });

    test(
      'sign in with Apple keeps loading state while request is pending',
      () async {
        final repository = DelayedAppleSignInAuthRepository();
        final streamController = StreamController<AuthState>();
        final container = _createContainer(
          repository: repository,
          streamController: streamController,
        );
        addTearDown(() {
          container.dispose();
          streamController.close();
        });
        await _hydrateFromAuthStream(
          container: container,
          streamController: streamController,
          initialAuthState: const AuthState.unauthenticated(),
        );

        final signInFuture = container
            .read(authProvider.notifier)
            .signInWithApple();

        expect(container.read(authProvider).isLoading, isTrue);

        repository.completeAppleSignIn(
          const AuthState.authenticated(
            userId: 'pending-apple-user',
            email: 'pending@apple.com',
          ),
        );
        await signInFuture;
        expect(
          container.read(authProvider).value,
          const AuthState.authenticated(
            userId: 'pending-apple-user',
            email: 'pending@apple.com',
          ),
        );
      },
    );

    test('sign in with Google exposes repository errors', () async {
      final fixture = await _createHydratedFixture(
        repository: FakeAuthRepository(
          signInWithGoogleError: Exception('google sign-in failed'),
        ),
      );

      await fixture.container.read(authProvider.notifier).signInWithGoogle();

      expect(fixture.container.read(authProvider).hasError, isTrue);
      expect(fixture.repository.signInWithGoogleCallCount, 1);
    });

    test(
      'emits structured logs for sign-in, sign-up, sign-out, and social sign-ins',
      () async {
        final loggedEvents = <Map<String, Object?>>[];
        final fixture = await _createHydratedFixture(
          logger: AppLogger(sink: loggedEvents.add),
        );

        await fixture.container
            .read(authProvider.notifier)
            .signIn('log@in.com', 'pw');
        await fixture.container
            .read(authProvider.notifier)
            .signUp('new@user.com', 'pw', 'Name');
        await fixture.container.read(authProvider.notifier).signOut();
        await fixture.container.read(authProvider.notifier).signInWithApple();
        await fixture.container.read(authProvider.notifier).signInWithGoogle();

        expect(
          loggedEvents,
          contains(
            allOf(
              containsPair('event_type', 'auth.sign_in.password'),
              containsPair('outcome', 'success'),
            ),
          ),
        );
        expect(
          loggedEvents,
          contains(
            allOf(
              containsPair('event_type', 'auth.sign_up.password'),
              containsPair('outcome', 'success'),
            ),
          ),
        );
        expect(
          loggedEvents,
          contains(
            allOf(
              containsPair('event_type', 'auth.sign_out'),
              containsPair('outcome', 'success'),
            ),
          ),
        );
        expect(
          loggedEvents,
          contains(
            allOf(
              containsPair('event_type', 'auth.sign_in.apple'),
              containsPair('outcome', 'success'),
            ),
          ),
        );
        expect(
          loggedEvents,
          contains(
            allOf(
              containsPair('event_type', 'auth.sign_in.google'),
              containsPair('outcome', 'success'),
            ),
          ),
        );
      },
    );

    test('records telemetry breadcrumbs for auth boundary methods', () async {
      final recordedBreadcrumbs = <Map<String, Object?>>[];
      final fixture = await _createHydratedFixture(
        breadcrumbRecorder:
            ({
              required String message,
              required Map<String, Object?> metadata,
            }) async {
              recordedBreadcrumbs.add(<String, Object?>{
                'message': message,
                'metadata': Map<String, Object?>.from(metadata),
              });
            },
      );

      await fixture.container
          .read(authProvider.notifier)
          .signIn('crumb@in.com', 'pw');
      await fixture.container
          .read(authProvider.notifier)
          .signUp('crumb@up.com', 'pw', 'Name');
      await fixture.container.read(authProvider.notifier).signOut();
      await fixture.container.read(authProvider.notifier).signInWithApple();
      await fixture.container.read(authProvider.notifier).signInWithGoogle();

      const expectedBreadcrumbContracts = <Map<String, Object?>>[
        {'message': 'auth.build', 'operation': 'build'},
        {
          'message': 'auth.sign_in',
          'operation': 'sign_in_password',
          'provider': 'password',
        },
        {
          'message': 'auth.sign_up',
          'operation': 'sign_up_password',
          'provider': 'password',
        },
        {'message': 'auth.sign_out', 'operation': 'sign_out'},
        {
          'message': 'auth.sign_in_apple',
          'operation': 'sign_in_apple',
          'provider': 'apple',
        },
        {
          'message': 'auth.sign_in_google',
          'operation': 'sign_in_google',
          'provider': 'google',
        },
      ];
      expect(
        recordedBreadcrumbs,
        hasLength(expectedBreadcrumbContracts.length),
      );
      for (var index = 0; index < expectedBreadcrumbContracts.length; index++) {
        final expected = expectedBreadcrumbContracts[index];
        final entry = recordedBreadcrumbs[index];
        final metadata = entry['metadata']! as Map<String, Object?>;

        expect(entry['message'], expected['message']);
        expect(metadata, containsPair('boundary', 'auth'));
        expect(metadata, containsPair('operation', expected['operation']));

        if (expected.containsKey('provider')) {
          expect(metadata, containsPair('provider', expected['provider']));
        } else {
          expect(metadata.containsKey('provider'), isFalse);
        }
      }
    });

    test(
      'ignores synchronous breadcrumb recorder failures and still signs in',
      () async {
        final fixture = await _createHydratedFixture(
          breadcrumbRecorder:
              ({
                required String message,
                required Map<String, Object?> metadata,
              }) {
                throw StateError('breadcrumb sink failed');
              },
        );

        await fixture.container
            .read(authProvider.notifier)
            .signIn('crumb@in.com', 'pw');

        expect(fixture.repository.signInCallCount, 1);
        expect(
          fixture.container.read(authProvider).value,
          const AuthState.authenticated(
            userId: 'fake-crumb@in.com',
            email: 'crumb@in.com',
          ),
        );
      },
    );

    test('emits structured failure log for failed social sign-in', () async {
      final loggedEvents = <Map<String, Object?>>[];
      final fixture = await _createHydratedFixture(
        repository: FakeAuthRepository(
          signInWithGoogleError: Exception('google sign-in failed'),
        ),
        logger: AppLogger(sink: loggedEvents.add),
      );

      await fixture.container.read(authProvider.notifier).signInWithGoogle();

      expect(fixture.container.read(authProvider).hasError, isTrue);
      expect(
        loggedEvents,
        contains(
          allOf(
            containsPair('event_type', 'auth.sign_in.google'),
            containsPair('outcome', 'failure'),
          ),
        ),
      );
    });
  });

  group('stream-driven auth state changes', () {
    test('stream event updates auth state after initial hydration', () async {
      final repository = FakeAuthRepository();
      final streamController = StreamController<AuthState>();
      final container = _createContainer(
        repository: repository,
        streamController: streamController,
      );
      addTearDown(() {
        container.dispose();
        streamController.close();
      });

      // Keep authProvider alive so the ref.listen subscription stays active.
      final subscription = container.listen(authProvider, (_, __) {});
      addTearDown(subscription.close);
      await _hydrateFromAuthStream(
        container: container,
        streamController: streamController,
        initialAuthState: const AuthState.unauthenticated(),
      );

      expect(
        container.read(authProvider).value,
        const AuthState.unauthenticated(),
      );

      // Simulate external auth event (e.g. sign-in from another tab).
      streamController.add(
        const AuthState.authenticated(
          userId: 'stream-user',
          email: 'stream@example.com',
        ),
      );
      // Allow the stream event and listener to propagate.
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(authProvider).value,
        const AuthState.authenticated(
          userId: 'stream-user',
          email: 'stream@example.com',
        ),
      );
    });

    test('stream sign-out event resets auth state', () async {
      final repository = FakeAuthRepository(
        initialState: const AuthState.authenticated(
          userId: 'seed-user',
          email: 'seed@example.com',
        ),
      );
      final streamController = StreamController<AuthState>();
      final container = _createContainer(
        repository: repository,
        streamController: streamController,
      );
      addTearDown(() {
        container.dispose();
        streamController.close();
      });

      final subscription = container.listen(authProvider, (_, __) {});
      addTearDown(subscription.close);
      await _hydrateFromAuthStream(
        container: container,
        streamController: streamController,
        initialAuthState: const AuthState.authenticated(
          userId: 'seed-user',
          email: 'seed@example.com',
        ),
      );

      streamController.add(const AuthState.unauthenticated());
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(authProvider).value,
        const AuthState.unauthenticated(),
      );
    });

    test(
      'emits structured auth-state transition logs from stream updates',
      () async {
        final loggedEvents = <Map<String, Object?>>[];
        final repository = FakeAuthRepository();
        final streamController = StreamController<AuthState>();
        final container = _createContainer(
          repository: repository,
          streamController: streamController,
          logger: AppLogger(sink: loggedEvents.add),
        );
        addTearDown(() {
          container.dispose();
          streamController.close();
        });

        final subscription = container.listen(authProvider, (_, __) {});
        addTearDown(subscription.close);
        await _hydrateFromAuthStream(
          container: container,
          streamController: streamController,
          initialAuthState: const AuthState.unauthenticated(),
        );
        streamController.add(
          const AuthState.authenticated(
            userId: 'stream-user',
            email: 'stream@example.com',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          loggedEvents,
          contains(
            allOf(
              containsPair('event_type', 'auth.state.transition'),
              containsPair('outcome', 'received'),
            ),
          ),
        );
      },
    );

    test(
      'unauthenticated stream transition invalidates cached saved activities before next user session',
      () async {
        final repository = AuthScopedSavedActivitiesRepository(
          savedSessionsByUserId: {
            'owner-user': [
              _savedSession(id: 101, remoteId: 'owner-remote-activity'),
            ],
            'viewer-user': [
              _savedSession(id: 202, remoteId: 'viewer-remote-activity'),
            ],
          },
        )..currentUserId = 'owner-user';
        final streamController = StreamController<AuthState>();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            // Override with no-op: unit tests do not have a real Drift database.
            localDataCleanupProvider.overrideWithValue(() async {}),
            authStateChangesProvider.overrideWith(
              (ref) => streamController.stream,
            ),
            trackingRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(() {
          container.dispose();
          streamController.close();
        });

        final authSubscription = container.listen(authProvider, (_, __) {});
        addTearDown(authSubscription.close);
        final savedActivitiesSubscription = container.listen(
          savedActivitiesProvider,
          (_, __) {},
        );
        addTearDown(savedActivitiesSubscription.close);

        final initialAuthStateFuture = container.read(authProvider.future);
        streamController.add(
          const AuthState.authenticated(
            userId: 'owner-user',
            email: 'owner@example.com',
          ),
        );
        await initialAuthStateFuture;

        final ownerSessions = await container.read(
          savedActivitiesProvider.future,
        );
        expect(ownerSessions.map((session) => session.id).toList(), [101]);
        expect(repository.loadSavedSessionsCallCount, 1);

        repository.currentUserId = null;
        streamController.add(const AuthState.unauthenticated());
        await Future<void>.delayed(Duration.zero);

        repository.currentUserId = 'viewer-user';
        streamController.add(
          const AuthState.authenticated(
            userId: 'viewer-user',
            email: 'viewer@example.com',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final viewerSessions = await container.read(
          savedActivitiesProvider.future,
        );
        expect(viewerSessions.map((session) => session.id).toList(), [202]);
        expect(repository.loadSavedSessionsCallCount, 2);
      },
    );

    test(
      'unauthenticated stream transition invalidates cached activityDetailProvider so stale session data is not retained',
      () async {
        const ownerSessionId = 101;
        final ownerSession = _savedSession(
          id: ownerSessionId,
          remoteId: 'owner-remote-detail',
        );
        final repository = AuthScopedSavedActivitiesRepository(
          savedSessionsByUserId: const {},
          sessionDetailsByUserId: {
            'owner-user': {ownerSessionId: ownerSession},
            'viewer-user': const <int, TrackingSessionRecord>{},
          },
        )..currentUserId = 'owner-user';
        final streamController = StreamController<AuthState>();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            // Override with no-op: unit tests do not have a real Drift database.
            localDataCleanupProvider.overrideWithValue(() async {}),
            authStateChangesProvider.overrideWith(
              (ref) => streamController.stream,
            ),
            trackingRepositoryProvider.overrideWithValue(repository),
            // profileProvider is a dependency of activityDetailProvider;
            // stub it out so the test stays self-contained.
            profileProvider.overrideWith(_StubProfileNotifier.new),
          ],
        );
        addTearDown(() {
          container.dispose();
          streamController.close();
        });

        // Keep authProvider alive so the ref.listen subscription stays active.
        final authSubscription = container.listen(authProvider, (_, __) {});
        addTearDown(authSubscription.close);
        final detailSubscription = container.listen(
          activityDetailProvider(ownerSessionId),
          (_, __) {},
        );
        addTearDown(detailSubscription.close);

        // Hydrate as owner.
        final initialAuthFuture = container.read(authProvider.future);
        streamController.add(
          const AuthState.authenticated(
            userId: 'owner-user',
            email: 'owner@example.com',
          ),
        );
        await initialAuthFuture;

        // Read owner's activity detail — should return the session.
        final ownerDetail = await container.read(
          activityDetailProvider(ownerSessionId).future,
        );
        expect(ownerDetail?.session.id, ownerSessionId);
        expect(ownerDetail?.session.remoteId, 'owner-remote-detail');
        expect(repository.loadSessionCallCount, 1);

        // Transition to unauthenticated.
        repository.currentUserId = null;
        streamController.add(const AuthState.unauthenticated());
        await Future<void>.delayed(Duration.zero);

        // Transition to viewer.
        repository.currentUserId = 'viewer-user';
        streamController.add(
          const AuthState.authenticated(
            userId: 'viewer-user',
            email: 'viewer@example.com',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        // Read the same sessionId as viewer — should return null because
        // the provider was invalidated and re-fetched for the new user context.
        final viewerDetail = await container.read(
          activityDetailProvider(ownerSessionId).future,
        );
        expect(viewerDetail, isNull);
        // loadSession called exactly twice: once for owner, once after
        // invalidation re-fetch for viewer.
        expect(repository.loadSessionCallCount, 2);
      },
    );

    test(
      'unauthenticated stream transition invalidates cached socialFeedProvider so stale feed data is not retained',
      () async {
        final socialRepository = AuthScopedSocialActivityRepository()
          ..currentUserId = 'owner-user';
        final streamController = StreamController<AuthState>();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            // Override with no-op: unit tests do not have a real Drift database.
            localDataCleanupProvider.overrideWithValue(() async {}),
            authStateChangesProvider.overrideWith(
              (ref) => streamController.stream,
            ),
            socialActivityRepositoryProvider.overrideWithValue(
              socialRepository,
            ),
          ],
        );
        addTearDown(() {
          container.dispose();
          streamController.close();
        });

        final authSubscription = container.listen(authProvider, (_, __) {});
        addTearDown(authSubscription.close);
        final feedSubscription = container.listen(
          socialFeedProvider,
          (_, __) {},
        );
        addTearDown(feedSubscription.close);

        // Hydrate as owner.
        final initialAuthFuture = container.read(authProvider.future);
        streamController.add(
          const AuthState.authenticated(
            userId: 'owner-user',
            email: 'owner@example.com',
          ),
        );
        await initialAuthFuture;

        // Read owner's social feed — should return owner's feed item.
        final ownerFeed = await container.read(socialFeedProvider.future);
        expect(
          ownerFeed.activities.map((activity) => activity.activityId).toList(),
          ['owner-feed-1'],
        );
        expect(socialRepository.loadFeedActivitiesCallCount, 1);

        // Transition to unauthenticated.
        socialRepository.currentUserId = null;
        streamController.add(const AuthState.unauthenticated());
        await Future<void>.delayed(Duration.zero);

        // Transition to viewer.
        socialRepository.currentUserId = 'viewer-user';
        streamController.add(
          const AuthState.authenticated(
            userId: 'viewer-user',
            email: 'viewer@example.com',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        // Read social feed as viewer — should return viewer's feed item,
        // proving the provider was invalidated and re-fetched.
        final viewerFeed = await container.read(socialFeedProvider.future);
        expect(
          viewerFeed.activities.map((activity) => activity.activityId).toList(),
          ['viewer-feed-1'],
        );
        // loadFeedActivities called exactly twice: once for owner, once after
        // invalidation re-fetch for viewer.
        expect(socialRepository.loadFeedActivitiesCallCount, 2);
      },
    );

    test(
      'unauthenticated stream transition invalidates cached remoteActivityDetailProvider so stale remote detail is not retained',
      () async {
        const activityId = 'shared-remote-activity';
        final socialRepository = AuthScopedSocialActivityRepository()
          ..currentUserId = 'owner-user';
        final streamController = StreamController<AuthState>();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            // Override with no-op: unit tests do not have a real Drift database.
            localDataCleanupProvider.overrideWithValue(() async {}),
            authStateChangesProvider.overrideWith(
              (ref) => streamController.stream,
            ),
            socialActivityRepositoryProvider.overrideWithValue(
              socialRepository,
            ),
            // Stub out photo provider — not under test here.
            activityPhotoListProvider(
              activityId,
            ).overrideWith((ref) async => const []),
          ],
        );
        addTearDown(() {
          container.dispose();
          streamController.close();
        });

        final authSubscription = container.listen(authProvider, (_, __) {});
        addTearDown(authSubscription.close);
        final detailSubscription = container.listen(
          remoteActivityDetailProvider(activityId),
          (_, __) {},
        );
        addTearDown(detailSubscription.close);

        // Hydrate as owner.
        final initialAuthFuture = container.read(authProvider.future);
        streamController.add(
          const AuthState.authenticated(
            userId: 'owner-user',
            email: 'owner@example.com',
          ),
        );
        await initialAuthFuture;

        // Read remote activity detail as owner — should return owner-visible detail.
        final ownerDetail = await container.read(
          remoteActivityDetailProvider(activityId).future,
        );
        expect(ownerDetail?.detail.activityId, activityId);
        expect(ownerDetail?.detail.title, 'Owner Visible Detail');
        expect(socialRepository.loadActivityDetailCallCount, 1);

        // Transition to unauthenticated.
        socialRepository.currentUserId = null;
        streamController.add(const AuthState.unauthenticated());
        await Future<void>.delayed(Duration.zero);

        // Transition to viewer.
        socialRepository.currentUserId = 'viewer-user';
        streamController.add(
          const AuthState.authenticated(
            userId: 'viewer-user',
            email: 'viewer@example.com',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        // Read same activity as viewer — should return null because viewer
        // cannot see the private activity, proving provider was invalidated.
        final viewerDetail = await container.read(
          remoteActivityDetailProvider(activityId).future,
        );
        expect(viewerDetail, isNull);
        // loadActivityDetail called exactly twice: once for owner, once after
        // invalidation re-fetch for viewer.
        expect(socialRepository.loadActivityDetailCallCount, 2);
      },
    );

    test(
      'unauthenticated stream transition clears FCM token from backend profile',
      () async {
        final profileRepository = _FakeProfileRepository();
        final streamController = StreamController<AuthState>();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            // Override with no-op: unit tests do not have a real Drift database.
            localDataCleanupProvider.overrideWithValue(() async {}),
            authStateChangesProvider.overrideWith(
              (ref) => streamController.stream,
            ),
            profileRepositoryProvider.overrideWithValue(profileRepository),
          ],
        );
        addTearDown(() {
          container.dispose();
          streamController.close();
        });

        // Keep authProvider alive so the ref.listen subscription stays active.
        final authSubscription = container.listen(authProvider, (_, __) {});
        addTearDown(authSubscription.close);

        // Hydrate as authenticated user.
        final initialAuthFuture = container.read(authProvider.future);
        streamController.add(
          const AuthState.authenticated(
            userId: 'user-with-token',
            email: 'token@example.com',
          ),
        );
        await initialAuthFuture;

        // Verify no FCM token clear has happened yet while authenticated.
        expect(profileRepository.clearFcmTokenCallCount, 0);

        // Transition to unauthenticated — should trigger FCM token cleanup.
        streamController.add(const AuthState.unauthenticated());
        await Future<void>.delayed(Duration.zero);

        // The sign-out cleanup should have called clearFcmToken exactly once
        // to prevent push notifications from routing to the wrong user.
        expect(profileRepository.clearFcmTokenCallCount, 1);
      },
    );
  });
}

/// Fake social activity repository scoped by [currentUserId] to test that
/// auth transitions invalidate social providers correctly.
class AuthScopedSocialActivityRepository implements SocialActivityRepository {
  String? currentUserId;
  int loadFeedActivitiesCallCount = 0;
  int loadActivityDetailCallCount = 0;

  static const _ownerSummary = SocialUserSummary(
    userId: 'owner-user',
    displayName: 'Owner',
    avatarUrl: null,
    relationship: FollowRelationship(
      currentUserId: 'owner-user',
      targetUserId: 'owner-user',
      status: FollowRelationshipStatus.none,
    ),
  );

  @override
  Future<List<SocialActivitySummary>> loadFeedActivities({
    required int offset,
    required int limit,
  }) async {
    loadFeedActivitiesCallCount++;
    switch (currentUserId) {
      case 'owner-user':
        return [
          SocialActivitySummary(
            activityId: 'owner-feed-1',
            owner: _ownerSummary,
            sportType: 'run',
            startedAt: DateTime.utc(2026, 3, 26, 9),
            finishedAt: DateTime.utc(2026, 3, 26, 9, 30),
            distanceMeters: 5000,
            durationSeconds: 1800,
            elevationGainMeters: null,
            avgPaceSecondsPerKm: null,
            title: 'Owner Feed Run',
            description: null,
            visibility: 'private',
            polylineEncoded: null,
            commentCount: 0,
            kudosCount: 0,
            viewerHasKudo: false,
          ),
        ];
      case 'viewer-user':
        return [
          SocialActivitySummary(
            activityId: 'viewer-feed-1',
            owner: _ownerSummary,
            sportType: 'run',
            startedAt: DateTime.utc(2026, 3, 26, 10),
            finishedAt: DateTime.utc(2026, 3, 26, 10, 30),
            distanceMeters: 3000,
            durationSeconds: 1200,
            elevationGainMeters: null,
            avgPaceSecondsPerKm: null,
            title: 'Viewer Feed Run',
            description: null,
            visibility: 'public',
            polylineEncoded: null,
            commentCount: 0,
            kudosCount: 0,
            viewerHasKudo: false,
          ),
        ];
      default:
        return const [];
    }
  }

  @override
  Future<List<SocialActivitySummary>> loadUserActivities(String userId) async {
    return const [];
  }

  @override
  Future<SocialActivityDetail?> loadActivityDetail(String activityId) async {
    loadActivityDetailCallCount++;
    if (currentUserId == 'owner-user') {
      return SocialActivityDetail(
        activityId: activityId,
        owner: _ownerSummary,
        sportType: 'run',
        startedAt: DateTime.utc(2026, 3, 26, 9),
        finishedAt: DateTime.utc(2026, 3, 26, 9, 30),
        distanceMeters: 5000,
        durationSeconds: 1800,
        elevationGainMeters: null,
        avgPaceSecondsPerKm: null,
        title: 'Owner Visible Detail',
        description: null,
        visibility: 'private',
        polylineEncoded: null,
        kudosCount: 0,
        viewerHasKudo: false,
        splits: const [],
        trackPoints: const [],
      );
    }
    // Viewer cannot see private activities — return null.
    return null;
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_controller.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_repository.dart';
import 'package:uff/src/features/auth/data/auth_oauth_config.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_repository.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';

const _defaultOnboardingCompleteProfile = Profile(
  userId: 'stub-user',
  preferredUnits: 'metric',
  defaultActivityVisibility: 'private',
  onboardingCompleted: true,
  displayName: 'Stub User',
);

typedef LabeledFinder = ({String label, Finder finder});

void expectPrimaryActionAboveOAuthDividerAndButtons(
  WidgetTester tester, {
  required LabeledFinder primaryAction,
  required Finder dividerText,
  required List<LabeledFinder> socialAuthButtons,
}) {
  expect(primaryAction.finder, findsOneWidget);
  expect(dividerText, findsOneWidget);
  for (final socialAuthButton in socialAuthButtons) {
    expect(
      socialAuthButton.finder,
      findsOneWidget,
      reason: '${socialAuthButton.label} social auth button should render',
    );
  }

  final primaryActionY = tester.getTopLeft(primaryAction.finder).dy;
  final dividerTextY = tester.getTopLeft(dividerText).dy;
  expect(
    primaryActionY,
    lessThan(dividerTextY),
    reason: '${primaryAction.label} button must render above the OAuth divider',
  );
  for (final socialAuthButton in socialAuthButtons) {
    final socialAuthButtonY = tester.getTopLeft(socialAuthButton.finder).dy;
    expect(
      dividerTextY,
      lessThan(socialAuthButtonY),
      reason:
          'OAuth divider must render above the ${socialAuthButton.label} button',
    );
  }
}

class _AuthTestProfileNotifier extends ProfileNotifier {
  _AuthTestProfileNotifier(this.profile);

  final Profile profile;

  @override
  Profile? build() => profile;
}

/// TODO: Document RecordingAuthRepository.
class RecordingAuthRepository implements AuthRepository {
  RecordingAuthRepository({
    AuthState initialState = const AuthState.unauthenticated(),
    this.memberSinceResult,
  }) : _session = initialState;

  AuthState _session;
  String? signInEmail;
  String? signInPassword;
  String? signUpEmail;
  String? signUpPassword;
  String? signUpDisplayName;
  int signInWithAppleCallCount = 0;
  int signInWithGoogleCallCount = 0;
  int signOutCallCount = 0;
  int updatePasswordCallCount = 0;
  String? lastUpdatedPassword;
  List<String> connectedProvidersResult = const <String>[];
  DateTime? memberSinceResult;

  @override
  Future<AuthState> getCurrentSession() async => _session;

  @override
  AuthState getCurrentSessionSync() => _session;

  @override
  Future<AuthState> signIn({
    required String email,
    required String password,
  }) async {
    signInEmail = email;
    signInPassword = password;
    _session = AuthState.authenticated(userId: 'stub-$email', email: email);
    return _session;
  }

  @override
  Future<AuthState> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    signUpEmail = email;
    signUpPassword = password;
    signUpDisplayName = displayName;
    _session = AuthState.authenticated(userId: 'stub-$email', email: email);
    return _session;
  }

  @override
  Future<AuthState> signInWithApple() async {
    signInWithAppleCallCount++;
    _session = const AuthState.authenticated(
      userId: 'stub-apple-user',
      email: 'apple@example.com',
    );
    return _session;
  }

  @override
  Future<AuthState> signInWithGoogle() async {
    signInWithGoogleCallCount++;
    _session = const AuthState.authenticated(
      userId: 'stub-google-user',
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
  Future<void> updatePassword(String newPassword) async {
    updatePasswordCallCount++;
    lastUpdatedPassword = newPassword;
  }

  @override
  Future<List<String>> connectedProviders() async {
    return connectedProvidersResult;
  }

  @override
  DateTime? memberSince() {
    return memberSinceResult;
  }
}

/// TODO: Document DelayedSignInAuthRepository.
class DelayedSignInAuthRepository implements AuthRepository {
  DelayedSignInAuthRepository({
    AuthState initialState = const AuthState.unauthenticated(),
    this.delaySignUp = false,
    this.delaySignOut = false,
  }) : _session = initialState;

  final Completer<AuthState> _signInCompleter = Completer<AuthState>();
  final Completer<AuthState> _signUpCompleter = Completer<AuthState>();
  final Completer<void> _signOutCompleter = Completer<void>();
  AuthState _session;
  final bool delaySignUp;
  final bool delaySignOut;
  int signInCallCount = 0;
  int signUpCallCount = 0;
  int signOutCallCount = 0;
  int signInWithAppleCallCount = 0;
  int signInWithGoogleCallCount = 0;

  void completeSignIn(AuthState nextState) {
    if (!_signInCompleter.isCompleted) {
      _session = nextState;
      _signInCompleter.complete(nextState);
    }
  }

  void completeSignUp(AuthState nextState) {
    if (!_signUpCompleter.isCompleted) {
      _session = nextState;
      _signUpCompleter.complete(nextState);
    }
  }

  void completeSignOut() {
    if (!_signOutCompleter.isCompleted) {
      _session = const AuthState.unauthenticated();
      _signOutCompleter.complete();
    }
  }

  @override
  Future<AuthState> getCurrentSession() async => _session;

  @override
  AuthState getCurrentSessionSync() => _session;

  @override
  Future<AuthState> signIn({required String email, required String password}) {
    signInCallCount++;
    return _signInCompleter.future;
  }

  @override
  Future<AuthState> signUp({
    required String email,
    required String password,
    required String displayName,
  }) {
    signUpCallCount++;
    if (!delaySignUp) {
      _session = AuthState.authenticated(userId: 'stub-$email', email: email);
      return Future<AuthState>.value(_session);
    }
    return _signUpCompleter.future;
  }

  @override
  Future<AuthState> signInWithApple() async {
    signInWithAppleCallCount++;
    _session = const AuthState.authenticated(
      userId: 'stub-apple-user',
      email: 'apple@example.com',
    );
    return _session;
  }

  @override
  Future<AuthState> signInWithGoogle() async {
    signInWithGoogleCallCount++;
    _session = const AuthState.authenticated(
      userId: 'stub-google-user',
      email: 'google@example.com',
    );
    return _session;
  }

  @override
  Future<void> signOut() {
    signOutCallCount++;
    if (!delaySignOut) {
      _session = const AuthState.unauthenticated();
      return Future<void>.value();
    }
    return _signOutCompleter.future;
  }

  @override
  Future<void> updatePassword(String newPassword) async {}

  @override
  Future<List<String>> connectedProviders() async {
    return const <String>[];
  }

  @override
  DateTime? memberSince() {
    return null;
  }
}

/// NOTE(stuart): Document AuthTestTrackingRepository.
class AuthTestTrackingRepository implements TrackingRepository {
  @override
  Future<TrackingSessionRecord> createSession() async {
    return TrackingSessionRecord(
      id: 1,
      status: TrackingSessionStatus.idle,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );
  }

  @override
  Future<void> appendPointBatch(List<TrackingPoint> points) async {}

  @override
  Future<List<TrackingSessionRecord>> loadSavedSessions() async {
    return const [];
  }

  @override
  FutureOr<TrackingSessionRecord?> loadSession(int sessionId) {
    return null;
  }

  @override
  Future<List<TrackingPoint>> loadPointsForSession(int sessionId) async {
    return [];
  }

  @override
  Future<void> saveSession(TrackingSessionRecord session) async {}

  @override
  Future<void> updateSessionStatus(
    int sessionId,
    TrackingSessionStatus status,
    DateTime at,
  ) async {}

  @override
  Future<void> finalizeSession(int sessionId) async {}

  @override
  Future<void> discardSession(int sessionId) async {}

  @override
  Future<TrackingSessionRecord?> loadActiveSession() async {
    return null;
  }

  @override
  Future<void> updateSessionRemoteId(int sessionId, String remoteId) async {}

  @override
  Future<void> upsertSyncQueueEntry({
    required int sessionId,
    required SyncQueueEntryStatus status,
    required DateTime queuedAt,
    int retryCount = 0,
    String? lastError,
  }) async {}

  @override
  Future<List<SyncQueueEntry>> loadPendingSyncQueueEntries() async {
    return const [];
  }

  @override
  Future<SyncQueueEntry?> loadSyncQueueEntry(int sessionId) async {
    return null;
  }

  @override
  Future<void> updateSyncQueueEntryStatus({
    required int sessionId,
    required SyncQueueEntryStatus status,
    int? retryCount,
    String? lastError,
  }) async {}

  @override
  Future<void> deleteActivity(int sessionId) async {}

  @override
  Future<int> saveImportedSession(
    TrackingSessionRecord session,
    List<TrackingPoint> points,
  ) async {
    return 0;
  }
}

Widget buildAuthTestScope({
  required AuthRepository repository,
  required Widget child,
  TrackingRepository? trackingRepository,
  Profile profile = _defaultOnboardingCompleteProfile,
  AuthOAuthConfig authOAuthConfig = const AuthOAuthConfig(
    googleWebClientId: 'test-google-web-client-id',
    googleIosClientId: 'test-google-ios-client-id',
    isAppleSignInEnabled: true,
    isGoogleSignInEnabled: true,
  ),
  AuthState initialAuthState = const AuthState.unauthenticated(),
  Stream<AuthState>? authStateChanges,
}) {
  final authStateStream =
      authStateChanges ?? Stream<AuthState>.value(initialAuthState);

  return ProviderScope(
    overrides: [
      authOAuthConfigProvider.overrideWithValue(authOAuthConfig),
      authRepositoryProvider.overrideWithValue(repository),
      authStateChangesProvider.overrideWith((ref) => authStateStream),
      profileProvider.overrideWith(() => _AuthTestProfileNotifier(profile)),
      if (trackingRepository != null)
        trackingRepositoryProvider.overrideWithValue(trackingRepository),
    ],
    child: child,
  );
}

/// TODO: Document ThrowingAuthRepository.
class ThrowingAuthRepository implements AuthRepository {
  ThrowingAuthRepository({this.signInError, this.signUpError});

  final Exception? signInError;
  final Exception? signUpError;

  @override
  Future<AuthState> getCurrentSession() async {
    return const AuthState.unauthenticated();
  }

  @override
  AuthState getCurrentSessionSync() => const AuthState.unauthenticated();

  @override
  Future<AuthState> signIn({
    required String email,
    required String password,
  }) async {
    if (signInError != null) throw signInError!;
    return AuthState.authenticated(userId: 'stub-$email', email: email);
  }

  @override
  Future<AuthState> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    if (signUpError != null) throw signUpError!;
    return AuthState.authenticated(userId: 'stub-$email', email: email);
  }

  @override
  Future<AuthState> signInWithApple() async {
    if (signInError != null) throw signInError!;
    return const AuthState.authenticated(
      userId: 'stub-apple-user',
      email: 'apple@example.com',
    );
  }

  @override
  Future<AuthState> signInWithGoogle() async {
    if (signInError != null) throw signInError!;
    return const AuthState.authenticated(
      userId: 'stub-google-user',
      email: 'google@example.com',
    );
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> updatePassword(String newPassword) async {}

  @override
  Future<List<String>> connectedProviders() async {
    return const <String>[];
  }

  @override
  DateTime? memberSince() {
    return null;
  }
}

// TODO(uff): Document ConfirmationPendingAuthRepository.
/// TODO: Document ConfirmationPendingAuthRepository.
class ConfirmationPendingAuthRepository implements AuthRepository {
  @override
  Future<AuthState> getCurrentSession() async {
    return const AuthState.unauthenticated();
  }

  @override
  AuthState getCurrentSessionSync() => const AuthState.unauthenticated();

  @override
  Future<AuthState> signIn({
    required String email,
    required String password,
  }) async {
    return AuthState.authenticated(userId: 'stub-$email', email: email);
  }

  @override
  Future<AuthState> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    return const AuthState.unauthenticated();
  }

  @override
  Future<AuthState> signInWithApple() async {
    return const AuthState.authenticated(
      userId: 'stub-apple-user',
      email: 'apple@example.com',
    );
  }

  @override
  Future<AuthState> signInWithGoogle() async {
    return const AuthState.authenticated(
      userId: 'stub-google-user',
      email: 'google@example.com',
    );
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> updatePassword(String newPassword) async {}

  @override
  Future<List<String>> connectedProviders() async {
    return const <String>[];
  }

  @override
  DateTime? memberSince() {
    return null;
  }
}

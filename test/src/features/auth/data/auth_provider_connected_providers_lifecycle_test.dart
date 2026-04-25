import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_repository.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';

// ## Test Scenarios
// - [negative] Viewer does not inherit previous user's connected provider badges after account switch
// - [isolation] Unauthenticated transition invalidates cached connectedProvidersProvider so stale provider badges are not retained
void main() {
  group('connectedProvidersProvider lifecycle', () {
    test(
      'unauthenticated stream transition invalidates cached connectedProvidersProvider so stale provider badges are not retained',
      () async {
        final repository = _ConnectedProvidersAuthRepository()
          ..connectedProvidersValue = const <String>['apple'];
        final streamController = StreamController<AuthState>();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(repository),
            localDataCleanupProvider.overrideWithValue(() async {}),
            authStateChangesProvider.overrideWith(
              (ref) => streamController.stream,
            ),
          ],
        );
        addTearDown(() {
          container.dispose();
          streamController.close();
        });

        final authSubscription = container.listen(authProvider, (_, __) {});
        addTearDown(authSubscription.close);
        final connectedProvidersSubscription = container.listen(
          connectedProvidersProvider,
          (_, __) {},
        );
        addTearDown(connectedProvidersSubscription.close);

        final initialAuthFuture = container.read(authProvider.future);
        streamController.add(
          const AuthState.authenticated(
            userId: 'owner-user',
            email: 'owner@example.com',
          ),
        );
        await initialAuthFuture;

        final ownerConnectedProviders = await container.read(
          connectedProvidersProvider.future,
        );
        expect(ownerConnectedProviders, const <String>['apple']);
        expect(repository.connectedProvidersCallCount, 1);

        repository.connectedProvidersValue = const <String>[];
        streamController.add(const AuthState.unauthenticated());
        await Future<void>.delayed(Duration.zero);

        repository.connectedProvidersValue = const <String>['google'];
        streamController.add(
          const AuthState.authenticated(
            userId: 'viewer-user',
            email: 'viewer@example.com',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final viewerConnectedProviders = await container.read(
          connectedProvidersProvider.future,
        );
        expect(viewerConnectedProviders, const <String>['google']);
        expect(repository.connectedProvidersCallCount, 2);
      },
    );
  });
}

class _ConnectedProvidersAuthRepository implements AuthRepository {
  AuthState _session = const AuthState.unauthenticated();

  int connectedProvidersCallCount = 0;
  List<String> connectedProvidersValue = const <String>[];

  @override
  Future<List<String>> connectedProviders() async {
    connectedProvidersCallCount++;
    return connectedProvidersValue;
  }

  @override
  Future<AuthState> getCurrentSession() async {
    return _session;
  }

  @override
  AuthState getCurrentSessionSync() {
    return _session;
  }

  @override
  DateTime? memberSince() => null;

  @override
  Future<AuthState> signIn({
    required String email,
    required String password,
  }) async {
    _session = AuthState.authenticated(userId: 'stub-$email', email: email);
    return _session;
  }

  @override
  Future<AuthState> signInWithApple() async {
    _session = const AuthState.authenticated(
      userId: 'stub-apple-user',
      email: 'apple@example.com',
    );
    return _session;
  }

  @override
  Future<AuthState> signInWithGoogle() async {
    _session = const AuthState.authenticated(
      userId: 'stub-google-user',
      email: 'google@example.com',
    );
    return _session;
  }

  @override
  Future<void> signOut() async {
    _session = const AuthState.unauthenticated();
  }

  @override
  Future<AuthState> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _session = AuthState.authenticated(userId: 'stub-$email', email: email);
    return _session;
  }

  @override
  Future<void> updatePassword(String newPassword) async {}
}

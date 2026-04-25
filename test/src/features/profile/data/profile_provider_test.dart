import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/profile/data/profile_repository.dart';

// ## Test Scenarios
// - [positive] Auto-loads profile when user is authenticated
// - [negative] Unauthenticated users read a null profile without repository access
// - [isolation] Authenticated profile loads use only the current auth user ID
// - [edge] Returns null when unauthenticated or auth loading
// - [positive] updateProfile updates provider state
// - [edge] Preserves null lthrBpm through update cycle
// - [error] updateProfile restores the previous profile and rethrows write failures

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class FakeProfileRepository implements ProfileRepository {
  Profile? profileToReturn;
  Exception? updateProfileException;
  int getProfileCallCount = 0;
  int updateProfileCallCount = 0;
  String? lastGetProfileUserId;
  Profile? lastUpdatedProfile;

  @override
  Future<Profile> getProfile(String userId) async {
    getProfileCallCount++;
    lastGetProfileUserId = userId;
    if (profileToReturn == null) {
      throw StateError('No profile configured for test');
    }
    return profileToReturn!;
  }

  @override
  Future<Profile> updateProfile(Profile profile) async {
    updateProfileCallCount++;
    lastUpdatedProfile = profile;
    final writeFailure = updateProfileException;
    if (writeFailure != null) {
      throw writeFailure;
    }
    return profile;
  }

  @override
  Future<void> updateFcmToken(String? token) async {}

  @override
  Future<void> clearFcmToken() async {}

  @override
  Future<String> uploadAvatar(
    String userId,
    dynamic bytes,
    String fileName,
  ) async {
    return 'https://storage.example.com/avatars/$userId/$fileName';
  }

  @override
  Future<Map<String, dynamic>> exportMyData() async {
    return <String, dynamic>{
      'profiles': <dynamic>[],
      'activities': <dynamic>[],
    };
  }

  @override
  Future<void> deleteMyAccount() async {}
}

const _testProfile = Profile(
  userId: 'user-1',
  preferredUnits: 'metric',
  defaultActivityVisibility: 'private',
  onboardingCompleted: true,
  displayName: 'Alice',
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProviderContainer _createContainer({
  required FakeProfileRepository profileRepo,
  required AsyncValue<AuthState> authState,
  StreamController<AuthState>? authStreamController,
}) {
  return ProviderContainer(
    overrides: [
      profileRepositoryProvider.overrideWithValue(profileRepo),
      authProvider.overrideWith(() => _FakeAuthNotifier(authState)),
      if (authStreamController != null)
        authStateChangesProvider.overrideWith(
          (ref) => authStreamController.stream,
        ),
    ],
  );
}

class _FakeAuthNotifier extends Auth {
  _FakeAuthNotifier(this._initialState);
  final AsyncValue<AuthState> _initialState;

  @override
  FutureOr<AuthState> build() {
    final data = _initialState.asData;
    if (data != null) return data.value;
    throw StateError('Auth not data');
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('profileProvider', () {
    test('auto-loads profile when auth is authenticated', () async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = _testProfile;

      final container = _createContainer(
        profileRepo: profileRepo,
        authState: const AsyncData(
          AuthState.authenticated(userId: 'user-1', email: 'a@b.com'),
        ),
      );
      addTearDown(container.dispose);

      // Keep provider alive
      final sub = container.listen(profileProvider, (_, __) {});
      addTearDown(sub.close);

      final profile = await container.read(profileProvider.future);

      expect(profile, _testProfile);
      expect(profileRepo.getProfileCallCount, 1);
      expect(profileRepo.lastGetProfileUserId, 'user-1');
    });

    test('returns null when auth is unauthenticated', () async {
      final profileRepo = FakeProfileRepository();

      final container = _createContainer(
        profileRepo: profileRepo,
        authState: const AsyncData(AuthState.unauthenticated()),
      );
      addTearDown(container.dispose);

      final sub = container.listen(profileProvider, (_, __) {});
      addTearDown(sub.close);

      final profile = await container.read(profileProvider.future);

      expect(profile, isNull);
      expect(profileRepo.getProfileCallCount, 0);
    });

    test('returns null when auth is loading', () async {
      final profileRepo = FakeProfileRepository();

      final container = _createContainer(
        profileRepo: profileRepo,
        authState: const AsyncLoading<AuthState>(),
      );
      addTearDown(container.dispose);

      final sub = container.listen(profileProvider, (_, __) {});
      addTearDown(sub.close);

      final profile = await container.read(profileProvider.future);

      expect(profile, isNull);
      expect(profileRepo.getProfileCallCount, 0);
    });

    test('updateProfile updates state with returned Profile', () async {
      final profileRepo = FakeProfileRepository()
        ..profileToReturn = _testProfile;

      final container = _createContainer(
        profileRepo: profileRepo,
        authState: const AsyncData(
          AuthState.authenticated(userId: 'user-1', email: 'a@b.com'),
        ),
      );
      addTearDown(container.dispose);

      final sub = container.listen(profileProvider, (_, __) {});
      addTearDown(sub.close);

      // Wait for initial load
      await container.read(profileProvider.future);

      // Update profile
      const updatedProfile = Profile(
        userId: 'user-1',
        preferredUnits: 'imperial',
        defaultActivityVisibility: 'private',
        onboardingCompleted: true,
        displayName: 'Alice Updated',
        lthrBpm: 170,
      );

      await container
          .read(profileProvider.notifier)
          .updateProfile(updatedProfile);

      final result = container.read(profileProvider).value;
      expect(result, updatedProfile);
      expect(profileRepo.updateProfileCallCount, 1);
      expect(profileRepo.lastUpdatedProfile, updatedProfile);
    });

    test(
      'updateProfile preserves explicit null lthrBpm when user clears it',
      () async {
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = const Profile(
            userId: 'user-1',
            preferredUnits: 'metric',
            defaultActivityVisibility: 'private',
            onboardingCompleted: true,
            displayName: 'Alice',
            lthrBpm: 165,
          );

        final container = _createContainer(
          profileRepo: profileRepo,
          authState: const AsyncData(
            AuthState.authenticated(userId: 'user-1', email: 'a@b.com'),
          ),
        );
        addTearDown(container.dispose);

        final sub = container.listen(profileProvider, (_, __) {});
        addTearDown(sub.close);

        await container.read(profileProvider.future);

        const clearedProfile = Profile(
          userId: 'user-1',
          preferredUnits: 'metric',
          defaultActivityVisibility: 'private',
          onboardingCompleted: true,
          displayName: 'Alice',
        );

        await container
            .read(profileProvider.notifier)
            .updateProfile(clearedProfile);

        final result = container.read(profileProvider).value;
        expect(result, clearedProfile);
        expect(profileRepo.updateProfileCallCount, 1);
        expect(profileRepo.lastUpdatedProfile!.lthrBpm, isNull);
      },
    );

    test(
      'updateProfile restores previous state and rethrows write failures',
      () async {
        final writeFailure = Exception('write failed');
        final profileRepo = FakeProfileRepository()
          ..profileToReturn = _testProfile
          ..updateProfileException = writeFailure;

        final container = _createContainer(
          profileRepo: profileRepo,
          authState: const AsyncData(
            AuthState.authenticated(userId: 'user-1', email: 'a@b.com'),
          ),
        );
        addTearDown(container.dispose);

        final sub = container.listen(profileProvider, (_, __) {});
        addTearDown(sub.close);

        await container.read(profileProvider.future);

        const updatedProfile = Profile(
          userId: 'user-1',
          preferredUnits: 'imperial',
          defaultActivityVisibility: 'followers',
          onboardingCompleted: true,
          displayName: 'Failed Write',
          lthrBpm: 172,
        );

        try {
          await container
              .read(profileProvider.notifier)
              .updateProfile(updatedProfile);
          fail(
            'Expected updateProfile to rethrow the repository write failure',
          );
        } on Exception catch (error) {
          expect(identical(error, writeFailure), true);
        }

        final restoredState = container.read(profileProvider);
        expect(restoredState.asData?.value, _testProfile);
        expect(restoredState.hasError, false);
        expect(profileRepo.updateProfileCallCount, 1);
        expect(profileRepo.lastUpdatedProfile, updatedProfile);
      },
    );
  });
}

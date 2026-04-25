part of 'onboarding_screen_test.dart';

/// TODO: Document _RecordingProfileNotifier.
class _RecordingProfileNotifier extends ProfileNotifier {
  _RecordingProfileNotifier(this._profile);

  final Profile _profile;
  int updateProfileCallCount = 0;
  Profile? lastUpdatedProfile;

  @override
  Profile? build() {
    return _profile;
  }

  @override
  Future<void> updateProfile(Profile profile) async {
    updateProfileCallCount++;
    lastUpdatedProfile = profile;
    state = AsyncValue.data(profile);
  }
}

/// TODO: Document _RetryingProfileNotifier.
class _RetryingProfileNotifier extends ProfileNotifier {
  _RetryingProfileNotifier({
    this.profile,
    this.failBuild = false,
    this.returnNullProfile = false,
  });

  final Profile? profile;
  bool failBuild;
  bool returnNullProfile;
  int buildCallCount = 0;

  @override
  Future<Profile?> build() async {
    buildCallCount++;
    if (failBuild) {
      throw Exception('profile fetch failed');
    }
    if (returnNullProfile) {
      return null;
    }
    return profile;
  }
}

/// TODO: Document _DelayedUpdateProfileNotifier.
class _DelayedUpdateProfileNotifier extends ProfileNotifier {
  _DelayedUpdateProfileNotifier(this._profile);

  final Profile _profile;
  int updateProfileCallCount = 0;
  Profile? lastUpdatedProfile;
  Completer<void>? _pendingUpdateCompleter;

  @override
  Profile? build() {
    return _profile;
  }

  @override
  Future<void> updateProfile(Profile profile) {
    updateProfileCallCount++;
    lastUpdatedProfile = profile;
    state = const AsyncValue.loading();
    _pendingUpdateCompleter ??= Completer<void>();
    return _pendingUpdateCompleter!.future;
  }

  Future<void> finishPendingUpdate() async {
    final pendingUpdateCompleter = _pendingUpdateCompleter;
    if (pendingUpdateCompleter == null || pendingUpdateCompleter.isCompleted) {
      return;
    }

    pendingUpdateCompleter.complete();
    await pendingUpdateCompleter.future;
    state = AsyncValue.data(lastUpdatedProfile);
  }
}

/// TODO: Document _FailingSubmitProfileRepository.
class _FailingSubmitProfileRepository implements ProfileRepository {
  _FailingSubmitProfileRepository({required this.profile});

  final Profile profile;
  int getProfileCallCount = 0;
  int updateProfileCallCount = 0;

  @override
  Future<Profile> getProfile(String userId) async {
    getProfileCallCount++;
    return profile;
  }

  @override
  Future<Profile> updateProfile(Profile profile) async {
    updateProfileCallCount++;
    throw Exception('update profile failed');
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
    return 'https://example.com/$userId/$fileName';
  }

  @override
  Future<Map<String, dynamic>> exportMyData() async {
    return const <String, dynamic>{
      'profiles': <dynamic>[],
      'activities': <dynamic>[],
    };
  }

  @override
  Future<void> deleteMyAccount() async {}
}

class _StaticAuthNotifier extends Auth {
  _StaticAuthNotifier(this._authState);

  final AuthState _authState;

  @override
  FutureOr<AuthState> build() {
    return _authState;
  }
}

Future<void> _pumpOnboarding(
  WidgetTester tester, {
  required ProfileNotifier profileNotifier,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [profileProvider.overrideWith(() => profileNotifier)],
      child: const MaterialApp(home: OnboardingScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpOnboardingWithProfileRepository(
  WidgetTester tester, {
  required ProfileRepository profileRepository,
  required AuthState authState,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _StaticAuthNotifier(authState)),
        profileRepositoryProvider.overrideWithValue(profileRepository),
      ],
      child: const MaterialApp(home: OnboardingScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapContinue(WidgetTester tester) async {
  await _tapAndSettle(
    tester,
    find.byKey(const Key('onboarding_continue_button')),
  );
}

Future<void> _tapBack(WidgetTester tester) async {
  await _tapAndSettle(tester, find.byKey(const Key('onboarding_back_button')));
}

Future<void> _tapRetry(WidgetTester tester) async {
  await _tapAndSettle(tester, find.byKey(const Key('onboarding_retry_button')));
}

Future<void> _goToSportStep(WidgetTester tester) async {
  await _tapContinue(tester);
}

Future<void> _goToUnitsStep(WidgetTester tester) async {
  await _goToSportStep(tester);
  await _tapContinue(tester);
}

Future<void> _goToPrivacyStep(WidgetTester tester) async {
  await _goToUnitsStep(tester);
  await _tapContinue(tester);
}

FilterChip _sportChip(WidgetTester tester, String sportId) {
  return tester.widget<FilterChip>(find.byKey(Key('sport_chip_$sportId')));
}

Future<void> _selectCustomOnboardingChoices(WidgetTester tester) async {
  await _goToSportStep(tester);
  await _tapAndSettle(tester, find.byKey(const Key('sport_chip_ride')));

  await _tapContinue(tester);
  await _tapAndSettle(tester, find.byKey(const Key('units_option_imperial')));

  await _tapContinue(tester);
  await _tapAndSettle(
    tester,
    find.byKey(const Key('visibility_option_followers')),
  );
}

void _expectSubmittedProfile(
  _RecordingProfileNotifier notifier, {
  required String preferredUnits,
  required String defaultActivityVisibility,
  required List<String> sportPreferences,
}) {
  final submittedProfile = notifier.lastUpdatedProfile!;
  expect(notifier.updateProfileCallCount, 1);
  expect(submittedProfile.onboardingCompleted, isTrue);
  expect(submittedProfile.preferredUnits, preferredUnits);
  expect(submittedProfile.defaultActivityVisibility, defaultActivityVisibility);
  expect(submittedProfile.sportPreferences, sportPreferences);
}

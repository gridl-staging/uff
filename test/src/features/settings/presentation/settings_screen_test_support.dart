import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/core/telemetry/telemetry_enablement.dart';
import 'package:uff/src/core/theme/theme_providers.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_repository.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/legal/presentation/legal_routes.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/profile/presentation/profile_routes.dart';
import 'package:uff/src/features/settings/presentation/settings_routes.dart';
import 'package:uff/src/features/settings/presentation/settings_screen.dart';

import '../../auth/presentation/auth_test_support.dart';
import '../../profile/presentation/profile_screen_test_support.dart';

const settingsPopExitRouteText = 'Settings Exit Route';

const _authenticatedAuthState = AuthState.authenticated(
  userId: 'user-1',
  email: 'a@b.com',
);

/// TODO: Document _SettingsProfileNotifier.
class _SettingsProfileNotifier extends ProfileNotifier {
  _SettingsProfileNotifier(this._profileRepository);

  final FakeProfileRepository _profileRepository;

  @override
  FutureOr<Profile?> build() {
    return _profileRepository.profileToReturn;
  }

  @override
  Future<void> updateProfile(Profile profile) async {
    state = const AsyncLoading<Profile?>();
    state = await AsyncValue.guard(() async {
      final updatedProfile = await _profileRepository.updateProfile(profile);
      _profileRepository.profileToReturn = updatedProfile;
      return updatedProfile;
    });
  }
}

class _SettingsThemeModeNotifier extends ThemeModeNotifier {
  _SettingsThemeModeNotifier(this._initialThemeMode);

  final ThemeMode _initialThemeMode;

  @override
  ThemeMode build() => _initialThemeMode;

  @override
  Future<void> setThemeMode(ThemeMode themeMode) async {
    state = themeMode;
  }
}

class _SettingsTelemetryEnablementNotifier extends TelemetryEnablementNotifier {
  _SettingsTelemetryEnablementNotifier({
    required bool initialTelemetryEnabled,
  }) : _initialTelemetryEnabled = initialTelemetryEnabled;

  final bool _initialTelemetryEnabled;

  @override
  bool build() => _initialTelemetryEnabled;

  @override
  Future<void> setTelemetryEnabled({required bool isEnabled}) async {
    state = isEnabled;
  }
}

typedef SettingsProfileNotifierFactory =
    ProfileNotifier Function(FakeProfileRepository profileRepository);

Widget _buildSettingsTestScope({
  required FakeProfileRepository profileRepo,
  required Widget child,
  AuthRepository? authRepo,
  AuthState authState = _authenticatedAuthState,
  ThemeMode initialThemeMode = ThemeMode.system,
  bool initialTelemetryEnabled = true,
  SettingsProfileNotifierFactory? profileNotifierFactory,
}) {
  profileRepo.profileToReturn ??= testProfile;
  final authRepository =
      authRepo ?? RecordingAuthRepository(initialState: authState);

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepository),
      authStateChangesProvider.overrideWith((ref) => Stream.value(authState)),
      profileRepositoryProvider.overrideWithValue(profileRepo),
      profileProvider.overrideWith(
        () =>
            profileNotifierFactory?.call(profileRepo) ??
            _SettingsProfileNotifier(profileRepo),
      ),
      themeModeProvider.overrideWith(
        () => _SettingsThemeModeNotifier(initialThemeMode),
      ),
      telemetryEnablementProvider.overrideWith(
        () => _SettingsTelemetryEnablementNotifier(
          initialTelemetryEnabled: initialTelemetryEnabled,
        ),
      ),
    ],
    child: child,
  );
}

Widget buildSettingsTestScope({
  required FakeProfileRepository profileRepo,
  AuthRepository? authRepo,
  ThemeMode initialThemeMode = ThemeMode.system,
  bool initialTelemetryEnabled = true,
  SettingsProfileNotifierFactory? profileNotifierFactory,
}) {
  return _buildSettingsTestScope(
    profileRepo: profileRepo,
    authRepo: authRepo,
    initialThemeMode: initialThemeMode,
    initialTelemetryEnabled: initialTelemetryEnabled,
    profileNotifierFactory: profileNotifierFactory,
    child: const MaterialApp(home: SettingsScreen()),
  );
}

Widget buildSettingsRouterTestScope({
  required FakeProfileRepository profileRepo,
  AuthRepository? authRepo,
  ThemeMode initialThemeMode = ThemeMode.system,
  bool initialTelemetryEnabled = true,
  SettingsProfileNotifierFactory? profileNotifierFactory,
}) {
  final router = GoRouter(
    initialLocation: SettingsRoutes.settingsPath,
    routes: [
      GoRoute(
        path: SettingsRoutes.settingsPath,
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: ProfileRoutes.privacyZonesPath,
        builder: (_, __) => const Scaffold(body: Text('Privacy Zones Target')),
      ),
      GoRoute(
        path: SettingsRoutes.hrZonesPath,
        builder: (_, __) => const Scaffold(body: Text('HR Zones Target')),
      ),
      GoRoute(
        path: LegalRoutes.privacyPath,
        builder: (_, __) => const Scaffold(body: Text('Privacy Policy Target')),
      ),
      GoRoute(
        path: LegalRoutes.termsPath,
        builder: (_, __) =>
            const Scaffold(body: Text('Terms of Service Target')),
      ),
    ],
  );
  addTearDown(router.dispose);

  return _buildSettingsTestScope(
    profileRepo: profileRepo,
    authRepo: authRepo,
    initialThemeMode: initialThemeMode,
    initialTelemetryEnabled: initialTelemetryEnabled,
    profileNotifierFactory: profileNotifierFactory,
    child: MaterialApp.router(routerConfig: router),
  );
}

Widget buildPoppableSettingsRouterTestScope({
  required FakeProfileRepository profileRepo,
  AuthRepository? authRepo,
  ThemeMode initialThemeMode = ThemeMode.system,
  bool initialTelemetryEnabled = true,
  SettingsProfileNotifierFactory? profileNotifierFactory,
}) {
  final router = GoRouter(
    initialLocation: '/stack/home/settings',
    routes: [
      GoRoute(
        path: '/stack',
        builder: (_, __) =>
            const Scaffold(body: Text(settingsPopExitRouteText)),
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, __, navigationShell) => navigationShell,
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'home/settings',
                    builder: (_, __) => const SettingsScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: ProfileRoutes.privacyZonesPath,
        builder: (_, __) => const Scaffold(body: Text('Privacy Zones Target')),
      ),
      GoRoute(
        path: SettingsRoutes.hrZonesPath,
        builder: (_, __) => const Scaffold(body: Text('HR Zones Target')),
      ),
      GoRoute(
        path: LegalRoutes.privacyPath,
        builder: (_, __) => const Scaffold(body: Text('Privacy Policy Target')),
      ),
      GoRoute(
        path: LegalRoutes.termsPath,
        builder: (_, __) =>
            const Scaffold(body: Text('Terms of Service Target')),
      ),
    ],
  );
  addTearDown(router.dispose);

  return _buildSettingsTestScope(
    profileRepo: profileRepo,
    authRepo: authRepo,
    initialThemeMode: initialThemeMode,
    initialTelemetryEnabled: initialTelemetryEnabled,
    profileNotifierFactory: profileNotifierFactory,
    child: MaterialApp.router(routerConfig: router),
  );
}

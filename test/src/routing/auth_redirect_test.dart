/// ## Test Scenarios
/// - [positive] Splash redirects unauthenticated users to sign in and authenticated users to home
/// - [positive] Authenticated onboarded users stay on valid in-session routes
/// - [negative] Unauthenticated users are blocked from protected routes
/// - [negative] Onboarded users are redirected away from onboarding routes
/// - [isolation] Public legal routes remain accessible while signed out
/// - [isolation] Auth/profile loading and error states avoid destructive route jumps
/// - [edge] Profile-missing redirects remain shell-agnostic for nested home routes

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/legal/presentation/legal_routes.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/settings/presentation/settings_routes.dart';
import 'package:uff/src/routing/app_router.dart';

const _authenticatedU1 = AuthState.authenticated(
  userId: 'u1',
  email: 'u1@example.com',
);

const _notOnboardedProfile = Profile(
  userId: 'u1',
  preferredUnits: 'metric',
  defaultActivityVisibility: 'private',
  onboardingCompleted: false,
);

const _onboardedProfile = Profile(
  userId: 'u1',
  preferredUnits: 'metric',
  defaultActivityVisibility: 'private',
  onboardingCompleted: true,
);

void main() {
  group('resolveAuthRedirect', () {
    test('redirects splash to sign in when unauthenticated', () {
      expect(
        resolveAuthRedirect(
          authState: const AsyncValue.data(AuthState.unauthenticated()),
          profileState: const AsyncValue.data(null),
          matchedLocation: '/',
        ),
        '/auth/sign-in',
      );
    });

    test('redirects splash to home when authenticated', () {
      expect(
        resolveAuthRedirect(
          authState: const AsyncValue.data(
            _authenticatedU1,
          ),
          profileState: const AsyncValue.data(_onboardedProfile),
          matchedLocation: '/',
        ),
        '/home',
      );
    });

    test('redirects protected routes to sign in when unauthenticated', () {
      for (final route in const <String>[
        '/settings',
        SettingsRoutes.hrZonesPath,
      ]) {
        expect(
          resolveAuthRedirect(
            authState: const AsyncValue.data(AuthState.unauthenticated()),
            profileState: const AsyncValue.data(_notOnboardedProfile),
            matchedLocation: route,
          ),
          '/auth/sign-in',
        );
      }
    });

    test('keeps legal routes public while unauthenticated', () {
      for (final route in const <String>[
        LegalRoutes.privacyPath,
        LegalRoutes.termsPath,
      ]) {
        expect(
          resolveAuthRedirect(
            authState: const AsyncValue.data(AuthState.unauthenticated()),
            profileState: const AsyncValue.data(_notOnboardedProfile),
            matchedLocation: route,
          ),
          isNull,
        );
      }
    });

    test('redirects auth routes to home when authenticated', () {
      expect(
        resolveAuthRedirect(
          authState: const AsyncValue.data(
            _authenticatedU1,
          ),
          profileState: const AsyncValue.data(_onboardedProfile),
          matchedLocation: '/auth/sign-up',
        ),
        '/home',
      );
    });

    test('returns null for valid in-session route', () {
      for (final route in const <String>[
        '/settings',
        SettingsRoutes.hrZonesPath,
      ]) {
        expect(
          resolveAuthRedirect(
            authState: const AsyncValue.data(
              _authenticatedU1,
            ),
            profileState: const AsyncValue.data(_onboardedProfile),
            matchedLocation: route,
          ),
          isNull,
        );
      }
    });

    test('keeps auth routes in place while auth mutation is loading', () {
      expect(
        resolveAuthRedirect(
          authState: const AsyncValue<AuthState>.loading(),
          profileState: const AsyncValue.data(_onboardedProfile),
          matchedLocation: '/auth/sign-in',
        ),
        isNull,
      );
    });

    test('keeps protected routes in place while sign out is loading', () {
      expect(
        resolveAuthRedirect(
          authState: const AsyncValue<AuthState>.loading(),
          profileState: const AsyncValue.data(_onboardedProfile),
          matchedLocation: '/settings',
        ),
        isNull,
      );
    });

    test(
      'redirects authenticated non-onboarded user to onboarding route',
      () {
        expect(
          resolveAuthRedirect(
            authState: const AsyncValue.data(
              _authenticatedU1,
            ),
            profileState: const AsyncValue.data(_notOnboardedProfile),
            matchedLocation: '/settings',
          ),
          '/onboarding',
        );
      },
    );

    test('keeps authenticated onboarded user on non-onboarding route', () {
      expect(
        resolveAuthRedirect(
          authState: const AsyncValue.data(
            _authenticatedU1,
          ),
          profileState: const AsyncValue.data(_onboardedProfile),
          matchedLocation: '/settings',
        ),
        isNull,
      );
    });

    test('redirects onboarded user away from onboarding route', () {
      expect(
        resolveAuthRedirect(
          authState: const AsyncValue.data(
            _authenticatedU1,
          ),
          profileState: const AsyncValue.data(_onboardedProfile),
          matchedLocation: '/onboarding',
        ),
        '/home',
      );
    });

    test('redirects onboarding route to home when profile resolves null', () {
      expect(
        resolveAuthRedirect(
          authState: const AsyncValue.data(
            _authenticatedU1,
          ),
          profileState: const AsyncValue.data(null),
          matchedLocation: '/onboarding',
        ),
        '/home',
      );
    });

    test(
      'keeps onboarding route in place while profile is in an error state',
      () {
        expect(
          resolveAuthRedirect(
            authState: const AsyncValue.data(
              _authenticatedU1,
            ),
            profileState: AsyncValue<Profile?>.error(
              StateError('profile fetch failed'),
              StackTrace.empty,
            ),
            matchedLocation: '/onboarding',
          ),
          isNull,
        );
      },
    );

    test(
      'keeps authenticated user on current route while profile is loading',
      () {
        expect(
          resolveAuthRedirect(
            authState: const AsyncValue.data(
              _authenticatedU1,
            ),
            profileState: const AsyncValue<Profile?>.loading(),
            matchedLocation: '/settings',
          ),
          isNull,
        );
      },
    );

    test('unauthenticated routing ignores profile state', () {
      expect(
        resolveAuthRedirect(
          authState: const AsyncValue.data(AuthState.unauthenticated()),
          profileState: const AsyncValue.data(_onboardedProfile),
          matchedLocation: '/settings',
        ),
        '/auth/sign-in',
      );
    });

    test(
      'keeps authenticated onboarded users on nested /home shell routes',
      () {
        for (final route in const <String>[
          '/home',
          '/home/activity',
          '/home/record',
          '/home/analytics',
          '/home/profile',
        ]) {
          expect(
            resolveAuthRedirect(
              authState: const AsyncValue.data(
                _authenticatedU1,
              ),
              profileState: const AsyncValue.data(_onboardedProfile),
              matchedLocation: route,
            ),
            isNull,
          );
        }
      },
    );

    test(
      'profile-missing redirect stays shell-agnostic for nested /home routes',
      () {
        expect(
          resolveAuthRedirect(
            authState: const AsyncValue.data(
              _authenticatedU1,
            ),
            profileState: const AsyncValue.data(null),
            matchedLocation: '/home/activity',
          ),
          isNull,
        );
      },
    );
  });
}

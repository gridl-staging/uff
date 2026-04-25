import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/routing/home_shell_screen.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/presentation/club_detail_screen.dart';
import 'package:uff/src/features/clubs/presentation/club_form_screen.dart';
import 'package:uff/src/features/clubs/presentation/club_run_form_screen.dart';
import 'package:uff/src/features/clubs/presentation/club_routes.dart';
import 'package:uff/src/features/auth/presentation/login_screen.dart';
import 'package:uff/src/features/auth/presentation/signup_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_entry_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_routes.dart';
import 'package:uff/src/features/gear/domain/gear_item.dart';
import 'package:uff/src/features/gear/presentation/gear_form_screen.dart';
import 'package:uff/src/features/gear/presentation/gear_list_screen.dart';
import 'package:uff/src/features/gear/presentation/gear_routes.dart';
import 'package:uff/src/features/import/presentation/import_screen.dart';
import 'package:uff/src/features/legal/presentation/legal_document_screen.dart';
import 'package:uff/src/features/legal/presentation/legal_routes.dart';
import 'package:uff/src/features/profile/presentation/privacy_zone_form_screen.dart';
import 'package:uff/src/features/profile/presentation/privacy_zones_screen.dart';
import 'package:uff/src/features/profile/presentation/profile_routes.dart';
import 'package:uff/src/features/settings/presentation/hr_zone_setup_screen.dart';
import 'package:uff/src/features/settings/presentation/settings_routes.dart';
import 'package:uff/src/features/settings/presentation/settings_screen.dart';
import 'package:uff/src/features/social/presentation/pending_follow_requests_screen.dart';
import 'package:uff/src/features/social/presentation/remote_activity_detail_screen.dart';
import 'package:uff/src/features/social/presentation/relationship_search_screen.dart';
import 'package:uff/src/features/social/presentation/social_relationship_list_screen.dart';
import 'package:uff/src/features/social/presentation/social_route_recovery_scaffold.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';
import 'package:uff/src/features/social/presentation/viewed_user_profile_screen.dart';

export 'home_shell_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ValueNotifier<int>(0);
  ref
    ..listen<AsyncValue<AuthState>>(authProvider, (_, next) {
      refreshNotifier.value++;
    })
    ..listen<AsyncValue<Profile?>>(profileProvider, (_, next) {
      refreshNotifier.value++;
    })
    ..onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (_, state) {
      final authState = ref.read(authProvider);
      final profileState = _isAuthenticated(authState)
          ? ref.read(profileProvider)
          : const AsyncValue<Profile?>.data(null);
      return resolveAuthRedirect(
        authState: authState,
        profileState: profileState,
        matchedLocation: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(path: '/auth', redirect: (_, __) => '/auth/sign-in'),
      GoRoute(
        path: '/auth/sign-in',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/sign-up',
        builder: (_, __) => const SignUpScreen(),
      ),
      GoRoute(
        path: LegalRoutes.privacyPath,
        builder: (_, __) => const LegalDocumentScreen(
          title: LegalRoutes.privacyTitle,
          assetPath: LegalRoutes.privacyAssetPath,
        ),
      ),
      GoRoute(
        path: LegalRoutes.termsPath,
        builder: (_, __) => const LegalDocumentScreen(
          title: LegalRoutes.termsTitle,
          assetPath: LegalRoutes.termsAssetPath,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, __, navigationShell) =>
            HomeShellScreen(navigationShell: navigationShell),
        branches: [
          for (final destination in homeShellDestinations)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: destination.path,
                  builder: (_, __) =>
                      buildHomeShellBranchContent(destination.id),
                ),
              ],
            ),
        ],
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/record',
        redirect: (_, __) => homeRecordDestination.path,
      ),
      GoRoute(
        path: ActivityRoutes.activityPathPattern,
        builder: (_, state) {
          final sessionId = _parseIntPathParameter(state, 'id');
          if (sessionId == null) {
            return _buildInvalidRouteRecoveryScreen(
              message: 'Unable to open activity. Invalid id.',
            );
          }

          // `/activity/:id` is the single resource URL for both draft review
          // and saved detail. The wrapper watches async session state and
          // decides which screen to render.
          return ActivityEntryScreen(activityId: sessionId);
        },
      ),
      GoRoute(
        path: '/import',
        builder: (_, __) => const ImportScreen(),
      ),
      GoRoute(
        path: GearRoutes.gearPath,
        builder: (_, __) => const GearListScreen(),
      ),
      GoRoute(
        path: GearRoutes.gearNewPath,
        builder: (_, __) => const GearFormScreen(),
      ),
      GoRoute(
        path: GearRoutes.gearPathPattern,
        builder: (_, state) {
          final extra = state.extra;
          final gearId = state.pathParameters['id'];
          if (extra is! GearItem || gearId != extra.id) {
            return _buildInvalidRouteRecoveryScreen(
              message: 'Unable to open gear editor.',
            );
          }

          return GearFormScreen(existingItem: extra);
        },
      ),
      // Club non-shell routes — the list path is owned by the shell branch
      // loop via ClubRoutes.clubListPath; only new/detail are registered here.
      GoRoute(
        path: ClubRoutes.clubNewPath,
        builder: (_, __) => const ClubFormScreen(),
      ),
      GoRoute(
        path: ClubRoutes.clubEditPathPattern,
        builder: (_, state) {
          final extra = state.extra;
          final clubId = state.pathParameters['id'];
          if (extra is! Club || clubId != extra.id) {
            return _buildInvalidRouteRecoveryScreen(
              message: 'Unable to open club editor.',
            );
          }
          return ClubFormScreen(existingClub: extra);
        },
      ),
      GoRoute(
        path: ClubRoutes.clubRunNewPathPattern,
        builder: (_, state) => ClubRunFormScreen(
          clubId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: ClubRoutes.clubDetailPathPattern,
        builder: (_, state) => ClubDetailScreen(
          clubId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: SettingsRoutes.settingsPath,
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: SettingsRoutes.hrZonesPath,
        builder: (_, __) => const HrZoneSetupScreen(),
      ),
      GoRoute(
        path: ProfileRoutes.privacyZonesPath,
        builder: (_, __) => const PrivacyZonesScreen(),
      ),
      GoRoute(
        path: ProfileRoutes.privacyZonesNewPath,
        builder: (_, __) => const PrivacyZoneFormScreen(),
      ),
      GoRoute(
        path: ProfileRoutes.privacyZonesPathPattern,
        builder: (_, state) =>
            PrivacyZoneFormScreen(zoneId: state.pathParameters['id']),
      ),
      GoRoute(
        path: SocialRoutes.searchPath,
        builder: (_, __) => const RelationshipSearchScreen(),
      ),
      GoRoute(
        path: SocialRoutes.followersPath,
        builder: (_, __) => const SocialRelationshipListScreen(
          listType: SocialRelationshipListType.followers,
        ),
      ),
      GoRoute(
        path: SocialRoutes.followingPath,
        builder: (_, __) => const SocialRelationshipListScreen(
          listType: SocialRelationshipListType.following,
        ),
      ),
      GoRoute(
        path: SocialRoutes.requestsPath,
        builder: (_, __) => const PendingFollowRequestsScreen(),
      ),
      GoRoute(
        path: SocialRoutes.viewedUserProfilePathPattern,
        builder: (_, state) =>
            ViewedUserProfileScreen(userId: state.pathParameters['userId']!),
      ),
      GoRoute(
        path: SocialRoutes.remoteActivityDetailPathPattern,
        builder: (_, state) => RemoteActivityDetailScreen(
          activityId: state.pathParameters['activityId']!,
        ),
      ),
    ],
  );
});

String? resolveAuthRedirect({
  required AsyncValue<AuthState> authState,
  required AsyncValue<Profile?> profileState,
  required String matchedLocation,
}) {
  final routeState = _AuthRouteState.fromLocation(matchedLocation);
  final isAuthenticated = _isAuthenticated(authState);

  if (routeState.isSplash) {
    if (authState.isLoading) {
      return null;
    }

    if (!isAuthenticated) {
      return '/auth/sign-in';
    }
  }

  if (authState.isLoading) {
    return null;
  }

  if (!isAuthenticated && !routeState.isPublicWhenSignedOut) {
    return '/auth/sign-in';
  }

  if (!isAuthenticated) {
    return null;
  }

  if (profileState.isLoading) {
    return null;
  }

  if (profileState.hasError && routeState.isOnboarding) {
    return null;
  }

  final profile = profileState.asData?.value;
  if (profile == null) {
    return routeState.redirectHomeWhenProfileMissing ? '/home' : null;
  }

  if (!profile.onboardingCompleted && !routeState.isOnboarding) {
    return '/onboarding';
  }

  if (profile.onboardingCompleted && routeState.redirectHomeWhenOnboarded) {
    return '/home';
  }

  return null;
}

/// Route classification helpers used by authentication/profile redirects.
class _AuthRouteState {
  const _AuthRouteState({
    required this.isSplash,
    required this.isAuth,
    required this.isOnboarding,
    required this.isLegal,
  });

  factory _AuthRouteState.fromLocation(String matchedLocation) {
    return _AuthRouteState(
      isSplash: matchedLocation == '/',
      isAuth: matchedLocation.startsWith('/auth'),
      isOnboarding: matchedLocation == '/onboarding',
      isLegal:
          matchedLocation == LegalRoutes.privacyPath ||
          matchedLocation == LegalRoutes.termsPath,
    );
  }

  final bool isSplash;
  final bool isAuth;
  final bool isOnboarding;
  final bool isLegal;

  bool get isPublicWhenSignedOut => isAuth || isLegal;

  bool get redirectHomeWhenProfileMissing => isSplash || isAuth || isOnboarding;

  bool get redirectHomeWhenOnboarded => isSplash || isAuth || isOnboarding;
}

bool _isAuthenticated(AsyncValue<AuthState> authState) {
  final resolvedState =
      authState.asData?.value ?? const AuthState.unauthenticated();

  return resolvedState.maybeWhen(
    authenticated: (_, __) => true,
    orElse: () => false,
  );
}

String? _readRequiredPathParameter(GoRouterState state, String name) {
  final value = state.pathParameters[name];
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

int? _parseIntPathParameter(GoRouterState state, String name) {
  final value = _readRequiredPathParameter(state, name);
  if (value == null) {
    return null;
  }
  return int.tryParse(value);
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

const _invalidRouteRecoveryStateKey = Key('invalid_route_recovery');

Widget _buildInvalidRouteRecoveryScreen({required String message}) {
  return SocialRouteRecoveryScaffold(
    stateKey: _invalidRouteRecoveryStateKey,
    message: message,
  );
}

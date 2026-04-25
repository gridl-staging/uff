import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/auth/data/auth_oauth_config.dart';
import 'package:uff/src/features/legal/presentation/legal_document_screen.dart';
import 'package:uff/src/features/legal/presentation/legal_routes.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/profile/application/privacy_zone_location_service.dart';
import 'package:uff/src/features/profile/application/privacy_zone_providers.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';
import 'package:uff/src/features/profile/presentation/privacy_zone_form_screen.dart';
import 'package:uff/src/features/profile/presentation/privacy_zones_screen.dart';
import 'package:uff/src/features/settings/presentation/hr_zone_setup_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_routes.dart';
import 'package:uff/src/features/gear/presentation/gear_routes.dart';
import 'package:uff/src/features/profile/presentation/profile_routes.dart';
import 'package:uff/src/features/settings/presentation/settings_routes.dart';
import 'package:uff/src/features/social/presentation/social_route_recovery_scaffold.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';
import 'package:uff/src/routing/app_router.dart';

import '../features/profile/privacy_zone_test_support.dart';
import '../features/auth/presentation/auth_test_support.dart';

const _onboardedProfile = Profile(
  userId: 'user-1',
  preferredUnits: 'metric',
  defaultActivityVisibility: 'private',
  onboardingCompleted: true,
);

class _FakeProfileNotifier extends ProfileNotifier {
  _FakeProfileNotifier(this.profile);

  final Profile profile;

  @override
  Profile? build() => profile;
}

Future<GoRouter> _pumpRouter(
  WidgetTester tester, {
  required AuthState authState,
  FakePrivacyZoneRepository? privacyZoneRepository,
  Profile profile = _onboardedProfile,
}) async {
  final authRepository = RecordingAuthRepository(initialState: authState);
  final repository = privacyZoneRepository ?? FakePrivacyZoneRepository();
  final container = ProviderContainer(
    overrides: [
      authOAuthConfigProvider.overrideWithValue(
        const AuthOAuthConfig(
          googleWebClientId: 'test-google-web-client-id',
          googleIosClientId: 'test-google-ios-client-id',
          isAppleSignInEnabled: true,
          isGoogleSignInEnabled: true,
        ),
      ),
      authRepositoryProvider.overrideWithValue(authRepository),
      authStateChangesProvider.overrideWith((ref) => Stream.value(authState)),
      profileProvider.overrideWith(() => _FakeProfileNotifier(profile)),
      privacyZoneRepositoryProvider.overrideWithValue(repository),
      privacyZoneLocationServiceProvider.overrideWithValue(
        const _RouterFakeLocationService(),
      ),
    ],
  );
  final router = container.read(appRouterProvider);
  addTearDown(router.dispose);
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  return router;
}

Future<void> _pumpNavigation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

class _RouterFakeLocationService implements PrivacyZoneLocationService {
  const _RouterFakeLocationService();

  @override
  Future<PrivacyZoneCurrentLocationResult> fetchCurrentLocation() async {
    return const PrivacyZoneCurrentLocationResult.failure(
      PrivacyZoneCurrentLocationFailure.permissionDenied,
    );
  }
}

void main() {
  group('appRouterProvider home shell routes', () {
    testWidgets('/home lands on Feed destination after auth onboarding', (
      tester,
    ) async {
      final router = await _pumpRouter(
        tester,
        authState: const AuthState.authenticated(
          userId: 'user-1',
          email: 'user@example.com',
        ),
      );
      router.go('/home');
      await _pumpNavigation(tester);

      final navBar = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      expect(navBar.currentIndex, 0);
      expect(navBar.items.first.label, 'Feed');
    });

    test(
      'route tree includes stage 5 social paths and stage 6 routes',
      () {
        final authRepository = RecordingAuthRepository();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(authRepository),
            authStateChangesProvider.overrideWith(
              (ref) => const Stream<AuthState>.empty(),
            ),
            profileProvider.overrideWith(
              () => _FakeProfileNotifier(_onboardedProfile),
            ),
            privacyZoneRepositoryProvider.overrideWithValue(
              FakePrivacyZoneRepository(),
            ),
            privacyZoneLocationServiceProvider.overrideWithValue(
              const _RouterFakeLocationService(),
            ),
          ],
        );
        addTearDown(container.dispose);

        final router = container.read(appRouterProvider);
        final routePaths = RouteBase.routesRecursively(
          router.configuration.routes,
        ).whereType<GoRoute>().map((route) => route.path).toSet();

        expect(routePaths, contains('/auth'));
        expect(routePaths, contains('/auth/sign-in'));
        expect(routePaths, contains('/auth/sign-up'));
        expect(routePaths, contains('/onboarding'));
        expect(routePaths, contains(ActivityRoutes.activityPathPattern));
        expect(routePaths, contains('/import'));
        expect(routePaths, contains(GearRoutes.gearPath));
        expect(routePaths, contains(GearRoutes.gearNewPath));
        expect(routePaths, contains(GearRoutes.gearPathPattern));
        expect(routePaths, contains('/settings'));
        expect(routePaths, contains(ProfileRoutes.privacyZonesPath));
        expect(routePaths, contains(ProfileRoutes.privacyZonesNewPath));
        expect(routePaths, contains(ProfileRoutes.privacyZonesPathPattern));
        expect(routePaths, contains('/home'));
        expect(routePaths, contains('/home/activity'));
        expect(routePaths, contains('/home/record'));
        expect(routePaths, contains('/home/analytics'));
        expect(routePaths, contains('/home/profile'));
        expect(routePaths, contains(SocialRoutes.searchPath));
        expect(routePaths, contains(SocialRoutes.followersPath));
        expect(routePaths, contains(SocialRoutes.followingPath));
        expect(routePaths, contains(SocialRoutes.requestsPath));
        expect(routePaths, contains('/social/profile/:userId'));
        expect(routePaths, contains('/social/activity/:activityId'));
        expect(routePaths, contains(LegalRoutes.privacyPath));
        expect(routePaths, contains(LegalRoutes.termsPath));
        expect(routePaths, contains('/settings'));
        expect(routePaths, contains(SettingsRoutes.hrZonesPath));

        expect(routePaths, isNot(contains('/home/followers')));
        expect(routePaths, isNot(contains('/home/following')));
        expect(routePaths, isNot(contains('/home/discover')));
        expect(routePaths, isNot(contains('/home/profile/:id')));
      },
    );
  });

  group('appRouterProvider legal routes', () {
    testWidgets(
      'privacy legal route is reachable while unauthenticated',
      (tester) async {
        final router = await _pumpRouter(
          tester,
          authState: const AuthState.unauthenticated(),
        );

        router.go(LegalRoutes.privacyPath);
        await tester.pumpAndSettle();

        expect(find.byType(LegalDocumentScreen), findsOneWidget);
        expect(find.text(LegalRoutes.privacyTitle), findsOneWidget);
        expect(find.byKey(LegalDocumentScreen.markdownViewKey), findsOneWidget);
        expect(find.byKey(LegalDocumentScreen.errorMessageKey), findsNothing);
      },
    );

    testWidgets(
      'terms legal route is reachable while unauthenticated',
      (tester) async {
        final router = await _pumpRouter(
          tester,
          authState: const AuthState.unauthenticated(),
        );

        router.go(LegalRoutes.termsPath);
        await tester.pumpAndSettle();

        expect(find.byType(LegalDocumentScreen), findsOneWidget);
        expect(find.text(LegalRoutes.termsTitle), findsOneWidget);
        expect(find.byKey(LegalDocumentScreen.markdownViewKey), findsOneWidget);
        expect(find.byKey(LegalDocumentScreen.errorMessageKey), findsNothing);
      },
    );
  });

  group('appRouterProvider settings routes', () {
    testWidgets(
      '/settings/hr-zones resolves to HrZoneSetupScreen for signed-in users',
      (tester) async {
        final router = await _pumpRouter(
          tester,
          authState: const AuthState.authenticated(
            userId: 'user-1',
            email: 'user@example.com',
          ),
        );

        router.go(SettingsRoutes.hrZonesPath);
        await _pumpNavigation(tester);

        expect(find.byType(HrZoneSetupScreen), findsOneWidget);
      },
    );
  });

  group('appRouterProvider privacy-zone routes', () {
    testWidgets(
      '/privacy-zones resolves to PrivacyZonesScreen for signed-in users',
      (tester) async {
        final router = await _pumpRouter(
          tester,
          authState: const AuthState.authenticated(
            userId: 'user-1',
            email: 'user@example.com',
          ),
        );

        router.go(ProfileRoutes.privacyZonesPath);
        await _pumpNavigation(tester);

        expect(find.byType(PrivacyZonesScreen), findsOneWidget);
      },
    );

    testWidgets('/privacy-zones/new resolves to PrivacyZoneFormScreen', (
      tester,
    ) async {
      final router = await _pumpRouter(
        tester,
        authState: const AuthState.authenticated(
          userId: 'user-1',
          email: 'user@example.com',
        ),
      );

      router.go(ProfileRoutes.privacyZonesNewPath);
      await _pumpNavigation(tester);

      expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);
      expect(find.byKey(PrivacyZoneFormScreen.labelFieldKey), findsOneWidget);
    });

    testWidgets(
      '/privacy-zones/:id resolves to PrivacyZoneFormScreen in edit mode',
      (
        tester,
      ) async {
        const existingZone = PrivacyZone(
          id: 'zone-42',
          userId: 'user-1',
          label: 'Home',
          latitude: 40.71,
          longitude: -74.01,
          radiusMeters: 200,
        );
        final router = await _pumpRouter(
          tester,
          authState: const AuthState.authenticated(
            userId: 'user-1',
            email: 'user@example.com',
          ),
          privacyZoneRepository: FakePrivacyZoneRepository(
            zonesToReturn: const <PrivacyZone>[existingZone],
          ),
        );

        router.go(ProfileRoutes.privacyZoneDetailPath('zone-42'));
        await _pumpNavigation(tester);

        expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);
        expect(find.text('Edit Privacy Zone'), findsOneWidget);
      },
    );

    testWidgets(
      '/privacy-zones/:id missing id state renders safe recovery UI',
      (
        tester,
      ) async {
        final router = await _pumpRouter(
          tester,
          authState: const AuthState.authenticated(
            userId: 'user-1',
            email: 'user@example.com',
          ),
          privacyZoneRepository: FakePrivacyZoneRepository(),
        );

        router.go(ProfileRoutes.privacyZoneDetailPath('zone-missing'));
        await _pumpNavigation(tester);

        expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);
        expect(
          find.byKey(PrivacyZoneFormScreen.missingZoneStateKey),
          findsOneWidget,
        );
      },
    );

    test(
      'redirect guard blocks unauthenticated access to privacy-zone routes',
      () {
        for (final route in <String>[
          ProfileRoutes.privacyZonesPath,
          ProfileRoutes.privacyZonesNewPath,
          ProfileRoutes.privacyZoneDetailPath('zone-42'),
        ]) {
          expect(
            resolveAuthRedirect(
              authState: const AsyncValue.data(AuthState.unauthenticated()),
              profileState: const AsyncValue.data(_onboardedProfile),
              matchedLocation: route,
            ),
            '/auth/sign-in',
          );
        }
      },
    );
  });

  group('appRouterProvider activity detail route', () {
    testWidgets(
      '/activity/:id with invalid id renders shared recovery screen with action',
      (tester) async {
        final router = await _pumpRouter(
          tester,
          authState: const AuthState.authenticated(
            userId: 'user-1',
            email: 'user@example.com',
          ),
        );

        router.go('/activity/not-a-number');
        await tester.pumpAndSettle();

        expect(find.byType(AppBar), findsOneWidget);
        expect(find.text('Unable to Open Page'), findsOneWidget);
        expect(
          find.text('Unable to open activity. Invalid id.'),
          findsOneWidget,
        );
        expect(find.byType(SocialRouteRecoveryScaffold), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Go to Home'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Go to Home'));
        await _pumpNavigation(tester);

        expect(find.byType(BottomNavigationBar), findsOneWidget);
      },
    );
  });
}

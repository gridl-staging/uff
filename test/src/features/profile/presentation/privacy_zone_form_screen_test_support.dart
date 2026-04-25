import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/profile/application/privacy_zone_location_service.dart';
import 'package:uff/src/features/profile/application/privacy_zone_providers.dart';
import 'package:uff/src/features/profile/presentation/privacy_zone_form_screen.dart';
import 'package:uff/src/features/profile/presentation/profile_routes.dart';

import '../privacy_zone_test_support.dart';

const privacyZoneListRouteText = 'Privacy Zones List Route';
const privacyZoneFormExitRouteText = 'Privacy Zone Form Exit Route';

class FakePrivacyZoneLocationService implements PrivacyZoneLocationService {
  FakePrivacyZoneLocationService(this._result);

  final PrivacyZoneCurrentLocationResult _result;

  @override
  Future<PrivacyZoneCurrentLocationResult> fetchCurrentLocation() async {
    return _result;
  }
}

Widget buildPrivacyZoneFormRouterScreen({
  required FakePrivacyZoneRepository repository,
  required PrivacyZoneLocationService locationService,
  String initialLocation = ProfileRoutes.privacyZonesNewPath,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: ProfileRoutes.privacyZonesPath,
        builder: (_, __) =>
            const Scaffold(body: Text(privacyZoneListRouteText)),
      ),
      GoRoute(
        path: ProfileRoutes.privacyZonesNewPath,
        builder: (_, __) => const PrivacyZoneFormScreen(),
      ),
      GoRoute(
        path: ProfileRoutes.privacyZonesPathPattern,
        builder: (_, state) => PrivacyZoneFormScreen(
          zoneId: state.pathParameters['id'],
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  return ProviderScope(
    overrides: [
      privacyZoneRepositoryProvider.overrideWithValue(repository),
      privacyZoneLocationServiceProvider.overrideWithValue(locationService),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Widget buildPoppablePrivacyZoneFormRouterScreen({
  required FakePrivacyZoneRepository repository,
  required PrivacyZoneLocationService locationService,
  String initialLocation = '/stack/privacy-zones/new',
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/stack',
        builder: (_, __) =>
            const Scaffold(body: Text(privacyZoneFormExitRouteText)),
        routes: [
          GoRoute(
            path: 'privacy-zones/new',
            builder: (_, __) => const PrivacyZoneFormScreen(),
          ),
          GoRoute(
            path: 'privacy-zones/:id',
            builder: (_, state) => PrivacyZoneFormScreen(
              zoneId: state.pathParameters['id'],
            ),
          ),
        ],
      ),
      GoRoute(
        path: ProfileRoutes.privacyZonesPath,
        builder: (_, __) =>
            const Scaffold(body: Text(privacyZoneListRouteText)),
      ),
    ],
  );
  addTearDown(router.dispose);

  return ProviderScope(
    overrides: [
      privacyZoneRepositoryProvider.overrideWithValue(repository),
      privacyZoneLocationServiceProvider.overrideWithValue(locationService),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> enterValidPrivacyZoneFormValues(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(PrivacyZoneFormScreen.labelFieldKey),
    'Home',
  );
  await tester.enterText(
    find.byKey(PrivacyZoneFormScreen.latitudeFieldKey),
    '40.7128',
  );
  await tester.enterText(
    find.byKey(PrivacyZoneFormScreen.longitudeFieldKey),
    '-74.0060',
  );
  await tester.enterText(
    find.byKey(PrivacyZoneFormScreen.radiusFieldKey),
    '250',
  );
}

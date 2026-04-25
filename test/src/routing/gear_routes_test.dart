import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_controller.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/gear/application/gear_providers.dart';
import 'package:uff/src/features/gear/presentation/gear_routes.dart';
import 'package:uff/src/routing/app_router.dart';

import '../features/auth/presentation/auth_test_support.dart';
import '../test_helpers/gear_test_support.dart';

void main() {
  testWidgets('gear new route renders add gear form', (tester) async {
    final router = await _pumpRouterApp(tester);

    router.go(GearRoutes.gearNewPath);
    await tester.pumpAndSettle();

    expect(find.text('Add Gear'), findsOneWidget);
  });

  testWidgets('gear edit route without GearItem extra shows safe error', (
    tester,
  ) async {
    final router = await _pumpRouterApp(tester);

    router.go(GearRoutes.gearDetailPath('gear-shoe'));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Unable to Open Page'), findsOneWidget);
    expect(find.text('Unable to open gear editor.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Go to Home'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Go to Home'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomNavigationBar), findsOneWidget);
  });

  testWidgets(
    'gear edit route with mismatched GearItem extra shows safe error',
    (
      tester,
    ) async {
      final router = await _pumpRouterApp(tester);

      unawaited(
        router.push(
          GearRoutes.gearDetailPath('not-${testShoeGear.id}'),
          extra: testShoeGear,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Unable to Open Page'), findsOneWidget);
      expect(find.text('Unable to open gear editor.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Go to Home'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Go Back'), findsOneWidget);
    },
  );

  testWidgets('gear edit route with non-GearItem extra shows safe error', (
    tester,
  ) async {
    final router = await _pumpRouterApp(tester);

    unawaited(
      router.push(
        GearRoutes.gearDetailPath(testShoeGear.id),
        extra: 'not-a-gear-item',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Unable to Open Page'), findsOneWidget);
    expect(find.text('Unable to open gear editor.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Go to Home'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Go Back'), findsOneWidget);
  });

  testWidgets('gear edit route with GearItem extra renders edit form', (
    tester,
  ) async {
    final router = await _pumpRouterApp(tester);

    unawaited(
      router.push(
        GearRoutes.gearDetailPath(testShoeGear.id),
        extra: testShoeGear,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit Gear'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, testShoeGear.name),
      findsOneWidget,
    );
  });
}

Future<GoRouter> _pumpRouterApp(WidgetTester tester) async {
  const authenticatedState = AuthState.authenticated(
    userId: 'user-1',
    email: 'user@example.com',
  );

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        RecordingAuthRepository(initialState: authenticatedState),
      ),
      authStateChangesProvider.overrideWith(
        (ref) => Stream.value(authenticatedState),
      ),
      trackingRepositoryProvider.overrideWithValue(
        AuthTestTrackingRepository(),
      ),
      savedActivitiesProvider.overrideWith((ref) async {
        return <TrackingSessionRecord>[];
      }),
      gearRepositoryProvider.overrideWithValue(
        RecordingGearRepository(itemsToReturn: [testShoeGear]),
      ),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(appRouterProvider);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  return router;
}

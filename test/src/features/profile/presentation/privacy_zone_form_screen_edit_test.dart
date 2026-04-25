import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/profile/application/privacy_zone_location_service.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';
import 'package:uff/src/features/profile/presentation/privacy_zone_form_screen.dart';
import 'package:uff/src/features/profile/presentation/profile_routes.dart';

import '../privacy_zone_test_support.dart';
import 'privacy_zone_form_screen_test_support.dart';

/// ## Test Scenarios
/// - [positive] Edit mode pre-fills fields from selected zone
/// - [positive] Save calls update and returns to list
/// - [positive] Delete confirm calls deleteZone and returns to list
/// - [edge] Clean edit form exits immediately on back
/// - [edge] Delete cancel does not call delete
/// - [edge] In-flight delete ignores back attempts
/// - [error] Delete failure remains on form with feedback
/// - [error] Failed update keeps unsaved-change back guard active
/// - [error] Failed delete does not clear existing dirty back guard
/// - [error] Load failure shows recovery action back to the list
void main() {
  group('PrivacyZoneFormScreen edit mode', () {
    testWidgets('pre-fills fields from selected zone', (tester) async {
      final repository = FakePrivacyZoneRepository(
        zonesToReturn: const <PrivacyZone>[
          PrivacyZone(
            id: 'zone-1',
            userId: 'user-1',
            label: 'Home',
            latitude: 40.71,
            longitude: -74.01,
            radiusMeters: 200,
          ),
        ],
      );
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
          initialLocation: ProfileRoutes.privacyZoneDetailPath('zone-1'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit Privacy Zone'), findsOneWidget);
      final labelField = tester.widget<TextFormField>(
        find.byKey(PrivacyZoneFormScreen.labelFieldKey),
      );
      expect(labelField.controller?.text, 'Home');
    });

    testWidgets('clean edit form exits immediately on back', (tester) async {
      final repository = FakePrivacyZoneRepository(
        zonesToReturn: const <PrivacyZone>[
          PrivacyZone(
            id: 'zone-1',
            userId: 'user-1',
            label: 'Home',
            latitude: 40.71,
            longitude: -74.01,
            radiusMeters: 200,
          ),
        ],
      );
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPoppablePrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
          initialLocation: '/stack/privacy-zones/zone-1',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text(privacyZoneFormExitRouteText), findsOneWidget);
      expect(find.byType(PrivacyZoneFormScreen), findsNothing);
    });

    testWidgets('save calls update and returns to list', (tester) async {
      final repository = FakePrivacyZoneRepository(
        zonesToReturn: const <PrivacyZone>[
          PrivacyZone(
            id: 'zone-1',
            userId: 'user-1',
            label: 'Home',
            latitude: 40.71,
            longitude: -74.01,
            radiusMeters: 200,
          ),
        ],
      );
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
          initialLocation: ProfileRoutes.privacyZoneDetailPath('zone-1'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(PrivacyZoneFormScreen.labelFieldKey),
        'Updated Home',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(PrivacyZoneFormScreen.saveButtonKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PrivacyZoneFormScreen.saveButtonKey));
      await tester.pumpAndSettle();

      expect(repository.updateZoneCallCount, 1);
      expect(repository.lastUpdatedZone?.label, 'Updated Home');
      expect(find.text(privacyZoneListRouteText), findsOneWidget);
    });

    testWidgets('in-flight save with unchanged fields ignores back attempts', (
      tester,
    ) async {
      final updateCompleter = Completer<void>();
      final repository = FakePrivacyZoneRepository(
        zonesToReturn: const <PrivacyZone>[
          PrivacyZone(
            id: 'zone-1',
            userId: 'user-1',
            label: 'Home',
            latitude: 40.71,
            longitude: -74.01,
            radiusMeters: 200,
          ),
        ],
        updateCompleter: updateCompleter,
      );
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPoppablePrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
          initialLocation: '/stack/privacy-zones/zone-1',
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(PrivacyZoneFormScreen.saveButtonKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PrivacyZoneFormScreen.saveButtonKey));
      await tester.pump();

      expect(repository.updateZoneCallCount, 1);

      await tester.tap(find.byTooltip('Back'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);
      expect(find.text(privacyZoneFormExitRouteText), findsNothing);

      updateCompleter.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('delete cancel does not call delete and confirm does', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository(
        zonesToReturn: const <PrivacyZone>[
          PrivacyZone(
            id: 'zone-1',
            userId: 'user-1',
            label: 'Home',
            latitude: 40.71,
            longitude: -74.01,
            radiusMeters: 200,
          ),
        ],
      );
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
          initialLocation: ProfileRoutes.privacyZoneDetailPath('zone-1'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(PrivacyZoneFormScreen.deleteButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PrivacyZoneFormScreen.deleteCancelButtonKey));
      await tester.pumpAndSettle();

      expect(repository.deleteZoneCallCount, 0);
      expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);

      await tester.tap(find.byKey(PrivacyZoneFormScreen.deleteButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(PrivacyZoneFormScreen.deleteConfirmButtonKey),
      );
      await tester.pumpAndSettle();

      expect(repository.deleteZoneCallCount, 1);
      expect(repository.lastDeletedZoneId, 'zone-1');
      expect(find.text(privacyZoneListRouteText), findsOneWidget);
    });

    testWidgets('in-flight delete ignores back attempts', (tester) async {
      final deleteCompleter = Completer<void>();
      final repository = FakePrivacyZoneRepository(
        zonesToReturn: const <PrivacyZone>[
          PrivacyZone(
            id: 'zone-1',
            userId: 'user-1',
            label: 'Home',
            latitude: 40.71,
            longitude: -74.01,
            radiusMeters: 200,
          ),
        ],
        deleteCompleter: deleteCompleter,
      );
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPoppablePrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
          initialLocation: '/stack/privacy-zones/zone-1',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(PrivacyZoneFormScreen.deleteButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(PrivacyZoneFormScreen.deleteConfirmButtonKey),
      );
      await tester.pump();

      expect(repository.deleteZoneCallCount, 1);

      await tester.tap(find.byTooltip('Back'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);
      expect(find.text(privacyZoneFormExitRouteText), findsNothing);

      deleteCompleter.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('delete failure remains on form with feedback', (tester) async {
      final repository = FakePrivacyZoneRepository(
        zonesToReturn: const <PrivacyZone>[
          PrivacyZone(
            id: 'zone-1',
            userId: 'user-1',
            label: 'Home',
            latitude: 40.71,
            longitude: -74.01,
            radiusMeters: 200,
          ),
        ],
        deleteError: Exception('delete failed'),
      );
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
          initialLocation: ProfileRoutes.privacyZoneDetailPath('zone-1'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(PrivacyZoneFormScreen.deleteButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(PrivacyZoneFormScreen.deleteConfirmButtonKey),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);
      expect(
        find.text('Failed to delete privacy zone. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('failed update keeps unsaved-change back guard active', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository(
        zonesToReturn: const <PrivacyZone>[
          PrivacyZone(
            id: 'zone-1',
            userId: 'user-1',
            label: 'Home',
            latitude: 40.71,
            longitude: -74.01,
            radiusMeters: 200,
          ),
        ],
        updateError: Exception('update failed'),
      );
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPoppablePrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
          initialLocation: '/stack/privacy-zones/zone-1',
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(PrivacyZoneFormScreen.labelFieldKey),
        'Updated Home',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(PrivacyZoneFormScreen.saveButtonKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PrivacyZoneFormScreen.saveButtonKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(repository.updateZoneCallCount, 1);
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);
      expect(find.text(privacyZoneFormExitRouteText), findsNothing);
    });

    testWidgets('failed delete does not clear existing dirty back guard', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository(
        zonesToReturn: const <PrivacyZone>[
          PrivacyZone(
            id: 'zone-1',
            userId: 'user-1',
            label: 'Home',
            latitude: 40.71,
            longitude: -74.01,
            radiusMeters: 200,
          ),
        ],
        deleteError: Exception('delete failed'),
      );
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPoppablePrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
          initialLocation: '/stack/privacy-zones/zone-1',
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(PrivacyZoneFormScreen.labelFieldKey),
        'Still Dirty',
      );
      await tester.tap(find.byKey(PrivacyZoneFormScreen.deleteButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(PrivacyZoneFormScreen.deleteConfirmButtonKey),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(repository.deleteZoneCallCount, 1);
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);
      expect(find.text(privacyZoneFormExitRouteText), findsNothing);
    });

    testWidgets('load failure shows recovery action back to the list', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository(
        errorToThrow: Exception('load failed'),
      );
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
          initialLocation: ProfileRoutes.privacyZoneDetailPath('zone-1'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(PrivacyZoneFormScreen.loadErrorStateKey),
        findsOneWidget,
      );
      expect(find.text('Failed to load that privacy zone.'), findsOneWidget);

      await tester.tap(find.text('Back to Privacy Zones'));
      await tester.pumpAndSettle();

      expect(find.text(privacyZoneListRouteText), findsOneWidget);
    });
  });
}

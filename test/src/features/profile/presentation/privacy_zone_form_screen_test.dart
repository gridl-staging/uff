import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/profile/application/privacy_zone_location_service.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';
import 'package:uff/src/features/profile/presentation/privacy_zone_form_screen.dart';

import '../privacy_zone_test_support.dart';
import '../../../test_helpers/mapbox_platform_channel_stub.dart';
import 'privacy_zone_form_screen_test_support.dart';

// ## Test Scenarios
// - [positive] Create mode shows empty fields and stable control keys
// - [positive] All inputs render inside a single form widget
// - [positive] Successful create pops back to privacy-zone list route
// - [positive] Radius slider is present with default and updates label and text field
// - [positive] Radius text field clamps to slider-matched value on focus loss
// - [edge] Clean create form exits immediately on back
// - [edge] Dirty create form shows discard prompt and stay keeps input
// - [error] Failed create keeps unsaved-change back guard active
// - [positive] Current-location success fills lat/lon fields
// - [error] Current-location denied shows user-facing message
// - [error] Current-location permanently denied shows settings guidance
void main() {
  final mapCameraAnimationRecorder = MapCameraAnimationRecorder();
  setUpMapboxPlatformChannelStub(
    channelSuffix: 10,
    mapCameraAnimationRecorder: mapCameraAnimationRecorder,
  );

  group('PrivacyZoneFormScreen create mode', () {
    setUp(mapCameraAnimationRecorder.reset);

    testWidgets('shows empty fields and stable control keys on first render', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository();
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);
      expect(find.text('New Privacy Zone'), findsOneWidget);
      expect(find.byKey(PrivacyZoneFormScreen.labelFieldKey), findsOneWidget);
      expect(
        find.byKey(PrivacyZoneFormScreen.latitudeFieldKey),
        findsOneWidget,
      );
      expect(
        find.byKey(PrivacyZoneFormScreen.longitudeFieldKey),
        findsOneWidget,
      );
      expect(find.byKey(PrivacyZoneFormScreen.radiusFieldKey), findsOneWidget);
      expect(find.byKey(PrivacyZoneFormScreen.saveButtonKey), findsOneWidget);
      expect(
        find.byKey(PrivacyZoneFormScreen.currentLocationButtonKey),
        findsOneWidget,
      );

      final labelField = tester.widget<TextFormField>(
        find.byKey(PrivacyZoneFormScreen.labelFieldKey),
      );
      final latitudeField = tester.widget<TextFormField>(
        find.byKey(PrivacyZoneFormScreen.latitudeFieldKey),
      );
      final longitudeField = tester.widget<TextFormField>(
        find.byKey(PrivacyZoneFormScreen.longitudeFieldKey),
      );
      final radiusField = tester.widget<TextFormField>(
        find.byKey(PrivacyZoneFormScreen.radiusFieldKey),
      );

      expect(labelField.controller?.text, isEmpty);
      expect(latitudeField.controller?.text, isEmpty);
      expect(longitudeField.controller?.text, isEmpty);
      expect(radiusField.controller?.text, '200');
    });

    testWidgets('renders all inputs inside a single form widget', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository();
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Form), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(PrivacyZoneFormScreen.labelFieldKey),
          matching: find.byType(Form),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(PrivacyZoneFormScreen.latitudeFieldKey),
          matching: find.byType(Form),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(PrivacyZoneFormScreen.longitudeFieldKey),
          matching: find.byType(Form),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(PrivacyZoneFormScreen.radiusFieldKey),
          matching: find.byType(Form),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'shows validation feedback and blocks create when input is invalid',
      (tester) async {
        final repository = FakePrivacyZoneRepository();
        final locationService = FakePrivacyZoneLocationService(
          const PrivacyZoneCurrentLocationResult.failure(
            PrivacyZoneCurrentLocationFailure.permissionDenied,
          ),
        );

        await tester.pumpWidget(
          buildPrivacyZoneFormRouterScreen(
            repository: repository,
            locationService: locationService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(PrivacyZoneFormScreen.saveButtonKey),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(PrivacyZoneFormScreen.saveButtonKey));
        await tester.pumpAndSettle();

        expect(
          find.byKey(PrivacyZoneFormScreen.submissionMessageKey),
          findsOneWidget,
        );
        expect(find.text('Label is required.'), findsOneWidget);
        expect(repository.createZoneCallCount, 0);
      },
    );

    testWidgets(
      'disables save and shows busy affordance while create is in flight',
      (tester) async {
        final createCompleter = Completer<PrivacyZone>();
        final repository = FakePrivacyZoneRepository(
          createCompleter: createCompleter,
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
          ),
        );
        await tester.pumpAndSettle();

        await enterValidPrivacyZoneFormValues(tester);

        await tester.tap(find.byKey(PrivacyZoneFormScreen.saveButtonKey));
        await tester.pump();

        expect(repository.createZoneCallCount, 1);
        final saveButton = tester.widget<ElevatedButton>(
          find.byKey(PrivacyZoneFormScreen.saveButtonKey),
        );
        expect(saveButton.onPressed, isNull);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        createCompleter.complete(
          const PrivacyZone(
            id: 'zone-created',
            userId: 'user-1',
            label: 'Home',
            latitude: 40.7128,
            longitude: -74.006,
            radiusMeters: 250,
          ),
        );
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'in-flight create ignores back attempts and does not show discard prompt',
      (tester) async {
        final createCompleter = Completer<PrivacyZone>();
        final repository = FakePrivacyZoneRepository(
          createCompleter: createCompleter,
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
          ),
        );
        await tester.pumpAndSettle();

        await enterValidPrivacyZoneFormValues(tester);
        await tester.tap(find.byKey(PrivacyZoneFormScreen.saveButtonKey));
        await tester.pump();

        expect(repository.createZoneCallCount, 1);

        await tester.tap(find.byTooltip('Back'));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Discard changes?'), findsNothing);
        expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);
        expect(find.text(privacyZoneFormExitRouteText), findsNothing);

        createCompleter.complete(
          const PrivacyZone(
            id: 'zone-created',
            userId: 'user-1',
            label: 'Home',
            latitude: 40.7128,
            longitude: -74.006,
            radiusMeters: 250,
          ),
        );
        await tester.pumpAndSettle();
      },
    );

    testWidgets('successful create pops back to privacy-zone list route', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository();
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
        ),
      );
      await tester.pumpAndSettle();

      await enterValidPrivacyZoneFormValues(tester);

      await tester.tap(find.byKey(PrivacyZoneFormScreen.saveButtonKey));
      await tester.pumpAndSettle();

      expect(find.text(privacyZoneListRouteText), findsOneWidget);
      expect(repository.createZoneCallCount, 1);
      expect(repository.lastCreateZoneCall?.label, 'Home');
      expect(repository.lastCreateZoneCall?.radiusMeters, 250);
    });

    testWidgets('clean create form exits immediately on back', (tester) async {
      final repository = FakePrivacyZoneRepository();
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPoppablePrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text(privacyZoneFormExitRouteText), findsOneWidget);
      expect(find.byType(PrivacyZoneFormScreen), findsNothing);
    });

    testWidgets('dirty create form shows discard prompt and stay keeps input', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository();
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPoppablePrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(PrivacyZoneFormScreen.labelFieldKey),
        'Home Draft',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('You have unsaved changes.'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();

      final labelField = tester.widget<TextFormField>(
        find.byKey(PrivacyZoneFormScreen.labelFieldKey),
      );
      expect(labelField.controller?.text, 'Home Draft');
      expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);
      expect(find.text(privacyZoneFormExitRouteText), findsNothing);
    });

    testWidgets(
      'repository create failure keeps entered values and shows message',
      (tester) async {
        final repository = FakePrivacyZoneRepository(
          createError: Exception('create failed'),
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
          ),
        );
        await tester.pumpAndSettle();

        await enterValidPrivacyZoneFormValues(tester);

        await tester.tap(find.byKey(PrivacyZoneFormScreen.saveButtonKey));
        await tester.pumpAndSettle();

        expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);
        expect(
          find.byKey(PrivacyZoneFormScreen.submissionMessageKey),
          findsOneWidget,
        );
        expect(
          find.text('Failed to create privacy zone. Please try again.'),
          findsOneWidget,
        );

        final labelField = tester.widget<TextFormField>(
          find.byKey(PrivacyZoneFormScreen.labelFieldKey),
        );
        final latitudeField = tester.widget<TextFormField>(
          find.byKey(PrivacyZoneFormScreen.latitudeFieldKey),
        );
        final longitudeField = tester.widget<TextFormField>(
          find.byKey(PrivacyZoneFormScreen.longitudeFieldKey),
        );
        final radiusField = tester.widget<TextFormField>(
          find.byKey(PrivacyZoneFormScreen.radiusFieldKey),
        );

        expect(labelField.controller?.text, 'Home');
        expect(latitudeField.controller?.text, '40.7128');
        expect(longitudeField.controller?.text, '-74.0060');
        expect(radiusField.controller?.text, '250');
      },
    );

    testWidgets('failed create keeps unsaved-change back guard active', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository(
        createError: Exception('create failed'),
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
        ),
      );
      await tester.pumpAndSettle();

      await enterValidPrivacyZoneFormValues(tester);
      await tester.tap(find.byKey(PrivacyZoneFormScreen.saveButtonKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(repository.createZoneCallCount, 1);
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.byType(PrivacyZoneFormScreen), findsOneWidget);
      expect(find.text(privacyZoneFormExitRouteText), findsNothing);
    });

    testWidgets(
      'current-location success fills latitude and longitude fields',
      (tester) async {
        final repository = FakePrivacyZoneRepository();
        final locationService = FakePrivacyZoneLocationService(
          const PrivacyZoneCurrentLocationResult.success(
            PrivacyZoneCoordinates(latitude: 37.422, longitude: -122.084),
          ),
        );

        await tester.pumpWidget(
          buildPrivacyZoneFormRouterScreen(
            repository: repository,
            locationService: locationService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(PrivacyZoneFormScreen.currentLocationButtonKey),
        );
        await tester.pumpAndSettle();

        final latitudeField = tester.widget<TextFormField>(
          find.byKey(PrivacyZoneFormScreen.latitudeFieldKey),
        );
        final longitudeField = tester.widget<TextFormField>(
          find.byKey(PrivacyZoneFormScreen.longitudeFieldKey),
        );

        expect(latitudeField.controller?.text, '37.422000');
        expect(longitudeField.controller?.text, '-122.084000');
      },
    );

    testWidgets('current-location denied shows user-facing message', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository();
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        ),
      );

      await tester.pumpWidget(
        buildPrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(PrivacyZoneFormScreen.currentLocationButtonKey),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(PrivacyZoneFormScreen.currentLocationMessageKey),
        findsOneWidget,
      );
      expect(
        find.text(
          'Location permission denied. Enable it to autofill coordinates.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('current-location permanently denied shows settings guidance', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository();
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDeniedForever,
        ),
      );

      await tester.pumpWidget(
        buildPrivacyZoneFormRouterScreen(
          repository: repository,
          locationService: locationService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(PrivacyZoneFormScreen.currentLocationButtonKey),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Location permission is permanently denied. Update app settings to autofill coordinates.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'current-location lookup failure shows non-silent error message',
      (tester) async {
        final repository = FakePrivacyZoneRepository();
        final locationService = FakePrivacyZoneLocationService(
          const PrivacyZoneCurrentLocationResult.failure(
            PrivacyZoneCurrentLocationFailure.lookupFailed,
          ),
        );

        await tester.pumpWidget(
          buildPrivacyZoneFormRouterScreen(
            repository: repository,
            locationService: locationService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(PrivacyZoneFormScreen.currentLocationButtonKey),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Unable to read current location. Please enter coordinates manually.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'radius slider is present with default and updates label and text field',
      (tester) async {
        final repository = FakePrivacyZoneRepository();
        final locationService = FakePrivacyZoneLocationService(
          const PrivacyZoneCurrentLocationResult.failure(
            PrivacyZoneCurrentLocationFailure.permissionDenied,
          ),
        );

        await tester.pumpWidget(
          buildPrivacyZoneFormRouterScreen(
            repository: repository,
            locationService: locationService,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(PrivacyZoneFormScreen.radiusSliderKey),
          findsOneWidget,
        );

        final slider = tester.widget<Slider>(
          find.byKey(PrivacyZoneFormScreen.radiusSliderKey),
        );
        expect(slider.value, 200);
        expect(slider.min, 50);
        expect(slider.max, 1000);

        expect(find.text('Radius: 200 m'), findsOneWidget);

        final radiusField = tester.widget<TextFormField>(
          find.byKey(PrivacyZoneFormScreen.radiusFieldKey),
        );
        expect(radiusField.controller?.text, '200');

        final sliderFinder = find.byKey(PrivacyZoneFormScreen.radiusSliderKey);
        final sliderTopLeft = tester.getTopLeft(sliderFinder);
        final sliderSize = tester.getSize(sliderFinder);
        await tester.tapAt(
          Offset(
            sliderTopLeft.dx + sliderSize.width * 0.5,
            sliderTopLeft.dy + sliderSize.height / 2,
          ),
        );
        await tester.pumpAndSettle();

        final updatedSlider = tester.widget<Slider>(
          find.byKey(PrivacyZoneFormScreen.radiusSliderKey),
        );
        expect(updatedSlider.value, 550);

        expect(find.text('Radius: 550 m'), findsOneWidget);

        final updatedRadiusField = tester.widget<TextFormField>(
          find.byKey(PrivacyZoneFormScreen.radiusFieldKey),
        );
        expect(updatedRadiusField.controller?.text, '550');
      },
    );

    testWidgets(
      'radius text field clamps to slider-matched value on focus loss',
      (tester) async {
        final repository = FakePrivacyZoneRepository();
        final locationService = FakePrivacyZoneLocationService(
          const PrivacyZoneCurrentLocationResult.failure(
            PrivacyZoneCurrentLocationFailure.permissionDenied,
          ),
        );

        await tester.pumpWidget(
          buildPrivacyZoneFormRouterScreen(
            repository: repository,
            locationService: locationService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(PrivacyZoneFormScreen.radiusFieldKey),
          '77',
        );
        await tester.pumpAndSettle();

        final slider = tester.widget<Slider>(
          find.byKey(PrivacyZoneFormScreen.radiusSliderKey),
        );
        expect(slider.value, 100);
        expect(find.text('Radius: 100 m'), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(PrivacyZoneFormScreen.labelFieldKey),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(PrivacyZoneFormScreen.labelFieldKey));
        await tester.pumpAndSettle();

        final radiusField = tester.widget<TextFormField>(
          find.byKey(PrivacyZoneFormScreen.radiusFieldKey),
        );
        expect(radiusField.controller?.text, '100');
      },
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:uff/src/features/profile/application/privacy_zone_location_service.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';
import 'package:uff/src/features/profile/presentation/privacy_zone_form_screen.dart';
import 'package:uff/src/features/profile/presentation/privacy_zone_map_preview.dart';
import 'package:uff/src/features/profile/presentation/profile_routes.dart';

import '../../../test_helpers/mapbox_platform_channel_stub.dart';
import '../privacy_zone_test_support.dart';
import 'privacy_zone_form_screen_test_support.dart';

// ## Test Scenarios
// - [positive] Save payload uses map-selected coordinates with exact values
// - [negative] Manual text entry overrides previously map-selected coordinates
// - [positive] Edit mode re-centers map from stored zone coordinates
void main() {
  final mapCameraAnimationRecorder = MapCameraAnimationRecorder();
  setUpMapboxPlatformChannelStub(
    channelSuffix: 12,
    mapCameraAnimationRecorder: mapCameraAnimationRecorder,
  );

  group('PrivacyZoneFormScreen map coordinate contract', () {
    setUp(mapCameraAnimationRecorder.reset);

    testWidgets(
      'manual text entry overrides previously map-selected coordinates',
      (
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

        await tester.enterText(
          find.byKey(PrivacyZoneFormScreen.labelFieldKey),
          'Home',
        );

        expect(find.byType(MapWidget), findsOneWidget);
        _invokeCoordinateSelectionSeam(
          tester,
          latitude: 34.052235,
          longitude: -118.243683,
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(PrivacyZoneFormScreen.latitudeFieldKey),
          '51.5074',
        );
        await tester.enterText(
          find.byKey(PrivacyZoneFormScreen.longitudeFieldKey),
          '-0.1278',
        );
        await tester.pumpAndSettle();

        final latField = tester.widget<TextFormField>(
          find.byKey(PrivacyZoneFormScreen.latitudeFieldKey),
        );
        final lonField = tester.widget<TextFormField>(
          find.byKey(PrivacyZoneFormScreen.longitudeFieldKey),
        );
        expect(latField.controller?.text, '51.5074');
        expect(lonField.controller?.text, '-0.1278');

        await tester.tap(find.byKey(PrivacyZoneFormScreen.saveButtonKey));
        await tester.pumpAndSettle();

        expect(repository.createZoneCallCount, 1);
        expect(repository.lastCreateZoneCall?.latitude, 51.5074);
        expect(repository.lastCreateZoneCall?.longitude, -0.1278);
      },
    );

    testWidgets(
      'save succeeds with map-selected coordinates and exact payload values',
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
          find.byKey(PrivacyZoneFormScreen.labelFieldKey),
          'Home',
        );

        expect(find.byType(MapWidget), findsOneWidget);
        _invokeCoordinateSelectionSeam(
          tester,
          latitude: 34.052235,
          longitude: -118.243683,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(PrivacyZoneFormScreen.saveButtonKey));
        await tester.pumpAndSettle();

        expect(repository.createZoneCallCount, 1);
        expect(repository.lastCreateZoneCall?.label, 'Home');
        expect(repository.lastCreateZoneCall?.latitude, 34.052235);
        expect(repository.lastCreateZoneCall?.longitude, -118.243683);
        expect(repository.lastCreateZoneCall?.radiusMeters, 200);
        expect(find.text(privacyZoneListRouteText), findsOneWidget);
      },
    );

    testWidgets('edit mode re-centers map from existing zone coordinates', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository(
        zonesToReturn: const [
          PrivacyZone(
            id: 'zone-1',
            userId: 'user-1',
            label: 'Home',
            latitude: 34.052235,
            longitude: -118.243683,
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
          initialLocation: '${ProfileRoutes.privacyZonesPath}/zone-1',
        ),
      );
      await tester.pumpAndSettle();

      final latField = tester.widget<TextFormField>(
        find.byKey(PrivacyZoneFormScreen.latitudeFieldKey),
      );
      final lonField = tester.widget<TextFormField>(
        find.byKey(PrivacyZoneFormScreen.longitudeFieldKey),
      );
      expect(latField.controller?.text, '34.052235');
      expect(lonField.controller?.text, '-118.243683');
      expect(mapCameraAnimationRecorder.flyToCount, 1);
      expect(
        mapCameraAnimationRecorder.lastFlyToCenter,
        const RecordedPointAnnotation(
          latitude: 34.052235,
          longitude: -118.243683,
        ),
      );
      expect(find.byType(MapWidget), findsOneWidget);
    });
  });
}

void _invokeCoordinateSelectionSeam(
  WidgetTester tester, {
  required double latitude,
  required double longitude,
}) {
  final previewWidget = tester.widget<PrivacyZoneMapPreview>(
    find.byType(PrivacyZoneMapPreview),
  );
  final dynamic dynamicPreviewWidget = previewWidget;
  final Object? seamCandidate;
  try {
    // ignore: avoid_dynamic_calls, reason: Stage-2 red tests must probe a not-yet-implemented seam by name.
    seamCandidate = dynamicPreviewWidget.onCoordinateSelected;
    // ignore: avoid_catching_errors, reason: The seam is intentionally absent on current placeholder code.
  } on NoSuchMethodError {
    fail(
      'PrivacyZoneMapPreview must expose an onCoordinateSelected callback seam.',
    );
  }
  if (seamCandidate is! void Function(double, double)) {
    fail(
      'PrivacyZoneMapPreview.onCoordinateSelected must be a coordinate callback.',
    );
  }
  seamCandidate(latitude, longitude);
}

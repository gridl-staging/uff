import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:uff/src/features/profile/application/privacy_zone_location_service.dart';
import 'package:uff/src/features/profile/presentation/privacy_zone_form_screen.dart';
import 'package:uff/src/features/profile/presentation/privacy_zone_map_preview.dart';

import '../../../test_helpers/mapbox_platform_channel_stub.dart';
import '../privacy_zone_test_support.dart';
import 'privacy_zone_form_screen_test_support.dart';

// ## Test Scenarios
// - [positive] MapWidget renders above the manual coordinate fields
// - [positive] onCoordinateSelected callback writes exact six-decimal lat/lon
// - [positive] Radius slider updates polygon geometry to the selected radius
// - [positive] Current-location autofill re-centers rendered map state
// - [edge] Dispose ignores recoverable Mapbox polygon cleanup failures
// - [statemachine] In-flight current-location request blocks duplicate taps

class PendingPrivacyZoneLocationService implements PrivacyZoneLocationService {
  PendingPrivacyZoneLocationService(this.completer);

  final Completer<PrivacyZoneCurrentLocationResult> completer;
  int callCount = 0;

  @override
  Future<PrivacyZoneCurrentLocationResult> fetchCurrentLocation() {
    callCount++;
    return completer.future;
  }
}

void main() {
  final polygonAnnotationRecorder = PolygonAnnotationRecorder();
  final mapCameraAnimationRecorder = MapCameraAnimationRecorder();
  setUpMapboxPlatformChannelStub(
    channelSuffix: 9,
    polygonAnnotationRecorder: polygonAnnotationRecorder,
    mapCameraAnimationRecorder: mapCameraAnimationRecorder,
  );

  group('PrivacyZoneFormScreen coordinate preview', () {
    setUp(() {
      polygonAnnotationRecorder.reset();
      mapCameraAnimationRecorder.reset();
    });

    testWidgets(
      'map surface renders as MapWidget above manual lat/lon fields',
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

        expect(find.byType(MapWidget), findsOneWidget);

        final mapCenter = tester.getCenter(
          find.byType(MapWidget),
        );
        final latFieldCenter = tester.getCenter(
          find.byKey(PrivacyZoneFormScreen.latitudeFieldKey),
        );
        expect(mapCenter.dy, lessThan(latFieldCenter.dy));
      },
    );

    testWidgets('onCoordinateSelected writes exact six-decimal coordinates', (
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

      expect(find.byType(MapWidget), findsOneWidget);
      _invokeCoordinateSelectionSeam(
        tester,
        latitude: 34.052235,
        longitude: -118.243683,
      );
      await tester.pump();

      final latField = tester.widget<TextFormField>(
        find.byKey(PrivacyZoneFormScreen.latitudeFieldKey),
      );
      final lonField = tester.widget<TextFormField>(
        find.byKey(PrivacyZoneFormScreen.longitudeFieldKey),
      );
      expect(latField.controller?.text, '34.052235');
      expect(lonField.controller?.text, '-118.243683');
    });

    testWidgets(
      'after coordinate selection radius slider updates polygon annotation',
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

        _invokeCoordinateSelectionSeam(
          tester,
          latitude: 34.052235,
          longitude: -118.243683,
        );
        await tester.pumpAndSettle();
        expect(polygonAnnotationRecorder.createdPolygons, hasLength(1));

        final defaultRadiusMeters = _sampleRadiusMetersFromRecordedPolygon(
          centerLatitude: 34.052235,
          centerLongitude: -118.243683,
          polygon: polygonAnnotationRecorder.createdPolygons.last,
        );

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

        final radiusField = tester.widget<TextFormField>(
          find.byKey(PrivacyZoneFormScreen.radiusFieldKey),
        );
        expect(radiusField.controller?.text, '550');
        expect(polygonAnnotationRecorder.updateCount, 1);
        expect(polygonAnnotationRecorder.updatedPolygons, hasLength(1));

        final updatedRadiusMeters = _sampleRadiusMetersFromRecordedPolygon(
          centerLatitude: 34.052235,
          centerLongitude: -118.243683,
          polygon: polygonAnnotationRecorder.updatedPolygons.single,
        );
        expect(defaultRadiusMeters, closeTo(200, 12));
        expect(updatedRadiusMeters, closeTo(550, 12));
      },
    );

    testWidgets('current-location autofill re-centers rendered map state', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository();
      final locationService = FakePrivacyZoneLocationService(
        const PrivacyZoneCurrentLocationResult.success(
          PrivacyZoneCoordinates(latitude: 12.345678, longitude: -98.765432),
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

      final latField = tester.widget<TextFormField>(
        find.byKey(PrivacyZoneFormScreen.latitudeFieldKey),
      );
      final lonField = tester.widget<TextFormField>(
        find.byKey(PrivacyZoneFormScreen.longitudeFieldKey),
      );
      expect(latField.controller?.text, '12.345678');
      expect(lonField.controller?.text, '-98.765432');
      expect(mapCameraAnimationRecorder.flyToCount, 1);
      expect(
        mapCameraAnimationRecorder.lastFlyToCenter,
        const RecordedPointAnnotation(
          latitude: 12.345678,
          longitude: -98.765432,
        ),
      );
    });

    testWidgets('dispose ignores recoverable polygon cleanup failures', (
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

      _invokeCoordinateSelectionSeam(
        tester,
        latitude: 34.052235,
        longitude: -118.243683,
      );
      await tester.pumpAndSettle();
      expect(polygonAnnotationRecorder.createdPolygons, hasLength(1));

      polygonAnnotationRecorder.throwRecoverableOnDeleteAll = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Disposal cannot await native cleanup, so this verifies that the
      // fire-and-forget cleanup still owns the expected recoverable failure.
      expect(polygonAnnotationRecorder.deleteAllCount, 1);
      expect(tester.takeException(), null);
    });

    testWidgets('in-flight current-location request blocks duplicate taps', (
      tester,
    ) async {
      final repository = FakePrivacyZoneRepository();
      final lookupCompleter = Completer<PrivacyZoneCurrentLocationResult>();
      final locationService = PendingPrivacyZoneLocationService(
        lookupCompleter,
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
      await tester.pump();
      await tester.tap(
        find.byKey(PrivacyZoneFormScreen.currentLocationButtonKey),
      );
      await tester.pump();

      expect(locationService.callCount, 1);

      lookupCompleter.complete(
        const PrivacyZoneCurrentLocationResult.success(
          PrivacyZoneCoordinates(latitude: 1.234567, longitude: 2.345678),
        ),
      );
      await tester.pumpAndSettle();
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

double _sampleRadiusMetersFromRecordedPolygon({
  required double centerLatitude,
  required double centerLongitude,
  required RecordedPolygonAnnotation polygon,
}) {
  final ring = polygon.rings.first;
  final sample = ring.first;
  return _haversineDistanceMeters(
    startLatitude: centerLatitude,
    startLongitude: centerLongitude,
    endLatitude: sample.latitude,
    endLongitude: sample.longitude,
  );
}

double _haversineDistanceMeters({
  required double startLatitude,
  required double startLongitude,
  required double endLatitude,
  required double endLongitude,
}) {
  const earthRadiusMeters = 6371000.0;
  final deltaLatRadians = _toRadians(endLatitude - startLatitude);
  final deltaLonRadians = _toRadians(endLongitude - startLongitude);
  final startLatRadians = _toRadians(startLatitude);
  final endLatRadians = _toRadians(endLatitude);

  final a =
      (sin(deltaLatRadians / 2) * sin(deltaLatRadians / 2)) +
      cos(startLatRadians) *
          cos(endLatRadians) *
          sin(deltaLonRadians / 2) *
          sin(deltaLonRadians / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusMeters * c;
}

double _toRadians(double degrees) => degrees * (pi / 180.0);

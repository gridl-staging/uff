import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uff/src/features/maps/data/mapbox_channel_errors.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';
import 'package:uff/src/features/maps/presentation/map_view.dart';

import '../../../test_helpers/mapbox_platform_channel_stub.dart';

// ## Test Scenarios
// - [positive] The map-input diff helper detects route and follow-mode updates
// - [positive] The map-input diff helper detects photo marker changes
// - [statemachine] Repeated north-up action requests are treated as distinct
//   map-input updates even when the mode and heading booleans are unchanged
// - [positive] The viewport builder uses heading-following perspective semantics
//   when heading-following is enabled
// - [positive] The viewport builder uses constant-0 north-up bearing semantics
//   when heading-following is disabled
// - [edge] The viewport builder returns null when live location following is
//   disabled
// - [edge] forRoute([]) returns the default fallback camera position
// - [positive] Camera position centers on route bounds midpoint
// - [positive] Camera zooms farther out for wider routes
// - [error] Recoverable Mapbox channel exceptions are classified separately
//   from unrelated channel/platform failures
// - [error] Denied location permission keeps the follow-user viewport disabled
//   even if later north-up requests change the widget inputs
// - [positive] PhotoMarkerInput equality compares all fields
// - [edge] PhotoMarkerInput with same coords but different previewUrl is not equal
// - [edge] Initial empty photo markers do not create point-annotation work
// - [positive] Point annotation manager creates annotations for each photo marker
// - [positive] Point annotation manager deletes stale markers before re-render
// - [edge] Empty photo markers list triggers deleteAll but no creates
// - [error] Recoverable channel error during photo marker create does not crash MapView
const _permissionMethodChannel = MethodChannel(
  'flutter.baseflow.com/permissions/methods',
);
const _grantedPermissionStatus = 1;
const _deniedPermissionStatus = 0;

final _pointRecorder = PointAnnotationRecorder();

void main() {
  setUpMapboxPlatformChannelStub(pointAnnotationRecorder: _pointRecorder);

  MapViewInputs mapViewInputs({
    List<RoutePoint> routePoints = const [],
    List<PhotoMarkerInput> photoMarkers = const [],
    bool followUserLocation = false,
    MapViewUserLocationCameraMode cameraMode =
        MapViewUserLocationCameraMode.perspective,
    bool followUserHeading = true,
    int northUpRequestGeneration = 0,
  }) {
    return MapViewInputs(
      routePoints: routePoints,
      photoMarkers: photoMarkers,
      followUserLocation: followUserLocation,
      cameraMode: cameraMode,
      followUserHeading: followUserHeading,
      northUpRequestGeneration: northUpRequestGeneration,
    );
  }

  Future<void> stubLocationPermissionStatus(
    WidgetTester tester, {
    required int status,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _permissionMethodChannel,
      (MethodCall call) async {
        switch (call.method) {
          case 'checkPermissionStatus':
            return status;
          case 'checkServiceStatus':
            return _grantedPermissionStatus;
          case 'openAppSettings':
            return true;
          case 'shouldShowRequestPermissionRationale':
            return false;
          case 'requestPermissions':
            final requestedPermissions =
                (call.arguments as List<dynamic>? ?? const <dynamic>[])
                    .whereType<int>();
            return {
              for (final permission in requestedPermissions) permission: status,
            };
        }
        return null;
      },
    );
  }

  group('MapViewCameraPosition', () {
    test('centers the camera on the route bounds midpoint', () {
      final cameraPosition = MapViewCameraPosition.forRoute(const [
        RoutePoint(latitude: 10, longitude: 20),
        RoutePoint(latitude: 12, longitude: 24),
        RoutePoint(latitude: 11, longitude: 22),
      ]);

      expect(cameraPosition.latitude, 11);
      expect(cameraPosition.longitude, 22);
    });

    test('returns default fallback for an empty route list', () {
      final cameraPosition = MapViewCameraPosition.forRoute(const []);

      expect(cameraPosition.latitude, 40.7128);
      expect(cameraPosition.longitude, -74.0060);
      expect(cameraPosition.zoom, 12.0);
    });

    test('zooms farther out for wider routes', () {
      final compactRouteCamera = MapViewCameraPosition.forRoute(const [
        RoutePoint(latitude: 40.7128, longitude: -74.0060),
        RoutePoint(latitude: 40.7129, longitude: -74.0059),
      ]);
      final broadRouteCamera = MapViewCameraPosition.forRoute(const [
        RoutePoint(latitude: 40.7128, longitude: -74.0060),
        RoutePoint(latitude: 40.9128, longitude: -73.8060),
      ]);

      expect(compactRouteCamera.zoom, greaterThan(broadRouteCamera.zoom));
    });
  });

  group('didMapViewInputsChange', () {
    test(
      'detects route coordinate changes even when the point count is stable',
      () {
        expect(
          didMapViewInputsChange(
            previousInputs: mapViewInputs(
              routePoints: [
                const RoutePoint(latitude: 40.7128, longitude: -74.0060),
                const RoutePoint(latitude: 40.7198, longitude: -73.9980),
              ],
            ),
            nextInputs: mapViewInputs(
              routePoints: [
                const RoutePoint(latitude: 40.7308, longitude: -73.9975),
                const RoutePoint(latitude: 40.7368, longitude: -73.9890),
              ],
            ),
          ),
          isTrue,
        );
      },
    );

    test('ignores rebuilt route lists when the values are unchanged', () {
      expect(
        didMapViewInputsChange(
          previousInputs: mapViewInputs(
            routePoints: [
              const RoutePoint(latitude: 40.7128, longitude: -74.0060),
              const RoutePoint(latitude: 40.7198, longitude: -73.9980),
            ],
          ),
          nextInputs: mapViewInputs(
            routePoints: [
              const RoutePoint(latitude: 40.7128, longitude: -74.0060),
              const RoutePoint(latitude: 40.7198, longitude: -73.9980),
            ],
          ),
        ),
        isFalse,
      );
    });

    test('detects follow-user mode changes', () {
      expect(
        didMapViewInputsChange(
          previousInputs: mapViewInputs(),
          nextInputs: mapViewInputs(
            followUserLocation: true,
          ),
        ),
        isTrue,
      );
    });

    test('detects user-location camera-mode changes', () {
      expect(
        didMapViewInputsChange(
          previousInputs: mapViewInputs(
            followUserLocation: true,
          ),
          nextInputs: mapViewInputs(
            followUserLocation: true,
            cameraMode: MapViewUserLocationCameraMode.topDown,
          ),
        ),
        isTrue,
      );
    });

    test('detects north-up heading mode changes', () {
      expect(
        didMapViewInputsChange(
          previousInputs: mapViewInputs(
            followUserLocation: true,
          ),
          nextInputs: mapViewInputs(
            followUserLocation: true,
            followUserHeading: false,
          ),
        ),
        isTrue,
      );
    });

    test('treats repeated north-up action requests as new map inputs even when '
        'camera mode and heading flags stay at perspective + false', () {
      expect(
        didMapViewInputsChange(
          previousInputs: mapViewInputs(
            followUserLocation: true,
            followUserHeading: false,
            northUpRequestGeneration: 3,
          ),
          nextInputs: mapViewInputs(
            followUserLocation: true,
            followUserHeading: false,
            northUpRequestGeneration: 4,
          ),
        ),
        isTrue,
      );
    });
  });

  group('buildUserLocationViewportState', () {
    test('builds a heading-following perspective viewport by default', () {
      final viewport = buildUserLocationViewportState(
        followUserLocation: true,
        zoom: 16,
        cameraMode: MapViewUserLocationCameraMode.perspective,
        followUserHeading: true,
      );
      final followPuckViewport = viewport as FollowPuckViewportState?;

      expect(followPuckViewport?.pitch, 45);
      expect(
        followPuckViewport?.bearing.runtimeType,
        FollowPuckViewportStateBearingHeading,
      );
    });

    test('builds a north-up top-down viewport when requested', () {
      final viewport = buildUserLocationViewportState(
        followUserLocation: true,
        zoom: 16,
        cameraMode: MapViewUserLocationCameraMode.topDown,
        followUserHeading: false,
      );
      final followPuckViewport = viewport as FollowPuckViewportState?;

      expect(followPuckViewport?.pitch, 0);
      expect(
        followPuckViewport?.bearing.runtimeType,
        FollowPuckViewportStateBearingConstant,
      );
      final bearing =
          followPuckViewport?.bearing
              as FollowPuckViewportStateBearingConstant?;
      expect(bearing?.bearing, 0);
    });

    test('returns null when follow-user-location is disabled', () {
      final viewport = buildUserLocationViewportState(
        followUserLocation: false,
        zoom: 16,
        cameraMode: MapViewUserLocationCameraMode.perspective,
        followUserHeading: true,
      );

      expect(viewport, null);
    });
  });

  group('isRecoverableMapboxChannelError', () {
    test('returns true for mapbox channel-error platform exceptions', () {
      final error = PlatformException(
        code: 'channel-error',
        message:
            'Unable to establish connection on channel: '
            '"dev.flutter.pigeon.mapbox_maps_flutter._PolylineAnnotationMessenger.setLineJoin.0".',
      );

      expect(isRecoverableMapboxChannelError(error), isTrue);
    });

    test(
      'returns false for channel-error platform exceptions with unrelated messages',
      () {
        final error = PlatformException(
          code: 'channel-error',
          message:
              'Unable to establish connection on channel: '
              '"dev.flutter.pigeon.other_plugin.method.0".',
        );

        expect(isRecoverableMapboxChannelError(error), isFalse);
      },
    );

    test(
      'returns true for patrol annotation manager missing-plugin errors',
      () {
        final error = MissingPluginException(
          'No implementation found for method annotation#create_manager on '
          'channel plugins.flutter.io.1',
        );

        expect(isRecoverableMapboxChannelError(error), isTrue);
      },
    );

    test('returns false for non-channel-error platform exceptions', () {
      final error = PlatformException(
        code: 'permission-denied',
        message: 'location permission denied',
      );

      expect(isRecoverableMapboxChannelError(error), isFalse);
    });

    test('returns false for non-platform exceptions', () {
      expect(isRecoverableMapboxChannelError(StateError('x')), isFalse);
    });
  });

  testWidgets(
    'denied location permission keeps the viewport disabled across north-up updates',
    (tester) async {
      await stubLocationPermissionStatus(
        tester,
        status: _deniedPermissionStatus,
      );
      addTearDown(
        () => stubLocationPermissionStatus(
          tester,
          status: _grantedPermissionStatus,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MapView(
              followUserLocation: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialMapWidget = tester.widget<MapWidget>(find.byType(MapWidget));
      expect(initialMapWidget.viewport, isNull);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MapView(
              followUserLocation: true,
              followUserHeading: false,
              northUpRequestGeneration: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final updatedMapWidget = tester.widget<MapWidget>(find.byType(MapWidget));
      expect(updatedMapWidget.viewport, isNull);
    },
  );

  testWidgets(
    'concurrent location permission requests share a single platform call',
    (tester) async {
      var requestPermissionsCallCount = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _permissionMethodChannel,
        (MethodCall call) async {
          switch (call.method) {
            case 'checkPermissionStatus':
              return _deniedPermissionStatus;
            case 'checkServiceStatus':
              return _grantedPermissionStatus;
            case 'openAppSettings':
              return true;
            case 'shouldShowRequestPermissionRationale':
              return false;
            case 'requestPermissions':
              requestPermissionsCallCount += 1;
              await Future<void>.delayed(const Duration(milliseconds: 50));
              final requestedPermissions =
                  (call.arguments as List<dynamic>? ?? const <dynamic>[])
                      .whereType<int>();
              return {
                for (final permission in requestedPermissions)
                  permission: _grantedPermissionStatus,
              };
          }
          return null;
        },
      );
      addTearDown(
        () => stubLocationPermissionStatus(
          tester,
          status: _grantedPermissionStatus,
        ),
      );
      addTearDown(resetLocationPermissionRequestState);

      final results = (await tester.runAsync(
        () => Future.wait([
          requestLocationWhenInUsePermission(),
          requestLocationWhenInUsePermission(),
        ]),
      ))!;

      expect(
        results.every((status) => status == PermissionStatus.granted),
        isTrue,
      );
      expect(requestPermissionsCallCount, 1);
    },
  );

  group('didMapViewInputsChange with photo markers', () {
    test('detects photo marker additions', () {
      expect(
        didMapViewInputsChange(
          previousInputs: mapViewInputs(),
          nextInputs: mapViewInputs(
            photoMarkers: const [
              PhotoMarkerInput(
                photoId: 'photo-1',
                latitude: 40.7128,
                longitude: -74.0060,
              ),
            ],
          ),
        ),
        isTrue,
      );
    });

    test('ignores rebuilt marker lists when the values are unchanged', () {
      expect(
        didMapViewInputsChange(
          previousInputs: mapViewInputs(
            photoMarkers: const [
              PhotoMarkerInput(
                photoId: 'photo-1',
                latitude: 40.7128,
                longitude: -74.0060,
                previewUrl: 'https://example.com/thumb.jpg',
              ),
            ],
          ),
          nextInputs: mapViewInputs(
            photoMarkers: const [
              PhotoMarkerInput(
                photoId: 'photo-1',
                latitude: 40.7128,
                longitude: -74.0060,
                previewUrl: 'https://example.com/thumb.jpg',
              ),
            ],
          ),
        ),
        isFalse,
      );
    });

    test('detects preview URL changes for existing markers', () {
      expect(
        didMapViewInputsChange(
          previousInputs: mapViewInputs(
            photoMarkers: const [
              PhotoMarkerInput(
                photoId: 'photo-1',
                latitude: 40.7128,
                longitude: -74.0060,
                previewUrl: 'https://example.com/old.jpg',
              ),
            ],
          ),
          nextInputs: mapViewInputs(
            photoMarkers: const [
              PhotoMarkerInput(
                photoId: 'photo-1',
                latitude: 40.7128,
                longitude: -74.0060,
                previewUrl: 'https://example.com/new.jpg',
              ),
            ],
          ),
        ),
        isTrue,
      );
    });
  });

  group('PhotoMarkerInput', () {
    test('equality compares all fields', () {
      const first = PhotoMarkerInput(
        photoId: 'photo-1',
        latitude: 40.7128,
        longitude: -74.0060,
        previewUrl: 'https://example.com/thumb.jpg',
      );
      const second = PhotoMarkerInput(
        photoId: 'photo-1',
        latitude: 40.7128,
        longitude: -74.0060,
        previewUrl: 'https://example.com/thumb.jpg',
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('different previewUrl produces inequality', () {
      const withUrl = PhotoMarkerInput(
        photoId: 'photo-1',
        latitude: 40.7128,
        longitude: -74.0060,
        previewUrl: 'https://example.com/thumb.jpg',
      );
      const withoutUrl = PhotoMarkerInput(
        photoId: 'photo-1',
        latitude: 40.7128,
        longitude: -74.0060,
      );

      expect(withUrl, isNot(withoutUrl));
    });
  });

  group('photo marker point-annotation lifecycle', () {
    setUp(() {
      _pointRecorder.reset();
      // Override to iOS so MapWidget creates a UiKitView platform view,
      // triggering onPlatformViewCreated → onMapCreated → _renderPhotoMarkers.
      // On macOS (the test host) MapWidget renders a Text placeholder and
      // the map creation callback never fires.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'initial empty photo markers do not create or clear point annotations',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MapView(),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();

        expect(_pointRecorder.deleteAllCount, 0);
        expect(_pointRecorder.createCount, 0);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'creates one point annotation per photo marker on initial render',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MapView(
                photoMarkers: [
                  PhotoMarkerInput(
                    photoId: 'p-1',
                    latitude: 40.7128,
                    longitude: -74.0060,
                  ),
                  PhotoMarkerInput(
                    photoId: 'p-2',
                    latitude: 40.7198,
                    longitude: -73.9980,
                  ),
                ],
              ),
            ),
          ),
        );
        // _resolveBitmap → picture.toImage() is an engine-level async op
        // that requires real async to complete.  The first test in the group
        // builds the placeholder bitmap from scratch (static cache is empty),
        // so it needs enough real-async time for the engine to finish.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();

        // deleteAll is called once before creating new markers.
        expect(_pointRecorder.deleteAllCount, 1);
        expect(_pointRecorder.createCount, 2);
        expect(
          _pointRecorder.createdPoints,
          const [
            RecordedPointAnnotation(latitude: 40.7128, longitude: -74.0060),
            RecordedPointAnnotation(latitude: 40.7198, longitude: -73.9980),
          ],
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'deletes stale markers and re-creates on rebuild with different markers',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MapView(
                photoMarkers: [
                  PhotoMarkerInput(
                    photoId: 'p-1',
                    latitude: 40.7128,
                    longitude: -74.0060,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();

        final deleteAllAfterFirst = _pointRecorder.deleteAllCount;
        final createAfterFirst = _pointRecorder.createCount;
        expect(deleteAllAfterFirst, 1);
        expect(createAfterFirst, 1);
        expect(
          _pointRecorder.createdPoints,
          const [
            RecordedPointAnnotation(latitude: 40.7128, longitude: -74.0060),
          ],
        );

        _pointRecorder.reset();

        // Rebuild with a different marker.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MapView(
                photoMarkers: [
                  PhotoMarkerInput(
                    photoId: 'p-2',
                    latitude: 40.7308,
                    longitude: -73.9975,
                  ),
                  PhotoMarkerInput(
                    photoId: 'p-3',
                    latitude: 40.7368,
                    longitude: -73.9890,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();

        expect(_pointRecorder.deleteAllCount, 1);
        expect(_pointRecorder.createCount, 2);
        expect(
          _pointRecorder.createdPoints,
          const [
            RecordedPointAnnotation(latitude: 40.7308, longitude: -73.9975),
            RecordedPointAnnotation(latitude: 40.7368, longitude: -73.9890),
          ],
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'empty photo markers list triggers deleteAll but no creates',
      (tester) async {
        // Start with markers.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MapView(
                photoMarkers: [
                  PhotoMarkerInput(
                    photoId: 'p-1',
                    latitude: 40.7128,
                    longitude: -74.0060,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();

        final createAfterFirst = _pointRecorder.createCount;
        expect(createAfterFirst, 1);

        _pointRecorder.reset();

        // Rebuild with empty markers.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MapView(),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();

        // deleteAll called for cleanup, but no new creates.
        expect(_pointRecorder.deleteAllCount, 1);
        expect(_pointRecorder.createCount, 0);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'recoverable channel error during photo marker create does not crash MapView',
      (tester) async {
        _pointRecorder
          ..reset()
          ..throwRecoverableOnCreate = true;

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MapView(
                photoMarkers: [
                  PhotoMarkerInput(
                    photoId: 'p-err',
                    latitude: 40.7128,
                    longitude: -74.0060,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();

        // The create was attempted but the error was swallowed gracefully.
        // No annotations recorded because the stub threw before incrementing.
        expect(_pointRecorder.createCount, 0);

        // Widget survived — no crash, still in the tree.
        expect(find.byType(MapView), findsOneWidget);

        _pointRecorder.reset();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  });
}

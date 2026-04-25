import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:uff/src/features/profile/application/privacy_zone_location_service.dart';

/// ## Test Scenarios
/// - [positive] Returns coordinates when location permission is already granted
/// - [negative] Returns permissionDenied when request is still denied
/// - [negative] Returns permissionDeniedForever when request escalates to permanent denial
/// - [error] Returns lookupFailed when permission check throws
/// - [error] Returns lookupFailed when permission request throws
/// - [error] Returns lookupFailed when current-position lookup throws

class _FakeGeolocatorPlatform extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  _FakeGeolocatorPlatform({
    required this.checkPermissionResult,
    this.requestPermissionResult,
    this.currentPosition,
    this.currentPositionError,
    this.checkPermissionError,
    this.requestPermissionError,
  });

  final LocationPermission checkPermissionResult;
  final LocationPermission? requestPermissionResult;
  final Position? currentPosition;
  final Object? currentPositionError;
  final Object? checkPermissionError;
  final Object? requestPermissionError;

  Never _throwConfiguredError(Object error) {
    if (error is Error) {
      throw error;
    }
    if (error is Exception) {
      throw error;
    }
    throw StateError('Unsupported test error type: ${error.runtimeType}');
  }

  @override
  Future<LocationPermission> checkPermission() async {
    final error = checkPermissionError;
    if (error != null) {
      _throwConfiguredError(error);
    }
    return checkPermissionResult;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    final error = requestPermissionError;
    if (error != null) {
      _throwConfiguredError(error);
    }
    return requestPermissionResult ?? checkPermissionResult;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    final error = currentPositionError;
    if (error != null) {
      _throwConfiguredError(error);
    }

    final position = currentPosition;
    if (position == null) {
      throw StateError('currentPosition must be set for getCurrentPosition');
    }
    return position;
  }
}

Position _buildPosition({
  required double latitude,
  required double longitude,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    accuracy: 1,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  late GeolocatorPlatform originalPlatform;

  setUp(() {
    originalPlatform = GeolocatorPlatform.instance;
  });

  tearDown(() {
    GeolocatorPlatform.instance = originalPlatform;
  });

  group('GeolocatorPrivacyZoneLocationService', () {
    test('returns coordinates when permission is already granted', () async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        checkPermissionResult: LocationPermission.whileInUse,
        currentPosition: _buildPosition(latitude: 40.71, longitude: -74.01),
      );

      final result = await GeolocatorPrivacyZoneLocationService()
          .fetchCurrentLocation();

      expect(result.isSuccess, isTrue);
      expect(result.coordinates?.latitude, 40.71);
      expect(result.coordinates?.longitude, -74.01);
      expect(result.failure, isNull);
    });

    test(
      'returns permission denied when the request is still denied',
      () async {
        GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
          checkPermissionResult: LocationPermission.denied,
          requestPermissionResult: LocationPermission.denied,
        );

        final result = await GeolocatorPrivacyZoneLocationService()
            .fetchCurrentLocation();

        expect(result.isSuccess, isFalse);
        expect(
          result.failure,
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        );
      },
    );

    test(
      'returns permission denied forever when the request escalates',
      () async {
        GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
          checkPermissionResult: LocationPermission.denied,
          requestPermissionResult: LocationPermission.deniedForever,
        );

        final result = await GeolocatorPrivacyZoneLocationService()
            .fetchCurrentLocation();

        expect(result.isSuccess, isFalse);
        expect(
          result.failure,
          PrivacyZoneCurrentLocationFailure.permissionDeniedForever,
        );
      },
    );

    test('returns lookup failure when permission checks throw', () async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        checkPermissionResult: LocationPermission.denied,
        checkPermissionError: StateError('permission check failed'),
      );

      final result = await GeolocatorPrivacyZoneLocationService()
          .fetchCurrentLocation();

      expect(result.isSuccess, isFalse);
      expect(result.failure, PrivacyZoneCurrentLocationFailure.lookupFailed);
    });

    test('returns lookup failure when permission requests throw', () async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        checkPermissionResult: LocationPermission.denied,
        requestPermissionError: StateError('permission request failed'),
      );

      final result = await GeolocatorPrivacyZoneLocationService()
          .fetchCurrentLocation();

      expect(result.isSuccess, isFalse);
      expect(result.failure, PrivacyZoneCurrentLocationFailure.lookupFailed);
    });

    test(
      'returns lookup failure when current-position lookup throws',
      () async {
        GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
          checkPermissionResult: LocationPermission.whileInUse,
          currentPositionError: Exception('position lookup failed'),
        );

        final result = await GeolocatorPrivacyZoneLocationService()
            .fetchCurrentLocation();

        expect(result.isSuccess, isFalse);
        expect(result.failure, PrivacyZoneCurrentLocationFailure.lookupFailed);
      },
    );
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

final Provider<PrivacyZoneLocationService> privacyZoneLocationServiceProvider =
    Provider<PrivacyZoneLocationService>(
      (ref) => GeolocatorPrivacyZoneLocationService(),
    );

// ignore: one_member_abstracts, reason: this single-method boundary is an intentional seam for geolocation injection in tests.
abstract interface class PrivacyZoneLocationService {
  Future<PrivacyZoneCurrentLocationResult> fetchCurrentLocation();
}

enum PrivacyZoneCurrentLocationFailure {
  permissionDenied,
  permissionDeniedForever,
  lookupFailed,
}

@immutable
class PrivacyZoneCoordinates {
  const PrivacyZoneCoordinates({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

/// NOTE(stuart): Document PrivacyZoneCurrentLocationResult.
@immutable
class PrivacyZoneCurrentLocationResult {
  const PrivacyZoneCurrentLocationResult._({
    this.coordinates,
    this.failure,
  });

  const PrivacyZoneCurrentLocationResult.success(PrivacyZoneCoordinates value)
    : this._(coordinates: value);

  const PrivacyZoneCurrentLocationResult.failure(
    PrivacyZoneCurrentLocationFailure reason,
  ) : this._(failure: reason);

  final PrivacyZoneCoordinates? coordinates;
  final PrivacyZoneCurrentLocationFailure? failure;

  bool get isSuccess => coordinates != null;
}

/// NOTE(stuart): Document GeolocatorPrivacyZoneLocationService.
class GeolocatorPrivacyZoneLocationService
    implements PrivacyZoneLocationService {
  @override
  Future<PrivacyZoneCurrentLocationResult> fetchCurrentLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        return const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDenied,
        );
      }

      if (permission == LocationPermission.deniedForever) {
        return const PrivacyZoneCurrentLocationResult.failure(
          PrivacyZoneCurrentLocationFailure.permissionDeniedForever,
        );
      }

      final position = await Geolocator.getCurrentPosition();
      return PrivacyZoneCurrentLocationResult.success(
        PrivacyZoneCoordinates(
          latitude: position.latitude,
          longitude: position.longitude,
        ),
      );
    } on Object {
      return const PrivacyZoneCurrentLocationResult.failure(
        PrivacyZoneCurrentLocationFailure.lookupFailed,
      );
    }
  }
}

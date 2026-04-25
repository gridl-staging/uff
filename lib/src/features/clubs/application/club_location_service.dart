import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

final Provider<ClubLocationService> clubLocationServiceProvider =
    Provider<ClubLocationService>(
      (ref) => GeolocatorClubLocationService(),
    );

// ignore: one_member_abstracts, reason: this single-method boundary is an intentional seam for geolocation injection in tests.
abstract interface class ClubLocationService {
  Future<ClubCoordinates?> fetchCurrentLocation();
}

@immutable
class ClubCoordinates {
  const ClubCoordinates({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

/// TODO: Document GeolocatorClubLocationService.
class GeolocatorClubLocationService implements ClubLocationService {
  @override
  Future<ClubCoordinates?> fetchCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition();
      return ClubCoordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on Object {
      return null;
    }
  }
}

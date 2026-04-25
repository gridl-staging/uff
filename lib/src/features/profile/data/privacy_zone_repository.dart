import 'package:uff/src/features/profile/domain/privacy_zone.dart';

abstract interface class PrivacyZoneRepository {
  Future<List<PrivacyZone>> loadZones();

  Future<PrivacyZone> createZone({
    required String label,
    required double latitude,
    required double longitude,
    required int radiusMeters,
  });

  Future<void> updateZone(PrivacyZone zone);

  Future<void> deleteZone(String id);
}

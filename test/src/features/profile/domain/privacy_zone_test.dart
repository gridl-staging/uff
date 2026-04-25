import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';

/// ## Test Scenarios
/// - [positive] fromJson maps all fields from a full Supabase row
/// - [positive] fromJson maps snake_case columns to camelCase fields
/// - [edge] fromJson handles integer latitude and longitude values
void main() {
  group('PrivacyZone.fromJson', () {
    test('maps all fields from a full Supabase row', () {
      final row = <String, dynamic>{
        'id': 'zone-abc-123',
        'user_id': 'user-def-456',
        'label': 'Home',
        'latitude': 51.5074,
        'longitude': -0.1278,
        'radius_meters': 200,
        'created_at': '2026-03-16T10:00:00Z',
        'updated_at': '2026-03-16T10:00:00Z',
      };

      final zone = PrivacyZone.fromJson(row);

      expect(zone.id, 'zone-abc-123');
      expect(zone.userId, 'user-def-456');
      expect(zone.label, 'Home');
      expect(zone.latitude, 51.5074);
      expect(zone.longitude, -0.1278);
      expect(zone.radiusMeters, 200);
    });

    test('maps snake_case columns to camelCase fields', () {
      final row = <String, dynamic>{
        'id': 'z1',
        'user_id': 'u1',
        'label': 'Work',
        'latitude': 40.7128,
        'longitude': -74.006,
        'radius_meters': 500,
      };

      final zone = PrivacyZone.fromJson(row);

      expect(zone.userId, 'u1');
      expect(zone.radiusMeters, 500);
    });

    test('handles integer latitude and longitude values', () {
      final row = <String, dynamic>{
        'id': 'z2',
        'user_id': 'u2',
        'label': 'Equator',
        'latitude': 0,
        'longitude': 0,
        'radius_meters': 100,
      };

      final zone = PrivacyZone.fromJson(row);

      expect(zone.latitude, 0.0);
      expect(zone.longitude, 0.0);
    });
  });
}

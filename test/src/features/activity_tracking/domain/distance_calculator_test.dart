import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/domain/distance_calculator.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

void main() {
  group('calculateGeodesicDistanceMeters edge cases', () {
    test('calculates antipodal points near the global maximum distance', () {
      const start = GeoCoordinate(latitude: 0, longitude: 0);
      const end = GeoCoordinate(latitude: 0, longitude: 180);

      final distance = calculateGeodesicDistanceMeters(start, end);

      expect(distance, closeTo(20015087, 100));
    });

    test('calculates pure north-south movement with zero longitude delta', () {
      const start = GeoCoordinate(latitude: 0, longitude: 0);
      const end = GeoCoordinate(latitude: 1, longitude: 0);

      final distance = calculateGeodesicDistanceMeters(start, end);

      expect(distance, closeTo(111195, 50));
    });

    test('calculates southern hemisphere route with negative coordinates', () {
      const sydney = GeoCoordinate(latitude: -33.8688, longitude: 151.2093);
      const melbourne = GeoCoordinate(latitude: -37.8136, longitude: 144.9631);

      final distance = calculateGeodesicDistanceMeters(sydney, melbourne);

      expect(distance, closeTo(714000, 5000));
    });

    test('preserves small positive GPS jitter distance around one meter', () {
      const start = GeoCoordinate(latitude: 0, longitude: 0);
      const end = GeoCoordinate(latitude: 0, longitude: 0.000009);

      final distance = calculateGeodesicDistanceMeters(start, end);

      expect(distance, closeTo(1.0, 0.5));
    });

    test('handles near-pole movement where longitude is degenerate', () {
      const start = GeoCoordinate(latitude: 90, longitude: 0);
      const end = GeoCoordinate(latitude: 89.9999, longitude: 0);

      final distance = calculateGeodesicDistanceMeters(start, end);

      expect(distance, closeTo(11.1, 0.5));
    });
  });
}

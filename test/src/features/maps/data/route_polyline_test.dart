import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';

/// ## Test Scenarios
/// - [positive] GeoJSON LineString feature creation from 2+ points
/// - [edge] Empty point list returns null (no geometry)
/// - [edge] Single-point list returns null (no geometry)
/// - [positive] RoutePoint equality compares latitude and longitude values
/// - [positive] RoutePolylineStyle defaults match expected constant values

void main() {
  group('RoutePolyline', () {
    test('RoutePoint equality compares latitude and longitude values', () {
      const reference = RoutePoint(latitude: 40.7128, longitude: -74.0060);

      expect(
        reference,
        const RoutePoint(latitude: 40.7128, longitude: -74.0060),
      );
      expect(
        reference,
        isNot(const RoutePoint(latitude: 40.7130, longitude: -74.0060)),
      );
    });

    test('returns no geometry for an empty point list', () {
      final feature = RoutePolyline.toGeoJsonFeature(const []);
      expect(feature, isNull);
    });

    test('returns no geometry for a single-point list', () {
      final feature = RoutePolyline.toGeoJsonFeature(
        const [RoutePoint(latitude: 37.7749, longitude: -122.4194)],
      );
      expect(feature, isNull);
    });

    test('builds a valid GeoJSON LineString for two or more points', () {
      final feature = RoutePolyline.toGeoJsonFeature(
        const [
          RoutePoint(latitude: 37.7749, longitude: -122.4194),
          RoutePoint(latitude: 37.7754, longitude: -122.4189),
          RoutePoint(latitude: 37.7760, longitude: -122.4181),
        ],
      );

      expect(feature!['type'], 'Feature');
      expect(feature['properties'], <String, Object?>{});

      final geometry = feature['geometry']! as Map<String, Object?>;
      expect(geometry['type'], 'LineString');
      expect(
        geometry['coordinates'],
        [
          [-122.4194, 37.7749],
          [-122.4189, 37.7754],
          [-122.4181, 37.7760],
        ],
      );
    });
  });

  group('RoutePolylineStyle', () {
    test('defaults match expected constant values', () {
      const style = RoutePolylineStyle();

      // 0xFFFF5A1F is the _defaultPolylineColor defined in route_polyline.dart
      expect(style.lineColorArgb, 0xFFFF5A1F);
      expect(style.lineWidth, 3.5);
      expect(style.lineCap, LineCap.ROUND);
      expect(style.lineJoin, LineJoin.ROUND);
    });
  });
}

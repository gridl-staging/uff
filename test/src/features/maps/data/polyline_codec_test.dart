// Scenario tags use bracket syntax enforced by the test standards script.
// ignore_for_file: comment_references

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/maps/data/polyline_codec.dart';

/// ## Test Scenarios
/// - [positive] Google encoded polylines decode to exact expected coordinates.
/// - [edge] Null and empty encoded strings return an empty route.
/// - [edge] Malformed encoded strings return an empty route.
/// - [negative] Oversized encoded strings fail closed instead of decoding on the UI path.
void main() {
  group('decodePolyline', () {
    test('decodes canonical Google polyline example coordinates', () {
      final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');

      expect(points.length, 3);
      expect(points[0].latitude, closeTo(38.5, 0.000001));
      expect(points[0].longitude, closeTo(-120.2, 0.000001));
      expect(points[1].latitude, closeTo(40.7, 0.000001));
      expect(points[1].longitude, closeTo(-120.95, 0.000001));
      expect(points[2].latitude, closeTo(43.252, 0.000001));
      expect(points[2].longitude, closeTo(-126.453, 0.000001));
    });

    test('null input returns an empty list', () {
      final points = decodePolyline(null);
      expect(points, isEmpty);
    });

    test('empty input returns an empty list', () {
      final points = decodePolyline('');
      expect(points, isEmpty);
    });

    test('malformed input returns an empty list', () {
      final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq');
      expect(points, isEmpty);
    });

    test('oversized input returns an empty list', () {
      final oversizedPolyline = List<String>.filled(10000, '?').join();

      final points = decodePolyline(oversizedPolyline);

      expect(points.length, 0);
    });
  });
}

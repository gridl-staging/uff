import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/maps/data/offline_tile_spike.dart';

/// ## Test Scenarios
/// - [positive] Downloader invoked with plan values (tileRegionId, bounds, style, zoom range)
/// - [positive] Safe wrapper returns true on successful download
/// - [error] Safe wrapper returns false and captures error on download failure
/// - [edge] Invalid bounds (minLat >= maxLat or minLon >= maxLon) throw AssertionError
/// - [positive] toGeoJsonPolygon produces a 5-vertex ring matching min/max lat/lon corners
///
/// NOTE: This is a spike file. `MapboxOfflineTileSpike.downloadRegion` is
/// intentionally untested because it calls the real Mapbox SDK.

void main() {
  group('OfflineTileRegionBounds', () {
    test('throws when minLatitude is not less than maxLatitude', () {
      expect(
        () => OfflineTileRegionBounds(
          minLatitude: 40,
          minLongitude: -74,
          maxLatitude: 40,
          maxLongitude: -73,
        ),
        // Stage 3: AssertionError has no stable message field; isA is the
        // most concrete matcher for a Dart assert() guard.
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws when minLongitude is not less than maxLongitude', () {
      expect(
        () => OfflineTileRegionBounds(
          minLatitude: 40,
          minLongitude: -73,
          maxLatitude: 41,
          maxLongitude: -74,
        ),
        // Stage 3: AssertionError has no stable message field; isA is the
        // most concrete matcher for a Dart assert() guard.
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('OfflineTileRegionBounds.toGeoJsonPolygon', () {
    test('produces a 5-vertex ring matching min/max lat/lon corners', () {
      const bounds = OfflineTileRegionBounds(
        minLatitude: 40.70,
        minLongitude: -74.02,
        maxLatitude: 40.73,
        maxLongitude: -73.97,
      );

      final polygon = bounds.toGeoJsonPolygon();

      // Mapbox Polygon.toJson() produces a standard GeoJSON structure.
      expect(polygon['type'], 'Polygon');

      final coordinates = polygon['coordinates'] as List<dynamic>;
      expect(coordinates.length, 1); // single ring

      final ring = coordinates[0] as List<dynamic>;
      expect(ring.length, 5); // 4 corners + closing vertex

      // Verify corners: [lon, lat] ordering per GeoJSON spec.
      // SW corner
      expect((ring[0] as List<dynamic>)[0], -74.02);
      expect((ring[0] as List<dynamic>)[1], 40.70);
      // SE corner
      expect((ring[1] as List<dynamic>)[0], -73.97);
      expect((ring[1] as List<dynamic>)[1], 40.70);
      // NE corner
      expect((ring[2] as List<dynamic>)[0], -73.97);
      expect((ring[2] as List<dynamic>)[1], 40.73);
      // NW corner
      expect((ring[3] as List<dynamic>)[0], -74.02);
      expect((ring[3] as List<dynamic>)[1], 40.73);
      // Closing vertex matches SW
      expect((ring[4] as List<dynamic>)[0], -74.02);
      expect((ring[4] as List<dynamic>)[1], 40.70);
    });
  });

  group('defaultStage2OfflineTileSpikePlan', () {
    test('uses a bounded NYC region and zoom range 10-16', () {
      const plan = defaultStage2OfflineTileSpikePlan;

      expect(plan.tileRegionId, 'stage-02-lower-manhattan');
      expect(plan.minZoom, 10);
      expect(plan.maxZoom, 16);
      expect(plan.styleUri, 'mapbox://styles/mapbox/streets-v12');
      expect(plan.bounds.minLatitude, closeTo(40.7005, 0.0001));
      expect(plan.bounds.minLongitude, closeTo(-74.0196, 0.0001));
      expect(plan.bounds.maxLatitude, closeTo(40.7259, 0.0001));
      expect(plan.bounds.maxLongitude, closeTo(-73.9712, 0.0001));
    });
  });

  group('runStage2OfflineTileSpike', () {
    test('invokes downloader with the plan values', () async {
      var invocationCount = 0;
      String? capturedTileRegionId;
      OfflineTileRegionBounds? capturedBounds;
      String? capturedStyleUri;
      int? capturedMinZoom;
      int? capturedMaxZoom;

      await runStage2OfflineTileSpike(
        downloadRegion:
            ({
              required String tileRegionId,
              required OfflineTileRegionBounds bounds,
              String styleUri = '',
              int minZoom = -1,
              int maxZoom = -1,
            }) async {
              invocationCount += 1;
              capturedTileRegionId = tileRegionId;
              capturedBounds = bounds;
              capturedStyleUri = styleUri;
              capturedMinZoom = minZoom;
              capturedMaxZoom = maxZoom;
            },
      );

      expect(invocationCount, 1);
      expect(
        capturedTileRegionId,
        defaultStage2OfflineTileSpikePlan.tileRegionId,
      );
      expect(capturedBounds, same(defaultStage2OfflineTileSpikePlan.bounds));
      expect(capturedStyleUri, defaultStage2OfflineTileSpikePlan.styleUri);
      expect(capturedMinZoom, defaultStage2OfflineTileSpikePlan.minZoom);
      expect(capturedMaxZoom, defaultStage2OfflineTileSpikePlan.maxZoom);
    });
  });

  group('runStage2OfflineTileSpikeSafely', () {
    test('returns true on successful download', () async {
      final result = await runStage2OfflineTileSpikeSafely(
        downloadRegion:
            ({
              required String tileRegionId,
              required OfflineTileRegionBounds bounds,
              String styleUri = '',
              int minZoom = -1,
              int maxZoom = -1,
            }) async {},
      );

      expect(result, isTrue);
    });

    test('returns false and captures error on download failure', () async {
      Object? capturedError;

      final result = await runStage2OfflineTileSpikeSafely(
        downloadRegion:
            ({
              required String tileRegionId,
              required OfflineTileRegionBounds bounds,
              String styleUri = '',
              int minZoom = -1,
              int maxZoom = -1,
            }) async {
              throw StateError('download failed');
            },
        onError: (error, _) {
          capturedError = error;
        },
      );

      expect(result, isFalse);
      expect(
        capturedError,
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'download failed',
        ),
      );
    });
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:tracelet/tracelet.dart';
import 'package:uff/src/features/activity_tracking/data/tracelet_tracking_engine.dart';

Location _buildLocation({
  required String timestamp,
  required String uuid,
  required Coords coords,
}) {
  return Location(
    coords: coords,
    timestamp: timestamp,
    isMoving: true,
    uuid: uuid,
    odometer: 0,
  );
}

/// ## Test Scenarios
/// - `[positive]` Sampling-gate defaults and overrides flow into GeoConfig unchanged.
/// - `[positive]` Normalization maps raw Tracelet locations to UTC tracking points.
/// - `[edge]` Malformed timestamps are dropped without fabricating points.
/// - `[isolation]` Provider wiring resolves the engine implementation used in production.
void main() {
  group('TraceletTrackingEngine sampling gate', () {
    test('single engine-owned gate drives GeoConfig interval and distance', () {
      final engine = TraceletTrackingEngine(
        minLocationInterval: const Duration(seconds: 7),
        minDistanceMeters: 42,
      );

      final samplingGate = engine.samplingGate;
      expect(samplingGate.minLocationInterval, const Duration(seconds: 7));
      expect(samplingGate.minDistanceMeters, 42);

      final geoConfig = samplingGate.toGeoConfig();
      expect(geoConfig.locationUpdateInterval, 7000);
      expect(geoConfig.distanceFilter, 42);
    });

    test('constructor defaults flow through the same sampling owner seam', () {
      const expectedDefaultInterval = Duration(seconds: 2);
      const expectedDefaultDistanceMeters = 5.0;
      expect(
        TraceletSamplingGate.defaultMinLocationInterval,
        expectedDefaultInterval,
      );
      expect(
        TraceletSamplingGate.defaultMinDistanceMeters,
        expectedDefaultDistanceMeters,
      );

      const defaultGate = TraceletSamplingGate();
      final engineGate = TraceletTrackingEngine().samplingGate;
      final geoConfig = engineGate.toGeoConfig();
      final ownerGeoConfig = defaultGate.toGeoConfig();

      expect(engineGate.minLocationInterval, defaultGate.minLocationInterval);
      expect(engineGate.minDistanceMeters, defaultGate.minDistanceMeters);
      expect(
        geoConfig.locationUpdateInterval,
        ownerGeoConfig.locationUpdateInterval,
      );
      expect(geoConfig.distanceFilter, ownerGeoConfig.distanceFilter);
    });

    test('trackingEngineProvider keeps default engine sampling seam', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final engine = container.read(trackingEngineProvider);
      expect(engine.runtimeType, TraceletTrackingEngine);

      final samplingGate = (engine as TraceletTrackingEngine).samplingGate;
      expect(
        samplingGate.minLocationInterval,
        TraceletSamplingGate.defaultMinLocationInterval,
      );
      expect(
        samplingGate.minDistanceMeters,
        TraceletSamplingGate.defaultMinDistanceMeters,
      );
    });
  });

  group('TraceletTrackingEngine normalization seam', () {
    test(
      'maps recovered samples 1:1 with UTC parsing and no route thinning',
      () {
        final locations = [
          _buildLocation(
            timestamp: '2026-03-25T13:00:00.000Z',
            uuid: 'loc-1',
            coords: const Coords(
              latitude: 40.71,
              longitude: -74,
              altitude: 12,
              accuracy: 4,
              speed: 2,
            ),
          ),
          _buildLocation(
            timestamp: '2026-03-25T13:00:05.000Z',
            uuid: 'loc-2',
            coords: const Coords(
              latitude: 40.72,
              longitude: -73.99,
              altitude: 14,
              accuracy: 5,
              speed: 2.5,
            ),
          ),
          _buildLocation(
            timestamp: '2026-03-25T13:00:10.000Z',
            uuid: 'loc-3',
            coords: const Coords(
              latitude: 40.73,
              longitude: -73.98,
              altitude: 15,
              accuracy: 6,
              speed: 3,
            ),
          ),
        ];

        final points = normalizeTraceletLocations(
          locations: locations,
          sessionId: 99,
        );

        expect(points, hasLength(locations.length));
        expect(points.map((p) => p.coordinate.latitude).toList(), [
          40.71,
          40.72,
          40.73,
        ]);
        expect(points.map((p) => p.coordinate.longitude).toList(), [
          -74,
          -73.99,
          -73.98,
        ]);
        expect(points.every((p) => p.timestamp.isUtc), isTrue);
        expect(points.first.timestamp, DateTime.utc(2026, 3, 25, 13));
        expect(points.last.timestamp, DateTime.utc(2026, 3, 25, 13, 0, 10));
      },
    );

    test(
      'applies afterTimestamp recovery filter with no additional remapping',
      () {
        final locations = [
          _buildLocation(
            timestamp: '2026-03-25T13:00:00.000Z',
            uuid: 'loc-1',
            coords: const Coords(latitude: 40.71, longitude: -74),
          ),
          _buildLocation(
            timestamp: '2026-03-25T13:00:05.000Z',
            uuid: 'loc-2',
            coords: const Coords(latitude: 40.72, longitude: -73.99),
          ),
          _buildLocation(
            timestamp: '2026-03-25T13:00:10.000Z',
            uuid: 'loc-3',
            coords: const Coords(latitude: 40.73, longitude: -73.98),
          ),
        ];

        final points = normalizeTraceletLocations(
          locations: locations,
          sessionId: 123,
          afterTimestamp: DateTime.utc(2026, 3, 25, 13, 0, 5),
        );

        expect(points, hasLength(1));
        expect(points.single.sessionId, 123);
        expect(points.single.timestamp, DateTime.utc(2026, 3, 25, 13, 0, 10));
        expect(points.single.coordinate.latitude, 40.73);
        expect(points.single.coordinate.longitude, -73.98);
      },
    );

    test('drops malformed timestamps instead of fabricating fresh points', () {
      final points = normalizeTraceletLocations(
        locations: [
          _buildLocation(
            timestamp: 'not-a-timestamp',
            uuid: 'invalid-loc',
            coords: const Coords(latitude: 40.7, longitude: -74),
          ),
          _buildLocation(
            timestamp: '2026-03-25T13:00:10.000Z',
            uuid: 'valid-loc',
            coords: const Coords(latitude: 40.73, longitude: -73.98),
          ),
        ],
        sessionId: 456,
        afterTimestamp: DateTime.utc(2026, 3, 25, 13, 0, 5),
      );

      expect(points, hasLength(1));
      expect(points.single.sessionId, 456);
      expect(points.single.timestamp, DateTime.utc(2026, 3, 25, 13, 0, 10));
      expect(points.single.coordinate.latitude, 40.73);
      expect(points.single.coordinate.longitude, -73.98);
    });

    test(
      'single-location normalization returns null for malformed timestamps',
      () {
        final mapped = normalizeTraceletLocation(
          _buildLocation(
            timestamp: 'not-a-timestamp',
            uuid: 'invalid-loc',
            coords: const Coords(latitude: 40.7, longitude: -74),
          ),
          sessionId: 777,
        );

        expect(mapped, isNull);
      },
    );

    test('single-location mapping matches list normalization output', () {
      final location = _buildLocation(
        timestamp: '2026-03-25T13:00:00.000Z',
        uuid: 'loc-1',
        coords: const Coords(
          latitude: 40.71,
          longitude: -74,
          altitude: 12,
          accuracy: 4,
          speed: 2,
        ),
      );

      final mapped = normalizeTraceletLocation(location, sessionId: 777);
      final normalized = normalizeTraceletLocations(
        locations: [location],
        sessionId: 777,
      ).single;

      expect(mapped?.sessionId, normalized.sessionId);
      expect(mapped?.timestamp, normalized.timestamp);
      expect(mapped?.coordinate.latitude, normalized.coordinate.latitude);
      expect(mapped?.coordinate.longitude, normalized.coordinate.longitude);
      expect(mapped?.elevation, normalized.elevation);
      expect(mapped?.accuracy, normalized.accuracy);
      expect(mapped?.speed, normalized.speed);
    });
  });
}

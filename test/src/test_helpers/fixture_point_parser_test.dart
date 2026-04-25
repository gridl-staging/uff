import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'fixture_point_parser.dart';

void main() {
  group('parseFixturePointsFromJson', () {
    test(
      'loads existing 5k_run.json with all 7 fields, sensor fields null',
      () {
        // Load the real fixture file to validate backward compatibility.
        final json = File('e2e_test/test_data/5k_run.json').readAsStringSync();
        final points = parseFixturePointsFromJson(json, sessionId: 42);

        expect(points, hasLength(620));

        // All points should have the override sessionId.
        for (final point in points) {
          expect(point.sessionId, 42);
        }

        // First point field checks (from the known fixture).
        final first = points.first;
        expect(first.timestamp, DateTime.utc(2026, 3, 15, 10));
        expect(first.coordinate.latitude, closeTo(60.1699764, 1e-6));
        expect(first.coordinate.longitude, closeTo(24.9384, 1e-4));
        expect(first.elevation, closeTo(14.61, 1e-2));
        expect(first.accuracy, closeTo(6.31, 1e-2));
        expect(first.speed, closeTo(3.156, 1e-3));

        // Sensor fields must be null — 5k_run.json predates sensor support.
        expect(first.heartRateBpm, isNull);
        expect(first.cadenceRpm, isNull);
        expect(first.powerWatts, isNull);

        // Spot-check a few more points for sensor-null invariant.
        for (final point in points.take(10)) {
          expect(point.heartRateBpm, isNull);
          expect(point.cadenceRpm, isNull);
          expect(point.powerWatts, isNull);
        }
      },
    );

    test('parses heartRateBpm, cadenceRpm, powerWatts from JSON', () {
      final jsonString = jsonEncode([
        {
          'sessionId': 0,
          'timestamp': '2026-03-20T08:00:00.000Z',
          'latitude': 60.17,
          'longitude': 24.94,
          'elevation': 15.0,
          'accuracy': 5.0,
          'speed': 3.5,
          'heartRateBpm': 155,
          'cadenceRpm': 82.5,
          'powerWatts': 230,
        },
        {
          'sessionId': 0,
          'timestamp': '2026-03-20T08:00:05.000Z',
          'latitude': 60.171,
          'longitude': 24.941,
          'elevation': 16.0,
          'accuracy': 4.0,
          'speed': 3.2,
          'heartRateBpm': 160,
          'cadenceRpm': 84,
          'powerWatts': 245,
        },
      ]);

      final points = parseFixturePointsFromJson(jsonString, sessionId: 7);

      expect(points.length, 2);

      // First point — sensor fields present.
      expect(points[0].sessionId, 7);
      expect(points[0].heartRateBpm, 155);
      expect(points[0].cadenceRpm, 82.5);
      expect(points[0].powerWatts, 230);

      // Second point — integer cadenceRpm should be parsed as double.
      expect(points[1].heartRateBpm, 160);
      expect(points[1].cadenceRpm, 84.0);
      expect(points[1].powerWatts, 245);
    });

    test('mixed points: some with sensor fields, some without', () {
      final jsonString = jsonEncode([
        {
          'sessionId': 0,
          'timestamp': '2026-03-20T08:00:00.000Z',
          'latitude': 60.17,
          'longitude': 24.94,
          'elevation': 15.0,
          'accuracy': 5.0,
          'speed': 3.5,
          'heartRateBpm': 140,
        },
        {
          'sessionId': 0,
          'timestamp': '2026-03-20T08:00:05.000Z',
          'latitude': 60.171,
          'longitude': 24.941,
          'elevation': 16.0,
          'accuracy': 4.0,
          'speed': 3.2,
          // No sensor fields at all.
        },
      ]);

      final points = parseFixturePointsFromJson(jsonString, sessionId: 1);

      // First point has HR only.
      expect(points[0].heartRateBpm, 140);
      expect(points[0].cadenceRpm, isNull);
      expect(points[0].powerWatts, isNull);

      // Second point has no sensor fields.
      expect(points[1].heartRateBpm, isNull);
      expect(points[1].cadenceRpm, isNull);
      expect(points[1].powerWatts, isNull);
    });
  });
}

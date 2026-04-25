import 'dart:typed_data';

import 'package:fit_tool/fit_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/import/data/fit_importer.dart';
import 'package:uff/src/features/import/domain/import_normalizer.dart';

import 'fit_test_helpers.dart';

void main() {
  group('FitImporter.parse', () {
    test('extracts coordinates with semicircle conversion accuracy', () {
      final bytes = buildFitBytes(
        records: [
          FitTestRecord(
            timestampMs: fitBaseTimestamp,
            latitude: testLatitude,
            longitude: testLongitude,
          ),
          FitTestRecord(
            timestampMs: fitBaseTimestamp + 10000,
            latitude: testLatitude + 0.001,
            longitude: testLongitude + 0.001,
          ),
        ],
        sport: Sport.running,
      );

      final result = FitImporter.parse(bytes);

      expect(result.points, hasLength(2));
      expect(result.points[0].latitude, closeTo(testLatitude, 1e-6));
      expect(result.points[0].longitude, closeTo(testLongitude, 1e-6));
      expect(result.points[1].latitude, closeTo(testLatitude + 0.001, 1e-6));
    });

    test('converts FIT timestamps to DateTime correctly', () {
      final expectedTime = DateTime.utc(2024, 1, 1, 12);
      final bytes = buildFitBytes(
        records: [
          FitTestRecord(
            timestampMs: expectedTime.millisecondsSinceEpoch,
            latitude: 0,
            longitude: 0,
          ),
        ],
        sport: Sport.running,
      );

      final result = FitImporter.parse(bytes);

      expect(result.points.first.timestamp, expectedTime);
    });

    test('prefers enhancedAltitude over standard altitude', () {
      final bytes = buildFitBytes(
        records: [
          FitTestRecord(
            timestampMs: fitBaseTimestamp,
            latitude: 0,
            longitude: 0,
            altitude: 100,
            enhancedAltitude: 150.5,
          ),
          FitTestRecord(
            timestampMs: fitBaseTimestamp + 10000,
            latitude: 0,
            longitude: 0.001,
            altitude: 200,
          ),
        ],
        sport: Sport.running,
      );

      final result = FitImporter.parse(bytes);

      // First point: enhancedAltitude preferred over altitude
      expect(result.points[0].elevation, closeTo(150.5, 0.2));
      // Second point: falls back to altitude
      expect(result.points[1].elevation, closeTo(200, 0.2));
    });

    test('merges fractional cadence and falls back across cadence fields', () {
      final bytes = buildFitBytes(
        records: [
          FitTestRecord(
            timestampMs: fitBaseTimestamp,
            latitude: 0,
            longitude: 0,
            cadence: 90,
            fractionalCadence: 0.5,
          ),
          FitTestRecord(
            timestampMs: fitBaseTimestamp + 10000,
            latitude: 0,
            longitude: 0.001,
            cadence256: 85.75,
          ),
          FitTestRecord(
            timestampMs: fitBaseTimestamp + 20000,
            latitude: 0,
            longitude: 0.002,
            cadence: 85,
          ),
        ],
        sport: Sport.cycling,
      );

      final result = FitImporter.parse(bytes);

      // First point: integer cadence merged with fractional_cadence
      expect(result.points[0].cadenceRpm, closeTo(90.5, 0.1));
      // Second point: full-precision cadence256 still works when present
      expect(result.points[1].cadenceRpm, closeTo(85.75, 0.1));
      // Third point: falls back to integer cadence
      expect(result.points[2].cadenceRpm, 85);
    });

    test('maps sport enum to backend strings', () {
      final runBytes = buildFitBytes(
        records: [
          FitTestRecord(
            timestampMs: fitBaseTimestamp,
            latitude: 0,
            longitude: 0,
          ),
        ],
        sport: Sport.running,
      );
      final rideBytes = buildFitBytes(
        records: [
          FitTestRecord(
            timestampMs: fitBaseTimestamp,
            latitude: 0,
            longitude: 0,
          ),
        ],
        sport: Sport.cycling,
      );
      final unknownBytes = buildFitBytes(
        records: [
          FitTestRecord(
            timestampMs: fitBaseTimestamp,
            latitude: 0,
            longitude: 0,
          ),
        ],
        sport: Sport.golf,
      );
      final noSportBytes = buildFitBytes(
        records: [
          FitTestRecord(
            timestampMs: fitBaseTimestamp,
            latitude: 0,
            longitude: 0,
          ),
        ],
      );

      expect(FitImporter.parse(runBytes).sportType, 'run');
      expect(FitImporter.parse(rideBytes).sportType, 'ride');
      expect(FitImporter.parse(unknownBytes).sportType, 'workout');
      expect(FitImporter.parse(noSportBytes).sportType, 'workout');
    });

    test('extracts heart rate, cadence, and power sensor fields', () {
      final bytes = buildFitBytes(
        records: [
          FitTestRecord(
            timestampMs: fitBaseTimestamp,
            latitude: 0,
            longitude: 0,
            heartRate: 155,
            cadence: 92,
            power: 250,
          ),
        ],
        sport: Sport.cycling,
      );

      final result = FitImporter.parse(bytes);

      expect(result.points.first.heartRateBpm, 155);
      expect(result.points.first.cadenceRpm, 92);
      expect(result.points.first.powerWatts, 250);
    });

    test('extracts speed preferring enhancedSpeed', () {
      final bytes = buildFitBytes(
        records: [
          FitTestRecord(
            timestampMs: fitBaseTimestamp,
            latitude: 0,
            longitude: 0,
            speed: 3,
            enhancedSpeed: 3.5,
          ),
          FitTestRecord(
            timestampMs: fitBaseTimestamp + 10000,
            latitude: 0,
            longitude: 0.001,
            speed: 4,
          ),
        ],
        sport: Sport.running,
      );

      final result = FitImporter.parse(bytes);

      expect(result.points[0].speed, closeTo(3.5, 0.01));
      expect(result.points[1].speed, closeTo(4.0, 0.01));
    });
  });

  group('FitImporter.parse malformed input', () {
    test('truncated file bytes throws FormatException', () {
      final validBytes = buildFitBytes(
        records: [
          FitTestRecord(
            timestampMs: fitBaseTimestamp,
            latitude: 0,
            longitude: 0,
          ),
        ],
        sport: Sport.running,
      );
      // Truncate to half the file
      final truncated = Uint8List.sublistView(
        validBytes,
        0,
        validBytes.length ~/ 2,
      );

      expect(
        () => FitImporter.parse(truncated),
        throwsA(isA<FormatException>()),
      );
    });

    test('valid FIT with zero GPS records throws FormatException', () {
      final bytes = buildFitBytes(
        records: [
          FitTestRecord(timestampMs: fitBaseTimestamp),
          FitTestRecord(timestampMs: fitBaseTimestamp + 10000),
        ],
        sport: Sport.running,
      );

      expect(
        () => FitImporter.parse(bytes),
        throwsA(isA<FormatException>()),
      );
    });

    test('records missing position fields are skipped', () {
      final bytes = buildFitBytes(
        records: [
          FitTestRecord(
            timestampMs: fitBaseTimestamp,
            latitude: 0,
            longitude: 0,
          ),
          // Missing position
          FitTestRecord(timestampMs: fitBaseTimestamp + 10000),
          FitTestRecord(
            timestampMs: fitBaseTimestamp + 20000,
            latitude: 0,
            longitude: 0.001,
          ),
        ],
        sport: Sport.running,
      );

      final result = FitImporter.parse(bytes);

      expect(result.points, hasLength(2));
    });
  });

  group('FitImporter end-to-end', () {
    test('parse → normalize produces valid ImportedActivity', () {
      final bytes = buildFitBytes(
        records: [
          FitTestRecord(
            timestampMs: fitBaseTimestamp,
            latitude: 40.7128,
            longitude: -74.0060,
            enhancedAltitude: 10,
            heartRate: 140,
            cadence: 88,
            speed: 3,
          ),
          FitTestRecord(
            timestampMs: fitBaseTimestamp + 300000,
            latitude: 40.7138,
            longitude: -74.0050,
            enhancedAltitude: 20,
            heartRate: 155,
            cadence: 90,
            speed: 3.5,
          ),
          FitTestRecord(
            timestampMs: fitBaseTimestamp + 600000,
            latitude: 40.7148,
            longitude: -74.0040,
            enhancedAltitude: 30,
            heartRate: 160,
            cadence: 92,
            speed: 3.8,
          ),
          FitTestRecord(
            timestampMs: fitBaseTimestamp + 900000,
            latitude: 40.7158,
            longitude: -74.0030,
            enhancedAltitude: 25,
            heartRate: 150,
            cadence: 89,
            speed: 3.2,
          ),
          FitTestRecord(
            timestampMs: fitBaseTimestamp + 1200000,
            latitude: 40.7168,
            longitude: -74.0020,
            enhancedAltitude: 15,
            heartRate: 145,
            cadence: 86,
            speed: 3,
          ),
        ],
        sport: Sport.running,
      );

      final parsed = FitImporter.parse(bytes);
      final activity = normalizeImportedActivity(parsed);

      expect(activity.sportType, 'run');
      expect(activity.cleanedPoints, hasLength(5));

      // Valid coordinate ranges
      for (final point in activity.cleanedPoints) {
        expect(point.latitude, inInclusiveRange(-90, 90));
        expect(point.longitude, inInclusiveRange(-180, 180));
      }

      // Chronologically ordered timestamps
      for (var i = 1; i < activity.cleanedPoints.length; i++) {
        expect(
          activity.cleanedPoints[i].timestamp.isAfter(
            activity.cleanedPoints[i - 1].timestamp,
          ),
          isTrue,
        );
      }

      // Elevation and speed survive on cleaned points
      expect(activity.cleanedPoints[0].elevation, closeTo(10, 0.5));
      expect(activity.cleanedPoints[0].speed, closeTo(3.0, 0.1));

      // Pipeline-consistent metrics
      expect(
        activity.metrics.trackSummary.distanceMeters,
        closeTo(558, 5.0),
      );
      expect(
        activity.metrics.trackSummary.elevationGainMeters,
        closeTo(20, 0.1),
      );
    });
  });
}

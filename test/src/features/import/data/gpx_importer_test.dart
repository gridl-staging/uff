import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/import/data/gpx_importer.dart';
import 'package:uff/src/features/import/domain/import_normalizer.dart';

const _basicGpx = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test"
  xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Morning Run</name>
    <type>running</type>
    <trkseg>
      <trkpt lat="40.7128" lon="-74.0060">
        <ele>10.0</ele>
        <time>2024-01-01T12:00:00Z</time>
      </trkpt>
      <trkpt lat="40.7138" lon="-74.0050">
        <ele>20.0</ele>
        <time>2024-01-01T12:05:00Z</time>
      </trkpt>
      <trkpt lat="40.7148" lon="-74.0040">
        <ele>30.0</ele>
        <time>2024-01-01T12:10:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>
''';

const _garminExtensionsGpx = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
  <trk>
    <trkseg>
      <trkpt lat="40.7128" lon="-74.0060">
        <ele>10.0</ele>
        <time>2024-01-01T12:00:00Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>155</gpxtpx:hr>
            <gpxtpx:cad>90</gpxtpx:cad>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
      <trkpt lat="40.7138" lon="-74.0050">
        <ele>20.0</ele>
        <time>2024-01-01T12:05:00Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>160</gpxtpx:hr>
            <gpxtpx:cad>92</gpxtpx:cad>
            <gpxtpx:power>250</gpxtpx:power>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>
''';

const _multiSegmentGpx = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test"
  xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <trkseg>
      <trkpt lat="40.7128" lon="-74.0060">
        <ele>10.0</ele>
        <time>2024-01-01T12:00:00Z</time>
      </trkpt>
      <trkpt lat="40.7138" lon="-74.0050">
        <ele>15.0</ele>
        <time>2024-01-01T12:05:00Z</time>
      </trkpt>
    </trkseg>
    <trkseg>
      <trkpt lat="40.7148" lon="-74.0040">
        <ele>20.0</ele>
        <time>2024-01-01T12:10:00Z</time>
      </trkpt>
      <trkpt lat="40.7158" lon="-74.0030">
        <ele>25.0</ele>
        <time>2024-01-01T12:15:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>
''';

void main() {
  group('GpxImporter.parse', () {
    test('extracts trkpt lat/lon/ele/time', () {
      final result = GpxImporter.parse(_basicGpx);

      expect(result.points, hasLength(3));
      expect(result.points[0].latitude, 40.7128);
      expect(result.points[0].longitude, -74.0060);
      expect(result.points[0].elevation, 10.0);
      expect(result.points[0].timestamp, DateTime.utc(2024, 1, 1, 12));
      expect(result.points[2].latitude, 40.7148);
      expect(result.points[2].elevation, 30.0);
    });

    test('parses Garmin TrackPointExtension heart rate and cadence', () {
      final result = GpxImporter.parse(_garminExtensionsGpx);

      expect(result.points[0].heartRateBpm, 155);
      expect(result.points[0].cadenceRpm, 90);
      expect(result.points[0].powerWatts, isNull);
      expect(result.points[1].heartRateBpm, 160);
      expect(result.points[1].cadenceRpm, 92);
      expect(result.points[1].powerWatts, 250);
    });

    test('infers sport from type element', () {
      final result = GpxImporter.parse(_basicGpx);

      expect(result.sportType, 'run');
    });

    test('defaults to workout when type is absent', () {
      const noTypeGpx = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1"><trk><trkseg>
  <trkpt lat="0" lon="0"><time>2024-01-01T12:00:00Z</time></trkpt>
</trkseg></trk></gpx>
''';

      final result = GpxImporter.parse(noTypeGpx);

      expect(result.sportType, 'workout');
    });

    test('concatenates multi-segment tracks into single ordered list', () {
      final result = GpxImporter.parse(_multiSegmentGpx);

      expect(result.points, hasLength(4));
      expect(result.points[0].latitude, 40.7128);
      expect(result.points[3].latitude, 40.7158);

      // Verify chronological order
      for (var i = 1; i < result.points.length; i++) {
        expect(
          result.points[i].timestamp.isAfter(result.points[i - 1].timestamp),
          isTrue,
        );
      }
    });

    test('preserves track name as title', () {
      final result = GpxImporter.parse(_basicGpx);

      expect(result.title, 'Morning Run');
    });

    test('handles missing extensions gracefully', () {
      final result = GpxImporter.parse(_basicGpx);

      expect(result.points[0].heartRateBpm, isNull);
      expect(result.points[0].cadenceRpm, isNull);
      expect(result.points[0].powerWatts, isNull);
    });
  });

  group('GpxImporter.parse malformed input', () {
    test('empty string throws FormatException', () {
      expect(
        () => GpxImporter.parse(''),
        throwsA(isA<FormatException>()),
      );
    });

    test('valid XML with no trkpt elements throws FormatException', () {
      const noPoints = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1"><trk><trkseg></trkseg></trk></gpx>
''';

      expect(
        () => GpxImporter.parse(noPoints),
        throwsA(isA<FormatException>()),
      );
    });

    test('track points with missing time elements are skipped', () {
      const mixedTimeGpx = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1"><trk><trkseg>
  <trkpt lat="40.7128" lon="-74.0060">
    <time>2024-01-01T12:00:00Z</time>
  </trkpt>
  <trkpt lat="40.7138" lon="-74.0050">
  </trkpt>
  <trkpt lat="40.7148" lon="-74.0040">
    <time>2024-01-01T12:10:00Z</time>
  </trkpt>
</trkseg></trk></gpx>
''';

      final result = GpxImporter.parse(mixedTimeGpx);

      expect(result.points, hasLength(2));
      expect(result.points[0].latitude, 40.7128);
      expect(result.points[1].latitude, 40.7148);
    });

    test('track points with non-numeric ele get null elevation', () {
      const badEleGpx = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1"><trk><trkseg>
  <trkpt lat="40.7128" lon="-74.0060">
    <ele>not_a_number</ele>
    <time>2024-01-01T12:00:00Z</time>
  </trkpt>
  <trkpt lat="40.7138" lon="-74.0050">
    <ele>20.0</ele>
    <time>2024-01-01T12:05:00Z</time>
  </trkpt>
</trkseg></trk></gpx>
''';

      final result = GpxImporter.parse(badEleGpx);

      expect(result.points, hasLength(2));
      expect(result.points[0].elevation, isNull);
      expect(result.points[1].elevation, 20.0);
    });
  });

  group('GpxImporter end-to-end', () {
    test('parse → normalize produces valid ImportedActivity', () {
      final parsed = GpxImporter.parse(_basicGpx);
      final activity = normalizeImportedActivity(parsed);

      expect(activity.sportType, 'run');
      expect(activity.title, 'Morning Run');
      expect(activity.cleanedPoints, hasLength(3));
      expect(activity.metrics.trackSummary.distanceMeters, closeTo(279, 5.0));
      expect(
        activity.metrics.trackSummary.elevationGainMeters,
        closeTo(20, 0.1),
      );
    });
  });
}

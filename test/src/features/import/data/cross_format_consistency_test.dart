import 'package:fit_tool/fit_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/import/data/fit_importer.dart';
import 'package:uff/src/features/import/data/gpx_importer.dart';
import 'package:uff/src/features/import/domain/import_normalizer.dart';

import 'fit_test_helpers.dart';

/// Shared activity coordinates and timestamps used for cross-format tests.
/// These represent a short running activity with 5 points.
const _lat1 = 40.71280;
const _lon1 = -74.00600;
const _lat2 = 40.71380;
const _lon2 = -74.00500;
const _lat3 = 40.71480;
const _lon3 = -74.00400;
const _lat4 = 40.71580;
const _lon4 = -74.00300;
const _lat5 = 40.71680;
const _lon5 = -74.00200;

final _time1 = DateTime.utc(2024, 1, 1, 12);
final _time2 = DateTime.utc(2024, 1, 1, 12, 5);
final _time3 = DateTime.utc(2024, 1, 1, 12, 10);
final _time4 = DateTime.utc(2024, 1, 1, 12, 15);
final _time5 = DateTime.utc(2024, 1, 1, 12, 20);

const _ele1 = 10.0;
const _ele2 = 20.0;
const _ele3 = 30.0;
const _ele4 = 25.0;
const _ele5 = 15.0;

const _hr1 = 140;
const _hr2 = 155;
const _hr3 = 160;
const _hr4 = 150;
const _hr5 = 145;

void main() {
  test(
    'FIT and GPX representing the same activity produce matching normalized results',
    () {
      // Build FIT binary for the same activity
      final fitBytes = buildFitBytes(
        records: [
          FitTestRecord(
            timestampMs: _time1.millisecondsSinceEpoch,
            latitude: _lat1,
            longitude: _lon1,
            enhancedAltitude: _ele1,
            heartRate: _hr1,
          ),
          FitTestRecord(
            timestampMs: _time2.millisecondsSinceEpoch,
            latitude: _lat2,
            longitude: _lon2,
            enhancedAltitude: _ele2,
            heartRate: _hr2,
          ),
          FitTestRecord(
            timestampMs: _time3.millisecondsSinceEpoch,
            latitude: _lat3,
            longitude: _lon3,
            enhancedAltitude: _ele3,
            heartRate: _hr3,
          ),
          FitTestRecord(
            timestampMs: _time4.millisecondsSinceEpoch,
            latitude: _lat4,
            longitude: _lon4,
            enhancedAltitude: _ele4,
            heartRate: _hr4,
          ),
          FitTestRecord(
            timestampMs: _time5.millisecondsSinceEpoch,
            latitude: _lat5,
            longitude: _lon5,
            enhancedAltitude: _ele5,
            heartRate: _hr5,
          ),
        ],
        sport: Sport.running,
      );

      // Build equivalent GPX XML string
      final gpxContent =
          '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
  <trk>
    <type>running</type>
    <trkseg>
      <trkpt lat="$_lat1" lon="$_lon1">
        <ele>$_ele1</ele>
        <time>${_time1.toIso8601String()}</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>$_hr1</gpxtpx:hr>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
      <trkpt lat="$_lat2" lon="$_lon2">
        <ele>$_ele2</ele>
        <time>${_time2.toIso8601String()}</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>$_hr2</gpxtpx:hr>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
      <trkpt lat="$_lat3" lon="$_lon3">
        <ele>$_ele3</ele>
        <time>${_time3.toIso8601String()}</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>$_hr3</gpxtpx:hr>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
      <trkpt lat="$_lat4" lon="$_lon4">
        <ele>$_ele4</ele>
        <time>${_time4.toIso8601String()}</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>$_hr4</gpxtpx:hr>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
      <trkpt lat="$_lat5" lon="$_lon5">
        <ele>$_ele5</ele>
        <time>${_time5.toIso8601String()}</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>$_hr5</gpxtpx:hr>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>
''';

      // Parse both formats
      final fitParsed = FitImporter.parse(fitBytes);
      final gpxParsed = GpxImporter.parse(gpxContent);

      // Normalize both through the shared pipeline
      final fitActivity = normalizeImportedActivity(fitParsed);
      final gpxActivity = normalizeImportedActivity(gpxParsed);

      // Matching point counts
      expect(
        fitActivity.cleanedPoints.length,
        gpxActivity.cleanedPoints.length,
      );

      // Matching coordinates (within 1e-5 degrees to account for FIT
      // semicircle rounding)
      for (var i = 0; i < fitActivity.cleanedPoints.length; i++) {
        expect(
          fitActivity.cleanedPoints[i].latitude,
          closeTo(gpxActivity.cleanedPoints[i].latitude, 1e-5),
        );
        expect(
          fitActivity.cleanedPoints[i].longitude,
          closeTo(gpxActivity.cleanedPoints[i].longitude, 1e-5),
        );
      }

      // Matching timestamps (within 1 second)
      for (var i = 0; i < fitActivity.cleanedPoints.length; i++) {
        final fitMs =
            fitActivity.cleanedPoints[i].timestamp.millisecondsSinceEpoch;
        final gpxMs =
            gpxActivity.cleanedPoints[i].timestamp.millisecondsSinceEpoch;
        expect((fitMs - gpxMs).abs(), lessThan(1000));
      }

      // Matching track summary distance (within 1 meter)
      expect(
        fitActivity.metrics.trackSummary.distanceMeters,
        closeTo(gpxActivity.metrics.trackSummary.distanceMeters, 1),
      );

      // Matching split counts
      expect(
        fitActivity.metrics.splits.length,
        gpxActivity.metrics.splits.length,
      );

      // Both have same sport type
      expect(fitActivity.sportType, gpxActivity.sportType);
      expect(fitActivity.sportType, 'run');
    },
  );
}

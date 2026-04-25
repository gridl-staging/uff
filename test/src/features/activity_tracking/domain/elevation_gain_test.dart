import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/elevation_gain.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

const _sessionId = 77;
final _origin = DateTime.utc(2025);

TrackingPoint _pointAtMeters({
  required int seconds,
  required double metersFromOrigin,
  double? elevation,
}) {
  const metersPerDegreeAtEquator = earthRadiusMeters * (math.pi / 180);

  return TrackingPoint(
    sessionId: _sessionId,
    timestamp: _origin.add(Duration(seconds: seconds)),
    coordinate: GeoCoordinate(
      latitude: 0,
      longitude: metersFromOrigin / metersPerDegreeAtEquator,
    ),
    elevation: elevation,
  );
}

void main() {
  group('calculateElevationGainMeters edge cases', () {
    test('returns zero for empty and single-point inputs', () {
      final emptyGain = calculateElevationGainMeters(const []);
      final singleKnownGain = calculateElevationGainMeters([
        _pointAtMeters(seconds: 0, metersFromOrigin: 0, elevation: 100),
      ]);
      final singleNullGain = calculateElevationGainMeters([
        _pointAtMeters(seconds: 0, metersFromOrigin: 0),
      ]);

      expect(emptyGain, 0);
      expect(singleKnownGain, 0);
      expect(singleNullGain, 0);
    });

    test('returns zero for all-null elevations and pure descent', () {
      final allNullGain = calculateElevationGainMeters([
        _pointAtMeters(seconds: 0, metersFromOrigin: 0),
        _pointAtMeters(seconds: 1, metersFromOrigin: 10),
        _pointAtMeters(seconds: 2, metersFromOrigin: 20),
        _pointAtMeters(seconds: 3, metersFromOrigin: 30),
        _pointAtMeters(seconds: 4, metersFromOrigin: 40),
      ]);
      final pureDescentGain = calculateElevationGainMeters([
        _pointAtMeters(seconds: 0, metersFromOrigin: 0, elevation: 300),
        _pointAtMeters(seconds: 1, metersFromOrigin: 10, elevation: 200),
        _pointAtMeters(seconds: 2, metersFromOrigin: 20, elevation: 100),
      ]);

      expect(allNullGain, 0);
      expect(pureDescentGain, 0);
    });

    test('applies the >= 1.0m threshold precisely', () {
      final belowThresholdGain = calculateElevationGainMeters([
        _pointAtMeters(seconds: 0, metersFromOrigin: 0, elevation: 100),
        _pointAtMeters(seconds: 1, metersFromOrigin: 10, elevation: 100.999),
      ]);
      final exactThresholdGain = calculateElevationGainMeters([
        _pointAtMeters(seconds: 0, metersFromOrigin: 0, elevation: 100),
        _pointAtMeters(seconds: 1, metersFromOrigin: 10, elevation: 101),
      ]);
      final aboveThresholdGain = calculateElevationGainMeters([
        _pointAtMeters(seconds: 0, metersFromOrigin: 0, elevation: 100),
        _pointAtMeters(seconds: 1, metersFromOrigin: 10, elevation: 101.001),
      ]);

      expect(belowThresholdGain, 0);
      expect(exactThresholdGain, 1);
      expect(aboveThresholdGain, closeTo(1.001, 1e-9));
    });

    test('handles mixed null sequences and negative elevations', () {
      final mixedNullGain = calculateElevationGainMeters([
        _pointAtMeters(seconds: 0, metersFromOrigin: 0, elevation: 10),
        _pointAtMeters(seconds: 1, metersFromOrigin: 10),
        _pointAtMeters(seconds: 2, metersFromOrigin: 20),
        _pointAtMeters(seconds: 3, metersFromOrigin: 30, elevation: 15),
        _pointAtMeters(seconds: 4, metersFromOrigin: 40),
        _pointAtMeters(seconds: 5, metersFromOrigin: 50, elevation: 20),
      ]);
      final negativeElevationGain = calculateElevationGainMeters([
        _pointAtMeters(seconds: 0, metersFromOrigin: 0, elevation: -50),
        _pointAtMeters(seconds: 1, metersFromOrigin: 10, elevation: -40),
        _pointAtMeters(seconds: 2, metersFromOrigin: 20, elevation: -45),
        _pointAtMeters(seconds: 3, metersFromOrigin: 30, elevation: -30),
      ]);

      expect(mixedNullGain, 10);
      expect(negativeElevationGain, 25);
    });

    test('returns zero when all known elevations are unchanged', () {
      final repeatedSameGain = calculateElevationGainMeters([
        _pointAtMeters(seconds: 0, metersFromOrigin: 0, elevation: 100),
        _pointAtMeters(seconds: 1, metersFromOrigin: 10, elevation: 100),
        _pointAtMeters(seconds: 2, metersFromOrigin: 20, elevation: 100),
        _pointAtMeters(seconds: 3, metersFromOrigin: 30, elevation: 100),
        _pointAtMeters(seconds: 4, metersFromOrigin: 40, elevation: 100),
      ]);

      expect(repeatedSameGain, 0);
    });
  });
}

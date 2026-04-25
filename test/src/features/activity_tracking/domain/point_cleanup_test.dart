import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/point_cleanup.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

const _sessionId = 77;
final _origin = DateTime.utc(2025);

TrackingPoint _pointAtMeters({
  required int seconds,
  required double metersFromOrigin,
  int? timestampSeconds,
}) {
  const metersPerDegreeAtEquator = earthRadiusMeters * (math.pi / 180);

  return TrackingPoint(
    sessionId: _sessionId,
    timestamp: _origin.add(
      Duration(seconds: timestampSeconds ?? seconds),
    ),
    coordinate: GeoCoordinate(
      latitude: 0,
      longitude: metersFromOrigin / metersPerDegreeAtEquator,
    ),
  );
}

void main() {
  group('cleanTrackingPoints edge cases', () {
    test('returns expected results for empty and single-point guard paths', () {
      final emptyResult = cleanTrackingPoints(const []);
      final singlePoint = _pointAtMeters(seconds: 10, metersFromOrigin: 25);
      final singlePointResult = cleanTrackingPoints([singlePoint]);

      expect(emptyResult.cleanedPoints, isEmpty);
      expect(emptyResult.droppedDuplicateCount, 0);
      expect(emptyResult.droppedOutlierCount, 0);
      expect(singlePointResult.cleanedPoints.length, 1);
      expect(
        singlePointResult.cleanedPoints.single.timestamp,
        singlePoint.timestamp,
      );
      expect(
        singlePointResult.cleanedPoints.single.longitude,
        singlePoint.longitude,
      );
      expect(singlePointResult.droppedDuplicateCount, 0);
      expect(singlePointResult.droppedOutlierCount, 0);
    });

    test('keeps first sample when all timestamps are identical', () {
      final points = [
        _pointAtMeters(seconds: 0, metersFromOrigin: 0, timestampSeconds: 5),
        _pointAtMeters(seconds: 1, metersFromOrigin: 10, timestampSeconds: 5),
        _pointAtMeters(seconds: 2, metersFromOrigin: 20, timestampSeconds: 5),
        _pointAtMeters(seconds: 3, metersFromOrigin: 30, timestampSeconds: 5),
        _pointAtMeters(seconds: 4, metersFromOrigin: 40, timestampSeconds: 5),
      ];

      final result = cleanTrackingPoints(points);

      expect(result.cleanedPoints.length, 1);
      expect(result.cleanedPoints.single.longitude, points.first.longitude);
      expect(result.droppedDuplicateCount, 4);
      expect(result.droppedOutlierCount, 0);
    });

    test('accepts speed at threshold and rejects speed above threshold', () {
      final thresholdSpeedResult = cleanTrackingPoints([
        _pointAtMeters(seconds: 0, metersFromOrigin: 0),
        _pointAtMeters(seconds: 1, metersFromOrigin: 18),
      ]);
      final aboveThresholdSpeedResult = cleanTrackingPoints([
        _pointAtMeters(seconds: 0, metersFromOrigin: 0),
        _pointAtMeters(seconds: 1, metersFromOrigin: 18.001),
      ]);

      expect(thresholdSpeedResult.cleanedPoints.length, 2);
      expect(thresholdSpeedResult.droppedOutlierCount, 0);
      expect(aboveThresholdSpeedResult.cleanedPoints.length, 1);
      expect(aboveThresholdSpeedResult.droppedOutlierCount, 1);
    });

    test('keeps zero-distance segment when timestamps differ', () {
      final firstPoint = _pointAtMeters(seconds: 0, metersFromOrigin: 100);
      final secondPoint = _pointAtMeters(seconds: 5, metersFromOrigin: 100);
      final result = cleanTrackingPoints([
        firstPoint,
        secondPoint,
      ]);

      expect(result.cleanedPoints.length, 2);
      expect(result.cleanedPoints.first.longitude, firstPoint.longitude);
      expect(result.cleanedPoints.last.longitude, secondPoint.longitude);
      expect(result.droppedDuplicateCount, 0);
      expect(result.droppedOutlierCount, 0);
    });

    test('keeps only first point when all following samples are outliers', () {
      final result = cleanTrackingPoints([
        _pointAtMeters(seconds: 0, metersFromOrigin: 0),
        _pointAtMeters(seconds: 1, metersFromOrigin: 30),
        _pointAtMeters(seconds: 2, metersFromOrigin: 60),
        _pointAtMeters(seconds: 3, metersFromOrigin: 90),
      ]);

      expect(result.cleanedPoints.length, 1);
      expect(result.cleanedPoints.single.timestamp, _origin);
      expect(result.droppedDuplicateCount, 0);
      expect(result.droppedOutlierCount, 3);
    });
  });
}

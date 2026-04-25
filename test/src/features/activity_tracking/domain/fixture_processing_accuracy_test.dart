import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

import '../../../../fixtures/fixture_loader.dart';

const double _earthRadiusMeters = 6371000;

double _toRadians(double degrees) => degrees * (math.pi / 180.0);

double _independentHaversineMeters(
  GeoCoordinate start,
  GeoCoordinate end,
) {
  final lat1 = _toRadians(start.latitude);
  final lat2 = _toRadians(end.latitude);
  final dLat = lat2 - lat1;
  final dLon = _toRadians(end.longitude - start.longitude);

  final a =
      math.pow(math.sin(dLat / 2.0), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2.0), 2);
  final c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a));
  return _earthRadiusMeters * c;
}

double _sumIndependentDistanceMeters(List<TrackingPoint> points) {
  var sum = 0.0;
  for (var index = 1; index < points.length; index += 1) {
    sum += _independentHaversineMeters(
      points[index - 1].coordinate,
      points[index].coordinate,
    );
  }
  return sum;
}

TrackingPoint _copyPoint(
  TrackingPoint point, {
  DateTime? timestamp,
  GeoCoordinate? coordinate,
}) {
  return TrackingPoint(
    sessionId: point.sessionId,
    timestamp: timestamp ?? point.timestamp,
    coordinate: coordinate ?? point.coordinate,
    elevation: point.elevation,
    accuracy: point.accuracy,
    speed: point.speed,
    heartRateBpm: point.heartRateBpm,
    cadenceRpm: point.cadenceRpm,
    powerWatts: point.powerWatts,
  );
}

void main() {
  group('fixture processing accuracy', () {
    test(
      'hilly_10k segment distances match independent haversine calculations',
      () async {
        final points = await loadFixtureTrackingPoints('hilly_10k');

        for (var index = 1; index < points.length; index += 1) {
          final expectedSegmentDistance = _independentHaversineMeters(
            points[index - 1].coordinate,
            points[index].coordinate,
          );
          final actualSegmentDistance = calculateGeodesicDistanceMeters(
            points[index - 1].coordinate,
            points[index].coordinate,
          );
          expect(actualSegmentDistance, closeTo(expectedSegmentDistance, 1e-6));
        }

        final expectedTotalDistance = _sumIndependentDistanceMeters(points);
        final actualTotalDistance = calculateTrackDistanceMeters(points);
        expect(actualTotalDistance, closeTo(expectedTotalDistance, 1e-6));
      },
    );

    test(
      'cleanup removes one duplicate and one impossible jump while preserving baseline order',
      () async {
        final baseline = await loadFixtureTrackingPoints('long_easy_run');
        const duplicateIndex = 120;
        const outlierAnchorIndex = 240;

        final duplicatePoint = _copyPoint(
          baseline[duplicateIndex],
          coordinate: GeoCoordinate(
            latitude: baseline[duplicateIndex].latitude + 0.0001,
            longitude: baseline[duplicateIndex].longitude + 0.0001,
          ),
        );
        final outlierPoint = _copyPoint(
          baseline[outlierAnchorIndex],
          timestamp: baseline[outlierAnchorIndex].timestamp.add(
            const Duration(seconds: 1),
          ),
          coordinate: GeoCoordinate(
            latitude: baseline[outlierAnchorIndex].latitude + 1.0,
            longitude: baseline[outlierAnchorIndex].longitude + 1.0,
          ),
        );

        final corrupted = List<TrackingPoint>.of(baseline)
          ..insert(duplicateIndex + 1, duplicatePoint)
          ..insert(outlierAnchorIndex + 2, outlierPoint);

        final result = cleanTrackingPoints(corrupted);

        expect(result.droppedDuplicateCount, 1);
        expect(result.droppedOutlierCount, 1);
        expect(result.cleanedPoints, hasLength(baseline.length));

        for (var index = 0; index < baseline.length; index += 1) {
          final expected = baseline[index];
          final actual = result.cleanedPoints[index];
          expect(actual.timestamp, expected.timestamp);
          expect(actual.coordinate.latitude, expected.coordinate.latitude);
          expect(actual.coordinate.longitude, expected.coordinate.longitude);
        }
      },
    );
  });
}

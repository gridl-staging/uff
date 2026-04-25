import 'dart:math' as math;

import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

double calculateGeodesicDistanceMeters(
  GeoCoordinate start,
  GeoCoordinate end,
) {
  final latitudeStartRadians = _toRadians(start.latitude);
  final latitudeEndRadians = _toRadians(end.latitude);
  final latitudeDelta = latitudeEndRadians - latitudeStartRadians;
  final longitudeDelta = _toRadians(end.longitude - start.longitude);

  final haversineTerm =
      math.pow(math.sin(latitudeDelta / 2), 2) +
      math.cos(latitudeStartRadians) *
          math.cos(latitudeEndRadians) *
          math.pow(math.sin(longitudeDelta / 2), 2);

  final centralAngle =
      2 * math.atan2(math.sqrt(haversineTerm), math.sqrt(1 - haversineTerm));
  return earthRadiusMeters * centralAngle;
}

double _toRadians(double degrees) {
  return degrees * (math.pi / 180);
}

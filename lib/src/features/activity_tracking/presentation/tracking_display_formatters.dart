import 'package:flutter/material.dart';
import 'package:uff/src/core/units/preferred_units.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';

String formatDuration(Duration? duration) {
  if (duration == null) {
    return '--';
  }

  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  final hours = minutes ~/ 60;
  final remainderMinutes = minutes % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${remainderMinutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

String formatDistanceKilometers(double? distanceMeters) {
  return formatDistanceForUnit(distanceMeters, SplitUnit.kilometer);
}

String formatDistanceMiles(double? distanceMeters) {
  return formatDistanceForUnit(distanceMeters, SplitUnit.mile);
}

String formatDistance(
  double? distanceMeters, {
  String? preferredUnits,
}) {
  return formatDistanceForUnit(
    distanceMeters,
    splitUnitForPreferredUnits(preferredUnits),
  );
}

String formatDistanceForUnit(double? distanceMeters, SplitUnit unit) {
  if (distanceMeters == null) {
    return '-- ${_distanceUnitLabel(unit)}';
  }

  final convertedDistance = distanceMeters / unit.unitDistanceMeters;
  return '${convertedDistance.toStringAsFixed(2)} ${_distanceUnitLabel(unit)}';
}

String formatPace(Duration? pacePerKilometer) {
  return formatPaceForUnit(pacePerKilometer, SplitUnit.kilometer);
}

String formatPaceForPreferredUnits({
  required Duration? pacePerKilometer,
  required Duration? pacePerMile,
  String? preferredUnits,
}) {
  final unit = splitUnitForPreferredUnits(preferredUnits);
  final selectedPace = switch (unit) {
    SplitUnit.kilometer => pacePerKilometer,
    SplitUnit.mile => pacePerMile,
  };
  return formatPaceForUnit(selectedPace, unit);
}

String formatPaceForUnit(Duration? pace, SplitUnit unit) {
  if (pace == null) {
    return '--:--';
  }

  final minutes = pace.inMinutes;
  final seconds = pace.inSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}'
      ':${seconds.toString().padLeft(2, '0')} /${_distanceUnitLabel(unit)}';
}

String formatDateLabel(DateTime? dateTime) {
  if (dateTime == null) {
    return '--';
  }

  final localDateTime = dateTime.toLocal();
  final month = localDateTime.month.toString().padLeft(2, '0');
  final day = localDateTime.day.toString().padLeft(2, '0');
  final hour = localDateTime.hour.toString().padLeft(2, '0');
  final minute = localDateTime.minute.toString().padLeft(2, '0');
  return '${localDateTime.year}-$month-$day $hour:$minute';
}

List<RoutePoint> toRoutePoints(List<TrackingPoint> points) {
  return points
      .map(
        (point) => RoutePoint(
          latitude: point.latitude,
          longitude: point.longitude,
        ),
      )
      .toList(growable: false);
}

/// Conversion factor: 1 meter = 3.28084 feet.
const double _metersToFeet = 3.28084;

/// Formats elevation gain for display, respecting the user's preferred units.
/// Metric users see meters (e.g., "125 m"), imperial users see feet
/// (e.g., "410 ft"). Rounds to whole numbers since sub-meter/sub-foot
/// precision for elevation gain is meaningless for runners.
String formatElevation(
  double? elevationMeters, {
  String? preferredUnits,
}) {
  if (elevationMeters == null) {
    return usesImperialUnits(preferredUnits) ? '-- ft' : '-- m';
  }

  if (usesImperialUnits(preferredUnits)) {
    final feet = elevationMeters * _metersToFeet;
    return '${feet.round()} ft';
  }

  return '${elevationMeters.round()} m';
}

/// Generates a default activity title based on the time of day the run
/// started, matching the pattern used by Strava and other fitness apps.
/// Returns titles like "Morning Run", "Lunch Run", "Afternoon Run",
/// "Evening Run", or "Night Run".
///
/// The [sportType] parameter allows customization for non-run activities
/// (e.g., "Morning Ride" for cycling). Defaults to "Run" if null.
String generateDefaultActivityTitle({
  required DateTime startedAt,
  String? sportType,
}) {
  final localHour = startedAt.toLocal().hour;
  final activityLabel = _sportTypeLabel(sportType);
  final timeOfDay = _timeOfDayLabel(localHour);
  return '$timeOfDay $activityLabel';
}

/// Maps a sport type string to a human-readable label for title generation.
/// Capitalizes the first letter. Falls back to "Run" for null/empty values.
String _sportTypeLabel(String? sportType) {
  if (sportType == null || sportType.isEmpty) {
    return 'Run';
  }
  // Capitalize first letter: "workout" → "Workout", "run" → "Run"
  return '${sportType[0].toUpperCase()}${sportType.substring(1)}';
}

/// Maps the hour of day to a descriptive time-of-day label.
/// Thresholds match common fitness app conventions:
///   5-11  → Morning
///   12-13 → Lunch
///   14-16 → Afternoon
///   17-20 → Evening
///   21-4  → Night
String _timeOfDayLabel(int hour) {
  if (hour >= 5 && hour < 12) return 'Morning';
  if (hour >= 12 && hour < 14) return 'Lunch';
  if (hour >= 14 && hour < 17) return 'Afternoon';
  if (hour >= 17 && hour < 21) return 'Evening';
  return 'Night';
}

Color paceColor(Duration? pacePerKilometer) {
  if (pacePerKilometer == null) {
    return Colors.grey;
  }
  if (pacePerKilometer < const Duration(minutes: 10)) {
    return Colors.green;
  }
  if (pacePerKilometer < const Duration(minutes: 12)) {
    return Colors.orange;
  }
  return Colors.red;
}

String _distanceUnitLabel(SplitUnit unit) {
  return switch (unit) {
    SplitUnit.kilometer => 'km',
    SplitUnit.mile => 'mi',
  };
}

Widget metricDetailRow(String label, String value, {Key? valueKey}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, key: valueKey),
      ],
    ),
  );
}

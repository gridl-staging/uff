import 'package:flutter/material.dart';
import 'package:uff/src/features/analytics/domain/sport_type.dart';

/// Shared icon mapping for social/activity sport types.
class SportTypeIcon extends StatelessWidget {
  const SportTypeIcon({
    required this.sportType,
    this.size,
    super.key,
  });

  final String? sportType;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return Icon(_iconForSportType(_sportTypeFromName(sportType)), size: size);
  }
}

SportType? _sportTypeFromName(String? sportType) {
  for (final supportedSportType in SportType.values) {
    if (supportedSportType.name == sportType) {
      return supportedSportType;
    }
  }
  return null;
}

IconData _iconForSportType(SportType? sportType) => switch (sportType) {
  SportType.run => Icons.directions_run,
  SportType.ride => Icons.directions_bike,
  null => Icons.fitness_center,
};

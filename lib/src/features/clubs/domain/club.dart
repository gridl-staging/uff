import 'package:meta/meta.dart';
import 'package:uff/src/features/clubs/domain/club_sport_type.dart';

/// Source classification for where a club record originated.
enum ClubSource {
  userCreated('user_created'),
  autoDiscovered('auto_discovered')
  ;

  const ClubSource(this.databaseValue);

  final String databaseValue;

  static ClubSource fromDatabaseValue(String value) {
    return values.firstWhere(
      (source) => source.databaseValue == value,
      orElse: () => throw StateError('Unsupported club source value: $value'),
    );
  }
}

/// Visibility policy for discoverability and membership access.
enum ClubVisibility {
  public('public'),
  private('private')
  ;

  const ClubVisibility(this.databaseValue);

  final String databaseValue;

  static ClubVisibility fromDatabaseValue(String value) {
    return values.firstWhere(
      (visibility) => visibility.databaseValue == value,
      orElse: () =>
          throw StateError('Unsupported club visibility value: $value'),
    );
  }
}

/// Immutable value object for one row in `public.clubs`.
@immutable
class Club {
  const Club({
    required this.id,
    required this.name,
    required this.description,
    required this.avatarUrl,
    required this.city,
    required this.stateRegion,
    required this.country,
    required this.locationLat,
    required this.locationLng,
    required this.source,
    required this.sourceUrl,
    required this.sourceId,
    required this.creatorId,
    required this.claimedBy,
    required this.visibility,
    required this.memberCount,
    required this.createdAt,
    required this.updatedAt,
    this.sportType,
  });

  final String id;
  final String name;
  final String? description;
  final String? avatarUrl;
  final String? city;
  final String? stateRegion;
  final String? country;
  final double? locationLat;
  final double? locationLng;
  final ClubSource source;
  final String? sourceUrl;
  final String? sourceId;
  final String? creatorId;
  final String? claimedBy;
  final ClubVisibility visibility;
  final int memberCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ClubSportType? sportType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Club &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          description == other.description &&
          avatarUrl == other.avatarUrl &&
          city == other.city &&
          stateRegion == other.stateRegion &&
          country == other.country &&
          locationLat == other.locationLat &&
          locationLng == other.locationLng &&
          source == other.source &&
          sourceUrl == other.sourceUrl &&
          sourceId == other.sourceId &&
          creatorId == other.creatorId &&
          claimedBy == other.claimedBy &&
          visibility == other.visibility &&
          memberCount == other.memberCount &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          sportType == other.sportType;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    avatarUrl,
    city,
    stateRegion,
    country,
    locationLat,
    locationLng,
    source,
    sourceUrl,
    sourceId,
    creatorId,
    claimedBy,
    visibility,
    memberCount,
    createdAt,
    updatedAt,
    sportType,
  );
}

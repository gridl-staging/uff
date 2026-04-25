import 'package:meta/meta.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/domain/club_member.dart';
import 'package:uff/src/features/clubs/domain/club_run.dart';
import 'package:uff/src/features/clubs/domain/club_sport_type.dart';

/// Input payload for creating one club row and creator membership.
@immutable
class CreateClubInput {
  const CreateClubInput({
    required this.name,
    this.description,
    this.avatarUrl,
    this.city,
    this.stateRegion,
    this.country,
    this.locationLat,
    this.locationLng,
    this.visibility = ClubVisibility.public,
    this.sportType,
  });

  final String name;
  final String? description;
  final String? avatarUrl;
  final String? city;
  final String? stateRegion;
  final String? country;
  final double? locationLat;
  final double? locationLng;
  final ClubVisibility visibility;
  final ClubSportType? sportType;
}

/// Input payload for scheduling one upcoming club run.
@immutable
class CreateClubRunInput {
  const CreateClubRunInput({
    required this.clubId,
    required this.title,
    required this.scheduledAt,
    this.description,
    this.meetingPointLat,
    this.meetingPointLng,
    this.meetingPointName,
    this.distanceMeters,
    this.paceDescription,
  });

  final String clubId;
  final String title;
  final DateTime scheduledAt;
  final String? description;
  final double? meetingPointLat;
  final double? meetingPointLng;
  final String? meetingPointName;
  final double? distanceMeters;
  final String? paceDescription;
}

/// Trims optional text input so blank values are stored as `null`.
String? normalizeOptionalClubText(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Single read/write seam for clubs, membership, and scheduled club runs.
abstract interface class ClubRepository {
  Future<Club?> getClub(String clubId);

  Future<List<Club>> listClubs();

  Future<List<Club>> searchClubs(String query);

  Future<List<Club>> getMyClubs();

  Future<Club> createClub(CreateClubInput input);

  Future<void> updateClub(Club club);

  Future<void> deleteClub(String clubId);

  Future<void> joinClub(String clubId);

  Future<void> leaveClub(String clubId);

  Future<List<ClubMember>> getClubMembers(String clubId);

  Future<List<ClubRun>> getUpcomingClubRuns(String clubId);

  Future<ClubRun> createClubRun(CreateClubRunInput input);
}

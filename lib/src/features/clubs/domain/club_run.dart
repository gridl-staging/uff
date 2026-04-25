import 'package:meta/meta.dart';

/// Immutable value object for one row in `public.club_runs`.
@immutable
class ClubRun {
  const ClubRun({
    required this.id,
    required this.clubId,
    required this.title,
    required this.description,
    required this.scheduledAt,
    required this.meetingPointLat,
    required this.meetingPointLng,
    required this.meetingPointName,
    required this.distanceMeters,
    required this.paceDescription,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String clubId;
  final String title;
  final String? description;
  final DateTime scheduledAt;
  final double? meetingPointLat;
  final double? meetingPointLng;
  final String? meetingPointName;
  final double? distanceMeters;
  final String? paceDescription;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClubRun &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          clubId == other.clubId &&
          title == other.title &&
          description == other.description &&
          scheduledAt == other.scheduledAt &&
          meetingPointLat == other.meetingPointLat &&
          meetingPointLng == other.meetingPointLng &&
          meetingPointName == other.meetingPointName &&
          distanceMeters == other.distanceMeters &&
          paceDescription == other.paceDescription &&
          createdBy == other.createdBy &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    clubId,
    title,
    description,
    scheduledAt,
    meetingPointLat,
    meetingPointLng,
    meetingPointName,
    distanceMeters,
    paceDescription,
    createdBy,
    createdAt,
    updatedAt,
  );
}

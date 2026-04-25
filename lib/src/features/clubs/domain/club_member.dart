import 'package:meta/meta.dart';

/// Membership role for a user within a club.
enum ClubMemberRole {
  admin('admin'),
  organizer('organizer'),
  member('member');

  const ClubMemberRole(this.databaseValue);

  final String databaseValue;

  static ClubMemberRole fromDatabaseValue(String value) {
    return values.firstWhere(
      (role) => role.databaseValue == value,
      orElse: () =>
          throw StateError('Unsupported club member role value: $value'),
    );
  }
}

/// Membership lifecycle status for a club member row.
enum ClubMemberStatus {
  active('active'),
  pending('pending'),
  invited('invited');

  const ClubMemberStatus(this.databaseValue);

  final String databaseValue;

  static ClubMemberStatus fromDatabaseValue(String value) {
    return values.firstWhere(
      (status) => status.databaseValue == value,
      orElse: () =>
          throw StateError('Unsupported club member status value: $value'),
    );
  }
}

/// Immutable value object for one row in `public.club_members`.
@immutable
class ClubMember {
  const ClubMember({
    required this.id,
    required this.clubId,
    required this.userId,
    required this.role,
    required this.status,
    required this.joinedAt,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String clubId;
  final String userId;
  final ClubMemberRole role;
  final ClubMemberStatus status;
  final DateTime joinedAt;
  final String? displayName;
  final String? avatarUrl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClubMember &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          clubId == other.clubId &&
          userId == other.userId &&
          role == other.role &&
          status == other.status &&
          joinedAt == other.joinedAt &&
          displayName == other.displayName &&
          avatarUrl == other.avatarUrl;

  @override
  int get hashCode => Object.hash(
    id,
    clubId,
    userId,
    role,
    status,
    joinedAt,
    displayName,
    avatarUrl,
  );
}

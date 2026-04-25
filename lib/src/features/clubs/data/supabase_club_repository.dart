import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/clubs/data/club_repository.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/domain/club_member.dart';
import 'package:uff/src/features/clubs/domain/club_run.dart';
import 'package:uff/src/features/clubs/domain/club_sport_type.dart';

const _clubColumns =
    'id,name,description,avatar_url,city,state_region,country,location_lat,'
    'location_lng,source,source_url,source_id,creator_id,claimed_by,visibility,'
    'member_count,created_at,updated_at,sport_type';
const _clubMemberColumns =
    'id,club_id,user_id,role,status,joined_at,'
    'profiles!club_members_user_id_fkey(display_name,avatar_url)';
const _clubRunColumns =
    'id,club_id,title,description,scheduled_at,meeting_point_lat,'
    'meeting_point_lng,meeting_point_name,distance_meters,pace_description,'
    'created_by,created_at,updated_at';

/// TODO: Document SupabaseClubRepository.
class SupabaseClubRepository implements ClubRepository {
  SupabaseClubRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Club?> getClub(String clubId) async {
    final rows = await _client
        .from('clubs')
        .select(_clubColumns)
        .eq('id', clubId);
    if (rows.isEmpty) {
      return null;
    }
    return clubFromJson(rows.first);
  }

  @override
  Future<List<Club>> listClubs() async {
    final rows = await _client
        .from('clubs')
        .select(_clubColumns)
        .order('member_count', ascending: false);
    return rows.map(clubFromJson).toList(growable: false);
  }

  @override
  Future<List<Club>> searchClubs(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const <Club>[];
    }
    final escapedQuery = _escapeIlikePattern(trimmed);

    final rows = await _client
        .from('clubs')
        .select(_clubColumns)
        .ilike('name', '%$escapedQuery%')
        .order('member_count', ascending: false);
    return rows.map(clubFromJson).toList(growable: false);
  }

  @override
  Future<List<Club>> getMyClubs() async {
    final currentUserId = _requireCurrentUserId();
    final rows = await _client
        .from('club_members')
        .select('clubs!inner($_clubColumns)')
        .eq('user_id', currentUserId)
        .eq('status', ClubMemberStatus.active.databaseValue);

    return rows
        .map(
          (row) => _extractJoinedRow(
            row['clubs'],
            isRequired: true,
            joinLabel: 'club',
          ),
        )
        .map(clubFromJson)
        .toList(growable: false);
  }

  @override
  Future<Club> createClub(CreateClubInput input) async {
    final currentUserId = _requireCurrentUserId();
    final createdClubRow = await _client
        .from('clubs')
        .insert(_clubInsertPayload(input, creatorId: currentUserId))
        .select(_clubColumns)
        .single();
    final createdClub = clubFromJson(createdClubRow);

    try {
      await _client
          .from('club_members')
          .insert({
            'club_id': createdClub.id,
            'user_id': currentUserId,
            'role': ClubMemberRole.admin.databaseValue,
            'status': ClubMemberStatus.active.databaseValue,
          })
          .select('id');
    } catch (_) {
      await _cleanupCreatedClub(clubId: createdClub.id);
      rethrow;
    }

    final refreshedClub = await getClub(createdClub.id);
    if (refreshedClub != null) {
      return refreshedClub;
    }
    throw StateError(
      'Created club ${createdClub.id} could not be reloaded after membership '
      'insert completed.',
    );
  }

  @override
  Future<void> updateClub(Club club) async {
    await _requireClubManagementPermission(clubId: club.id);
    final updatedRows = await _client
        .from('clubs')
        .update(_clubUpdatePayload(club))
        .eq('id', club.id)
        .select('id');
    _requireSingleAffectedRow(
      updatedRows,
      operation: 'update',
      entityName: 'club',
      entityId: club.id,
    );
  }

  @override
  Future<void> deleteClub(String clubId) async {
    await _requireClubManagementPermission(clubId: clubId);
    final deletedRows = await _client
        .from('clubs')
        .delete()
        .eq('id', clubId)
        .select('id');
    _requireSingleAffectedRow(
      deletedRows,
      operation: 'delete',
      entityName: 'club',
      entityId: clubId,
    );
  }

  @override
  Future<void> joinClub(String clubId) async {
    final currentUserId = _requireCurrentUserId();
    final club = await getClub(clubId);
    if (club == null) {
      throw StateError(
        'Unable to join club because club $clubId is not visible or does not exist.',
      );
    }

    final membershipStatus = club.visibility == ClubVisibility.private
        ? ClubMemberStatus.pending
        : ClubMemberStatus.active;
    await _client
        .from('club_members')
        .insert({
          'club_id': clubId,
          'user_id': currentUserId,
          'role': ClubMemberRole.member.databaseValue,
          'status': membershipStatus.databaseValue,
        })
        .select('id');
  }

  @override
  Future<void> leaveClub(String clubId) async {
    final currentUserId = _requireCurrentUserId();
    final deletedRows = await _client
        .from('club_members')
        .delete()
        .eq('club_id', clubId)
        .eq('user_id', currentUserId)
        .select('id');
    if (deletedRows.isNotEmpty) {
      return;
    }
    throw StateError(
      'Unable to leave club because membership for club $clubId was not '
      'found or is no longer accessible.',
    );
  }

  @override
  Future<List<ClubMember>> getClubMembers(String clubId) async {
    final rows = await _client
        .from('club_members')
        .select(_clubMemberColumns)
        .eq('club_id', clubId)
        .order('joined_at', ascending: true);
    return rows.map(clubMemberFromJson).toList(growable: false);
  }

  @override
  Future<List<ClubRun>> getUpcomingClubRuns(String clubId) async {
    final rows = await _client
        .from('club_runs')
        .select(_clubRunColumns)
        .eq('club_id', clubId)
        .gte('scheduled_at', DateTime.now().toUtc().toIso8601String())
        .order('scheduled_at', ascending: true);
    return rows.map(clubRunFromJson).toList(growable: false);
  }

  @override
  Future<ClubRun> createClubRun(CreateClubRunInput input) async {
    final currentUserId = _requireCurrentUserId();
    await _requireClubManagementPermission(
      clubId: input.clubId,
      currentUserId: currentUserId,
    );
    final row = await _client
        .from('club_runs')
        .insert(_clubRunInsertPayload(input, creatorUserId: currentUserId))
        .select(_clubRunColumns)
        .single();
    return clubRunFromJson(row);
  }

  Future<void> _cleanupCreatedClub({required String clubId}) async {
    try {
      await _client.from('clubs').delete().eq('id', clubId).select('id');
    } on Object catch (_) {
      // Preserve the original membership-insert failure.
    }
  }

  String _requireCurrentUserId() {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw StateError(
        'Club operations require an authenticated user session.',
      );
    }
    return currentUserId;
  }

  Future<void> _requireClubManagementPermission({
    required String clubId,
    String? currentUserId,
  }) async {
    final managingUserId = currentUserId ?? _requireCurrentUserId();
    final club = await getClub(clubId);
    if (club == null) {
      throw StateError(
        'Unable to manage club because club $clubId is not visible or does '
        'not exist.',
      );
    }
    if (club.creatorId == managingUserId) {
      return;
    }

    final managingRole = await _getActiveClubRoleForUser(
      clubId: clubId,
      userId: managingUserId,
    );
    if (managingRole == ClubMemberRole.admin ||
        managingRole == ClubMemberRole.organizer) {
      return;
    }

    throw StateError(
      'Club management requires creator, admin, or organizer access for club '
      '$clubId.',
    );
  }

  Future<ClubMemberRole?> _getActiveClubRoleForUser({
    required String clubId,
    required String userId,
  }) async {
    final rows = await _client
        .from('club_members')
        .select('role')
        .eq('club_id', clubId)
        .eq('user_id', userId)
        .eq('status', ClubMemberStatus.active.databaseValue);
    if (rows.isEmpty) {
      return null;
    }

    final roleValue = rows.first['role'];
    if (roleValue is! String) {
      throw StateError('Club member role lookup returned an invalid payload.');
    }
    return ClubMemberRole.fromDatabaseValue(roleValue);
  }
}

Map<String, dynamic> _clubInsertPayload(
  CreateClubInput input, {
  required String creatorId,
}) {
  return <String, dynamic>{
    'name': input.name,
    'description': input.description,
    'avatar_url': input.avatarUrl,
    'city': input.city,
    'state_region': input.stateRegion,
    'country': input.country ?? 'US',
    'location_lat': input.locationLat,
    'location_lng': input.locationLng,
    'visibility': input.visibility.databaseValue,
    'creator_id': creatorId,
    'source': ClubSource.userCreated.databaseValue,
    'sport_type': input.sportType?.databaseValue,
  };
}

Map<String, dynamic> _clubUpdatePayload(Club club) {
  return <String, dynamic>{
    'name': club.name,
    'description': club.description,
    'avatar_url': club.avatarUrl,
    'city': club.city,
    'state_region': club.stateRegion,
    'country': club.country,
    'location_lat': club.locationLat,
    'location_lng': club.locationLng,
    'visibility': club.visibility.databaseValue,
    'sport_type': club.sportType?.databaseValue,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
}

Map<String, dynamic> _clubRunInsertPayload(
  CreateClubRunInput input, {
  required String creatorUserId,
}) {
  return <String, dynamic>{
    'club_id': input.clubId,
    'title': input.title,
    'description': input.description,
    'scheduled_at': input.scheduledAt.toUtc().toIso8601String(),
    'meeting_point_lat': input.meetingPointLat,
    'meeting_point_lng': input.meetingPointLng,
    'meeting_point_name': input.meetingPointName,
    'distance_meters': input.distanceMeters,
    'pace_description': input.paceDescription,
    'created_by': creatorUserId,
  };
}

void _requireSingleAffectedRow(
  List<dynamic> rows, {
  required String operation,
  required String entityName,
  required String entityId,
}) {
  if (rows.length == 1) {
    return;
  }
  throw StateError(
    '${entityName[0].toUpperCase()}${entityName.substring(1)} '
    '$operation must affect exactly one row for id $entityId, '
    'but affected ${rows.length}.',
  );
}

/// Maps one `public.clubs` row into a [Club] value object.
Club clubFromJson(Map<String, dynamic> json) {
  final row = _normalizeRow(json);
  return Club(
    id: row['id'] as String,
    name: row['name'] as String,
    description: row['description'] as String?,
    avatarUrl: row['avatar_url'] as String?,
    city: row['city'] as String?,
    stateRegion: row['state_region'] as String?,
    country: row['country'] as String?,
    locationLat: _parseOptionalDouble(row['location_lat']),
    locationLng: _parseOptionalDouble(row['location_lng']),
    source: ClubSource.fromDatabaseValue(row['source'] as String),
    sourceUrl: row['source_url'] as String?,
    sourceId: row['source_id'] as String?,
    creatorId: row['creator_id'] as String?,
    claimedBy: row['claimed_by'] as String?,
    visibility: ClubVisibility.fromDatabaseValue(row['visibility'] as String),
    memberCount: _parseRequiredInt(
      row['member_count'],
      fieldName: 'member_count',
    ),
    createdAt: _parseRequiredDateTime(
      row['created_at'],
      fieldName: 'created_at',
    ),
    updatedAt: _parseRequiredDateTime(
      row['updated_at'],
      fieldName: 'updated_at',
    ),
    sportType: ClubSportType.fromDatabaseValue(row['sport_type'] as String?),
  );
}

/// Maps one `public.club_members` row into a [ClubMember] value object.
ClubMember clubMemberFromJson(Map<String, dynamic> json) {
  final row = _normalizeRow(json);
  final profileRow = _extractJoinedRow(
    row['profiles'],
    isRequired: false,
    joinLabel: 'profile',
  );
  return ClubMember(
    id: row['id'] as String,
    clubId: row['club_id'] as String,
    userId: row['user_id'] as String,
    role: ClubMemberRole.fromDatabaseValue(row['role'] as String),
    status: ClubMemberStatus.fromDatabaseValue(row['status'] as String),
    joinedAt: _parseRequiredDateTime(row['joined_at'], fieldName: 'joined_at'),
    displayName: profileRow['display_name'] as String?,
    avatarUrl: profileRow['avatar_url'] as String?,
  );
}

/// Maps one `public.club_runs` row into a [ClubRun] value object.
ClubRun clubRunFromJson(Map<String, dynamic> json) {
  final row = _normalizeRow(json);
  return ClubRun(
    id: row['id'] as String,
    clubId: row['club_id'] as String,
    title: row['title'] as String,
    description: row['description'] as String?,
    scheduledAt: _parseRequiredDateTime(
      row['scheduled_at'],
      fieldName: 'scheduled_at',
    ),
    meetingPointLat: _parseOptionalDouble(row['meeting_point_lat']),
    meetingPointLng: _parseOptionalDouble(row['meeting_point_lng']),
    meetingPointName: row['meeting_point_name'] as String?,
    distanceMeters: _parseOptionalDouble(row['distance_meters']),
    paceDescription: row['pace_description'] as String?,
    createdBy: row['created_by'] as String,
    createdAt: _parseRequiredDateTime(
      row['created_at'],
      fieldName: 'created_at',
    ),
    updatedAt: _parseRequiredDateTime(
      row['updated_at'],
      fieldName: 'updated_at',
    ),
  );
}

Map<String, dynamic> _normalizeRow(Map<String, dynamic> row) {
  return Map<String, dynamic>.from(row);
}

Map<String, dynamic> _extractJoinedRow(
  dynamic joinedData, {
  required bool isRequired,
  required String joinLabel,
}) {
  if (joinedData is Map<String, dynamic>) {
    return Map<String, dynamic>.from(joinedData);
  }
  if (joinedData is List && joinedData.isNotEmpty) {
    final firstRow = joinedData.first;
    if (firstRow is Map) {
      return Map<String, dynamic>.from(firstRow);
    }
  }
  if (isRequired) {
    throw StateError('Expected joined $joinLabel row payload in query result.');
  }
  return const <String, dynamic>{};
}

DateTime _parseRequiredDateTime(dynamic value, {required String fieldName}) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw StateError('Club row has invalid $fieldName timestamp value.');
}

double? _parseOptionalDouble(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw StateError('Club row has invalid numeric value: $value');
}

int _parseRequiredInt(dynamic value, {required String fieldName}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw StateError('Club row has invalid integer $fieldName value: $value');
}

String _escapeIlikePattern(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}

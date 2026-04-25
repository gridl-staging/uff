import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';
import 'package:uff/src/features/social/data/social_activity_repository.dart';
import 'package:uff/src/features/social/data/supabase_follow_repository.dart';
import 'package:uff/src/features/social/domain/remote_activity_track_point.dart';
import 'package:uff/src/features/social/domain/social_activity_detail.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';

const _activitySelectColumns =
    'id,user_id,sport_type,started_at,finished_at,distance_meters,'
    'duration_seconds,elevation_gain_meters,avg_pace_seconds_per_km,title,'
    'description,visibility,polyline_encoded,comments(count),'
    'profiles!activities_user_id_fkey(id,display_name,avatar_url)';
const _kudosSelectColumns = 'activity_id,user_id';
const _relationshipSelectColumns =
    'id,follower_id,following_id,status,created_at';
const _splitSelectColumns =
    'split_number,distance_meters,duration_seconds,avg_pace_seconds_per_km,'
    'avg_heart_rate,elevation_change_meters';
const _acceptedFollowStatus = 'accepted';
const _pendingFollowStatus = 'pending';

/// Supabase-backed read repository for social activity feeds and detail pages.
class SupabaseSocialActivityRepository implements SocialActivityRepository {
  SupabaseSocialActivityRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<SocialActivitySummary>> loadFeedActivities({
    required int offset,
    required int limit,
  }) async {
    final viewerUserId = _requireCurrentUserId();
    final followedOwnerIds = await _loadFollowedOwnerIds(viewerUserId);
    if (followedOwnerIds.isEmpty) {
      return const <SocialActivitySummary>[];
    }

    final rows = await _client
        .from('activities')
        .select(_activitySelectColumns)
        .inFilter('user_id', followedOwnerIds)
        .order('started_at', ascending: false)
        .range(offset, offset + limit - 1);
    return _mapSummaries(
      viewerUserId: viewerUserId,
      activityRows: rows,
    );
  }

  @override
  Future<List<SocialActivitySummary>> loadUserActivities(String userId) async {
    final viewerUserId = _requireCurrentUserId();
    final rows = await _client
        .from('activities')
        .select(_activitySelectColumns)
        .eq('user_id', userId)
        .order('started_at', ascending: false);
    return _mapSummaries(
      viewerUserId: viewerUserId,
      activityRows: rows,
    );
  }

  @override
  Future<SocialActivityDetail?> loadActivityDetail(String activityId) async {
    final viewerUserId = _requireCurrentUserId();
    final activityRows = await _client
        .from('activities')
        .select(_activitySelectColumns)
        .eq('id', activityId);
    if (activityRows.isEmpty) {
      return null;
    }

    final activityRow = normalizeSupabaseRow(activityRows.first);
    final ownerRelationships = await _loadOwnerRelationships(
      viewerUserId: viewerUserId,
      ownerIds: <String>[activityRow['user_id'] as String],
    );
    final splitsRows = await _client
        .from('splits')
        .select(_splitSelectColumns)
        .eq('activity_id', activityId)
        .order('split_number', ascending: true);
    final kudosByActivity = await _loadKudosStateForActivityIds(
      viewerUserId: viewerUserId,
      activityIds: <String>[activityId],
    );
    final rawTrackPointRows = await _client.rpc<List<Map<String, dynamic>>>(
      'read_activity_track_points',
      params: <String, dynamic>{'p_activity_id': activityId},
    );
    final trackPointRows = rawTrackPointRows as List<dynamic>;
    final kudosState =
        kudosByActivity[activityId] ?? const _ActivityKudosState.empty();

    return SocialActivityDetail(
      activityId: activityRow['id'] as String,
      owner: _mapOwnerSummary(
        viewerUserId: viewerUserId,
        activityRow: activityRow,
        ownerRelationship: ownerRelationships[activityRow['user_id'] as String],
      ),
      sportType: activityRow['sport_type'] as String,
      startedAt: _parseRequiredDateTime(
        activityRow['started_at'],
        fieldName: 'started_at',
      ),
      finishedAt: _parseOptionalDateTime(activityRow['finished_at']),
      distanceMeters: _parseRequiredDouble(
        activityRow['distance_meters'],
        fieldName: 'distance_meters',
      ),
      durationSeconds: _parseRequiredInt(
        activityRow['duration_seconds'],
        fieldName: 'duration_seconds',
      ),
      elevationGainMeters: _parseOptionalDouble(
        activityRow['elevation_gain_meters'],
      ),
      avgPaceSecondsPerKm: _parseOptionalDouble(
        activityRow['avg_pace_seconds_per_km'],
      ),
      title: activityRow['title'] as String?,
      description: activityRow['description'] as String?,
      visibility: activityRow['visibility'] as String,
      polylineEncoded: activityRow['polyline_encoded'] as String?,
      kudosCount: kudosState.kudosCount,
      viewerHasKudo: kudosState.viewerHasKudo,
      splits: splitsRows
          .map((row) => _mapSplit(normalizeSupabaseRow(row)))
          .toList(growable: false),
      trackPoints: trackPointRows
          .map(
            (row) => _mapTrackPoint(
              normalizeSupabaseRow(row as Map<String, dynamic>),
            ),
          )
          .toList(growable: false),
    );
  }

  Future<List<SocialActivitySummary>> _mapSummaries({
    required String viewerUserId,
    required List<dynamic> activityRows,
  }) async {
    if (activityRows.isEmpty) {
      return const <SocialActivitySummary>[];
    }

    final normalizedRows = activityRows
        .map((row) => normalizeSupabaseRow(row as Map<String, dynamic>))
        .toList(growable: false);
    final activityIds = normalizedRows
        .map((row) => row['id'] as String)
        .toList(growable: false);
    final ownerRelationships = await _loadOwnerRelationships(
      viewerUserId: viewerUserId,
      ownerIds: normalizedRows
          .map((row) => row['user_id'] as String)
          .toList(growable: false),
    );
    final kudosByActivity = await _loadKudosStateForActivityIds(
      viewerUserId: viewerUserId,
      activityIds: activityIds,
    );
    final routePreviewByActivity = await _loadSummaryRoutePreviews(
      viewerUserId: viewerUserId,
      activityRows: normalizedRows,
    );

    return normalizedRows
        .map(
          (activityRow) => _mapSummary(
            viewerUserId: viewerUserId,
            activityRow: activityRow,
            ownerRelationship:
                ownerRelationships[activityRow['user_id'] as String],
            kudosState:
                kudosByActivity[activityRow['id'] as String] ??
                const _ActivityKudosState.empty(),
            routePreview:
                routePreviewByActivity[activityRow['id'] as String] ??
                const _SummaryRoutePreview.empty(),
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, _SummaryRoutePreview>> _loadSummaryRoutePreviews({
    required String viewerUserId,
    required List<Map<String, dynamic>> activityRows,
  }) async {
    final previewEntries = await Future.wait(
      activityRows.map((activityRow) async {
        final activityId = activityRow['id'] as String;
        final ownerUserId = activityRow['user_id'] as String;
        if (ownerUserId == viewerUserId) {
          return MapEntry(
            activityId,
            _SummaryRoutePreview(
              polylineEncoded: activityRow['polyline_encoded'] as String?,
            ),
          );
        }

        // Summary previews for non-owners must honor the same masked geometry
        // contract as remote detail instead of depending on the owner's stored
        // summary polyline being present.
        final routePoints = await _loadVisibleRoutePoints(activityId);
        return MapEntry(
          activityId,
          _SummaryRoutePreview(routePoints: routePoints),
        );
      }),
    );
    return <String, _SummaryRoutePreview>{
      for (final entry in previewEntries)
        if (entry.key.isNotEmpty) entry.key: entry.value,
    };
  }

  Future<List<String>> _loadFollowedOwnerIds(String viewerUserId) async {
    final rows = await _client
        .from('follows')
        .select('following_id')
        .eq('follower_id', viewerUserId)
        .eq('status', _acceptedFollowStatus);
    return rows
        .map(
          (row) => normalizeSupabaseRow(row)['following_id'] as String,
        )
        .toList(growable: false);
  }

  Future<Map<String, _OwnerRelationshipRow>> _loadOwnerRelationships({
    required String viewerUserId,
    required List<String> ownerIds,
  }) async {
    if (ownerIds.isEmpty) {
      return const <String, _OwnerRelationshipRow>{};
    }

    final distinctOwnerIds = ownerIds.toSet().toList(growable: false);
    final outgoingRows = await _loadRelationshipRows(
      matchedColumn: 'following_id',
      matchedUserIds: distinctOwnerIds,
      leadingFilters: <_RelationshipFilter>[
        _RelationshipFilter(column: 'follower_id', value: viewerUserId),
      ],
    );
    final incomingPendingRows = await _loadRelationshipRows(
      matchedColumn: 'follower_id',
      matchedUserIds: distinctOwnerIds,
      leadingFilters: <_RelationshipFilter>[
        _RelationshipFilter(column: 'following_id', value: viewerUserId),
        const _RelationshipFilter(
          column: 'status',
          value: _pendingFollowStatus,
        ),
      ],
    );

    final relationships = <String, _OwnerRelationshipRow>{};
    for (final row in outgoingRows) {
      final relationshipRow = normalizeSupabaseRow(row as Map<String, dynamic>);
      relationships[relationshipRow['following_id']
          as String] = _OwnerRelationshipRow(
        direction: SocialRelationshipDirection.outgoing,
        row: relationshipRow,
      );
    }
    for (final row in incomingPendingRows) {
      final relationshipRow = normalizeSupabaseRow(row as Map<String, dynamic>);
      final ownerId = relationshipRow['follower_id'] as String;
      relationships.putIfAbsent(
        ownerId,
        () => _OwnerRelationshipRow(
          direction: SocialRelationshipDirection.incoming,
          row: relationshipRow,
        ),
      );
    }
    return relationships;
  }

  Future<List<dynamic>> _loadRelationshipRows({
    required List<_RelationshipFilter> leadingFilters,
    required String matchedColumn,
    required List<String> matchedUserIds,
  }) async {
    var query = _client.from('follows').select(_relationshipSelectColumns);
    for (final filter in leadingFilters) {
      query = query.eq(filter.column, filter.value);
    }

    if (matchedUserIds.length == 1) {
      return query.eq(matchedColumn, matchedUserIds.single);
    }
    return query.inFilter(matchedColumn, matchedUserIds);
  }

  Future<Map<String, _ActivityKudosState>> _loadKudosStateForActivityIds({
    required String viewerUserId,
    required List<String> activityIds,
  }) async {
    if (activityIds.isEmpty) {
      return const <String, _ActivityKudosState>{};
    }

    final rows = activityIds.length == 1
        ? await _client
              .from('kudos')
              .select(_kudosSelectColumns)
              .eq('activity_id', activityIds.single)
        : await _client
              .from('kudos')
              .select(_kudosSelectColumns)
              .inFilter('activity_id', activityIds);

    final states = <String, _ActivityKudosState>{
      for (final activityId in activityIds)
        activityId: const _ActivityKudosState.empty(),
    };
    for (final row in rows) {
      final kudosRow = normalizeSupabaseRow(row);
      final activityId = kudosRow['activity_id'] as String;
      final kudosUserId = kudosRow['user_id'] as String;
      final previousState =
          states[activityId] ?? const _ActivityKudosState.empty();
      states[activityId] = previousState.increment(
        hasViewerKudo: kudosUserId == viewerUserId,
      );
    }
    return states;
  }

  SocialActivitySummary _mapSummary({
    required String viewerUserId,
    required Map<String, dynamic> activityRow,
    required _OwnerRelationshipRow? ownerRelationship,
    required _ActivityKudosState kudosState,
    required _SummaryRoutePreview routePreview,
  }) {
    return SocialActivitySummary(
      activityId: activityRow['id'] as String,
      owner: _mapOwnerSummary(
        viewerUserId: viewerUserId,
        activityRow: activityRow,
        ownerRelationship: ownerRelationship,
      ),
      sportType: activityRow['sport_type'] as String,
      startedAt: _parseRequiredDateTime(
        activityRow['started_at'],
        fieldName: 'started_at',
      ),
      finishedAt: _parseOptionalDateTime(activityRow['finished_at']),
      distanceMeters: _parseRequiredDouble(
        activityRow['distance_meters'],
        fieldName: 'distance_meters',
      ),
      durationSeconds: _parseRequiredInt(
        activityRow['duration_seconds'],
        fieldName: 'duration_seconds',
      ),
      elevationGainMeters: _parseOptionalDouble(
        activityRow['elevation_gain_meters'],
      ),
      avgPaceSecondsPerKm: _parseOptionalDouble(
        activityRow['avg_pace_seconds_per_km'],
      ),
      title: activityRow['title'] as String?,
      description: activityRow['description'] as String?,
      visibility: activityRow['visibility'] as String,
      polylineEncoded: routePreview.polylineEncoded,
      routePoints: routePreview.routePoints,
      commentCount: _parseEmbeddedCount(activityRow['comments']),
      kudosCount: kudosState.kudosCount,
      viewerHasKudo: kudosState.viewerHasKudo,
    );
  }

  SocialUserSummary _mapOwnerSummary({
    required String viewerUserId,
    required Map<String, dynamic> activityRow,
    required _OwnerRelationshipRow? ownerRelationship,
  }) {
    return socialUserSummaryFromProfileRow(
      currentUserId: viewerUserId,
      profileRow: extractJoinedProfileRow(activityRow['profiles']),
      relationshipDirection:
          ownerRelationship?.direction ?? SocialRelationshipDirection.outgoing,
      relationshipRow: ownerRelationship?.row,
    );
  }

  SocialActivitySplit _mapSplit(Map<String, dynamic> splitRow) {
    return SocialActivitySplit(
      splitNumber: _parseRequiredInt(
        splitRow['split_number'],
        fieldName: 'split_number',
      ),
      distanceMeters: _parseRequiredDouble(
        splitRow['distance_meters'],
        fieldName: 'distance_meters',
      ),
      durationSeconds: _parseRequiredInt(
        splitRow['duration_seconds'],
        fieldName: 'duration_seconds',
      ),
      avgPaceSecondsPerKm: _parseOptionalDouble(
        splitRow['avg_pace_seconds_per_km'],
      ),
      avgHeartRate: _parseOptionalInt(splitRow['avg_heart_rate']),
      elevationChangeMeters: _parseOptionalDouble(
        splitRow['elevation_change_meters'],
      ),
    );
  }

  RemoteActivityTrackPoint _mapTrackPoint(Map<String, dynamic> trackPointRow) {
    return RemoteActivityTrackPoint(
      id: _parseRequiredInt(trackPointRow['id'], fieldName: 'id'),
      activityId: trackPointRow['activity_id'] as String,
      timestamp: _parseRequiredDateTime(
        trackPointRow['timestamp'],
        fieldName: 'timestamp',
      ),
      latitude: _parseOptionalDouble(trackPointRow['latitude']),
      longitude: _parseOptionalDouble(trackPointRow['longitude']),
      elevation: _parseOptionalDouble(trackPointRow['elevation']),
      heartRate: _parseOptionalInt(trackPointRow['heart_rate']),
      cadence: _parseOptionalInt(trackPointRow['cadence']),
      power: _parseOptionalInt(trackPointRow['power']),
      speed: _parseOptionalDouble(trackPointRow['speed']),
      distance: _parseOptionalDouble(trackPointRow['distance']),
      temperature: _parseOptionalInt(trackPointRow['temperature']),
    );
  }

  Future<List<RoutePoint>?> _loadVisibleRoutePoints(String activityId) async {
    final rawTrackPointRows = await _client.rpc<List<Map<String, dynamic>>>(
      'read_activity_track_points',
      params: <String, dynamic>{'p_activity_id': activityId},
    );
    final trackPointRows = rawTrackPointRows as List<dynamic>;
    final visibleRoutePoints = trackPointRows
        .map(
          (row) => _mapTrackPoint(
            normalizeSupabaseRow(row as Map<String, dynamic>),
          ),
        )
        .where((point) => point.latitude != null && point.longitude != null)
        .map(
          (point) => RoutePoint(
            latitude: point.latitude!,
            longitude: point.longitude!,
          ),
        )
        .toList(growable: false);
    if (visibleRoutePoints.length < 2) {
      return null;
    }
    return visibleRoutePoints;
  }

  String _requireCurrentUserId() {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) {
      throw StateError(
        'Social activity reads require an authenticated user session.',
      );
    }
    return currentUserId;
  }
}

/// Tracks aggregate and viewer-specific kudos state while mapping feed rows.
class _ActivityKudosState {
  const _ActivityKudosState({
    required this.kudosCount,
    required this.viewerHasKudo,
  });

  const _ActivityKudosState.empty() : kudosCount = 0, viewerHasKudo = false;

  final int kudosCount;
  final bool viewerHasKudo;

  _ActivityKudosState increment({required bool hasViewerKudo}) {
    return _ActivityKudosState(
      kudosCount: kudosCount + 1,
      viewerHasKudo: viewerHasKudo || hasViewerKudo,
    );
  }
}

class _SummaryRoutePreview {
  const _SummaryRoutePreview({
    this.polylineEncoded,
    this.routePoints,
  });

  const _SummaryRoutePreview.empty()
    : polylineEncoded = null,
      routePoints = null;

  final String? polylineEncoded;
  final List<RoutePoint>? routePoints;
}

class _OwnerRelationshipRow {
  const _OwnerRelationshipRow({
    required this.direction,
    required this.row,
  });

  final SocialRelationshipDirection direction;
  final Map<String, dynamic> row;
}

class _RelationshipFilter {
  const _RelationshipFilter({
    required this.column,
    required this.value,
  });

  final String column;
  final Object value;
}

DateTime _parseRequiredDateTime(
  dynamic value, {
  required String fieldName,
}) {
  final dateTime = _parseOptionalDateTime(value);
  if (dateTime == null) {
    throw StateError('Expected a timestamp for $fieldName but found $value.');
  }
  return dateTime;
}

DateTime? _parseOptionalDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String) {
    return DateTime.parse(value).toUtc();
  }
  throw StateError('Unsupported timestamp value: $value');
}

double _parseRequiredDouble(
  dynamic value, {
  required String fieldName,
}) {
  final parsedValue = _parseOptionalDouble(value);
  if (parsedValue == null) {
    throw StateError('Expected a number for $fieldName but found $value.');
  }
  return parsedValue;
}

double? _parseOptionalDouble(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw StateError('Unsupported numeric value: $value');
}

int _parseRequiredInt(
  dynamic value, {
  required String fieldName,
}) {
  final parsedValue = _parseOptionalInt(value);
  if (parsedValue == null) {
    throw StateError('Expected an integer for $fieldName but found $value.');
  }
  return parsedValue;
}

int? _parseOptionalInt(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toInt();
  }
  throw StateError('Unsupported integer value: $value');
}

int _parseEmbeddedCount(dynamic value) {
  if (value == null) {
    return 0;
  }
  if (value is List && value.isNotEmpty) {
    final row = value.first;
    if (row is Map<String, dynamic>) {
      return _parseOptionalInt(normalizeSupabaseRow(row)['count']) ?? 0;
    }
  }
  if (value is Map<String, dynamic>) {
    return _parseOptionalInt(normalizeSupabaseRow(value)['count']) ?? 0;
  }
  return 0;
}

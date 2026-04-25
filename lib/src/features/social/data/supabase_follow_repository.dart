import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/social/data/follow_repository.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/relationship_counts.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/domain/viewed_user_profile_header.dart';

const _acceptedFollowStatus = 'accepted';
const _pendingFollowStatus = 'pending';
const _profileHeaderSelect = 'id,display_name,avatar_url';
const _followsBaseSelect = 'id,follower_id,following_id,status,created_at';
const _followersJoinSelect =
    '$_followsBaseSelect,profiles!follows_follower_id_fkey(id,display_name,avatar_url)';
const _followingJoinSelect =
    '$_followsBaseSelect,profiles!follows_following_id_fkey(id,display_name,avatar_url)';

/// Controls whether a follow edge should be interpreted as outgoing or incoming.
enum SocialRelationshipDirection { outgoing, incoming }

/// NOTE(stuart): Document SupabaseFollowRepository.
class SupabaseFollowRepository implements FollowRepository {
  SupabaseFollowRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> sendFollowRequest(String targetUserId) async {
    final currentUserId = _requireCurrentUserId();
    await _client.from('follows').insert({
      'follower_id': currentUserId,
      'following_id': targetUserId,
      'status': _pendingFollowStatus,
    });
  }

  @override
  Future<void> acceptFollowRequest(String followId) async {
    _requireCurrentUserId();
    final updatedRows = await _client
        .from('follows')
        .update({'status': _acceptedFollowStatus})
        .eq('id', followId)
        .select('id');
    _requireAffectedRow(
      rows: updatedRows,
      actionDescription: 'accept follow request',
    );
  }

  @override
  Future<void> rejectFollowRequest(String followId) async {
    _requireCurrentUserId();
    final deletedRows = await _client
        .from('follows')
        .delete()
        .eq('id', followId)
        .select('id');
    _requireAffectedRow(
      rows: deletedRows,
      actionDescription: 'reject follow request',
    );
  }

  @override
  Future<void> unfollow(String targetUserId) async {
    final currentUserId = _requireCurrentUserId();
    final deletedRows = await _client
        .from('follows')
        .delete()
        .eq('follower_id', currentUserId)
        .eq('following_id', targetUserId)
        .select('id');
    _requireAffectedRow(
      rows: deletedRows,
      actionDescription: 'unfollow user',
    );
  }

  @override
  Future<List<SocialUserSummary>> getFollowers() async {
    final currentUserId = _requireCurrentUserId();
    final rows = await _client
        .from('follows')
        .select(_followersJoinSelect)
        .eq('following_id', currentUserId)
        .eq('status', _acceptedFollowStatus)
        .order('created_at', ascending: false);
    final outgoingRelationships = await _loadOutgoingRelationships(
      currentUserId: currentUserId,
    );

    return rows
        .map((row) {
          final rowMap = _normalizeRow(row);
          final profileRow = _extractJoinedProfile(rowMap['profiles']);
          final followerId = rowMap['follower_id'] as String;
          return socialUserSummaryFromProfileRow(
            currentUserId: currentUserId,
            profileRow: profileRow,
            relationshipDirection: SocialRelationshipDirection.outgoing,
            relationshipRow: outgoingRelationships[followerId],
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<SocialUserSummary>> getFollowing() async {
    final currentUserId = _requireCurrentUserId();
    final rows = await _client
        .from('follows')
        .select(_followingJoinSelect)
        .eq('follower_id', currentUserId)
        .eq('status', _acceptedFollowStatus)
        .order('created_at', ascending: false);

    return rows
        .map((row) {
          final rowMap = _normalizeRow(row);
          final profileRow = _extractJoinedProfile(rowMap['profiles']);
          return socialUserSummaryFromProfileRow(
            currentUserId: currentUserId,
            profileRow: profileRow,
            relationshipDirection: SocialRelationshipDirection.outgoing,
            relationshipRow: rowMap,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<SocialUserSummary>> getPendingRequests() async {
    final currentUserId = _requireCurrentUserId();
    final rows = await _client
        .from('follows')
        .select(_followersJoinSelect)
        .eq('following_id', currentUserId)
        .eq('status', _pendingFollowStatus)
        .order('created_at', ascending: false);

    return rows
        .map((row) {
          final rowMap = _normalizeRow(row);
          final profileRow = _extractJoinedProfile(rowMap['profiles']);
          return socialUserSummaryFromProfileRow(
            currentUserId: currentUserId,
            profileRow: profileRow,
            relationshipDirection: SocialRelationshipDirection.incoming,
            relationshipRow: rowMap,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<RelationshipCounts> getRelationshipCounts() async {
    final currentUserId = _requireCurrentUserId();
    final followersRows = await _client
        .from('follows')
        .select('id')
        .eq('following_id', currentUserId)
        .eq('status', _acceptedFollowStatus);
    final followingRows = await _client
        .from('follows')
        .select('id')
        .eq('follower_id', currentUserId)
        .eq('status', _acceptedFollowStatus);
    final pendingRows = await _client
        .from('follows')
        .select('id')
        .eq('following_id', currentUserId)
        .eq('status', _pendingFollowStatus);

    return RelationshipCounts(
      userId: currentUserId,
      followers: followersRows.length,
      following: followingRows.length,
      pendingRequests: pendingRows.length,
    );
  }

  @override
  Future<ViewedUserProfileHeader?> getViewedUserProfileHeader(
    String userId,
  ) async {
    final currentUserId = _requireCurrentUserId();
    final profileRows = await _client
        .from('profiles')
        .select(_profileHeaderSelect)
        .eq('id', userId);
    if (profileRows.isEmpty) {
      return null;
    }

    final outgoingRows = await _client
        .from('follows')
        .select(_followsBaseSelect)
        .eq('follower_id', currentUserId)
        .eq('following_id', userId);
    final incomingPendingRows = await _client
        .from('follows')
        .select(_followsBaseSelect)
        .eq('following_id', currentUserId)
        .eq('follower_id', userId)
        .eq('status', _pendingFollowStatus);
    final followersRows = await _client
        .from('follows')
        .select('id')
        .eq('following_id', userId)
        .eq('status', _acceptedFollowStatus);
    final followingRows = await _client
        .from('follows')
        .select('id')
        .eq('follower_id', userId)
        .eq('status', _acceptedFollowStatus);

    final relationshipRow = outgoingRows.isNotEmpty
        ? normalizeSupabaseRow(outgoingRows.first)
        : incomingPendingRows.isNotEmpty
        ? normalizeSupabaseRow(incomingPendingRows.first)
        : null;
    final relationshipDirection = outgoingRows.isNotEmpty
        ? SocialRelationshipDirection.outgoing
        : incomingPendingRows.isNotEmpty
        ? SocialRelationshipDirection.incoming
        : SocialRelationshipDirection.outgoing;

    return ViewedUserProfileHeader(
      user: socialUserSummaryFromProfileRow(
        currentUserId: currentUserId,
        profileRow: normalizeSupabaseRow(profileRows.first),
        relationshipDirection: relationshipDirection,
        relationshipRow: relationshipRow,
      ),
      followersCount: followersRows.length,
      followingCount: followingRows.length,
    );
  }

  Future<Map<String, Map<String, dynamic>>> _loadOutgoingRelationships({
    required String currentUserId,
  }) async {
    final rows = await _client
        .from('follows')
        .select(_followsBaseSelect)
        .eq('follower_id', currentUserId);
    final relationshipByTarget = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final rowMap = _normalizeRow(row);
      relationshipByTarget[rowMap['following_id'] as String] = rowMap;
    }
    return relationshipByTarget;
  }

  String _requireCurrentUserId() {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) {
      throw StateError(
        'Follow operations require an authenticated user session.',
      );
    }
    return currentUserId;
  }

  void _requireAffectedRow({
    required List<dynamic> rows,
    required String actionDescription,
  }) {
    if (rows.isNotEmpty) {
      return;
    }
    throw StateError(
      'Unable to $actionDescription because the requested relationship '
      'was not found or is no longer accessible.',
    );
  }
}

/// Builds a [SocialUserSummary] from profile and relationship rows.
SocialUserSummary socialUserSummaryFromProfileRow({
  required String currentUserId,
  required Map<String, dynamic> profileRow,
  required SocialRelationshipDirection relationshipDirection,
  Map<String, dynamic>? relationshipRow,
}) {
  final userId = profileRow['id'] as String;
  return SocialUserSummary(
    userId: userId,
    displayName: profileRow['display_name'] as String?,
    avatarUrl: profileRow['avatar_url'] as String?,
    relationship: followRelationshipFromRow(
      currentUserId: currentUserId,
      targetUserId: userId,
      direction: relationshipDirection,
      row: relationshipRow,
    ),
  );
}

/// Builds a [FollowRelationship] from a row in `public.follows`.
FollowRelationship followRelationshipFromRow({
  required String currentUserId,
  required String targetUserId,
  required SocialRelationshipDirection direction,
  required Map<String, dynamic>? row,
}) {
  if (row == null) {
    return FollowRelationship(
      currentUserId: currentUserId,
      targetUserId: targetUserId,
      status: FollowRelationshipStatus.none,
    );
  }

  final rawStatus = row['status'] as String?;
  final relationshipStatus = switch (rawStatus) {
    _acceptedFollowStatus => FollowRelationshipStatus.following,
    _pendingFollowStatus
        when direction == SocialRelationshipDirection.outgoing =>
      FollowRelationshipStatus.outgoingPending,
    _pendingFollowStatus
        when direction == SocialRelationshipDirection.incoming =>
      FollowRelationshipStatus.incomingPending,
    _ => FollowRelationshipStatus.none,
  };

  return FollowRelationship(
    currentUserId: currentUserId,
    targetUserId: targetUserId,
    status: relationshipStatus,
    followId: row['id'] as String?,
    createdAt: _parseCreatedAt(row['created_at']),
  );
}

Map<String, dynamic> _normalizeRow(Map<String, dynamic> row) {
  return normalizeSupabaseRow(row);
}

Map<String, dynamic> _extractJoinedProfile(dynamic profileData) {
  return extractJoinedProfileRow(profileData);
}

Map<String, dynamic> normalizeSupabaseRow(Map<String, dynamic> row) {
  return Map<String, dynamic>.from(row);
}

Map<String, dynamic> extractJoinedProfileRow(dynamic profileData) {
  if (profileData is Map<String, dynamic>) {
    return Map<String, dynamic>.from(profileData);
  }
  if (profileData is List && profileData.isNotEmpty) {
    return Map<String, dynamic>.from(profileData.first as Map);
  }
  return const <String, dynamic>{};
}

DateTime? _parseCreatedAt(dynamic value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

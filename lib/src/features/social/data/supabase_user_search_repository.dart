import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/social/data/supabase_follow_repository.dart';
import 'package:uff/src/features/social/data/user_search_repository.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';

const _searchRelationshipSelect =
    'id,follower_id,following_id,status,created_at';
const _pendingFollowStatus = 'pending';

/// NOTE(stuart): Document SupabaseUserSearchRepository.
class SupabaseUserSearchRepository implements UserSearchRepository {
  SupabaseUserSearchRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<SocialUserSummary>> searchUsers(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const <SocialUserSummary>[];
    }

    final currentUserId = _requireCurrentUserId();
    final profileRows = await _client
        .from('profiles')
        .select('id,display_name,avatar_url')
        // Escape LIKE metacharacters so search input is treated literally
        // rather than allowing wildcard-driven profile enumeration.
        .ilike('display_name', _buildDisplayNameSearchPattern(trimmedQuery))
        .neq('id', currentUserId)
        .order('display_name', ascending: true);

    if (profileRows.isEmpty) {
      return const <SocialUserSummary>[];
    }

    final relationshipRows = await _client
        .from('follows')
        .select(_searchRelationshipSelect)
        .eq('follower_id', currentUserId);

    final incomingPendingRows = await _client
        .from('follows')
        .select(_searchRelationshipSelect)
        .eq('following_id', currentUserId)
        .eq('status', _pendingFollowStatus);

    final outgoingRelationshipsByTarget = <String, Map<String, dynamic>>{};
    for (final row in relationshipRows) {
      final normalizedRow = Map<String, dynamic>.from(row);
      outgoingRelationshipsByTarget[normalizedRow['following_id'] as String] =
          normalizedRow;
    }

    final incomingPendingByRequester = <String, Map<String, dynamic>>{};
    for (final row in incomingPendingRows) {
      final normalizedRow = Map<String, dynamic>.from(row);
      incomingPendingByRequester[normalizedRow['follower_id'] as String] =
          normalizedRow;
    }

    return profileRows
        .map((row) {
          final profileRow = Map<String, dynamic>.from(row);
          final targetUserId = profileRow['id'] as String;
          final outgoingRelationship =
              outgoingRelationshipsByTarget[targetUserId];
          final relationshipRow =
              outgoingRelationship ?? incomingPendingByRequester[targetUserId];
          final relationshipDirection = outgoingRelationship != null
              ? SocialRelationshipDirection.outgoing
              : SocialRelationshipDirection.incoming;
          return socialUserSummaryFromProfileRow(
            currentUserId: currentUserId,
            profileRow: profileRow,
            relationshipDirection: relationshipDirection,
            relationshipRow: relationshipRow,
          );
        })
        .toList(growable: false);
  }

  String _requireCurrentUserId() {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) {
      throw StateError(
        'User search requires an authenticated user session.',
      );
    }
    return currentUserId;
  }
}

String _buildDisplayNameSearchPattern(String query) {
  return '%${_escapeLikePattern(query)}%';
}

String _escapeLikePattern(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}

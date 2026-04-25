import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/social/data/kudos_repository.dart';
import 'package:uff/src/features/social/data/supabase_follow_repository.dart';
import 'package:uff/src/features/social/domain/activity_kudos.dart';

const _kudosSelectColumns =
    'activity_id,user_id,profiles!kudos_user_id_fkey(id,display_name,avatar_url)';

/// Supabase-backed implementation of [KudosRepository].
class SupabaseKudosRepository implements KudosRepository {
  SupabaseKudosRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ActivityKudosSummary> loadActivityKudos(String activityId) async {
    final viewerUserId = _requireCurrentUserId();
    final rows = await _client
        .from('kudos')
        .select(_kudosSelectColumns)
        .eq('activity_id', activityId);

    var viewerHasKudo = false;
    final users = <ActivityKudoUser>[];
    for (final row in rows) {
      final rowMap = normalizeSupabaseRow(row);
      final userId = rowMap['user_id'] as String;
      if (userId == viewerUserId) {
        viewerHasKudo = true;
      }
      final profileRow = extractJoinedProfileRow(rowMap['profiles']);
      users.add(
        ActivityKudoUser(
          userId: userId,
          displayName: profileRow['display_name'] as String?,
          avatarUrl: profileRow['avatar_url'] as String?,
        ),
      );
    }

    return ActivityKudosSummary(
      kudosCount: rows.length,
      viewerHasKudo: viewerHasKudo,
      users: users,
    );
  }

  @override
  Future<void> toggleKudos({
    required String activityId,
    required bool viewerHasKudo,
  }) async {
    final viewerUserId = _requireCurrentUserId();
    if (viewerHasKudo) {
      final deletedRows = await _client
          .from('kudos')
          .delete()
          .eq('activity_id', activityId)
          .eq('user_id', viewerUserId)
          .select('id');
      if (deletedRows.isEmpty) {
        throw StateError(
          'Unable to remove kudos because the existing kudos row was not '
          'found or is no longer accessible.',
        );
      }
      return;
    }

    await _client.from('kudos').insert({
      'activity_id': activityId,
      'user_id': viewerUserId,
    });
  }

  String _requireCurrentUserId() {
    final viewerUserId = _client.auth.currentUser?.id;
    if (viewerUserId == null) {
      throw StateError(
        'Kudos operations require an authenticated user session.',
      );
    }
    return viewerUserId;
  }
}

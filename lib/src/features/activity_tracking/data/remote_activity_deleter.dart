import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/utils/app_logger.dart';

typedef UserIdProvider = String? Function();

/// TODO: Document RemoteActivityDeleter.
class RemoteActivityDeleter {
  RemoteActivityDeleter({
    required SupabaseClient supabaseClient,
    required UserIdProvider currentUserIdProvider,
    required AppLogger logger,
  }) : _supabaseClient = supabaseClient,
       _currentUserIdProvider = currentUserIdProvider,
       _logger = logger;

  final SupabaseClient _supabaseClient;
  final UserIdProvider _currentUserIdProvider;
  final AppLogger _logger;

  Future<void> deleteRemoteActivity(String remoteActivityId) async {
    final userId = _currentUserIdProvider();
    if (userId == null) {
      throw StateError(
        'Cannot delete remote activities without an authenticated user.',
      );
    }

    final photoRows =
        await _supabaseClient
                .from('activity_photos')
                .select('storage_path,thumbnail_path')
                .eq('activity_id', remoteActivityId)
                .eq('user_id', userId)
            as List<dynamic>;
    final pathsToDelete = <String>{};
    for (final row in photoRows) {
      final photoRow = row as Map<String, dynamic>;
      _addOwnedPhotoPath(
        pathsToDelete,
        photoRow['storage_path'] as String?,
        userId: userId,
        remoteActivityId: remoteActivityId,
      );
      _addOwnedPhotoPath(
        pathsToDelete,
        photoRow['thumbnail_path'] as String?,
        userId: userId,
        remoteActivityId: remoteActivityId,
      );
    }

    if (pathsToDelete.isNotEmpty) {
      try {
        await _supabaseClient.storage
            .from('activity-photos')
            .remove(pathsToDelete.toList(growable: false));
      } on Object catch (error) {
        _logger.logEvent(
          eventType: 'sync.remote_delete.storage_cleanup',
          outcome: 'failure',
          identifiers: {
            'activity_id': remoteActivityId,
            'reason': error.runtimeType.toString(),
          },
        );
      }
    }

    await _supabaseClient
        .from('activities')
        .delete()
        .eq('id', remoteActivityId)
        .eq('user_id', userId);
  }

  void _addOwnedPhotoPath(
    Set<String> pathsToDelete,
    String? candidatePath, {
    required String userId,
    required String remoteActivityId,
  }) {
    final normalizedPath = candidatePath?.trim();
    if (normalizedPath == null || normalizedPath.isEmpty) {
      return;
    }

    // Only delete objects inside the current user's folder for the activity
    // being removed. Database rows are not treated as authoritative for bucket
    // object ownership.
    if (!_isOwnedActivityPhotoPath(
      normalizedPath,
      userId: userId,
      remoteActivityId: remoteActivityId,
    )) {
      _logger.logEvent(
        eventType: 'sync.remote_delete.storage_cleanup',
        outcome: 'skipped_unowned_path',
        identifiers: {'activity_id': remoteActivityId},
      );
      return;
    }

    pathsToDelete.add(normalizedPath);
  }

  bool _isOwnedActivityPhotoPath(
    String path, {
    required String userId,
    required String remoteActivityId,
  }) {
    return path.startsWith('$userId/$remoteActivityId/');
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class ActivityGearAssignmentRepository {
  Future<String?> loadAssignedGearId(String remoteActivityId);

  Future<void> updateAssignedGearId(String remoteActivityId, String? gearId);
}

/// NOTE(stuart): Document SupabaseActivityGearAssignmentRepository.
class SupabaseActivityGearAssignmentRepository
    implements ActivityGearAssignmentRepository {
  SupabaseActivityGearAssignmentRepository(this._supabaseClient);

  final SupabaseClient _supabaseClient;

  @override
  Future<String?> loadAssignedGearId(String remoteActivityId) async {
    final rows = await _supabaseClient
        .from('activities')
        .select('gear_id')
        .eq('id', remoteActivityId);

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    return row['gear_id'] as String?;
  }

  @override
  Future<void> updateAssignedGearId(
    String remoteActivityId,
    String? gearId,
  ) async {
    final updatedRows = await _supabaseClient
        .from('activities')
        .update(<String, dynamic>{'gear_id': gearId})
        .eq('id', remoteActivityId)
        .select('id');
    if (updatedRows.isEmpty) {
      throw StateError(
        'Cannot assign gear for missing remote activity: $remoteActivityId',
      );
    }
  }
}

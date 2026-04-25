import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/gear/data/gear_repository.dart';
import 'package:uff/src/features/gear/domain/gear_item.dart';

/// TODO: Document SupabaseGearRepository.
class SupabaseGearRepository implements GearRepository {
  SupabaseGearRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<GearItem>> loadGear() async {
    final data = await _client
        .from('gear')
        .select()
        .order('created_at', ascending: false);
    return data.map(gearItemFromJson).toList();
  }

  @override
  Future<GearItem> createGear(GearItem item) async {
    final authenticatedUserId = _requireAuthenticatedUserId(_client);
    final row = await _client
        .from('gear')
        .insert({'user_id': authenticatedUserId, ..._writableGearColumns(item)})
        .select()
        .single();
    return gearItemFromJson(row);
  }

  @override
  Future<void> updateGear(GearItem item) async {
    final authenticatedUserId = _requireAuthenticatedUserId(_client);
    final updatedRows = await _client
        .from('gear')
        .update({..._writableGearColumns(item), 'retired': item.retired})
        .eq('id', item.id)
        .eq('user_id', authenticatedUserId)
        .select('id');
    _requireSingleAffectedRow(
      updatedRows,
      operation: 'update',
      gearId: item.id,
    );
  }

  @override
  Future<void> deleteGear(String id) async {
    final authenticatedUserId = _requireAuthenticatedUserId(_client);
    final deletedRows = await _client
        .from('gear')
        .delete()
        .eq('id', id)
        .eq('user_id', authenticatedUserId)
        .select('id');
    _requireSingleAffectedRow(deletedRows, operation: 'delete', gearId: id);
  }
}

Map<String, dynamic> _writableGearColumns(GearItem item) {
  return {
    'name': item.name,
    'gear_type': item.gearType.name,
    'total_distance_meters': item.totalDistanceMeters,
    'start_date': _serializeDateColumn(item.startDate),
    'brand': item.brand,
    'model': item.model,
    'notes': item.notes,
  };
}

String _requireAuthenticatedUserId(SupabaseClient client) {
  final userId = client.auth.currentUser?.id;
  if (userId != null && userId.isNotEmpty) {
    return userId;
  }

  throw StateError('Gear mutations require an authenticated user session.');
}

void _requireSingleAffectedRow(
  List<dynamic> rows, {
  required String operation,
  required String gearId,
}) {
  if (rows.length == 1) {
    return;
  }

  throw StateError(
    'Gear $operation must affect exactly one row for id $gearId, '
    'but affected ${rows.length}.',
  );
}

/// Deserializes a Supabase gear row into a [GearItem].
GearItem gearItemFromJson(Map<String, dynamic> json) {
  return GearItem(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    name: json['name'] as String,
    gearType: GearType.values.byName(json['gear_type'] as String),
    totalDistanceMeters: (json['total_distance_meters'] as num).toDouble(),
    retired: json['retired'] as bool,
    startDate: _deserializeDateColumn(json['start_date']),
    brand: json['brand'] as String?,
    model: json['model'] as String?,
    notes: json['notes'] as String?,
  );
}

String? _serializeDateColumn(DateTime? value) {
  if (value == null) {
    return null;
  }

  final normalized = DateTime(value.year, value.month, value.day);
  final year = normalized.year.toString().padLeft(4, '0');
  final month = normalized.month.toString().padLeft(2, '0');
  final day = normalized.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

DateTime? _deserializeDateColumn(Object? value) {
  if (value == null) {
    return null;
  }

  final parsed = value is DateTime ? value : DateTime.parse(value as String);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

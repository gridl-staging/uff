import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/profile/data/privacy_zone_repository.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';

/// NOTE(stuart): Document SupabasePrivacyZoneRepository.
class SupabasePrivacyZoneRepository implements PrivacyZoneRepository {
  SupabasePrivacyZoneRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<PrivacyZone>> loadZones() async {
    final rows = await _client
        .from('privacy_zones')
        .select()
        .order('created_at', ascending: false);

    return rows.map(PrivacyZone.fromJson).toList(growable: false);
  }

  @override
  Future<PrivacyZone> createZone({
    required String label,
    required double latitude,
    required double longitude,
    required int radiusMeters,
  }) async {
    final userId = _requireCurrentUserId();
    final row = await _client
        .from('privacy_zones')
        .insert({
          'user_id': userId,
          'label': label,
          'latitude': latitude,
          'longitude': longitude,
          'radius_meters': radiusMeters,
        })
        .select()
        .single();

    return PrivacyZone.fromJson(row);
  }

  @override
  Future<void> updateZone(PrivacyZone zone) async {
    await _client
        .from('privacy_zones')
        .update({
          'label': zone.label,
          'latitude': zone.latitude,
          'longitude': zone.longitude,
          'radius_meters': zone.radiusMeters,
        })
        .eq('id', zone.id);
  }

  @override
  Future<void> deleteZone(String id) async {
    await _client.from('privacy_zones').delete().eq('id', id);
  }

  String _requireCurrentUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError(
        'Cannot create a privacy zone without an authenticated user.',
      );
    }
    return userId;
  }
}

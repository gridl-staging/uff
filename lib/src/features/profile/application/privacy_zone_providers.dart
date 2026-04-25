import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/profile/data/privacy_zone_repository.dart';
import 'package:uff/src/features/profile/data/supabase_privacy_zone_repository.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';

final Provider<PrivacyZoneRepository> privacyZoneRepositoryProvider =
    Provider<PrivacyZoneRepository>(
      (ref) => SupabasePrivacyZoneRepository(Supabase.instance.client),
    );

final FutureProvider<List<PrivacyZone>> privacyZonesProvider =
    FutureProvider.autoDispose<List<PrivacyZone>>(
      (ref) => ref.read(privacyZoneRepositoryProvider).loadZones(),
    );

final FutureProvider<PrivacyZone?> Function(String zoneId)
privacyZoneByIdProvider = FutureProvider.autoDispose
    .family<PrivacyZone?, String>((ref, zoneId) async {
      final zones = await ref.watch(privacyZonesProvider.future);
      return _findZoneById(zones, zoneId);
    });

PrivacyZone? _findZoneById(List<PrivacyZone> zones, String zoneId) {
  for (final zone in zones) {
    if (zone.id == zoneId) {
      return zone;
    }
  }
  return null;
}

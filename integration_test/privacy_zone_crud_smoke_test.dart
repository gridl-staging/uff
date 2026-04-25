import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/profile/data/supabase_privacy_zone_repository.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';

import 'supabase_smoke_helpers.dart';

/// ## Test Scenarios
/// - `[positive]` create/load/update/delete persists exact privacy zone values
/// - `[isolation]` Teardown removes all seeded rows for the authenticated user
void main() {
  group('Privacy-zone CRUD smoke test', skip: skipReason, () {
    late SupabaseClient client;
    late SupabasePrivacyZoneRepository repository;
    late String userId;

    setUp(() async {
      client = createTestClient();
      await client.auth.signUp(
        email: generateTestEmail(),
        password: testPassword,
        data: {'display_name': 'Privacy Zone CRUD Smoke'},
      );

      userId = client.auth.currentUser!.id;
      repository = SupabasePrivacyZoneRepository(client);
    });

    tearDown(() async {
      await _deleteAllZonesForCurrentUser(client, userId);
      await cleanupSupabaseClient(client);
    });

    test('create/load/update/delete persists expected row shape', () async {
      final createdZone = await repository.createZone(
        label: 'Home',
        latitude: 37.7749,
        longitude: -122.4194,
        radiusMeters: 250,
      );

      expect(createdZone.userId, userId);
      expect(createdZone.label, 'Home');
      expect(createdZone.latitude, closeTo(37.7749, 0.000001));
      expect(createdZone.longitude, closeTo(-122.4194, 0.000001));
      expect(createdZone.radiusMeters, 250);

      final createdRow = await client
          .from('privacy_zones')
          .select()
          .eq('id', createdZone.id)
          .single();

      expect(createdRow['id'], createdZone.id);
      expect(createdRow['user_id'], userId);
      expect(createdRow['label'], 'Home');
      expect(
        (createdRow['latitude'] as num).toDouble(),
        closeTo(37.7749, 0.000001),
      );
      expect(
        (createdRow['longitude'] as num).toDouble(),
        closeTo(-122.4194, 0.000001),
      );
      expect(createdRow['radius_meters'], 250);
      final createdAt = DateTime.parse(createdRow['created_at'] as String);
      final updatedAt = DateTime.parse(createdRow['updated_at'] as String);
      expect(updatedAt.isBefore(createdAt), isFalse);
      expect(updatedAt.difference(createdAt).inSeconds, 0);

      final loadedZones = await repository.loadZones();
      expect(loadedZones, hasLength(1));
      expect(loadedZones.single.id, createdZone.id);

      final updatedZone = PrivacyZone(
        id: createdZone.id,
        userId: createdZone.userId,
        label: 'Home Updated',
        latitude: 37.7755,
        longitude: -122.4188,
        radiusMeters: 300,
      );
      await repository.updateZone(updatedZone);

      final updatedRow = await client
          .from('privacy_zones')
          .select()
          .eq('id', createdZone.id)
          .single();
      expect(updatedRow['label'], 'Home Updated');
      expect(
        (updatedRow['latitude'] as num).toDouble(),
        closeTo(37.7755, 0.000001),
      );
      expect(
        (updatedRow['longitude'] as num).toDouble(),
        closeTo(-122.4188, 0.000001),
      );
      expect(updatedRow['radius_meters'], 300);

      await repository.deleteZone(createdZone.id);

      final deletedRows = await client
          .from('privacy_zones')
          .select('id')
          .eq('id', createdZone.id);
      expect(deletedRows, isEmpty);

      final remainingRowsForUser = await client
          .from('privacy_zones')
          .select('id')
          .eq('user_id', userId);
      expect(
        remainingRowsForUser,
        isEmpty,
        reason:
            'CRUD smoke test must not leak privacy_zones rows for the user.',
      );
    });
  });
}

Future<void> _deleteAllZonesForCurrentUser(
  SupabaseClient client,
  String userId,
) async {
  await client.from('privacy_zones').delete().eq('user_id', userId);
}

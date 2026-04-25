import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/profile/data/supabase_privacy_zone_repository.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';

import 'supabase_smoke_helpers.dart';

/// ## Test Scenarios
/// - [negative] Other user's direct SELECT on owner's privacy_zones row returns empty
/// - [negative] Other user's loadZones() excludes owner's zone ID
/// - [negative] Other user's UPDATE attempt leaves all 4 owner fields unchanged
/// - [negative] Other user's DELETE attempt leaves owner row present
/// - [isolation] Each test run creates fresh users and tears down owner rows
void main() {
  group('Privacy-zone RLS smoke test', skip: skipReason, () {
    late SupabaseClient ownerClient;
    late SupabaseClient otherClient;
    late SupabasePrivacyZoneRepository ownerRepository;
    late SupabasePrivacyZoneRepository otherRepository;
    late String ownerUserId;

    setUp(() async {
      ownerClient = createTestClient();
      otherClient = createTestClient();

      await ownerClient.auth.signUp(
        email: generateTestEmail(),
        password: testPassword,
        data: {'display_name': 'Privacy Zone Owner'},
      );
      await otherClient.auth.signUp(
        email: generateTestEmail(),
        password: testPassword,
        data: {'display_name': 'Privacy Zone Other User'},
      );

      ownerUserId = ownerClient.auth.currentUser!.id;
      ownerRepository = SupabasePrivacyZoneRepository(ownerClient);
      otherRepository = SupabasePrivacyZoneRepository(otherClient);
    });

    tearDown(() async {
      await ownerClient
          .from('privacy_zones')
          .delete()
          .eq('user_id', ownerUserId);
      await cleanupSupabaseClient(ownerClient);
      await cleanupSupabaseClient(otherClient);
    });

    test(
      'second user cannot read, update, or delete owner privacy-zone row',
      () async {
        final ownerZone = await ownerRepository.createZone(
          label: 'Owner Home',
          latitude: 40.7128,
          longitude: -74.0060,
          radiusMeters: 200,
        );

        final otherVisibleRows = await otherClient
            .from('privacy_zones')
            .select('id')
            .eq('id', ownerZone.id);
        expect(
          otherVisibleRows,
          isEmpty,
          reason: 'RLS should hide owner rows from another authenticated user.',
        );

        final otherLoadedZones = await otherRepository.loadZones();
        expect(
          otherLoadedZones.map((zone) => zone.id),
          isNot(contains(ownerZone.id)),
        );

        await otherRepository.updateZone(
          PrivacyZone(
            id: ownerZone.id,
            userId: ownerZone.userId,
            label: 'Tampered Label',
            latitude: 41,
            longitude: -73.5,
            radiusMeters: 450,
          ),
        );

        final ownerRowAfterCrossUserUpdate = await ownerClient
            .from('privacy_zones')
            .select()
            .eq('id', ownerZone.id)
            .single();
        expect(ownerRowAfterCrossUserUpdate['label'], 'Owner Home');
        expect(
          (ownerRowAfterCrossUserUpdate['latitude'] as num).toDouble(),
          closeTo(40.7128, 0.000001),
        );
        expect(
          (ownerRowAfterCrossUserUpdate['longitude'] as num).toDouble(),
          closeTo(-74.0060, 0.000001),
        );
        expect(ownerRowAfterCrossUserUpdate['radius_meters'], 200);

        await otherRepository.deleteZone(ownerZone.id);

        final ownerRowsAfterCrossUserDelete = await ownerClient
            .from('privacy_zones')
            .select('id')
            .eq('id', ownerZone.id);
        expect(
          ownerRowsAfterCrossUserDelete,
          hasLength(1),
          reason: 'Cross-user delete must be blocked by RLS.',
        );
      },
    );
  });
}

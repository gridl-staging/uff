import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/gear/data/supabase_gear_repository.dart';
import 'package:uff/src/features/gear/domain/gear_item.dart';

import 'supabase_smoke_helpers.dart';

/// ## Test Scenarios
/// - `[positive]` Owner create and load return exact GearItem fields plus migration defaults.
/// - `[negative]` Spoofed create payloads cannot force gear rows onto another user id.
/// - `[negative]` Non-owner load and direct select cannot read owner gear row.
/// - `[negative]` Non-owner update and delete calls cannot mutate owner gear row.
/// - `[isolation]` Parallel user sessions only observe their own gear rows across cleanup-safe reruns.
void main() {
  group('Gear RLS smoke test', skip: skipReason, () {
    late SmokeTestUser owner;
    late SmokeTestUser otherUser;
    late SupabaseGearRepository ownerRepository;
    late SupabaseGearRepository otherUserRepository;

    setUp(() async {
      owner = await createSignedInTestUser(displayName: 'Gear Owner');
      otherUser = await createSignedInTestUser(displayName: 'Gear Other User');
      ownerRepository = SupabaseGearRepository(owner.client);
      otherUserRepository = SupabaseGearRepository(otherUser.client);
    });

    tearDown(() async {
      await cleanupSmokeTestUsers([owner, otherUser]);
    });

    test(
      'owner create and load return exact fields plus migration defaults',
      () async {
        final ownerCreated = await _createGear(
          ownerRepository,
          userId: owner.userId,
          name: 'Owner Daily Trainer',
          gearType: GearType.shoe,
          totalDistanceMeters: 12345,
          brand: 'Acme',
          model: 'Velocity',
        );

        expect(
          ownerCreated.id,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            ),
          ),
        );
        expect(ownerCreated.userId, owner.userId);
        expect(ownerCreated.name, 'Owner Daily Trainer');
        expect(ownerCreated.gearType, GearType.shoe);
        expect(ownerCreated.brand, 'Acme');
        expect(ownerCreated.model, 'Velocity');
        expect(ownerCreated.totalDistanceMeters, 0);
        expect(ownerCreated.retired, isFalse);

        final ownerLoaded = await ownerRepository.loadGear();
        expect(ownerLoaded, [ownerCreated]);
      },
    );

    test(
      'createGear ignores spoofed user ids and binds rows to the active session',
      () async {
        final spoofedCreate = await otherUserRepository.createGear(
          GearItem(
            id: 'ignored-on-insert',
            userId: owner.userId,
            name: 'Spoof Attempt',
            gearType: GearType.component,
            totalDistanceMeters: 999,
            retired: false,
            brand: 'Spoofed',
            model: 'Cross User',
          ),
        );

        expect(spoofedCreate.userId, otherUser.userId);
        expect(spoofedCreate.name, 'Spoof Attempt');

        final ownerVisibleRows = await ownerRepository.loadGear();
        expect(ownerVisibleRows, isEmpty);

        final otherVisibleRows = await otherUserRepository.loadGear();
        expect(otherVisibleRows, [spoofedCreate]);
      },
    );

    test(
      'non-owner load and direct select stay empty for owner rows',
      () async {
        final ownerCreated = await _createGear(
          ownerRepository,
          userId: owner.userId,
          name: 'Owner Daily Trainer',
          gearType: GearType.shoe,
          totalDistanceMeters: 12345,
          brand: 'Acme',
          model: 'Velocity',
        );

        final otherLoadedBeforeOwnCreate = await otherUserRepository.loadGear();
        expect(otherLoadedBeforeOwnCreate, isEmpty);

        final otherDirectOwnerRows = await otherUser.client
            .from('gear')
            .select('id,user_id,name,gear_type,retired')
            .eq('id', ownerCreated.id);
        expect(otherDirectOwnerRows, isEmpty);

        final otherCreated = await _createGear(
          otherUserRepository,
          userId: otherUser.userId,
          name: 'Other User Bike',
          gearType: GearType.bike,
          totalDistanceMeters: 333,
          brand: 'Townsend',
          model: 'Roadster',
        );
        expect(otherCreated.userId, otherUser.userId);
        expect(otherCreated.name, 'Other User Bike');
        expect(otherCreated.gearType, GearType.bike);
        expect(otherCreated.totalDistanceMeters, 0);
        expect(otherCreated.retired, isFalse);

        final ownerVisibleRowsAfterOtherCreate = await ownerRepository
            .loadGear();
        expect(ownerVisibleRowsAfterOtherCreate, [ownerCreated]);

        final otherVisibleRowsAfterOwnCreate = await otherUserRepository
            .loadGear();
        expect(otherVisibleRowsAfterOwnCreate, [otherCreated]);
      },
    );

    test(
      'non-owner update and delete calls cannot mutate owner rows',
      () async {
        final ownerCreated = await _createGear(
          ownerRepository,
          userId: owner.userId,
          name: 'Owner Daily Trainer',
          gearType: GearType.shoe,
          totalDistanceMeters: 12345,
          brand: 'Acme',
          model: 'Velocity',
        );
        final otherCreated = await _createGear(
          otherUserRepository,
          userId: otherUser.userId,
          name: 'Other User Bike',
          gearType: GearType.bike,
          totalDistanceMeters: 333,
          brand: 'Townsend',
          model: 'Roadster',
        );

        await expectLater(
          otherUserRepository.updateGear(
            GearItem(
              id: ownerCreated.id,
              userId: otherUser.userId,
              name: 'Tampered Cross User Name',
              gearType: GearType.component,
              totalDistanceMeters: 77,
              retired: true,
              brand: 'Evil',
              model: 'Mutation',
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains(
                'Gear update must affect exactly one row for id ${ownerCreated.id}',
              ),
            ),
          ),
        );

        final ownerRowsAfterCrossUserUpdate = await ownerRepository.loadGear();
        expect(ownerRowsAfterCrossUserUpdate, [ownerCreated]);
        final ownerDirectAfterCrossUserUpdate = await owner.client
            .from('gear')
            .select('id,name,gear_type,retired')
            .eq('id', ownerCreated.id)
            .single();
        expect(ownerDirectAfterCrossUserUpdate['name'], 'Owner Daily Trainer');
        expect(ownerDirectAfterCrossUserUpdate['gear_type'], 'shoe');
        expect(ownerDirectAfterCrossUserUpdate['retired'], false);

        await expectLater(
          otherUserRepository.deleteGear(ownerCreated.id),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains(
                'Gear delete must affect exactly one row for id ${ownerCreated.id}',
              ),
            ),
          ),
        );

        final ownerRowsAfterCrossUserDelete = await ownerRepository.loadGear();
        expect(ownerRowsAfterCrossUserDelete, [ownerCreated]);
        final otherRowsAfterCrossUserDelete = await otherUserRepository
            .loadGear();
        expect(otherRowsAfterCrossUserDelete, [otherCreated]);
        final ownerDirectAfterCrossUserDelete = await owner.client
            .from('gear')
            .select('id,user_id,name,gear_type,retired')
            .eq('id', ownerCreated.id);
        expect(ownerDirectAfterCrossUserDelete, [
          {
            'id': ownerCreated.id,
            'user_id': owner.userId,
            'name': 'Owner Daily Trainer',
            'gear_type': 'shoe',
            'retired': false,
          },
        ]);
      },
    );
  });
}

Future<GearItem> _createGear(
  SupabaseGearRepository repository, {
  required String userId,
  required String name,
  required GearType gearType,
  required double totalDistanceMeters,
  required String? brand,
  required String? model,
}) {
  return repository.createGear(
    GearItem(
      id: 'ignored-on-insert',
      userId: userId,
      name: name,
      gearType: gearType,
      totalDistanceMeters: totalDistanceMeters,
      retired: true,
      brand: brand,
      model: model,
    ),
  );
}

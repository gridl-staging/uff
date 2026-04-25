/// ## Test Scenarios
/// - [positive] GearItem display label includes name and type
/// - [positive] gearItemFromJson maps shoe, bike, component, integer distance correctly
/// - [positive] gearListProvider returns items from repository
/// - [edge] gearListProvider returns empty list when no gear exists
/// - [positive] gearListProvider invalidation triggers reload

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/gear/application/gear_providers.dart';
import 'package:uff/src/features/gear/data/gear_repository.dart';
import 'package:uff/src/features/gear/data/supabase_gear_repository.dart';
import 'package:uff/src/features/gear/domain/gear_item.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class FakeGearRepository implements GearRepository {
  List<GearItem> itemsToReturn = [];
  int loadGearCallCount = 0;
  int createGearCallCount = 0;
  int updateGearCallCount = 0;
  int deleteGearCallCount = 0;
  GearItem? lastCreatedItem;
  GearItem? lastUpdatedItem;
  String? lastDeletedId;

  @override
  Future<List<GearItem>> loadGear() async {
    loadGearCallCount++;
    return itemsToReturn;
  }

  @override
  Future<GearItem> createGear(GearItem item) async {
    createGearCallCount++;
    lastCreatedItem = item;
    return item;
  }

  @override
  Future<void> updateGear(GearItem item) async {
    updateGearCallCount++;
    lastUpdatedItem = item;
  }

  @override
  Future<void> deleteGear(String id) async {
    deleteGearCallCount++;
    lastDeletedId = id;
  }
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const _testShoe = GearItem(
  id: 'gear-1',
  userId: 'user-1',
  name: 'Pegasus 40',
  gearType: GearType.shoe,
  totalDistanceMeters: 523400,
  retired: false,
  brand: 'Nike',
  model: 'Pegasus 40',
);

const _testBike = GearItem(
  id: 'gear-2',
  userId: 'user-1',
  name: 'Canyon Aeroad',
  gearType: GearType.bike,
  totalDistanceMeters: 12050000,
  retired: false,
  brand: 'Canyon',
  model: 'Aeroad CF SLX',
);

ProviderContainer _createGearListContainer(FakeGearRepository repository) {
  final container = ProviderContainer(
    overrides: [
      gearRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);

  final subscription = container.listen(gearListProvider, (_, __) {});
  addTearDown(subscription.close);

  return container;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  test('GearItem exposes display label for its gear type', () {
    expect(_testShoe.gearTypeLabel, 'Shoe');
    expect(_testBike.gearTypeLabel, 'Bike');
  });

  group('gearItemFromJson', () {
    test('maps shoe with all fields', () {
      final json = <String, dynamic>{
        'id': 'gear-1',
        'user_id': 'user-1',
        'name': 'Pegasus 40',
        'gear_type': 'shoe',
        'total_distance_meters': 523.4,
        'retired': false,
        'brand': 'Nike',
        'model': 'Pegasus 40',
      };

      final item = gearItemFromJson(json);

      expect(item.id, 'gear-1');
      expect(item.userId, 'user-1');
      expect(item.name, 'Pegasus 40');
      expect(item.gearType, GearType.shoe);
      expect(item.totalDistanceMeters, 523.4);
      expect(item.retired, false);
      expect(item.brand, 'Nike');
      expect(item.model, 'Pegasus 40');
    });

    test('maps bike variant', () {
      final json = <String, dynamic>{
        'id': 'gear-2',
        'user_id': 'user-1',
        'name': 'My Bike',
        'gear_type': 'bike',
        'total_distance_meters': 0,
        'retired': false,
        'brand': null,
        'model': null,
      };

      final item = gearItemFromJson(json);

      expect(item.gearType, GearType.bike);
      expect(item.brand, isNull);
      expect(item.model, isNull);
    });

    test('maps component variant', () {
      final json = <String, dynamic>{
        'id': 'gear-3',
        'user_id': 'user-1',
        'name': 'Chain',
        'gear_type': 'component',
        'total_distance_meters': 1500.5,
        'retired': true,
        'brand': 'Shimano',
        'model': null,
      };

      final item = gearItemFromJson(json);

      expect(item.gearType, GearType.component);
      expect(item.retired, true);
      expect(item.brand, 'Shimano');
      expect(item.model, isNull);
    });

    test('handles integer total_distance_meters from Supabase', () {
      final json = <String, dynamic>{
        'id': 'gear-4',
        'user_id': 'user-1',
        'name': 'Shoe',
        'gear_type': 'shoe',
        'total_distance_meters': 100,
        'retired': false,
      };

      final item = gearItemFromJson(json);

      expect(item.totalDistanceMeters, 100.0);
    });
  });

  group('gearListProvider', () {
    test('returns items from repository', () async {
      final fakeRepo = FakeGearRepository()
        ..itemsToReturn = [_testShoe, _testBike];
      final container = _createGearListContainer(fakeRepo);

      final items = await container.read(gearListProvider.future);

      expect(items, hasLength(2));
      expect(items[0], _testShoe);
      expect(items[1], _testBike);
      expect(fakeRepo.loadGearCallCount, 1);
    });

    test('returns empty list when no gear exists', () async {
      final fakeRepo = FakeGearRepository();
      final container = _createGearListContainer(fakeRepo);

      final items = await container.read(gearListProvider.future);

      expect(items, isEmpty);
      expect(fakeRepo.loadGearCallCount, 1);
    });

    test('calls loadGear on each invalidation', () async {
      final fakeRepo = FakeGearRepository()..itemsToReturn = [_testShoe];
      final container = _createGearListContainer(fakeRepo);

      await container.read(gearListProvider.future);
      expect(fakeRepo.loadGearCallCount, 1);

      // Invalidate triggers a reload
      container.invalidate(gearListProvider);
      await container.read(gearListProvider.future);
      expect(fakeRepo.loadGearCallCount, 2);
    });
  });
}

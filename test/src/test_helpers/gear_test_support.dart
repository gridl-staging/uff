import 'dart:async';

import 'package:uff/src/features/gear/data/gear_repository.dart';
import 'package:uff/src/features/gear/domain/gear_item.dart';

/// NOTE(stuart): Document RecordingGearRepository.
class RecordingGearRepository implements GearRepository {
  RecordingGearRepository({
    this.itemsToReturn = const [],
    this.loadGearError,
    this.createGearError,
    this.updateGearError,
    this.deleteGearError,
  });

  List<GearItem> itemsToReturn;
  Object? loadGearError;
  Object? createGearError;
  Object? updateGearError;
  Object? deleteGearError;

  int loadGearCallCount = 0;
  int createGearCallCount = 0;
  int updateGearCallCount = 0;
  int deleteGearCallCount = 0;

  GearItem? lastCreatedItem;
  GearItem? lastUpdatedItem;
  String? lastDeletedId;

  Completer<GearItem>? createGearCompleter;
  Completer<void>? updateGearCompleter;

  @override
  Future<List<GearItem>> loadGear() async {
    loadGearCallCount += 1;

    if (loadGearError case final Object error) {
      // ignore: only_throw_errors, needed to exercise non-Error paths in tests
      throw error;
    }

    return itemsToReturn;
  }

  @override
  Future<GearItem> createGear(GearItem item) async {
    createGearCallCount += 1;
    lastCreatedItem = item;

    if (createGearError case final Object error) {
      // ignore: only_throw_errors, needed to exercise non-Error paths in tests
      throw error;
    }

    if (createGearCompleter case final Completer<GearItem> completer) {
      return completer.future;
    }

    return item;
  }

  @override
  Future<void> updateGear(GearItem item) async {
    updateGearCallCount += 1;
    lastUpdatedItem = item;

    if (updateGearError case final Object error) {
      // ignore: only_throw_errors, needed to exercise non-Error paths in tests
      throw error;
    }

    if (updateGearCompleter case final Completer<void> completer) {
      return completer.future;
    }
  }

  @override
  Future<void> deleteGear(String id) async {
    deleteGearCallCount += 1;
    lastDeletedId = id;

    if (deleteGearError case final Object error) {
      // ignore: only_throw_errors, needed to exercise non-Error paths in tests
      throw error;
    }
  }
}

const testShoeGear = GearItem(
  id: 'gear-shoe',
  userId: 'user-1',
  name: 'Daily Trainer',
  gearType: GearType.shoe,
  totalDistanceMeters: 120500,
  retired: false,
  brand: 'Nike',
  model: 'Pegasus',
  notes: 'Everyday training pair',
);

const testShoeGearNoBrand = GearItem(
  id: 'gear-shoe-no-brand',
  userId: 'user-1',
  name: 'Daily Trainer',
  gearType: GearType.shoe,
  totalDistanceMeters: 120500,
  retired: false,
  model: 'Pegasus',
);

const testShoeGearNoModel = GearItem(
  id: 'gear-shoe-no-model',
  userId: 'user-1',
  name: 'Daily Trainer',
  gearType: GearType.shoe,
  totalDistanceMeters: 120500,
  retired: false,
  brand: 'Nike',
);

const testShoeGearNoBrandOrModel = GearItem(
  id: 'gear-shoe-no-brand-or-model',
  userId: 'user-1',
  name: 'Daily Trainer',
  gearType: GearType.shoe,
  totalDistanceMeters: 120500,
  retired: false,
);

const testBikeGear = GearItem(
  id: 'gear-bike',
  userId: 'user-1',
  name: 'Road Bike',
  gearType: GearType.bike,
  totalDistanceMeters: 2500000,
  retired: false,
  brand: 'Canyon',
  model: 'Endurace',
);

const testRetiredComponentGear = GearItem(
  id: 'gear-component',
  userId: 'user-1',
  name: 'Old Chain',
  gearType: GearType.component,
  totalDistanceMeters: 810000,
  retired: true,
  brand: 'Shimano',
  model: 'HG701',
);

final testShoeGearWithLifecycleFields = GearItem(
  id: 'gear-shoe-with-lifecycle',
  userId: 'user-1',
  name: 'Daily Trainer',
  gearType: GearType.shoe,
  totalDistanceMeters: 120500,
  retired: false,
  startDate: DateTime(2024, 3, 5),
  brand: 'Nike',
  model: 'Pegasus',
  notes: 'Everyday training pair',
);

import 'package:uff/src/features/gear/domain/gear_item.dart';

abstract interface class GearRepository {
  Future<List<GearItem>> loadGear();

  Future<GearItem> createGear(GearItem item);

  Future<void> updateGear(GearItem item);

  Future<void> deleteGear(String id);
}

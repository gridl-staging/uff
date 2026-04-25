import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/gear/domain/gear_item.dart';

/// ## Test Scenarios
/// - [isolation] Same calendar start date compares equal across timezone types
/// - [negative] Different calendar start dates compare unequal
void main() {
  test('GearItem equality and hashCode treat startDate as date-only', () {
    final utcDateItem = _buildGearItem(startDate: DateTime.utc(2024, 3, 5));
    final localDateItem = _buildGearItem(startDate: DateTime(2024, 3, 5));

    expect(utcDateItem, localDateItem);
    expect(utcDateItem.hashCode, localDateItem.hashCode);
  });

  test('GearItem inequality still distinguishes different calendar days', () {
    final firstDayItem = _buildGearItem(startDate: DateTime.utc(2024, 3, 5));
    final secondDayItem = _buildGearItem(startDate: DateTime.utc(2024, 3, 6));

    expect(firstDayItem == secondDayItem, isFalse);
  });
}

GearItem _buildGearItem({DateTime? startDate}) {
  return GearItem(
    id: 'gear-id',
    userId: 'user-id',
    name: 'Daily Trainer',
    gearType: GearType.shoe,
    totalDistanceMeters: 1234,
    retired: false,
    startDate: startDate,
    brand: 'Brand',
    model: 'Model',
    notes: 'Notes',
  );
}

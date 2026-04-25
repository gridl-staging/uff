import 'package:meta/meta.dart';

/// NOTE(stuart): Document GearType.
enum GearType {
  shoe,
  bike,
  component;

  String get label {
    switch (this) {
      case GearType.shoe:
        return 'Shoe';
      case GearType.bike:
        return 'Bike';
      case GearType.component:
        return 'Component';
    }
  }
}

/// NOTE(stuart): Document GearItem.
@immutable
class GearItem {
  const GearItem({
    required this.id,
    required this.userId,
    required this.name,
    required this.gearType,
    required this.totalDistanceMeters,
    required this.retired,
    this.startDate,
    this.brand,
    this.model,
    this.notes,
  });

  final String id;
  final String userId;
  final String name;
  final GearType gearType;
  final double totalDistanceMeters;
  final bool retired;
  final DateTime? startDate;
  final String? brand;
  final String? model;
  final String? notes;

  String get gearTypeLabel => gearType.label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GearItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          userId == other.userId &&
          name == other.name &&
          gearType == other.gearType &&
          totalDistanceMeters == other.totalDistanceMeters &&
          retired == other.retired &&
          _sameCalendarDate(startDate, other.startDate) &&
          brand == other.brand &&
          model == other.model &&
          notes == other.notes;

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    name,
    gearType,
    totalDistanceMeters,
    retired,
    _calendarDateHashKey(startDate),
    brand,
    model,
    notes,
  );
}

bool _sameCalendarDate(DateTime? first, DateTime? second) {
  if (first == null || second == null) {
    return first == second;
  }
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

({int year, int month, int day})? _calendarDateHashKey(DateTime? value) {
  if (value == null) {
    return null;
  }
  return (year: value.year, month: value.month, day: value.day);
}

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uff/src/features/gear/data/gear_repository.dart';
import 'package:uff/src/features/gear/data/supabase_gear_repository.dart';
import 'package:uff/src/features/gear/domain/gear_item.dart';

part 'gear_providers.g.dart';

@riverpod
GearRepository gearRepository(Ref ref) {
  return SupabaseGearRepository(Supabase.instance.client);
}

@riverpod
Future<List<GearItem>> gearList(Ref ref) async {
  return ref.read(gearRepositoryProvider).loadGear();
}

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_repository.dart';
import 'package:uff/src/features/profile/data/supabase_profile_repository.dart';

part 'profile_provider.g.dart';

@riverpod
ProfileRepository profileRepository(Ref ref) {
  return SupabaseProfileRepository(Supabase.instance.client);
}

/// NOTE(stuart): Document ProfileNotifier.
@riverpod
class ProfileNotifier extends _$ProfileNotifier {
  @override
  FutureOr<Profile?> build() async {
    final authState = ref.watch(authProvider).asData?.value;
    if (authState == null) return null;

    return switch (authState) {
      Authenticated(:final userId) =>
        ref.read(profileRepositoryProvider).getProfile(userId),
      Unauthenticated() => null,
    };
  }

  Future<void> updateProfile(Profile profile) async {
    final previousState = state;
    state = const AsyncLoading<Profile?>();
    try {
      final updatedProfile = await ref
          .read(profileRepositoryProvider)
          .updateProfile(profile);
      state = AsyncValue.data(updatedProfile);
    } on Exception {
      state = previousState;
      rethrow;
    }
  }
}

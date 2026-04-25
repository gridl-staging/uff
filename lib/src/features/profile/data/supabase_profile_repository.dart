import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_repository.dart';
import 'package:uff/src/utils/storage_file_name_sanitizer.dart';
// 2026-03-18 merge: keep mwip shared sanitizer utility with onboarding auth checks.

// TODO(uff): Document SupabaseProfileRepository.
/// TODO: Document SupabaseProfileRepository.
class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Profile> getProfile(String userId) async {
    _requireCurrentUserId(expectedUserId: userId);
    final data = await _client
        .rpc<List<Map<String, dynamic>>>('get_my_profile')
        .single();
    return Profile.fromJson(data);
  }

  @override
  Future<Profile> updateProfile(Profile profile) async {
    final currentUserId = _requireCurrentUserId(expectedUserId: profile.userId);
    await _client
        .from('profiles')
        .update({
          'display_name': profile.displayName,
          'preferred_units': profile.preferredUnits,
          'default_activity_visibility': profile.defaultActivityVisibility,
          'onboarding_completed': profile.onboardingCompleted,
          'sport_preferences': profile.sportPreferences,
          'lthr_bpm': profile.lthrBpm,
        })
        .eq('id', currentUserId);
    return getProfile(currentUserId);
  }

  @override
  Future<void> updateFcmToken(String? token) async {
    final currentUserId = _requireAuthenticatedUserId();
    await _client
        .from('profiles')
        .update({'fcm_token': token})
        .eq(
          'id',
          currentUserId,
        );
  }

  @override
  Future<void> clearFcmToken() async {
    // Called during sign-out. The Supabase session may already be invalidated
    // by the time this runs (the auth stream fires unauthenticated before the
    // cleanup hook executes). If there's no current user, there's nothing to
    // clear — just return silently rather than throwing.
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) {
      return;
    }
    await _client
        .from('profiles')
        .update({'fcm_token': null})
        .eq('id', currentUserId);
  }

  @override
  Future<String> uploadAvatar(
    String userId,
    Uint8List bytes,
    String fileName,
  ) async {
    final currentUserId = _requireCurrentUserId(expectedUserId: userId);
    final sanitizedFileName = sanitizeStorageFileName(
      fileName,
      fallbackName: 'avatar',
    );
    final path = '$currentUserId/$sanitizedFileName';
    await _client.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final publicUrl = _client.storage.from('avatars').getPublicUrl(path);

    await _client
        .from('profiles')
        .update({'avatar_url': publicUrl})
        .eq('id', currentUserId);

    return publicUrl;
  }

  @override
  Future<Map<String, dynamic>> exportMyData() async {
    final result = await _client.rpc<Map<String, dynamic>>('export_my_data');
    return result;
  }

  @override
  Future<void> deleteMyAccount() async {
    await _client.functions.invoke('delete-my-account');
  }

  String _requireCurrentUserId({required String expectedUserId}) {
    final currentUserId = _requireAuthenticatedUserId();
    if (currentUserId != expectedUserId) {
      throw StateError(
        'Profile operations may only target the authenticated user.',
      );
    }
    return currentUserId;
  }

  String _requireAuthenticatedUserId() {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) {
      throw StateError(
        'Profile operations require an authenticated user session.',
      );
    }
    return currentUserId;
  }
}

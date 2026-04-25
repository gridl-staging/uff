import 'dart:typed_data';

import 'package:uff/src/features/profile/data/profile.dart';

/// TODO: Document ProfileRepository.
abstract interface class ProfileRepository {
  Future<Profile> getProfile(String userId);

  Future<Profile> updateProfile(Profile profile);

  Future<void> updateFcmToken(String? token);

  /// Clears the FCM push notification token from the user's backend profile.
  ///
  /// Called during sign-out to prevent push notifications intended for user A
  /// from routing to user B's device if they sign in on the same device.
  /// Must handle the case where the session is already gone gracefully (no-op).
  Future<void> clearFcmToken();

  Future<String> uploadAvatar(
    String userId,
    Uint8List bytes,
    String fileName,
  );

  Future<Map<String, dynamic>> exportMyData();

  Future<void> deleteMyAccount();
}

// ignore_for_file: invalid_annotation_target, Freezed places @JsonKey on constructor params

import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

/// NOTE(stuart): Document Profile.
@freezed
sealed class Profile with _$Profile {
  const factory Profile({
    @JsonKey(name: 'id') required String userId,
    @JsonKey(name: 'preferred_units') required String preferredUnits,
    @JsonKey(name: 'default_activity_visibility')
    required String defaultActivityVisibility,
    @JsonKey(name: 'onboarding_completed') required bool onboardingCompleted,
    @JsonKey(name: 'sport_preferences')
    @Default(<String>[])
    List<String> sportPreferences,
    @JsonKey(name: 'display_name') String? displayName,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    @JsonKey(name: 'lthr_bpm') int? lthrBpm,
  }) = _Profile;

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Profile _$ProfileFromJson(Map<String, dynamic> json) => _Profile(
  userId: json['id'] as String,
  preferredUnits: json['preferred_units'] as String,
  defaultActivityVisibility: json['default_activity_visibility'] as String,
  onboardingCompleted: json['onboarding_completed'] as bool,
  sportPreferences:
      (json['sport_preferences'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  displayName: json['display_name'] as String?,
  avatarUrl: json['avatar_url'] as String?,
  lthrBpm: (json['lthr_bpm'] as num?)?.toInt(),
);

Map<String, dynamic> _$ProfileToJson(_Profile instance) => <String, dynamic>{
  'id': instance.userId,
  'preferred_units': instance.preferredUnits,
  'default_activity_visibility': instance.defaultActivityVisibility,
  'onboarding_completed': instance.onboardingCompleted,
  'sport_preferences': instance.sportPreferences,
  'display_name': instance.displayName,
  'avatar_url': instance.avatarUrl,
  'lthr_bpm': instance.lthrBpm,
};

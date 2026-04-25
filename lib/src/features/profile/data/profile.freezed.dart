// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'profile.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Profile {

@JsonKey(name: 'id') String get userId;@JsonKey(name: 'preferred_units') String get preferredUnits;@JsonKey(name: 'default_activity_visibility') String get defaultActivityVisibility;@JsonKey(name: 'onboarding_completed') bool get onboardingCompleted;@JsonKey(name: 'sport_preferences') List<String> get sportPreferences;@JsonKey(name: 'display_name') String? get displayName;@JsonKey(name: 'avatar_url') String? get avatarUrl;@JsonKey(name: 'lthr_bpm') int? get lthrBpm;
/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfileCopyWith<Profile> get copyWith => _$ProfileCopyWithImpl<Profile>(this as Profile, _$identity);

  /// Serializes this Profile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Profile&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.preferredUnits, preferredUnits) || other.preferredUnits == preferredUnits)&&(identical(other.defaultActivityVisibility, defaultActivityVisibility) || other.defaultActivityVisibility == defaultActivityVisibility)&&(identical(other.onboardingCompleted, onboardingCompleted) || other.onboardingCompleted == onboardingCompleted)&&const DeepCollectionEquality().equals(other.sportPreferences, sportPreferences)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl)&&(identical(other.lthrBpm, lthrBpm) || other.lthrBpm == lthrBpm));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,userId,preferredUnits,defaultActivityVisibility,onboardingCompleted,const DeepCollectionEquality().hash(sportPreferences),displayName,avatarUrl,lthrBpm);

@override
String toString() {
  return 'Profile(userId: $userId, preferredUnits: $preferredUnits, defaultActivityVisibility: $defaultActivityVisibility, onboardingCompleted: $onboardingCompleted, sportPreferences: $sportPreferences, displayName: $displayName, avatarUrl: $avatarUrl, lthrBpm: $lthrBpm)';
}


}

/// @nodoc
abstract mixin class $ProfileCopyWith<$Res>  {
  factory $ProfileCopyWith(Profile value, $Res Function(Profile) _then) = _$ProfileCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'id') String userId,@JsonKey(name: 'preferred_units') String preferredUnits,@JsonKey(name: 'default_activity_visibility') String defaultActivityVisibility,@JsonKey(name: 'onboarding_completed') bool onboardingCompleted,@JsonKey(name: 'sport_preferences') List<String> sportPreferences,@JsonKey(name: 'display_name') String? displayName,@JsonKey(name: 'avatar_url') String? avatarUrl,@JsonKey(name: 'lthr_bpm') int? lthrBpm
});




}
/// @nodoc
class _$ProfileCopyWithImpl<$Res>
    implements $ProfileCopyWith<$Res> {
  _$ProfileCopyWithImpl(this._self, this._then);

  final Profile _self;
  final $Res Function(Profile) _then;

/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? userId = null,Object? preferredUnits = null,Object? defaultActivityVisibility = null,Object? onboardingCompleted = null,Object? sportPreferences = null,Object? displayName = freezed,Object? avatarUrl = freezed,Object? lthrBpm = freezed,}) {
  return _then(_self.copyWith(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,preferredUnits: null == preferredUnits ? _self.preferredUnits : preferredUnits // ignore: cast_nullable_to_non_nullable
as String,defaultActivityVisibility: null == defaultActivityVisibility ? _self.defaultActivityVisibility : defaultActivityVisibility // ignore: cast_nullable_to_non_nullable
as String,onboardingCompleted: null == onboardingCompleted ? _self.onboardingCompleted : onboardingCompleted // ignore: cast_nullable_to_non_nullable
as bool,sportPreferences: null == sportPreferences ? _self.sportPreferences : sportPreferences // ignore: cast_nullable_to_non_nullable
as List<String>,displayName: freezed == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,lthrBpm: freezed == lthrBpm ? _self.lthrBpm : lthrBpm // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [Profile].
extension ProfilePatterns on Profile {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Profile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Profile() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Profile value)  $default,){
final _that = this;
switch (_that) {
case _Profile():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Profile value)?  $default,){
final _that = this;
switch (_that) {
case _Profile() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'id')  String userId, @JsonKey(name: 'preferred_units')  String preferredUnits, @JsonKey(name: 'default_activity_visibility')  String defaultActivityVisibility, @JsonKey(name: 'onboarding_completed')  bool onboardingCompleted, @JsonKey(name: 'sport_preferences')  List<String> sportPreferences, @JsonKey(name: 'display_name')  String? displayName, @JsonKey(name: 'avatar_url')  String? avatarUrl, @JsonKey(name: 'lthr_bpm')  int? lthrBpm)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Profile() when $default != null:
return $default(_that.userId,_that.preferredUnits,_that.defaultActivityVisibility,_that.onboardingCompleted,_that.sportPreferences,_that.displayName,_that.avatarUrl,_that.lthrBpm);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'id')  String userId, @JsonKey(name: 'preferred_units')  String preferredUnits, @JsonKey(name: 'default_activity_visibility')  String defaultActivityVisibility, @JsonKey(name: 'onboarding_completed')  bool onboardingCompleted, @JsonKey(name: 'sport_preferences')  List<String> sportPreferences, @JsonKey(name: 'display_name')  String? displayName, @JsonKey(name: 'avatar_url')  String? avatarUrl, @JsonKey(name: 'lthr_bpm')  int? lthrBpm)  $default,) {final _that = this;
switch (_that) {
case _Profile():
return $default(_that.userId,_that.preferredUnits,_that.defaultActivityVisibility,_that.onboardingCompleted,_that.sportPreferences,_that.displayName,_that.avatarUrl,_that.lthrBpm);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'id')  String userId, @JsonKey(name: 'preferred_units')  String preferredUnits, @JsonKey(name: 'default_activity_visibility')  String defaultActivityVisibility, @JsonKey(name: 'onboarding_completed')  bool onboardingCompleted, @JsonKey(name: 'sport_preferences')  List<String> sportPreferences, @JsonKey(name: 'display_name')  String? displayName, @JsonKey(name: 'avatar_url')  String? avatarUrl, @JsonKey(name: 'lthr_bpm')  int? lthrBpm)?  $default,) {final _that = this;
switch (_that) {
case _Profile() when $default != null:
return $default(_that.userId,_that.preferredUnits,_that.defaultActivityVisibility,_that.onboardingCompleted,_that.sportPreferences,_that.displayName,_that.avatarUrl,_that.lthrBpm);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Profile implements Profile {
  const _Profile({@JsonKey(name: 'id') required this.userId, @JsonKey(name: 'preferred_units') required this.preferredUnits, @JsonKey(name: 'default_activity_visibility') required this.defaultActivityVisibility, @JsonKey(name: 'onboarding_completed') required this.onboardingCompleted, @JsonKey(name: 'sport_preferences') final  List<String> sportPreferences = const <String>[], @JsonKey(name: 'display_name') this.displayName, @JsonKey(name: 'avatar_url') this.avatarUrl, @JsonKey(name: 'lthr_bpm') this.lthrBpm}): _sportPreferences = sportPreferences;
  factory _Profile.fromJson(Map<String, dynamic> json) => _$ProfileFromJson(json);

@override@JsonKey(name: 'id') final  String userId;
@override@JsonKey(name: 'preferred_units') final  String preferredUnits;
@override@JsonKey(name: 'default_activity_visibility') final  String defaultActivityVisibility;
@override@JsonKey(name: 'onboarding_completed') final  bool onboardingCompleted;
 final  List<String> _sportPreferences;
@override@JsonKey(name: 'sport_preferences') List<String> get sportPreferences {
  if (_sportPreferences is EqualUnmodifiableListView) return _sportPreferences;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_sportPreferences);
}

@override@JsonKey(name: 'display_name') final  String? displayName;
@override@JsonKey(name: 'avatar_url') final  String? avatarUrl;
@override@JsonKey(name: 'lthr_bpm') final  int? lthrBpm;

/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProfileCopyWith<_Profile> get copyWith => __$ProfileCopyWithImpl<_Profile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProfileToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Profile&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.preferredUnits, preferredUnits) || other.preferredUnits == preferredUnits)&&(identical(other.defaultActivityVisibility, defaultActivityVisibility) || other.defaultActivityVisibility == defaultActivityVisibility)&&(identical(other.onboardingCompleted, onboardingCompleted) || other.onboardingCompleted == onboardingCompleted)&&const DeepCollectionEquality().equals(other._sportPreferences, _sportPreferences)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl)&&(identical(other.lthrBpm, lthrBpm) || other.lthrBpm == lthrBpm));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,userId,preferredUnits,defaultActivityVisibility,onboardingCompleted,const DeepCollectionEquality().hash(_sportPreferences),displayName,avatarUrl,lthrBpm);

@override
String toString() {
  return 'Profile(userId: $userId, preferredUnits: $preferredUnits, defaultActivityVisibility: $defaultActivityVisibility, onboardingCompleted: $onboardingCompleted, sportPreferences: $sportPreferences, displayName: $displayName, avatarUrl: $avatarUrl, lthrBpm: $lthrBpm)';
}


}

/// @nodoc
abstract mixin class _$ProfileCopyWith<$Res> implements $ProfileCopyWith<$Res> {
  factory _$ProfileCopyWith(_Profile value, $Res Function(_Profile) _then) = __$ProfileCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'id') String userId,@JsonKey(name: 'preferred_units') String preferredUnits,@JsonKey(name: 'default_activity_visibility') String defaultActivityVisibility,@JsonKey(name: 'onboarding_completed') bool onboardingCompleted,@JsonKey(name: 'sport_preferences') List<String> sportPreferences,@JsonKey(name: 'display_name') String? displayName,@JsonKey(name: 'avatar_url') String? avatarUrl,@JsonKey(name: 'lthr_bpm') int? lthrBpm
});




}
/// @nodoc
class __$ProfileCopyWithImpl<$Res>
    implements _$ProfileCopyWith<$Res> {
  __$ProfileCopyWithImpl(this._self, this._then);

  final _Profile _self;
  final $Res Function(_Profile) _then;

/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? preferredUnits = null,Object? defaultActivityVisibility = null,Object? onboardingCompleted = null,Object? sportPreferences = null,Object? displayName = freezed,Object? avatarUrl = freezed,Object? lthrBpm = freezed,}) {
  return _then(_Profile(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,preferredUnits: null == preferredUnits ? _self.preferredUnits : preferredUnits // ignore: cast_nullable_to_non_nullable
as String,defaultActivityVisibility: null == defaultActivityVisibility ? _self.defaultActivityVisibility : defaultActivityVisibility // ignore: cast_nullable_to_non_nullable
as String,onboardingCompleted: null == onboardingCompleted ? _self.onboardingCompleted : onboardingCompleted // ignore: cast_nullable_to_non_nullable
as bool,sportPreferences: null == sportPreferences ? _self._sportPreferences : sportPreferences // ignore: cast_nullable_to_non_nullable
as List<String>,displayName: freezed == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,lthrBpm: freezed == lthrBpm ? _self.lthrBpm : lthrBpm // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on

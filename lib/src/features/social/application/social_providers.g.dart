// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'social_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(followRepository)
const followRepositoryProvider = FollowRepositoryProvider._();

final class FollowRepositoryProvider
    extends
        $FunctionalProvider<
          FollowRepository,
          FollowRepository,
          FollowRepository
        >
    with $Provider<FollowRepository> {
  const FollowRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'followRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$followRepositoryHash();

  @$internal
  @override
  $ProviderElement<FollowRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  FollowRepository create(Ref ref) {
    return followRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FollowRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FollowRepository>(value),
    );
  }
}

String _$followRepositoryHash() => r'bd5c7d17e8e50074f7a5f86bb05f03a2201a2ba0';

@ProviderFor(userSearchRepository)
const userSearchRepositoryProvider = UserSearchRepositoryProvider._();

final class UserSearchRepositoryProvider
    extends
        $FunctionalProvider<
          UserSearchRepository,
          UserSearchRepository,
          UserSearchRepository
        >
    with $Provider<UserSearchRepository> {
  const UserSearchRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'userSearchRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$userSearchRepositoryHash();

  @$internal
  @override
  $ProviderElement<UserSearchRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  UserSearchRepository create(Ref ref) {
    return userSearchRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UserSearchRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UserSearchRepository>(value),
    );
  }
}

String _$userSearchRepositoryHash() =>
    r'0239cdb2ee3086d62f90c1cf8af0f643dfcc9d12';

@ProviderFor(followers)
const followersProvider = FollowersProvider._();

final class FollowersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SocialUserSummary>>,
          List<SocialUserSummary>,
          FutureOr<List<SocialUserSummary>>
        >
    with
        $FutureModifier<List<SocialUserSummary>>,
        $FutureProvider<List<SocialUserSummary>> {
  const FollowersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'followersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$followersHash();

  @$internal
  @override
  $FutureProviderElement<List<SocialUserSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<SocialUserSummary>> create(Ref ref) {
    return followers(ref);
  }
}

String _$followersHash() => r'f0a892b57b1441b52cdc1c16ccb897d2200f9f0a';

@ProviderFor(following)
const followingProvider = FollowingProvider._();

final class FollowingProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SocialUserSummary>>,
          List<SocialUserSummary>,
          FutureOr<List<SocialUserSummary>>
        >
    with
        $FutureModifier<List<SocialUserSummary>>,
        $FutureProvider<List<SocialUserSummary>> {
  const FollowingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'followingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$followingHash();

  @$internal
  @override
  $FutureProviderElement<List<SocialUserSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<SocialUserSummary>> create(Ref ref) {
    return following(ref);
  }
}

String _$followingHash() => r'296d31fe063fc2059b573c78bf4017f76b20e78f';

@ProviderFor(pendingRequests)
const pendingRequestsProvider = PendingRequestsProvider._();

final class PendingRequestsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SocialUserSummary>>,
          List<SocialUserSummary>,
          FutureOr<List<SocialUserSummary>>
        >
    with
        $FutureModifier<List<SocialUserSummary>>,
        $FutureProvider<List<SocialUserSummary>> {
  const PendingRequestsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pendingRequestsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pendingRequestsHash();

  @$internal
  @override
  $FutureProviderElement<List<SocialUserSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<SocialUserSummary>> create(Ref ref) {
    return pendingRequests(ref);
  }
}

String _$pendingRequestsHash() => r'642d831402cf4d8186d3a88bb844463e9e60c251';

@ProviderFor(relationshipCounts)
const relationshipCountsProvider = RelationshipCountsProvider._();

final class RelationshipCountsProvider
    extends
        $FunctionalProvider<
          AsyncValue<RelationshipCounts>,
          RelationshipCounts,
          FutureOr<RelationshipCounts>
        >
    with
        $FutureModifier<RelationshipCounts>,
        $FutureProvider<RelationshipCounts> {
  const RelationshipCountsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'relationshipCountsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$relationshipCountsHash();

  @$internal
  @override
  $FutureProviderElement<RelationshipCounts> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RelationshipCounts> create(Ref ref) {
    return relationshipCounts(ref);
  }
}

String _$relationshipCountsHash() =>
    r'86b4d3e3b738d2c3d995af1d20e7e3a4876f3534';

@ProviderFor(userSearch)
const userSearchProvider = UserSearchFamily._();

final class UserSearchProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SocialUserSummary>>,
          List<SocialUserSummary>,
          FutureOr<List<SocialUserSummary>>
        >
    with
        $FutureModifier<List<SocialUserSummary>>,
        $FutureProvider<List<SocialUserSummary>> {
  const UserSearchProvider._({
    required UserSearchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'userSearchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$userSearchHash();

  @override
  String toString() {
    return r'userSearchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<SocialUserSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<SocialUserSummary>> create(Ref ref) {
    final argument = this.argument as String;
    return userSearch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is UserSearchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$userSearchHash() => r'2e07ce0b49da04836a53574ac4d99dd7a5c0def3';

final class UserSearchFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<SocialUserSummary>>, String> {
  const UserSearchFamily._()
    : super(
        retry: null,
        name: r'userSearchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UserSearchProvider call(String query) =>
      UserSearchProvider._(argument: query, from: this);

  @override
  String toString() => r'userSearchProvider';
}

@ProviderFor(viewedUserProfileHeader)
const viewedUserProfileHeaderProvider = ViewedUserProfileHeaderFamily._();

final class ViewedUserProfileHeaderProvider
    extends
        $FunctionalProvider<
          AsyncValue<ViewedUserProfileHeader?>,
          ViewedUserProfileHeader?,
          FutureOr<ViewedUserProfileHeader?>
        >
    with
        $FutureModifier<ViewedUserProfileHeader?>,
        $FutureProvider<ViewedUserProfileHeader?> {
  const ViewedUserProfileHeaderProvider._({
    required ViewedUserProfileHeaderFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'viewedUserProfileHeaderProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$viewedUserProfileHeaderHash();

  @override
  String toString() {
    return r'viewedUserProfileHeaderProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ViewedUserProfileHeader?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ViewedUserProfileHeader?> create(Ref ref) {
    final argument = this.argument as String;
    return viewedUserProfileHeader(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ViewedUserProfileHeaderProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$viewedUserProfileHeaderHash() =>
    r'01e14030c058de92d1dc318873cd3e21a33a3b69';

final class ViewedUserProfileHeaderFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ViewedUserProfileHeader?>, String> {
  const ViewedUserProfileHeaderFamily._()
    : super(
        retry: null,
        name: r'viewedUserProfileHeaderProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ViewedUserProfileHeaderProvider call(String userId) =>
      ViewedUserProfileHeaderProvider._(argument: userId, from: this);

  @override
  String toString() => r'viewedUserProfileHeaderProvider';
}

/// Handles follow mutations and refreshes dependent relationship caches.

@ProviderFor(FollowActionController)
const followActionControllerProvider = FollowActionControllerProvider._();

/// Handles follow mutations and refreshes dependent relationship caches.
final class FollowActionControllerProvider
    extends $AsyncNotifierProvider<FollowActionController, void> {
  /// Handles follow mutations and refreshes dependent relationship caches.
  const FollowActionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'followActionControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$followActionControllerHash();

  @$internal
  @override
  FollowActionController create() => FollowActionController();
}

String _$followActionControllerHash() =>
    r'e53c57b34b076d41780bddd128d5d7bfa58fad8d';

/// Handles follow mutations and refreshes dependent relationship caches.

abstract class _$FollowActionController extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    build();
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleValue(ref, null);
  }
}

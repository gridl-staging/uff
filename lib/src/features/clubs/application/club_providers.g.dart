// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'club_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(clubRepository)
const clubRepositoryProvider = ClubRepositoryProvider._();

final class ClubRepositoryProvider
    extends $FunctionalProvider<ClubRepository, ClubRepository, ClubRepository>
    with $Provider<ClubRepository> {
  const ClubRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clubRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clubRepositoryHash();

  @$internal
  @override
  $ProviderElement<ClubRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ClubRepository create(Ref ref) {
    return clubRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClubRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClubRepository>(value),
    );
  }
}

String _$clubRepositoryHash() => r'5be204dea8a182388f3d54629af2610245690872';

@ProviderFor(myClubs)
const myClubsProvider = MyClubsProvider._();

final class MyClubsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Club>>,
          List<Club>,
          FutureOr<List<Club>>
        >
    with $FutureModifier<List<Club>>, $FutureProvider<List<Club>> {
  const MyClubsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myClubsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myClubsHash();

  @$internal
  @override
  $FutureProviderElement<List<Club>> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Club>> create(Ref ref) {
    return myClubs(ref);
  }
}

String _$myClubsHash() => r'9f5bc3b88e3b270f0fff23300e7bdb82cab95b9f';

@ProviderFor(clubDetail)
const clubDetailProvider = ClubDetailFamily._();

final class ClubDetailProvider
    extends $FunctionalProvider<AsyncValue<Club?>, Club?, FutureOr<Club?>>
    with $FutureModifier<Club?>, $FutureProvider<Club?> {
  const ClubDetailProvider._({
    required ClubDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'clubDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$clubDetailHash();

  @override
  String toString() {
    return r'clubDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Club?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Club?> create(Ref ref) {
    final argument = this.argument as String;
    return clubDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ClubDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$clubDetailHash() => r'cea8f9e8b08ceb90bd87f31bd030c234869c1455';

final class ClubDetailFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Club?>, String> {
  const ClubDetailFamily._()
    : super(
        retry: null,
        name: r'clubDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ClubDetailProvider call(String clubId) =>
      ClubDetailProvider._(argument: clubId, from: this);

  @override
  String toString() => r'clubDetailProvider';
}

@ProviderFor(clubMembers)
const clubMembersProvider = ClubMembersFamily._();

final class ClubMembersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ClubMember>>,
          List<ClubMember>,
          FutureOr<List<ClubMember>>
        >
    with $FutureModifier<List<ClubMember>>, $FutureProvider<List<ClubMember>> {
  const ClubMembersProvider._({
    required ClubMembersFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'clubMembersProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$clubMembersHash();

  @override
  String toString() {
    return r'clubMembersProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<ClubMember>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ClubMember>> create(Ref ref) {
    final argument = this.argument as String;
    return clubMembers(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ClubMembersProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$clubMembersHash() => r'3d37de8103203f2c136e67c69de27a2439751885';

final class ClubMembersFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<ClubMember>>, String> {
  const ClubMembersFamily._()
    : super(
        retry: null,
        name: r'clubMembersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ClubMembersProvider call(String clubId) =>
      ClubMembersProvider._(argument: clubId, from: this);

  @override
  String toString() => r'clubMembersProvider';
}

@ProviderFor(clubSearch)
const clubSearchProvider = ClubSearchFamily._();

final class ClubSearchProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Club>>,
          List<Club>,
          FutureOr<List<Club>>
        >
    with $FutureModifier<List<Club>>, $FutureProvider<List<Club>> {
  const ClubSearchProvider._({
    required ClubSearchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'clubSearchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$clubSearchHash();

  @override
  String toString() {
    return r'clubSearchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<Club>> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Club>> create(Ref ref) {
    final argument = this.argument as String;
    return clubSearch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ClubSearchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$clubSearchHash() => r'6fdc11ebae5eff6c038d2d3e5d4635c56f0f8de0';

final class ClubSearchFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<Club>>, String> {
  const ClubSearchFamily._()
    : super(
        retry: null,
        name: r'clubSearchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ClubSearchProvider call(String query) =>
      ClubSearchProvider._(argument: query, from: this);

  @override
  String toString() => r'clubSearchProvider';
}

@ProviderFor(nearbyClubs)
const nearbyClubsProvider = NearbyClubsProvider._();

final class NearbyClubsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Club>>,
          List<Club>,
          FutureOr<List<Club>>
        >
    with $FutureModifier<List<Club>>, $FutureProvider<List<Club>> {
  const NearbyClubsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'nearbyClubsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nearbyClubsHash();

  @$internal
  @override
  $FutureProviderElement<List<Club>> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Club>> create(Ref ref) {
    return nearbyClubs(ref);
  }
}

String _$nearbyClubsHash() => r'373110f9c747026003349429c30423c55c6e463c';

@ProviderFor(upcomingClubRuns)
const upcomingClubRunsProvider = UpcomingClubRunsFamily._();

final class UpcomingClubRunsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ClubRun>>,
          List<ClubRun>,
          FutureOr<List<ClubRun>>
        >
    with $FutureModifier<List<ClubRun>>, $FutureProvider<List<ClubRun>> {
  const UpcomingClubRunsProvider._({
    required UpcomingClubRunsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'upcomingClubRunsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$upcomingClubRunsHash();

  @override
  String toString() {
    return r'upcomingClubRunsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<ClubRun>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ClubRun>> create(Ref ref) {
    final argument = this.argument as String;
    return upcomingClubRuns(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is UpcomingClubRunsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$upcomingClubRunsHash() => r'bb8d6e901d960a1a56ca0aa3cb2294db4eba3520';

final class UpcomingClubRunsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<ClubRun>>, String> {
  const UpcomingClubRunsFamily._()
    : super(
        retry: null,
        name: r'upcomingClubRunsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UpcomingClubRunsProvider call(String clubId) =>
      UpcomingClubRunsProvider._(argument: clubId, from: this);

  @override
  String toString() => r'upcomingClubRunsProvider';
}

/// TODO: Document ClubMutationController.

@ProviderFor(ClubMutationController)
const clubMutationControllerProvider = ClubMutationControllerProvider._();

/// TODO: Document ClubMutationController.
final class ClubMutationControllerProvider
    extends $AsyncNotifierProvider<ClubMutationController, void> {
  /// TODO: Document ClubMutationController.
  const ClubMutationControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clubMutationControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clubMutationControllerHash();

  @$internal
  @override
  ClubMutationController create() => ClubMutationController();
}

String _$clubMutationControllerHash() =>
    r'ac1654aeffb665d75a0ebe863b3eb907b2edc59d';

/// TODO: Document ClubMutationController.

abstract class _$ClubMutationController extends $AsyncNotifier<void> {
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

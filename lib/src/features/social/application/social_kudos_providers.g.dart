// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'social_kudos_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(kudosRepository)
const kudosRepositoryProvider = KudosRepositoryProvider._();

final class KudosRepositoryProvider
    extends
        $FunctionalProvider<KudosRepository, KudosRepository, KudosRepository>
    with $Provider<KudosRepository> {
  const KudosRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'kudosRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$kudosRepositoryHash();

  @$internal
  @override
  $ProviderElement<KudosRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  KudosRepository create(Ref ref) {
    return kudosRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(KudosRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<KudosRepository>(value),
    );
  }
}

String _$kudosRepositoryHash() => r'9fcab126f4d9f760babedb447a44b5ecd01a8675';

@ProviderFor(activityKudos)
const activityKudosProvider = ActivityKudosFamily._();

final class ActivityKudosProvider
    extends
        $FunctionalProvider<
          AsyncValue<ActivityKudosSummary>,
          ActivityKudosSummary,
          FutureOr<ActivityKudosSummary>
        >
    with
        $FutureModifier<ActivityKudosSummary>,
        $FutureProvider<ActivityKudosSummary> {
  const ActivityKudosProvider._({
    required ActivityKudosFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'activityKudosProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$activityKudosHash();

  @override
  String toString() {
    return r'activityKudosProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ActivityKudosSummary> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ActivityKudosSummary> create(Ref ref) {
    final argument = this.argument as String;
    return activityKudos(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ActivityKudosProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$activityKudosHash() => r'15b2e81b157d15c2eb3d5aeef97c579f5da7e3a2';

final class ActivityKudosFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ActivityKudosSummary>, String> {
  const ActivityKudosFamily._()
    : super(
        retry: null,
        name: r'activityKudosProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ActivityKudosProvider call(String activityId) =>
      ActivityKudosProvider._(argument: activityId, from: this);

  @override
  String toString() => r'activityKudosProvider';
}

/// Optimistic viewer-kudos state keyed by remote activity id.

@ProviderFor(OptimisticKudosByActivity)
const optimisticKudosByActivityProvider = OptimisticKudosByActivityProvider._();

/// Optimistic viewer-kudos state keyed by remote activity id.
final class OptimisticKudosByActivityProvider
    extends $NotifierProvider<OptimisticKudosByActivity, Map<String, bool>> {
  /// Optimistic viewer-kudos state keyed by remote activity id.
  const OptimisticKudosByActivityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'optimisticKudosByActivityProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$optimisticKudosByActivityHash();

  @$internal
  @override
  OptimisticKudosByActivity create() => OptimisticKudosByActivity();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, bool> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, bool>>(value),
    );
  }
}

String _$optimisticKudosByActivityHash() =>
    r'ff5712563675408900ba3aa6d1b6fa173d193ef5';

/// Optimistic viewer-kudos state keyed by remote activity id.

abstract class _$OptimisticKudosByActivity
    extends $Notifier<Map<String, bool>> {
  Map<String, bool> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<Map<String, bool>, Map<String, bool>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, bool>, Map<String, bool>>,
              Map<String, bool>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Single mutation path for kudos toggles across social and owner detail flows.

@ProviderFor(KudosToggleController)
const kudosToggleControllerProvider = KudosToggleControllerProvider._();

/// Single mutation path for kudos toggles across social and owner detail flows.
final class KudosToggleControllerProvider
    extends $AsyncNotifierProvider<KudosToggleController, void> {
  /// Single mutation path for kudos toggles across social and owner detail flows.
  const KudosToggleControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'kudosToggleControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$kudosToggleControllerHash();

  @$internal
  @override
  KudosToggleController create() => KudosToggleController();
}

String _$kudosToggleControllerHash() =>
    r'972eeab66d2cac078dc86123bbcbcc4b47c34308';

/// Single mutation path for kudos toggles across social and owner detail flows.

abstract class _$KudosToggleController extends $AsyncNotifier<void> {
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

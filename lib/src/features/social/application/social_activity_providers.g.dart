// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'social_activity_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(socialActivityRepository)
const socialActivityRepositoryProvider = SocialActivityRepositoryProvider._();

final class SocialActivityRepositoryProvider
    extends
        $FunctionalProvider<
          SocialActivityRepository,
          SocialActivityRepository,
          SocialActivityRepository
        >
    with $Provider<SocialActivityRepository> {
  const SocialActivityRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'socialActivityRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$socialActivityRepositoryHash();

  @$internal
  @override
  $ProviderElement<SocialActivityRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SocialActivityRepository create(Ref ref) {
    return socialActivityRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SocialActivityRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SocialActivityRepository>(value),
    );
  }
}

String _$socialActivityRepositoryHash() =>
    r'2de8339732118418cc062e73bced976ee846286e';

@ProviderFor(SocialFeed)
const socialFeedProvider = SocialFeedProvider._();

final class SocialFeedProvider
    extends $AsyncNotifierProvider<SocialFeed, SocialFeedState> {
  const SocialFeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'socialFeedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$socialFeedHash();

  @$internal
  @override
  SocialFeed create() => SocialFeed();
}

String _$socialFeedHash() => r'8a0ac8da0889ad61d4d7574f307382cb836e63f3';

abstract class _$SocialFeed extends $AsyncNotifier<SocialFeedState> {
  FutureOr<SocialFeedState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<SocialFeedState>, SocialFeedState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SocialFeedState>, SocialFeedState>,
              AsyncValue<SocialFeedState>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(viewedUserActivityList)
const viewedUserActivityListProvider = ViewedUserActivityListFamily._();

final class ViewedUserActivityListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SocialActivitySummary>>,
          List<SocialActivitySummary>,
          FutureOr<List<SocialActivitySummary>>
        >
    with
        $FutureModifier<List<SocialActivitySummary>>,
        $FutureProvider<List<SocialActivitySummary>> {
  const ViewedUserActivityListProvider._({
    required ViewedUserActivityListFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'viewedUserActivityListProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$viewedUserActivityListHash();

  @override
  String toString() {
    return r'viewedUserActivityListProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<SocialActivitySummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<SocialActivitySummary>> create(Ref ref) {
    final argument = this.argument as String;
    return viewedUserActivityList(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ViewedUserActivityListProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$viewedUserActivityListHash() =>
    r'fa9f6db361ec4fba8a0143a11068dd985b1c1d70';

final class ViewedUserActivityListFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<SocialActivitySummary>>,
          String
        > {
  const ViewedUserActivityListFamily._()
    : super(
        retry: null,
        name: r'viewedUserActivityListProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ViewedUserActivityListProvider call(String userId) =>
      ViewedUserActivityListProvider._(argument: userId, from: this);

  @override
  String toString() => r'viewedUserActivityListProvider';
}

@ProviderFor(remoteActivityDetail)
const remoteActivityDetailProvider = RemoteActivityDetailFamily._();

final class RemoteActivityDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<RemoteActivityDetailData?>,
          RemoteActivityDetailData?,
          FutureOr<RemoteActivityDetailData?>
        >
    with
        $FutureModifier<RemoteActivityDetailData?>,
        $FutureProvider<RemoteActivityDetailData?> {
  const RemoteActivityDetailProvider._({
    required RemoteActivityDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'remoteActivityDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$remoteActivityDetailHash();

  @override
  String toString() {
    return r'remoteActivityDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<RemoteActivityDetailData?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RemoteActivityDetailData?> create(Ref ref) {
    final argument = this.argument as String;
    return remoteActivityDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RemoteActivityDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$remoteActivityDetailHash() =>
    r'10685e7dd931dfe54967cbad09c2f4a081a566f3';

final class RemoteActivityDetailFamily extends $Family
    with
        $FunctionalFamilyOverride<FutureOr<RemoteActivityDetailData?>, String> {
  const RemoteActivityDetailFamily._()
    : super(
        retry: null,
        name: r'remoteActivityDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  RemoteActivityDetailProvider call(String activityId) =>
      RemoteActivityDetailProvider._(argument: activityId, from: this);

  @override
  String toString() => r'remoteActivityDetailProvider';
}

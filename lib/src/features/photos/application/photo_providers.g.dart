// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(photoPickerService)
const photoPickerServiceProvider = PhotoPickerServiceProvider._();

final class PhotoPickerServiceProvider
    extends
        $FunctionalProvider<
          PhotoPickerService,
          PhotoPickerService,
          PhotoPickerService
        >
    with $Provider<PhotoPickerService> {
  const PhotoPickerServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'photoPickerServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$photoPickerServiceHash();

  @$internal
  @override
  $ProviderElement<PhotoPickerService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PhotoPickerService create(Ref ref) {
    return photoPickerService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PhotoPickerService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PhotoPickerService>(value),
    );
  }
}

String _$photoPickerServiceHash() =>
    r'd8bbf78190d7ce060fdccf72f3fa5e946e6a8035';

@ProviderFor(photoRepository)
const photoRepositoryProvider = PhotoRepositoryProvider._();

final class PhotoRepositoryProvider
    extends
        $FunctionalProvider<PhotoRepository, PhotoRepository, PhotoRepository>
    with $Provider<PhotoRepository> {
  const PhotoRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'photoRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$photoRepositoryHash();

  @$internal
  @override
  $ProviderElement<PhotoRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PhotoRepository create(Ref ref) {
    return photoRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PhotoRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PhotoRepository>(value),
    );
  }
}

String _$photoRepositoryHash() => r'3b89c994ed6ff0652e434c3e28b927b8e07702de';

@ProviderFor(activityPhotoList)
const activityPhotoListProvider = ActivityPhotoListFamily._();

final class ActivityPhotoListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ActivityPhoto>>,
          List<ActivityPhoto>,
          FutureOr<List<ActivityPhoto>>
        >
    with
        $FutureModifier<List<ActivityPhoto>>,
        $FutureProvider<List<ActivityPhoto>> {
  const ActivityPhotoListProvider._({
    required ActivityPhotoListFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'activityPhotoListProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$activityPhotoListHash();

  @override
  String toString() {
    return r'activityPhotoListProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<ActivityPhoto>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ActivityPhoto>> create(Ref ref) {
    final argument = this.argument as String;
    return activityPhotoList(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ActivityPhotoListProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$activityPhotoListHash() => r'618eb31fb5200ab35cebbd5fef79f5c9ee84497c';

final class ActivityPhotoListFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<ActivityPhoto>>, String> {
  const ActivityPhotoListFamily._()
    : super(
        retry: null,
        name: r'activityPhotoListProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ActivityPhotoListProvider call(String activityId) =>
      ActivityPhotoListProvider._(argument: activityId, from: this);

  @override
  String toString() => r'activityPhotoListProvider';
}

/// TODO: Document ActivityPhotoController.

@ProviderFor(ActivityPhotoController)
const activityPhotoControllerProvider = ActivityPhotoControllerFamily._();

/// TODO: Document ActivityPhotoController.
final class ActivityPhotoControllerProvider
    extends
        $NotifierProvider<
          ActivityPhotoController,
          ActivityPhotoControllerState
        > {
  /// TODO: Document ActivityPhotoController.
  const ActivityPhotoControllerProvider._({
    required ActivityPhotoControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'activityPhotoControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$activityPhotoControllerHash();

  @override
  String toString() {
    return r'activityPhotoControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ActivityPhotoController create() => ActivityPhotoController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ActivityPhotoControllerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ActivityPhotoControllerState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ActivityPhotoControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$activityPhotoControllerHash() =>
    r'1ca13c5ad3ff0487e49d72625145e649347d9bda';

/// TODO: Document ActivityPhotoController.

final class ActivityPhotoControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ActivityPhotoController,
          ActivityPhotoControllerState,
          ActivityPhotoControllerState,
          ActivityPhotoControllerState,
          String
        > {
  const ActivityPhotoControllerFamily._()
    : super(
        retry: null,
        name: r'activityPhotoControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// TODO: Document ActivityPhotoController.

  ActivityPhotoControllerProvider call(String activityId) =>
      ActivityPhotoControllerProvider._(argument: activityId, from: this);

  @override
  String toString() => r'activityPhotoControllerProvider';
}

/// TODO: Document ActivityPhotoController.

abstract class _$ActivityPhotoController
    extends $Notifier<ActivityPhotoControllerState> {
  late final _$args = ref.$arg as String;
  String get activityId => _$args;

  ActivityPhotoControllerState build(String activityId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref =
        this.ref
            as $Ref<ActivityPhotoControllerState, ActivityPhotoControllerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                ActivityPhotoControllerState,
                ActivityPhotoControllerState
              >,
              ActivityPhotoControllerState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

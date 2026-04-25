// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gear_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(gearRepository)
const gearRepositoryProvider = GearRepositoryProvider._();

final class GearRepositoryProvider
    extends $FunctionalProvider<GearRepository, GearRepository, GearRepository>
    with $Provider<GearRepository> {
  const GearRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gearRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gearRepositoryHash();

  @$internal
  @override
  $ProviderElement<GearRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GearRepository create(Ref ref) {
    return gearRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GearRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GearRepository>(value),
    );
  }
}

String _$gearRepositoryHash() => r'081bd5958a92b0763b1979689a859181b5a57179';

@ProviderFor(gearList)
const gearListProvider = GearListProvider._();

final class GearListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<GearItem>>,
          List<GearItem>,
          FutureOr<List<GearItem>>
        >
    with $FutureModifier<List<GearItem>>, $FutureProvider<List<GearItem>> {
  const GearListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gearListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gearListHash();

  @$internal
  @override
  $FutureProviderElement<List<GearItem>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<GearItem>> create(Ref ref) {
    return gearList(ref);
  }
}

String _$gearListHash() => r'fe7457c69172e8c80c4b368987ec5e087cbb8262';

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'telemetry_enablement.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(telemetryEnablementOwner)
const telemetryEnablementOwnerProvider = TelemetryEnablementOwnerProvider._();

final class TelemetryEnablementOwnerProvider
    extends
        $FunctionalProvider<
          TelemetryEnablementOwner,
          TelemetryEnablementOwner,
          TelemetryEnablementOwner
        >
    with $Provider<TelemetryEnablementOwner> {
  const TelemetryEnablementOwnerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'telemetryEnablementOwnerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$telemetryEnablementOwnerHash();

  @$internal
  @override
  $ProviderElement<TelemetryEnablementOwner> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TelemetryEnablementOwner create(Ref ref) {
    return telemetryEnablementOwner(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TelemetryEnablementOwner value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TelemetryEnablementOwner>(value),
    );
  }
}

String _$telemetryEnablementOwnerHash() =>
    r'cb08a91b47762c1274ea63058a7985b698d5fd15';

/// App-facing single source of truth for telemetry enablement state.

@ProviderFor(TelemetryEnablementNotifier)
const telemetryEnablementProvider = TelemetryEnablementNotifierProvider._();

/// App-facing single source of truth for telemetry enablement state.
final class TelemetryEnablementNotifierProvider
    extends $NotifierProvider<TelemetryEnablementNotifier, bool> {
  /// App-facing single source of truth for telemetry enablement state.
  const TelemetryEnablementNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'telemetryEnablementProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$telemetryEnablementNotifierHash();

  @$internal
  @override
  TelemetryEnablementNotifier create() => TelemetryEnablementNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$telemetryEnablementNotifierHash() =>
    r'a4e13b7665076985dfe5b5422ae8033396e2a914';

/// App-facing single source of truth for telemetry enablement state.

abstract class _$TelemetryEnablementNotifier extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

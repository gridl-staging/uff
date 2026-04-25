// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_preferences.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// App-facing source of truth for local notifications preference state.

@ProviderFor(NotificationPreferencesNotifier)
const notificationPreferencesProvider =
    NotificationPreferencesNotifierProvider._();

/// App-facing source of truth for local notifications preference state.
final class NotificationPreferencesNotifierProvider
    extends $NotifierProvider<NotificationPreferencesNotifier, bool> {
  /// App-facing source of truth for local notifications preference state.
  const NotificationPreferencesNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notificationPreferencesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationPreferencesNotifierHash();

  @$internal
  @override
  NotificationPreferencesNotifier create() => NotificationPreferencesNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$notificationPreferencesNotifierHash() =>
    r'3a9550d1bcbd5e93ef070cbeab9537df8f1efaa0';

/// App-facing source of truth for local notifications preference state.

abstract class _$NotificationPreferencesNotifier extends $Notifier<bool> {
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

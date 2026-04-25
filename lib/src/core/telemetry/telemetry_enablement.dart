import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uff/src/core/telemetry/data/supabase_telemetry_uploader.dart';
import 'package:uff/src/core/telemetry/data/telemetry_store.dart';
import 'package:uff/src/core/telemetry/domain/telemetry_scrubber.dart';
import 'package:uff/src/core/telemetry/lazy_telemetry_store_client.dart';
import 'package:uff/src/core/telemetry/service/telemetry_flush_scheduler.dart';
import 'package:uff/src/core/telemetry/service/telemetry_service.dart';
import 'package:uff/src/core/telemetry/service/telemetry_uploader.dart';
import 'package:uff/src/utils/uuid.dart';

part 'telemetry_enablement.g.dart';

const _telemetryEnabledPreferenceKey = 'telemetry_enabled';
const _unknownTelemetryBuildValue = 'unknown';

typedef SharedPreferencesLoader = Future<SharedPreferences> Function();
typedef PendingTelemetryClearer = Future<void> Function();
typedef InMemoryTelemetryClearer = void Function();
typedef TelemetryBreadcrumbRecorder =
    Future<void> Function({
      required String message,
      required Map<String, Object?> metadata,
    });

Future<void> noopTelemetryBreadcrumbRecorder({
  required String message,
  required Map<String, Object?> metadata,
}) async {}

/// Fires a breadcrumb recorder without letting telemetry side effects escape.
void recordTelemetryBreadcrumbSafely(
  TelemetryBreadcrumbRecorder recorder, {
  required String message,
  required Map<String, Object?> metadata,
}) {
  try {
    final breadcrumbFuture = recorder(
      message: message,
      metadata: metadata,
    );
    unawaited(breadcrumbFuture.catchError((Object _, StackTrace __) {}));
  } on Object {
    // Core product flows must not fail because telemetry side effects do.
  }
}

void recordBoundaryTelemetryBreadcrumb(
  TelemetryBreadcrumbRecorder recorder, {
  required String boundary,
  required String operation,
  required String message,
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  recordTelemetryBreadcrumbSafely(
    recorder,
    message: message,
    metadata: <String, Object?>{
      'boundary': boundary,
      'operation': operation,
      ...metadata,
    },
  );
}

final telemetrySharedPreferencesLoaderProvider =
    Provider<SharedPreferencesLoader>(
      (ref) => SharedPreferences.getInstance,
    );

final telemetryRootDirectoryPathLoaderProvider =
    Provider<TelemetryRootDirectoryPathLoader>(
      (ref) => () async {
        final documentsDirectory = await getApplicationDocumentsDirectory();
        return documentsDirectory.path;
      },
    );

final telemetryStoreProvider = Provider<TelemetryStoreClient>((ref) {
  final storeClient = LazyTelemetryStoreClient(
    loadRootDirectoryPath: ref.read(telemetryRootDirectoryPathLoaderProvider),
  );
  ref.onDispose(() {
    unawaited(storeClient.dispose());
  });
  return storeClient;
});

final telemetryScrubberProvider = Provider<TelemetryScrubber>(
  (ref) => TelemetryScrubber(),
);

final telemetryUploaderProvider = Provider<TelemetryUploader>(
  (ref) => SupabaseTelemetryUploader(
    invoke: (String name, {Object? body}) =>
        Supabase.instance.client.functions.invoke(name, body: body),
  ),
);

final telemetryContextSourceProvider = Provider<AppBuildPlatformContextSource>(
  (ref) => const _DefaultAppBuildPlatformContextSource(),
);

final telemetryAuthAvailabilityProvider = Provider<bool Function()>(
  (ref) => () {
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } on Object {
      // Supabase may not be initialized during early startup.
      return false;
    }
  },
);

final telemetryServiceProvider = Provider<TelemetryService>((ref) {
  final scrubber = ref.read(telemetryScrubberProvider);
  return TelemetryService(
    dependencies: TelemetryServiceDependencies(
      now: DateTime.now,
      eventIdFactory: generateUuidV4,
      io: TelemetryIO(
        store: ref.read(telemetryStoreProvider),
        uploader: ref.read(telemetryUploaderProvider),
      ),
      contextSource: ref.read(telemetryContextSourceProvider),
      scrubMetadata: scrubber.scrubBreadcrumbMetadata,
      flushConfig: TelemetryFlushConfig(
        isAuthAvailable: ref.read(telemetryAuthAvailabilityProvider),
      ),
    ),
    isTelemetryEnabled: ref.read(telemetryIsEnabledReaderProvider),
  );
});

final telemetryFlushSchedulerProvider = Provider<TelemetryFlushScheduler>(
  (ref) {
    final service = ref.read(telemetryServiceProvider);
    final scheduler = TelemetryFlushScheduler(flush: service.flushPending);
    ref.onDispose(scheduler.dispose);
    return scheduler;
  },
);

final telemetryBreadcrumbRecorderProvider =
    Provider<TelemetryBreadcrumbRecorder>(
      (ref) {
        return ({
          required String message,
          required Map<String, Object?> metadata,
        }) {
          return ref
              .read(telemetryServiceProvider)
              .recordBreadcrumb(
                message: message,
                metadata: metadata,
              );
        };
      },
    );

final telemetryPendingTelemetryClearerProvider =
    Provider<PendingTelemetryClearer>(
      (ref) => () async {
        await ref.read(telemetryStoreProvider).clear();
      },
    );

final telemetryInMemoryTelemetryClearerProvider =
    Provider<InMemoryTelemetryClearer>(
      (ref) => () {
        ref.read(telemetryServiceProvider).clearBreadcrumbs();
      },
    );

/// In-memory owner that applies telemetry enablement side effects.
class TelemetryEnablementOwner {
  TelemetryEnablementOwner({
    required Future<bool?> Function() readPersisted,
    required Future<void> Function({required bool isEnabled}) writePersisted,
    required Future<void> Function() clearPendingTelemetry,
    required void Function() clearInMemoryTelemetry,
  }) : _readPersisted = readPersisted,
       _writePersisted = writePersisted,
       _clearPendingTelemetry = clearPendingTelemetry,
       _clearInMemoryTelemetry = clearInMemoryTelemetry;

  final Future<bool?> Function() _readPersisted;
  final Future<void> Function({required bool isEnabled}) _writePersisted;
  final Future<void> Function() _clearPendingTelemetry;
  final void Function() _clearInMemoryTelemetry;

  bool _isEnabled = true;

  bool get isEnabled => _isEnabled;

  Future<void> hydrate() async {
    try {
      final persistedValue = await _readPersisted();
      if (persistedValue == null) {
        return;
      }
      _isEnabled = persistedValue;
    } on Object catch (_) {
      // Keep the in-memory value when persistence read fails.
    }
  }

  Future<void> setTelemetryEnabled({required bool isEnabled}) async {
    _isEnabled = isEnabled;

    try {
      await _writePersisted(isEnabled: isEnabled);
    } on Object catch (_) {
      // Keep the in-memory value when persistence write fails.
    }

    if (!isEnabled) {
      _clearInMemoryTelemetrySafely();
      await _clearPendingQueueSafely();
    }
  }

  void _clearInMemoryTelemetrySafely() {
    try {
      _clearInMemoryTelemetry();
    } on Object catch (_) {
      // Disabling telemetry should remain sticky even if in-memory clearing fails.
    }
  }

  Future<void> _clearPendingQueueSafely() async {
    try {
      await _clearPendingTelemetry();
    } on Object catch (_) {
      // Disabling telemetry should remain sticky even if queue clearing fails.
    }
  }
}

@Riverpod(keepAlive: true)
TelemetryEnablementOwner telemetryEnablementOwner(Ref ref) {
  final loadSharedPreferences = ref.read(
    telemetrySharedPreferencesLoaderProvider,
  );
  final clearPendingTelemetry = ref.read(
    telemetryPendingTelemetryClearerProvider,
  );
  final clearInMemoryTelemetry = ref.read(
    telemetryInMemoryTelemetryClearerProvider,
  );
  final sharedPreferencesLoader = RetryingAsyncLoader<SharedPreferences>(
    loadSharedPreferences,
  );

  return TelemetryEnablementOwner(
    readPersisted: () async {
      final preferences = await sharedPreferencesLoader.load();
      return preferences.getBool(_telemetryEnabledPreferenceKey);
    },
    writePersisted: ({required bool isEnabled}) async {
      final preferences = await sharedPreferencesLoader.load();
      await preferences.setBool(_telemetryEnabledPreferenceKey, isEnabled);
    },
    clearPendingTelemetry: clearPendingTelemetry,
    clearInMemoryTelemetry: clearInMemoryTelemetry,
  );
}

/// App-facing single source of truth for telemetry enablement state.
@Riverpod(keepAlive: true)
class TelemetryEnablementNotifier extends _$TelemetryEnablementNotifier {
  bool _hasLocalOverride = false;
  Future<void> _pendingMutation = Future<void>.value();
  int _latestMutationToken = 0;

  @override
  bool build() {
    unawaited(_hydratePersistedTelemetryEnabled());
    return ref.read(telemetryEnablementOwnerProvider).isEnabled;
  }

  Future<void> setTelemetryEnabled({required bool isEnabled}) async {
    _hasLocalOverride = true;
    final mutationToken = ++_latestMutationToken;

    if (!isEnabled && state != isEnabled) {
      state = isEnabled;
    }

    final queuedMutation = _pendingMutation.catchError((Object _) {}).then((_) {
      return _applyQueuedTelemetryEnabledChange(
        mutationToken: mutationToken,
        isEnabled: isEnabled,
      );
    });
    _pendingMutation = queuedMutation;

    await queuedMutation;
  }

  Future<void> _hydratePersistedTelemetryEnabled() async {
    final owner = ref.read(telemetryEnablementOwnerProvider);
    await owner.hydrate();
    if (!ref.mounted || _hasLocalOverride || state == owner.isEnabled) {
      return;
    }

    state = owner.isEnabled;
  }

  Future<void> _applyQueuedTelemetryEnabledChange({
    required int mutationToken,
    required bool isEnabled,
  }) async {
    if (!ref.mounted || mutationToken != _latestMutationToken) {
      return;
    }

    final owner = ref.read(telemetryEnablementOwnerProvider);
    if (state != isEnabled) {
      state = isEnabled;
    }

    await owner.setTelemetryEnabled(isEnabled: isEnabled);
    if (!ref.mounted || mutationToken != _latestMutationToken) {
      return;
    }

    final ownerValue = owner.isEnabled;
    if (state != ownerValue) {
      state = ownerValue;
    }
  }
}

final telemetryIsEnabledReaderProvider = Provider<bool Function()>(
  (ref) =>
      () => ref.read(telemetryEnablementProvider),
);

/// Reads build/version/platform context injected into captured telemetry payloads.
class _DefaultAppBuildPlatformContextSource
    implements AppBuildPlatformContextSource {
  const _DefaultAppBuildPlatformContextSource();

  @override
  Map<String, Object?> read() {
    return <String, Object?>{
      'appVersion': const String.fromEnvironment(
        'FLUTTER_BUILD_NAME',
        defaultValue: _unknownTelemetryBuildValue,
      ),
      'buildNumber': const String.fromEnvironment(
        'FLUTTER_BUILD_NUMBER',
        defaultValue: _unknownTelemetryBuildValue,
      ),
      'platform': defaultTargetPlatform.name,
    };
  }
}

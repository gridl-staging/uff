import 'dart:async';

import 'package:uff/src/core/telemetry/data/telemetry_store.dart';

typedef TelemetryRootDirectoryPathLoader = Future<String> Function();

/// Lazily opens the telemetry SQLite store on first use and retries after
/// failed opens by clearing the cached future in `RetryingAsyncLoader`.
class LazyTelemetryStoreClient implements TelemetryStoreClient {
  LazyTelemetryStoreClient({
    required TelemetryRootDirectoryPathLoader loadRootDirectoryPath,
  }) : _loadRootDirectoryPath = loadRootDirectoryPath;

  final TelemetryRootDirectoryPathLoader _loadRootDirectoryPath;
  late final RetryingAsyncLoader<TelemetryStore> _storeLoader =
      RetryingAsyncLoader<TelemetryStore>(_openStore);
  bool _isDisposed = false;

  @override
  Future<void> enqueue(Map<String, Object?> row) async {
    final store = await _store();
    await store.enqueue(row);
  }

  @override
  Future<List<Map<String, Object?>>> loadPending() async {
    final store = await _store();
    return store.loadPending();
  }

  @override
  Future<void> recordAttempt({
    required String eventId,
    required int attemptCount,
    required String lastAttemptStatus,
    DateTime? lastAttemptedAt,
  }) async {
    final store = await _store();
    await store.recordAttempt(
      eventId: eventId,
      attemptCount: attemptCount,
      lastAttemptStatus: lastAttemptStatus,
      lastAttemptedAt: lastAttemptedAt,
    );
  }

  @override
  Future<void> delete(String eventId) async {
    final store = await _store();
    await store.delete(eventId);
  }

  @override
  Future<void> clear() async {
    final store = await _store();
    await store.clear();
  }

  Future<void> dispose() async {
    _isDisposed = true;
    final storeFuture = _storeLoader.cachedFuture;
    if (storeFuture == null) {
      return;
    }

    try {
      final store = await storeFuture;
      await store.close();
    } on Object {
      // Disposal should not surface lazy-open failures during provider teardown.
    }
  }

  Future<TelemetryStore> _store() {
    if (_isDisposed) {
      return Future<TelemetryStore>.error(
        StateError('Telemetry store provider is already disposed.'),
      );
    }
    return _storeLoader.load();
  }

  Future<TelemetryStore> _openStore() async {
    final rootDirectoryPath = await _loadRootDirectoryPath();
    return TelemetryStore.open(rootDirectoryPath);
  }
}

/// Caches one async create call and drops the cache when creation fails so
/// future callers can retry.
class RetryingAsyncLoader<T> {
  RetryingAsyncLoader(this._create);

  final Future<T> Function() _create;
  Future<T>? _cachedFuture;

  Future<T>? get cachedFuture => _cachedFuture;

  Future<T> load() {
    final cachedFuture = _cachedFuture;
    if (cachedFuture != null) {
      return cachedFuture;
    }

    final createdFuture = _create();
    _cachedFuture = createdFuture;
    return createdFuture.onError((Object error, StackTrace stackTrace) {
      if (identical(_cachedFuture, createdFuture)) {
        _cachedFuture = null;
      }
      return Future<T>.error(error, stackTrace);
    });
  }
}

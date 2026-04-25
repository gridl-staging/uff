import 'package:uff/src/core/telemetry/data/telemetry_store.dart';
import 'package:uff/src/core/telemetry/domain/telemetry_breadcrumb.dart';
import 'package:uff/src/core/telemetry/domain/telemetry_context.dart';
import 'package:uff/src/core/telemetry/domain/telemetry_event.dart';
import 'package:uff/src/core/telemetry/domain/telemetry_retry_policy.dart';
import 'package:uff/src/core/telemetry/service/telemetry_uploader.dart';

// ignore: one_member_abstracts, reason: Stable seam for context policy source.
abstract class AppBuildPlatformContextSource {
  Map<String, Object?> read();
}

/// Store and uploader I/O channels for telemetry data.
class TelemetryIO {
  const TelemetryIO({required this.store, required this.uploader});

  final TelemetryStoreClient store;
  final TelemetryUploader uploader;
}

/// Flush-specific gating: auth availability and retry backoff policy.
class TelemetryFlushConfig {
  const TelemetryFlushConfig({
    required this.isAuthAvailable,
    this.retryPolicy = const TelemetryRetryPolicy(),
  });

  final bool Function() isAuthAvailable;
  final TelemetryRetryPolicy retryPolicy;
}

/// TODO: Document TelemetryServiceDependencies.
class TelemetryServiceDependencies {
  const TelemetryServiceDependencies({
    required this.now,
    required this.eventIdFactory,
    required this.io,
    required this.contextSource,
    required this.scrubMetadata,
    required this.flushConfig,
  });

  final DateTime Function() now;
  final String Function() eventIdFactory;
  final TelemetryIO io;
  final AppBuildPlatformContextSource contextSource;
  final Map<String, Object?> Function(Map<String, Object?> metadata)
  scrubMetadata;
  final TelemetryFlushConfig flushConfig;
}

// TODO(uff): Document TelemetryService.
/// TODO: Document TelemetryService.
class TelemetryService {
  TelemetryService({
    required TelemetryServiceDependencies dependencies,
    required bool Function() isTelemetryEnabled,
  }) : _now = dependencies.now,
       _eventIdFactory = dependencies.eventIdFactory,
       _store = dependencies.io.store,
       _uploader = dependencies.io.uploader,
       _contextSource = dependencies.contextSource,
       _scrubMetadata = dependencies.scrubMetadata,
       _isAuthAvailable = dependencies.flushConfig.isAuthAvailable,
       _retryPolicy = dependencies.flushConfig.retryPolicy,
       _isTelemetryEnabled = isTelemetryEnabled;

  final DateTime Function() _now;
  final String Function() _eventIdFactory;
  final TelemetryStoreClient _store;
  final TelemetryUploader _uploader;
  final AppBuildPlatformContextSource _contextSource;
  final Map<String, Object?> Function(Map<String, Object?> metadata)
  _scrubMetadata;
  final bool Function() _isAuthAvailable;
  final TelemetryRetryPolicy _retryPolicy;
  final bool Function() _isTelemetryEnabled;

  final List<TelemetryBreadcrumb> _breadcrumbs = <TelemetryBreadcrumb>[];

  void clearBreadcrumbs() {
    _breadcrumbs.clear();
  }

  Future<void> captureUnhandled({
    required Object error,
    required StackTrace stackTrace,
    required Map<String, Object?> metadata,
  }) async {
    if (!_isTelemetryEnabled()) {
      return;
    }

    final scrubbedMetadata = _scrubMetadata(
      _buildUnhandledMetadata(
        error: error,
        stackTrace: stackTrace,
        metadata: metadata,
      ),
    );
    final event = QueuedTelemetryEvent.forUnhandled(
      eventId: _eventIdFactory(),
      capturedAt: _now().toUtc(),
      context: _readContextEnvelope(),
      metadata: scrubbedMetadata,
      breadcrumbs: List<TelemetryBreadcrumb>.from(_breadcrumbs),
    );
    await _store.enqueue(event.toJson());
  }

  Future<void> recordBreadcrumb({
    required String message,
    required Map<String, Object?> metadata,
  }) async {
    if (!_isTelemetryEnabled()) {
      return;
    }

    final breadcrumb = TelemetryBreadcrumb(
      message: message,
      capturedAt: _now().toUtc(),
      metadata: _scrubMetadata(metadata),
    );
    _breadcrumbs.add(breadcrumb);
    _retainNewestBreadcrumbs();
  }

  /// Flushes all eligible pending rows and returns the duration until the
  /// earliest next-eligible row, or null if no rows are waiting on backoff.
  ///
  /// The returned duration lets the scheduler arm a one-shot timer without
  /// reimplementing backoff logic.
  Future<Duration?> flushPending() async {
    if (!_isTelemetryEnabled()) {
      return null;
    }
    if (!_isAuthAvailable()) {
      return null;
    }

    final pendingRows = await _store.loadPending();
    Duration? earliestNextEligible;
    for (final row in pendingRows) {
      final rowWait = await _flushPendingRow(row);
      if (rowWait != null) {
        if (earliestNextEligible == null || rowWait < earliestNextEligible) {
          earliestNextEligible = rowWait;
        }
      }
    }
    return earliestNextEligible;
  }

  /// Processes a single pending row. Returns the remaining backoff duration if
  /// the row was skipped, or null if it was uploaded, tombstoned, or failed.
  Future<Duration?> _flushPendingRow(Map<String, Object?> row) async {
    final eventId = _eventIdOf(row);
    final attemptCount = _currentAttemptCount(row);

    // Tombstone exhausted rows without burning another upload attempt.
    if (_retryPolicy.shouldTombstone(attemptCount: attemptCount)) {
      await _store.delete(eventId);
      return null;
    }

    // Skip rows still inside the backoff window.
    final now = _now();
    final lastAttemptedAt = _parseLastAttemptedAt(row);
    if (!_retryPolicy.isEligible(
      attemptCount: attemptCount,
      lastAttemptedAt: lastAttemptedAt,
      now: now,
    )) {
      final backoff = _retryPolicy.backoffDuration(attemptCount: attemptCount);
      final elapsed = now.difference(lastAttemptedAt!);
      final remaining = backoff - elapsed;
      return remaining > Duration.zero ? remaining : Duration.zero;
    }

    final uploadSucceeded = await _uploadRow(row);
    final nextAttemptCount = attemptCount + 1;
    final lastAttemptStatus = uploadSucceeded ? 'uploaded' : 'failed';

    await _store.recordAttempt(
      eventId: eventId,
      attemptCount: nextAttemptCount,
      lastAttemptStatus: lastAttemptStatus,
      lastAttemptedAt: _now().toUtc(),
    );

    if (uploadSucceeded) {
      await _store.delete(eventId);
    }
    return null;
  }

  Future<bool> _uploadRow(Map<String, Object?> row) async {
    try {
      return await _uploader.upload(row);
    } on Object catch (_) {
      return false;
    }
  }

  String _eventIdOf(Map<String, Object?> row) {
    final rawEventId = row['eventId'];
    if (rawEventId is String) {
      return rawEventId;
    }

    throw StateError('Queued telemetry row is missing a valid eventId.');
  }

  int _currentAttemptCount(Map<String, Object?> row) {
    final rawAttemptCount = row['attemptCount'];
    return switch (rawAttemptCount) {
      final int value => value,
      final num value when value.isFinite => value.toInt(),
      _ => 0,
    };
  }

  DateTime? _parseLastAttemptedAt(Map<String, Object?> row) {
    final raw = row['lastAttemptedAt'];
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  TelemetryContextEnvelope _readContextEnvelope() {
    final contextMap = _contextSource.read();
    return TelemetryContextEnvelope(
      appVersion: _readRequiredContextValue(contextMap, key: 'appVersion'),
      buildNumber: _readRequiredContextValue(contextMap, key: 'buildNumber'),
      platform: _readRequiredContextValue(contextMap, key: 'platform'),
    );
  }

  String _readRequiredContextValue(
    Map<String, Object?> context, {
    required String key,
  }) {
    final value = context[key];
    if (value is String) {
      return value;
    }

    throw StateError('Context key "$key" is missing or not a String.');
  }

  Map<String, Object?> _buildUnhandledMetadata({
    required Object error,
    required StackTrace stackTrace,
    required Map<String, Object?> metadata,
  }) {
    return <String, Object?>{
      ...metadata,
      'errorType': error.runtimeType.toString(),
      'exceptionMessage': error.toString(),
      'stackTrace': stackTrace.toString(),
    };
  }

  void _retainNewestBreadcrumbs() {
    const retainedCount = QueuedTelemetryEvent.breadcrumbRetentionLimit;
    if (_breadcrumbs.length <= retainedCount) {
      return;
    }

    final staleCount = _breadcrumbs.length - retainedCount;
    _breadcrumbs.removeRange(0, staleCount);
  }
}

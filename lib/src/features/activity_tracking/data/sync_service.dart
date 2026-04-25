import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/core/telemetry/telemetry_enablement.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/data/remote_activity_deleter.dart'
    show RemoteActivityDeleter;
import 'package:uff/src/features/activity_tracking/data/sync_payload_builder.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_repository.dart';
import 'package:uff/src/features/photos/application/pending_photo_upload_service.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart'
    show photoRepositoryProvider;
import 'package:uff/src/utils/app_logger.dart';
import 'package:uff/src/utils/uuid.dart';

enum SyncQueueStatus {
  idle,
  queued,
  processing,
  successful,
  failed,
}

/// NOTE(stuart): Document SyncService.
abstract interface class SyncService {
  /// Emits sync pipeline status for UI diagnostics and retries.
  ///
  /// Strategy:
  /// - Queue saves while offline.
  /// - Retry queued sessions on reconnect.
  /// - Resolve conflicts with device-data-wins.
  Stream<SyncQueueStatus> get syncStatus;

  /// Adds a session identifier to the outbound sync queue.
  Future<void> queueForSync(int sessionId);

  /// Processes queued sessions.
  Future<void> processQueue();

  /// Deletes a remote activity and best-effort related storage assets.
  Future<void> deleteRemoteActivity(String remoteActivityId);
}

/// NOTE(stuart): Document StubSyncService.
class StubSyncService implements SyncService {
  const StubSyncService();

  @override
  Stream<SyncQueueStatus> get syncStatus => const Stream.empty();

  @override
  Future<void> queueForSync(int sessionId) async {
    return;
  }

  @override
  Future<void> processQueue() async {
    return;
  }

  @override
  Future<void> deleteRemoteActivity(String remoteActivityId) async {
    return;
  }
}

typedef ConnectivityCheck = Future<List<ConnectivityResult>> Function();
typedef UserIdProvider = String? Function();
typedef UuidGenerator = String Function();
typedef Clock = DateTime Function();

const String syncQueueTrackPointsLimitErrorMessage =
    'Activity exceeds the maximum track point limit.';
const String syncQueueActivitiesPerUserLimitErrorMessage =
    'Activity limit reached for this account.';
const _trackPointsPerActivityLimitToken = 'UFF_LIMIT_TRACK_POINTS_PER_ACTIVITY';
const _activitiesPerUserLimitToken = 'UFF_LIMIT_ACTIVITIES_PER_USER';

/// TODO: Document SupabaseSyncService.
class SupabaseSyncService implements SyncService {
  SupabaseSyncService({
    required TrackingRepository repository,
    required SupabaseClient supabaseClient,
    required Stream<List<ConnectivityResult>> connectivityChanges,
    required ConnectivityCheck checkConnectivity,
    UserIdProvider? currentUserIdProvider,
    UuidGenerator? uuidGenerator,
    Clock? now,
    int trackPointBatchSize = 1100,
    AppLogger? logger,
    TelemetryBreadcrumbRecorder? breadcrumbRecorder,
    PendingPhotoUploadService? pendingPhotoUploadService,
  }) : _repository = repository,
       _supabaseClient = supabaseClient,
       _connectivityChanges = connectivityChanges,
       _checkConnectivity = checkConnectivity,
       _currentUserIdProvider =
           currentUserIdProvider ?? (() => supabaseClient.auth.currentUser?.id),
       _uuidGenerator = uuidGenerator ?? generateUuidV4,
       _now = now ?? DateTime.now,
       _trackPointBatchSize = trackPointBatchSize,
       _logger = logger ?? AppLogger(),
       _pendingPhotoUploadService = pendingPhotoUploadService,
       _breadcrumbRecorder =
           breadcrumbRecorder ?? noopTelemetryBreadcrumbRecorder {
    if (_trackPointBatchSize <= 0 || _trackPointBatchSize > 1100) {
      throw ArgumentError.value(
        _trackPointBatchSize,
        'trackPointBatchSize',
        'Must be between 1 and 1100.',
      );
    }
    _remoteActivityDeleter = RemoteActivityDeleter(
      supabaseClient: _supabaseClient,
      currentUserIdProvider: _currentUserIdProvider,
      logger: _logger,
    );
    _connectivitySubscription = _connectivityChanges.listen(
      _handleConnectivityChange,
    );
    unawaited(_initializeConnectivityState());
  }

  final TrackingRepository _repository;
  final SupabaseClient _supabaseClient;
  final Stream<List<ConnectivityResult>> _connectivityChanges;
  final ConnectivityCheck _checkConnectivity;
  final UserIdProvider _currentUserIdProvider;
  final UuidGenerator _uuidGenerator;
  final Clock _now;
  final int _trackPointBatchSize;
  final AppLogger _logger;
  final PendingPhotoUploadService? _pendingPhotoUploadService;
  final TelemetryBreadcrumbRecorder _breadcrumbRecorder;
  late final RemoteActivityDeleter _remoteActivityDeleter;
  final StreamController<SyncQueueStatus> _syncStatusController =
      StreamController<SyncQueueStatus>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = false;
  bool _isProcessingQueue = false;
  bool _isDisposed = false;
  bool _shouldProcessQueuedEntriesAgain = false;

  @override
  Stream<SyncQueueStatus> get syncStatus => _syncStatusController.stream;

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _connectivitySubscription?.cancel();
    await _syncStatusController.close();
  }

  @override
  Future<void> queueForSync(int sessionId) async {
    _recordBoundaryBreadcrumb(
      message: 'sync.queue_for_sync',
      operation: 'queue_for_sync',
      sessionId: sessionId,
    );
    await _repository.upsertSyncQueueEntry(
      sessionId: sessionId,
      status: SyncQueueEntryStatus.queued,
      queuedAt: _now(),
      retryCount: 0,
    );
    _logger.logEvent(
      eventType: 'sync.queue.enqueue',
      outcome: 'queued',
      identifiers: {'session_id': sessionId},
    );
    if (_isProcessingQueue) {
      _shouldProcessQueuedEntriesAgain = true;
    }
    _emitSyncStatus(SyncQueueStatus.queued);

    if (await _isCurrentlyOnline()) {
      await processQueue();
    }
  }

  @override
  Future<void> processQueue() async {
    if (_isProcessingQueue || _isDisposed) {
      return;
    }
    _recordBoundaryBreadcrumb(
      message: 'sync.process_queue',
      operation: 'process_queue',
    );
    _isProcessingQueue = true;
    try {
      _logger.logEvent(
        eventType: 'sync.queue.process',
        outcome: 'start',
      );
      while (true) {
        _shouldProcessQueuedEntriesAgain = false;
        final pendingEntries = await _repository.loadPendingSyncQueueEntries();
        if (pendingEntries.isEmpty) {
          _emitIdleProcessEvent(pendingEntriesCount: 0);
          _emitSyncStatus(SyncQueueStatus.idle);
          return;
        }

        for (final pendingEntry in pendingEntries) {
          await _processQueueEntry(pendingEntry);
        }

        if (!_shouldProcessQueuedEntriesAgain || !await _isCurrentlyOnline()) {
          _emitIdleProcessEvent(
            pendingEntriesCount: await _currentPendingEntriesCount(),
          );
          _emitSyncStatus(SyncQueueStatus.idle);
          return;
        }
      }
    } on Object catch (error) {
      _logger.logEvent(
        eventType: 'sync.queue.process',
        outcome: 'failure',
        identifiers: {'reason': _syncFailureReason(error)},
      );
      rethrow;
    } finally {
      _isProcessingQueue = false;
    }
  }

  @override
  Future<void> deleteRemoteActivity(String remoteActivityId) =>
      _remoteActivityDeleter.deleteRemoteActivity(remoteActivityId);

  Future<void> _processQueueEntry(SyncQueueEntry entry) async {
    final latestQueuedEntry = await _repository.loadSyncQueueEntry(
      entry.sessionId,
    );
    if (latestQueuedEntry == null ||
        latestQueuedEntry.status != SyncQueueEntryStatus.queued) {
      return;
    }

    _recordBoundaryBreadcrumb(
      message: 'sync.process_queue_entry',
      operation: 'process_queue_entry',
      sessionId: latestQueuedEntry.sessionId,
    );

    _emitSyncStatus(SyncQueueStatus.processing);
    _logger.logEvent(
      eventType: 'sync.queue.entry',
      outcome: 'processing',
      identifiers: _entryIdentifiers(
        sessionId: latestQueuedEntry.sessionId,
        retryCount: latestQueuedEntry.retryCount,
      ),
    );
    await _repository.updateSyncQueueEntryStatus(
      sessionId: latestQueuedEntry.sessionId,
      status: SyncQueueEntryStatus.processing,
      retryCount: latestQueuedEntry.retryCount,
    );

    final stopwatch = Stopwatch()..start();
    try {
      final remoteId = await _syncEntry(latestQueuedEntry);
      if (await _wasRequeuedDuringProcessing(latestQueuedEntry.sessionId)) {
        _emitRequeuedEntryEvent(
          sessionId: latestQueuedEntry.sessionId,
          retryCount: latestQueuedEntry.retryCount,
          duration: _stopwatchElapsedAndStop(stopwatch),
        );
        _emitSyncStatus(SyncQueueStatus.queued);
        return;
      }
      await _repository.updateSyncQueueEntryStatus(
        sessionId: latestQueuedEntry.sessionId,
        status: SyncQueueEntryStatus.successful,
        retryCount: latestQueuedEntry.retryCount,
      );
      final duration = _stopwatchElapsedAndStop(stopwatch);
      _logger.logEvent(
        eventType: 'sync.queue.entry',
        outcome: 'success',
        duration: duration,
        identifiers: _entryIdentifiers(
          sessionId: latestQueuedEntry.sessionId,
          retryCount: latestQueuedEntry.retryCount,
        ),
      );
      _emitSyncStatus(SyncQueueStatus.successful);

      // Upload any photos captured during the recording session. This runs
      // after sync succeeds so the remoteId is available. Wrapped in
      // try/catch so photo upload failures never mark the sync as failed.
      try {
        await _pendingPhotoUploadService?.uploadPendingPhotos(
          sessionId: latestQueuedEntry.sessionId,
          remoteActivityId: remoteId,
        );
      } on Object catch (photoError) {
        _logger.logEvent(
          eventType: 'sync.pending_photo_upload',
          outcome: 'failure',
          identifiers: {
            'session_id': latestQueuedEntry.sessionId,
            'reason': photoError.runtimeType.toString(),
          },
        );
      }
    } on Object catch (error) {
      final duration = _stopwatchElapsedAndStop(stopwatch);
      if (await _wasRequeuedDuringProcessing(latestQueuedEntry.sessionId)) {
        _emitRequeuedEntryEvent(
          sessionId: latestQueuedEntry.sessionId,
          retryCount: latestQueuedEntry.retryCount,
          duration: duration,
        );
        _emitSyncStatus(SyncQueueStatus.queued);
        return;
      }
      final translatedError = _translateQueueFailure(error);
      final nextRetryCount = latestQueuedEntry.retryCount + 1;
      final failed = nextRetryCount >= 5;
      final failureReason = _syncFailureReason(error);
      await _repository.updateSyncQueueEntryStatus(
        sessionId: latestQueuedEntry.sessionId,
        status: failed
            ? SyncQueueEntryStatus.failed
            : SyncQueueEntryStatus.queued,
        retryCount: nextRetryCount,
        lastError: translatedError,
      );
      _logger.logEvent(
        eventType: failed ? 'sync.queue.failure' : 'sync.queue.retry',
        outcome: failed ? 'terminal' : 'scheduled',
        duration: duration,
        identifiers: _entryIdentifiers(
          sessionId: latestQueuedEntry.sessionId,
          retryCount: nextRetryCount,
          reason: failureReason,
        ),
      );
      _emitSyncStatus(failed ? SyncQueueStatus.failed : SyncQueueStatus.queued);
    }
  }

  Map<String, Object?> _entryIdentifiers({
    required int sessionId,
    required int retryCount,
    String? reason,
  }) {
    return <String, Object?>{
      'session_id': sessionId,
      'retry_count': retryCount,
      if (reason != null) 'reason': reason,
    };
  }

  void _emitRequeuedEntryEvent({
    required int sessionId,
    required int retryCount,
    required Duration duration,
  }) {
    _logger.logEvent(
      eventType: 'sync.queue.entry',
      outcome: 'requeued',
      duration: duration,
      identifiers: _entryIdentifiers(
        sessionId: sessionId,
        retryCount: retryCount,
      ),
    );
  }

  Duration _stopwatchElapsedAndStop(Stopwatch stopwatch) {
    if (stopwatch.isRunning) {
      stopwatch.stop();
    }
    return stopwatch.elapsed;
  }

  /// Syncs a single queue entry to Supabase. Returns the remoteId assigned
  /// to the activity, used by the caller to trigger pending photo uploads.
  Future<String> _syncEntry(SyncQueueEntry entry) async {
    final session = await _repository.loadSession(entry.sessionId);
    if (session == null) {
      throw StateError('Tracking session ${entry.sessionId} does not exist.');
    }

    final rawPoints = await _repository.loadPointsForSession(entry.sessionId);
    final cleanedPoints = cleanTrackingPoints(rawPoints).cleanedPoints;
    final processedMetrics = calculateProcessedActivityMetrics(
      session: session,
      cleanedPoints: cleanedPoints,
    );
    final remoteId = await _resolveRemoteId(session);
    final userId = _currentUserIdProvider();
    if (userId == null) {
      throw StateError('Cannot sync without an authenticated user.');
    }

    await _supabaseClient
        .from('activities')
        .upsert(
          buildActivityPayload(
            session: session,
            metrics: processedMetrics,
            cleanedPoints: cleanedPoints,
            remoteId: remoteId,
            userId: userId,
          ),
          onConflict: 'id',
        );

    await _supabaseClient
        .from('track_points')
        .delete()
        .eq('activity_id', remoteId);

    final trackPointRows = buildTrackPointRows(
      remoteId: remoteId,
      cleanedPoints: cleanedPoints,
    );
    for (final trackPointChunk in _chunk(
      trackPointRows,
      _trackPointBatchSize,
    )) {
      if (trackPointChunk.isEmpty) {
        continue;
      }
      await _supabaseClient.from('track_points').insert(trackPointChunk);
    }

    final splitRows = buildSplitRows(
      remoteId: remoteId,
      processedMetrics: processedMetrics,
    );
    if (splitRows.isNotEmpty) {
      await _supabaseClient
          .from('splits')
          .upsert(
            splitRows,
            onConflict: 'activity_id,split_number',
          );
    }

    return remoteId;
  }

  Future<String> _resolveRemoteId(TrackingSessionRecord session) async {
    final existingRemoteId = session.remoteId;
    if (existingRemoteId != null && existingRemoteId.isNotEmpty) {
      return existingRemoteId;
    }

    final generatedRemoteId = _uuidGenerator();
    await _repository.updateSessionRemoteId(session.id, generatedRemoteId);
    return generatedRemoteId;
  }

  Iterable<List<T>> _chunk<T>(List<T> items, int chunkSize) sync* {
    if (items.isEmpty) {
      return;
    }
    for (var start = 0; start < items.length; start += chunkSize) {
      final end = min(start + chunkSize, items.length);
      yield items.sublist(start, end);
    }
  }

  Future<void> _initializeConnectivityState() async {
    final connectivity = await _checkConnectivity();
    _isOnline = _hasOnlineConnection(connectivity);
    if (_isOnline && !_isDisposed) {
      unawaited(processQueue());
    }
  }

  Future<bool> _isCurrentlyOnline() async {
    final connectivity = await _checkConnectivity();
    _isOnline = _hasOnlineConnection(connectivity);
    return _isOnline;
  }

  void _handleConnectivityChange(List<ConnectivityResult> connectivity) {
    final nowOnline = _hasOnlineConnection(connectivity);
    final justReconnected = !_isOnline && nowOnline;
    _isOnline = nowOnline;
    if (justReconnected) {
      unawaited(processQueue());
    }
  }

  bool _hasOnlineConnection(List<ConnectivityResult> connectivity) {
    const onlineConnectivityResults = {
      ConnectivityResult.mobile,
      ConnectivityResult.wifi,
      ConnectivityResult.ethernet,
      ConnectivityResult.bluetooth,
      ConnectivityResult.vpn,
      ConnectivityResult.other,
    };
    return connectivity.any(onlineConnectivityResults.contains);
  }

  Future<bool> _wasRequeuedDuringProcessing(int sessionId) async {
    final latestEntry = await _repository.loadSyncQueueEntry(sessionId);
    return latestEntry?.status == SyncQueueEntryStatus.queued;
  }

  String _translateQueueFailure(Object error) {
    final rawError = error.toString();
    if (rawError.contains(_trackPointsPerActivityLimitToken)) {
      return syncQueueTrackPointsLimitErrorMessage;
    }
    if (rawError.contains(_activitiesPerUserLimitToken)) {
      return syncQueueActivitiesPerUserLimitErrorMessage;
    }
    return rawError;
  }

  String _syncFailureReason(Object error) {
    final rawError = error.toString();
    if (rawError.contains(_trackPointsPerActivityLimitToken)) {
      return 'limit_track_points_per_activity';
    }
    if (rawError.contains(_activitiesPerUserLimitToken)) {
      return 'limit_activities_per_user';
    }
    if (error is StateError && rawError.contains('does not exist')) {
      return 'session_not_found';
    }
    if (error is StateError && rawError.contains('authenticated user')) {
      return 'unauthenticated_user';
    }
    return 'unknown';
  }

  Future<int> _currentPendingEntriesCount() async {
    final pendingEntries = await _repository.loadPendingSyncQueueEntries();
    return pendingEntries.length;
  }

  void _emitIdleProcessEvent({required int pendingEntriesCount}) {
    _logger.logEvent(
      eventType: 'sync.queue.process',
      outcome: 'idle',
      identifiers: {'pending_entries': pendingEntriesCount},
    );
  }

  void _emitSyncStatus(SyncQueueStatus status) {
    if (_syncStatusController.isClosed) {
      return;
    }
    _syncStatusController.add(status);
  }

  void _recordBoundaryBreadcrumb({
    required String message,
    required String operation,
    int? sessionId,
  }) {
    recordBoundaryTelemetryBreadcrumb(
      _breadcrumbRecorder,
      boundary: 'sync_service',
      operation: operation,
      message: message,
      metadata: <String, Object?>{
        if (sessionId != null) 'session_id': sessionId,
      },
    );
  }
}

final connectivityProvider = Provider<Connectivity>((_) => Connectivity());

final syncServiceProvider = Provider<SyncService>(
  (ref) {
    final supabaseClient = Supabase.instance.client;
    final connectivity = ref.read(connectivityProvider);
    // Wire the pending photo upload service so mid-run photos are uploaded
    // to Supabase after sync assigns a remoteId. Without this, the
    // _pendingPhotoUploadService field on SupabaseSyncService is null and
    // the ?.uploadPendingPhotos() call silently no-ops — meaning photos
    // captured during recording are stored locally but never uploaded.
    final pendingPhotoUploader = PendingPhotoUploadService(
      db: ref.read(trackingDatabaseProvider),
      photoRepository: ref.read(photoRepositoryProvider),
    );
    final service = SupabaseSyncService(
      repository: ref.read(trackingRepositoryProvider),
      supabaseClient: supabaseClient,
      connectivityChanges: connectivity.onConnectivityChanged,
      checkConnectivity: connectivity.checkConnectivity,
      breadcrumbRecorder: ref.read(telemetryBreadcrumbRecorderProvider),
      pendingPhotoUploadService: pendingPhotoUploader,
    );
    ref.onDispose(service.dispose);
    return service;
  },
);

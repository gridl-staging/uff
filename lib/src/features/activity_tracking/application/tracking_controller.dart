import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/activity_tracking/application/draft_activity_actions.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/data/permission_service.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart'
    as tracking_domain;
import 'package:uff/src/features/activity_tracking/domain/tracking_engine.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_repository.dart';

export 'tracking_dependencies.dart'
    show
        trackingDatabaseProvider,
        trackingEngineProvider,
        trackingPermissionServiceProvider,
        trackingRepositoryProvider;

part 'session_restorer.dart';

final recordingControllerProvider =
    NotifierProvider<RecordingController, RecordingControllerState>(
      RecordingController.new,
    );

/// NOTE(stuart): Document RecordingTimeline.
@immutable
class RecordingTimeline {
  const RecordingTimeline({
    required this.activeDuration,
    this.segmentStartTimestamp,
    this.lastFixTimestamp,
    this.lastAccuracy,
  });

  const RecordingTimeline.idle()
    : activeDuration = Duration.zero,
      segmentStartTimestamp = null,
      lastFixTimestamp = null,
      lastAccuracy = null;

  final Duration activeDuration;
  final DateTime? segmentStartTimestamp;
  final DateTime? lastFixTimestamp;
  final double? lastAccuracy;

  Duration elapsed({required DateTime now}) {
    final currentSegment = segmentStartTimestamp == null
        ? Duration.zero
        : now.difference(segmentStartTimestamp!);
    return activeDuration + currentSegment;
  }

  RecordingTimeline beginSegment(DateTime startedAt) {
    return RecordingTimeline(
      activeDuration: activeDuration,
      segmentStartTimestamp: startedAt,
      lastFixTimestamp: lastFixTimestamp,
      lastAccuracy: lastAccuracy,
    );
  }

  RecordingTimeline closeSegment(DateTime endedAt) {
    final updatedDuration = segmentStartTimestamp == null
        ? activeDuration
        : activeDuration + endedAt.difference(segmentStartTimestamp!);
    return RecordingTimeline(
      activeDuration: updatedDuration,
      lastFixTimestamp: lastFixTimestamp,
      lastAccuracy: lastAccuracy,
    );
  }

  RecordingTimeline withLastFix(DateTime fixTimestamp, {double? accuracy}) {
    return RecordingTimeline(
      activeDuration: activeDuration,
      segmentStartTimestamp: segmentStartTimestamp,
      lastFixTimestamp: fixTimestamp,
      lastAccuracy: accuracy,
    );
  }

  RecordingTimeline clearLastFix() {
    return RecordingTimeline(
      activeDuration: activeDuration,
      segmentStartTimestamp: segmentStartTimestamp,
    );
  }
}

@immutable
class RecordingErrorState {
  const RecordingErrorState({required this.message});

  const RecordingErrorState.none() : message = null;

  final String? message;
}

/// NOTE(stuart): Document RecordingControllerState.
@immutable
class RecordingControllerState {
  const RecordingControllerState({
    required this.status,
    required this.points,
    required this.timeline,
    this.session,
    this.errorState = const RecordingErrorState.none(),
  });

  const RecordingControllerState.idle()
    : status = tracking_domain.TrackingSessionStatus.idle,
      points = const [],
      timeline = const RecordingTimeline.idle(),
      session = null,
      errorState = const RecordingErrorState.none();

  final tracking_domain.TrackingSessionStatus status;
  final tracking_domain.TrackingSessionRecord? session;
  final List<tracking_domain.TrackingPoint> points;
  final RecordingTimeline timeline;
  final RecordingErrorState errorState;

  int get pointCount => points.length;
  Duration get activeDuration => timeline.activeDuration;
  DateTime? get segmentStartTimestamp => timeline.segmentStartTimestamp;
  DateTime? get lastFixTimestamp => timeline.lastFixTimestamp;
  double? get lastAccuracy => timeline.lastAccuracy;
  tracking_domain.GpsSignalQuality get gpsSignalQuality =>
      tracking_domain.classifyGpsAccuracy(timeline.lastAccuracy);
  String? get errorMessage => errorState.message;

  Duration elapsed({required DateTime now}) => timeline.elapsed(now: now);

  RecordingControllerState copyWith({
    tracking_domain.TrackingSessionStatus? status,
    tracking_domain.TrackingSessionRecord? session,
    List<tracking_domain.TrackingPoint>? points,
    RecordingTimeline? timeline,
    RecordingErrorState? errorState,
  }) {
    return RecordingControllerState(
      status: status ?? this.status,
      session: session ?? this.session,
      points: points ?? this.points,
      timeline: timeline ?? this.timeline,
      errorState: errorState ?? this.errorState,
    );
  }
}

// TODO(uff): Document RecordingController.
/// TODO: Document RecordingController.
class RecordingController extends Notifier<RecordingControllerState> {
  static const _backgroundLocationWarning =
      'Background location access is off. Recording started, but it may stop '
      'when the app is in the background or the phone is locked. Enable '
      '"Always" in Settings for full run tracking.';

  late TrackingRepository _repository;
  late TrackingPermissionService _permissionService;
  late TrackingEngine _trackingEngine;
  late SyncService _syncService;
  late SessionRestorer _sessionRestorer;

  StreamSubscription<tracking_domain.TrackingPoint>? _pointSubscription;
  StreamSubscription<TrackingEngineStatus>? _engineStatusSubscription;
  Timer? _elapsedTimer;
  bool _isInitializing = false;
  bool _isDisposed = false;

  bool get _isRunning =>
      state.status == tracking_domain.TrackingSessionStatus.recording;

  @override
  RecordingControllerState build() {
    _isInitializing = false;
    _isDisposed = false;
    _repository = ref.read(trackingRepositoryProvider);
    _permissionService = ref.read(trackingPermissionServiceProvider);
    _trackingEngine = ref.read(trackingEngineProvider);
    _syncService = ref.read(syncServiceProvider);
    _sessionRestorer = SessionRestorer(
      repository: _repository,
      trackingEngine: _trackingEngine,
    );
    ref.onDispose(_handleDispose);

    _initialize(initialErrorState: const RecordingErrorState.none());
    return const RecordingControllerState.idle();
  }

  /// Bootstraps the recording controller. This runs once when the provider
  /// is first read. Order matters: subscribe to engine streams before the
  /// async restore so that GPS samples arriving mid-restore are not lost,
  /// then restore any in-flight session from Drift, then start the
  /// elapsed-time ticker for the UI.
  Future<void> _initialize({
    required RecordingErrorState initialErrorState,
  }) async {
    if (_isInitializing || _isDisposed) {
      return;
    }

    _isInitializing = true;
    try {
      _wireEngineStreams();
      await _sessionRestorer.restore(
        currentErrorState: initialErrorState,
        applyState: (restoredState) => state = restoredState,
      );
      _startElapsedTicker();
    } on Object catch (error) {
      setErrorMessage('Unable to initialize tracking state: $error');
    } finally {
      _isInitializing = false;
    }
  }

  /// Subscribes to the native tracking engine's GPS sample stream and
  /// error status stream. Cancels existing subscriptions first so this
  /// is safe to call during re-initialization.
  void _wireEngineStreams() {
    _pointSubscription?.cancel();
    _pointSubscription = _trackingEngine.sampleStream.listen(_appendPoint);

    _engineStatusSubscription?.cancel();
    _engineStatusSubscription = _trackingEngine.statusStream.listen((
      engineStatus,
    ) {
      if (engineStatus == TrackingEngineStatus.error) {
        setErrorMessage('Tracking service reported an error.');
      }
    });
  }

  Future<void> _appendPoint(tracking_domain.TrackingPoint sample) async {
    final sessionId = state.session?.id;
    if (sessionId == null || sample.sessionId != sessionId) {
      return;
    }

    final updatedPoints = [...state.points, sample];
    state = state.copyWith(
      points: updatedPoints,
      timeline: state.timeline.withLastFix(
        sample.timestamp,
        accuracy: sample.accuracy,
      ),
      errorState: const RecordingErrorState.none(),
    );
    try {
      await _repository.appendPointBatch([sample]);
    } on Object catch (error) {
      setErrorMessage('Unable to persist tracking point: $error');
    }
  }

  /// Persists and applies a state machine transition. The session row is
  /// written to Drift first (crash safety), then in-memory state is updated.
  ///
  /// Timeline management: starting/resuming a recording begins a new
  /// active-duration segment; pausing/stopping closes the current segment.
  /// startedAt is set only on the first recording transition; stoppedAt
  /// only on the stopped transition.
  Future<void> _checkpointSessionState(
    tracking_domain.TrackingSessionStatus nextStatus,
    DateTime now,
  ) async {
    final session = state.session;
    if (session == null) {
      return;
    }

    await _repository.updateSessionStatus(session.id, nextStatus, now);
    // Only set startedAt on the very first recording transition.
    final startedAt =
        nextStatus == tracking_domain.TrackingSessionStatus.recording &&
            session.startedAt == null
        ? now
        : session.startedAt;
    final stoppedAt =
        nextStatus == tracking_domain.TrackingSessionStatus.stopped
        ? now
        : session.stoppedAt;
    // Begin a new elapsed-time segment on resume/start; close on pause/stop.
    final nextTimeline =
        nextStatus == tracking_domain.TrackingSessionStatus.recording
        ? state.timeline.beginSegment(now)
        : state.timeline.closeSegment(now);
    state = state.copyWith(
      session: session.copyWith(
        status: nextStatus,
        updatedAt: now,
        startedAt: startedAt,
        stoppedAt: stoppedAt,
      ),
      status: nextStatus,
      timeline: nextTimeline,
      errorState: const RecordingErrorState.none(),
    );
  }

  void _ensureValidTransition(
    tracking_domain.TrackingSessionStatus nextStatus,
  ) {
    final transition = tracking_domain.TrackingStateTransition(
      from: state.status,
      to: nextStatus,
    );
    if (!transition.isAllowed) {
      throw tracking_domain.InvalidTrackingTransition(transition);
    }
  }

  Future<void> startRecording() async {
    _ensureValidTransition(tracking_domain.TrackingSessionStatus.recording);

    final foregroundPermission = await _permissionService
        .ensureForegroundPermission();
    if (foregroundPermission != TrackingPermissionDecision.granted) {
      final message = switch (foregroundPermission) {
        TrackingPermissionDecision.denied =>
          'Location permission was denied. Allow location access to start recording.',
        TrackingPermissionDecision.deniedPermanently =>
          'Location permission is permanently denied. Open app settings.',
        _ => 'Foreground location permission is required.',
      };
      setErrorMessage(message);
      return;
    }

    final backgroundPermission = await _permissionService
        .ensureBackgroundPermission();
    final backgroundWarning =
        backgroundPermission == TrackingPermissionDecision.granted
        ? null
        : _backgroundLocationWarning;

    tracking_domain.TrackingSessionRecord? createdSession;
    try {
      createdSession = await _repository.createSession();
      final startedAt = DateTime.now();
      state = state.copyWith(
        status: tracking_domain.TrackingSessionStatus.recording,
        session: createdSession,
        points: const [],
        timeline: const RecordingTimeline.idle().beginSegment(startedAt),
        errorState: const RecordingErrorState.none(),
      );

      await _checkpointSessionState(
        tracking_domain.TrackingSessionStatus.recording,
        startedAt,
      );
      await _trackingEngine.start(createdSession.id);
      if (backgroundWarning != null) {
        setErrorMessage(backgroundWarning);
      }
    } on Object catch (error) {
      var cleanupErrorSuffix = '';
      if (createdSession != null) {
        try {
          await _repository.discardSession(createdSession.id);
        } on Object catch (cleanupError) {
          cleanupErrorSuffix = ' Cleanup failed: $cleanupError';
        }
      }
      state = const RecordingControllerState.idle().copyWith(
        errorState: RecordingErrorState(
          message: 'Unable to start recording: $error$cleanupErrorSuffix',
        ),
      );
    }
  }

  Future<void> pauseRecording() async {
    _ensureValidTransition(tracking_domain.TrackingSessionStatus.paused);
    try {
      final pauseTime = DateTime.now();
      await _trackingEngine.pause();

      await _checkpointSessionState(
        tracking_domain.TrackingSessionStatus.paused,
        pauseTime,
      );
    } on Object catch (error) {
      setErrorMessage('Unable to pause recording: $error');
    }
  }

  Future<void> resumeRecording() async {
    _ensureValidTransition(tracking_domain.TrackingSessionStatus.recording);
    try {
      final resumeAt = DateTime.now();
      await _trackingEngine.resume();

      await _checkpointSessionState(
        tracking_domain.TrackingSessionStatus.recording,
        resumeAt,
      );
    } on Object catch (error) {
      setErrorMessage('Unable to resume recording: $error');
    }
  }

  Future<void> stopRecording() async {
    _ensureValidTransition(tracking_domain.TrackingSessionStatus.stopped);
    try {
      final stoppedAt = DateTime.now();

      await _trackingEngine.stop();
      await _checkpointSessionState(
        tracking_domain.TrackingSessionStatus.stopped,
        stoppedAt,
      );
    } on Object catch (error) {
      setErrorMessage('Unable to stop recording: $error');
    }
  }

  /// UI-facing alias for ending a run.
  ///
  /// The controller still uses `stopped` internally because that status is the
  /// terminal point before save or discard. The screen label says "Finish"
  /// because that is the user mental model we want to preserve.
  Future<void> finishRecording() => stopRecording();

  Future<int?> saveRecording() async {
    final session = state.session;
    if (session == null) {
      return null;
    }

    _ensureValidTransition(tracking_domain.TrackingSessionStatus.saving);

    final cleanedPoints = cleanTrackingPoints(state.points).cleanedPoints;
    final savedSessionId = session.id;

    try {
      state = state.copyWith(
        status: tracking_domain.TrackingSessionStatus.saving,
        session: session.copyWith(
          status: tracking_domain.TrackingSessionStatus.saving,
          updatedAt: DateTime.now(),
        ),
        errorState: const RecordingErrorState.none(),
      );
      await finalizeDraftActivity(
        repository: _repository,
        syncService: _syncService,
        session: session,
        cleanedPoints: cleanedPoints,
      );
      state = const RecordingControllerState.idle();
      return savedSessionId;
    } on Object catch (error) {
      final restoreTimestamp = DateTime.now();
      await _repository.updateSessionStatus(
        savedSessionId,
        tracking_domain.TrackingSessionStatus.stopped,
        restoreTimestamp,
      );
      final restoredSession = await _repository.loadSession(savedSessionId);
      state = state.copyWith(
        status: tracking_domain.TrackingSessionStatus.stopped,
        session: restoredSession?.copyWith(
          status: tracking_domain.TrackingSessionStatus.stopped,
        ),
        errorState: RecordingErrorState(
          message: 'Unable to save recording: $error',
        ),
      );
      return null;
    }
  }

  Future<void> discardRecording() async {
    _ensureValidTransition(tracking_domain.TrackingSessionStatus.discarded);

    final session = state.session;
    if (session == null) {
      return;
    }

    try {
      final now = DateTime.now();
      await _checkpointSessionState(
        tracking_domain.TrackingSessionStatus.discarded,
        now,
      );
      await _repository.discardSession(session.id);
      state = const RecordingControllerState.idle();
    } on Object catch (error) {
      setErrorMessage('Unable to discard recording: $error');
    }
  }

  void _startElapsedTicker() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isDisposed || !_isRunning) {
        return;
      }

      state = state.copyWith();
    });
  }

  void setErrorMessage(String message) {
    state = state.copyWith(errorState: RecordingErrorState(message: message));
  }

  void clearError() {
    state = state.copyWith(errorState: const RecordingErrorState.none());
  }

  void _handleDispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;

    _pointSubscription?.cancel();
    _engineStatusSubscription?.cancel();
    _elapsedTimer?.cancel();
    // Do NOT dispose the shared tracking engine here. The engine's lifecycle
    // is owned by trackingEngineProvider, not by this controller. Disposing
    // it here causes the next controller rebuild (after provider invalidation)
    // to bind to an already-disposed TraceletTrackingEngine.
  }
}

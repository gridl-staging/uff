import 'dart:async';

/// TODO: Document TelemetryFlushScheduler.
class TelemetryFlushScheduler {
  TelemetryFlushScheduler({
    required Future<Duration?> Function() flush,
  }) : _flush = flush;

  final Future<Duration?> Function() _flush;
  Timer? _pendingTimer;
  bool _isFlushInFlight = false;
  bool _flushRequestedWhileInFlight = false;
  bool _isDisposed = false;

  /// Trigger an immediate flush (used at startup and on app resume).
  ///
  /// If a flush is already in-flight, the request is deferred until the current
  /// flush completes. Only one deferred request is tracked — multiple resume
  /// events during a single flush collapse into one follow-up flush.
  void start() {
    _requestFlush();
  }

  /// Trigger a flush, typically from an app-resume lifecycle event.
  void triggerFlush() {
    _requestFlush();
  }

  /// Cancel any pending timer. Safe to call multiple times.
  void dispose() {
    _isDisposed = true;
    _cancelTimer();
  }

  void _requestFlush() {
    if (_isDisposed) {
      return;
    }
    if (_isFlushInFlight) {
      _flushRequestedWhileInFlight = true;
      return;
    }
    _runFlush();
  }

  void _runFlush() {
    if (_isDisposed) {
      return;
    }
    _beginFlush();

    // Wrap in try-catch so synchronous throws from _flush() also clear the
    // in-flight guard. Without this, a sync throw skips the .catchError chain
    // and leaves _isFlushInFlight permanently true.
    final Future<Duration?> flushFuture;
    try {
      flushFuture = _flush();
    } on Object {
      _completeFlush();
      return;
    }

    flushFuture.then(_completeFlush).catchError((Object _) => _completeFlush());
  }

  void _beginFlush() {
    _cancelTimer();
    _isFlushInFlight = true;
    _flushRequestedWhileInFlight = false;
  }

  void _completeFlush([Duration? nextEligibleIn]) {
    _isFlushInFlight = false;
    if (_isDisposed) {
      _flushRequestedWhileInFlight = false;
      return;
    }
    if (_flushRequestedWhileInFlight) {
      _flushRequestedWhileInFlight = false;
      _runFlush();
      return;
    }
    if (nextEligibleIn != null) {
      _pendingTimer = Timer(nextEligibleIn, _runFlush);
    }
  }

  void _cancelTimer() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
  }
}

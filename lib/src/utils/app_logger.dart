import 'dart:convert';
import 'dart:developer' as developer;

typedef AppLogSink = void Function(Map<String, Object?> event);
typedef AppLoggerClock = DateTime Function();
typedef AppLogIdentifiersBuilder<T> = Map<String, Object?> Function(T value);

/// Structured logger contract for app-level operational events.
///
/// Event payloads are intentionally constrained to:
/// - `event_type`
/// - `outcome`
/// - `duration_ms` (optional)
/// - `identifiers` (optional stable scalar values only)
class AppLogger {
  AppLogger({
    AppLogSink? sink,
    AppLoggerClock? now,
  }) : _sink = sink ?? _defaultAppLogSink,
       _now = now ?? DateTime.now;

  final AppLogSink _sink;
  final AppLoggerClock _now;

  void logEvent({
    required String eventType,
    required String outcome,
    Duration? duration,
    Map<String, Object?> identifiers = const {},
  }) {
    _validateIdentifiers(identifiers);
    final event = <String, Object?>{
      'event_type': eventType,
      'outcome': outcome,
      if (duration != null) 'duration_ms': duration.inMilliseconds,
      if (identifiers.isNotEmpty)
        'identifiers': Map<String, Object?>.unmodifiable(
          Map<String, Object?>.from(identifiers),
        ),
    };
    _sink(Map<String, Object?>.unmodifiable(event));
  }

  Future<T> runWithTiming<T>({
    required String eventType,
    required String successOutcome,
    required String failureOutcome,
    required Future<T> Function() operation,
    Map<String, Object?> identifiers = const {},
    AppLogIdentifiersBuilder<T>? successIdentifiers,
    AppLogIdentifiersBuilder<Object>? failureIdentifiers,
  }) async {
    final startedAt = _now();
    try {
      final value = await operation();
      final duration = _now().difference(startedAt);
      final eventIdentifiers = <String, Object?>{
        ...identifiers,
        if (successIdentifiers != null) ...successIdentifiers(value),
      };
      logEvent(
        eventType: eventType,
        outcome: successOutcome,
        duration: duration,
        identifiers: eventIdentifiers,
      );
      return value;
    } on Object catch (error) {
      final duration = _now().difference(startedAt);
      final eventIdentifiers = <String, Object?>{
        ...identifiers,
        if (failureIdentifiers != null) ...failureIdentifiers(error),
      };
      logEvent(
        eventType: eventType,
        outcome: failureOutcome,
        duration: duration,
        identifiers: eventIdentifiers,
      );
      rethrow;
    }
  }

  void _validateIdentifiers(Map<String, Object?> identifiers) {
    for (final entry in identifiers.entries) {
      if (_isStableIdentifierValue(entry.value)) {
        continue;
      }
      throw ArgumentError.value(
        entry.value,
        entry.key,
        'Identifier values must be null, bool, finite num, or String.',
      );
    }
  }

  bool _isStableIdentifierValue(Object? value) {
    if (value == null || value is bool || value is String) {
      return true;
    }
    if (value is num) {
      return value.isFinite;
    }
    return false;
  }
}

void _defaultAppLogSink(Map<String, Object?> event) {
  developer.log(
    jsonEncode(event),
    name: 'uff.app',
  );
}

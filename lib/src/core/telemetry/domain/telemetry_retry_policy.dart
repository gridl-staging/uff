import 'dart:math' as math;

/// Single source of truth for telemetry retry eligibility, backoff, and
/// tombstoning thresholds. Pure class with no dependencies.
class TelemetryRetryPolicy {
  const TelemetryRetryPolicy();

  /// Base delay before the first retry (doubles per subsequent attempt).
  static const Duration baseDelay = Duration(seconds: 30);

  /// Maximum backoff cap regardless of attempt count.
  static const Duration maxBackoff = Duration(seconds: 300);

  /// Rows with this many or more attempts are tombstoned (deleted without
  /// upload).
  static const int maxAttempts = 5;

  /// Whether a row should be permanently deleted without further upload
  /// attempts.
  bool shouldTombstone({required int attemptCount}) {
    return attemptCount >= maxAttempts;
  }

  /// Whether a row is eligible for an upload attempt right now.
  ///
  /// Never-attempted rows (null [lastAttemptedAt]) are always eligible.
  /// Otherwise, the row must have waited at least [backoffDuration] since its
  /// last attempt.
  bool isEligible({
    required int attemptCount,
    required DateTime? lastAttemptedAt,
    required DateTime now,
  }) {
    if (lastAttemptedAt == null) {
      return true;
    }

    final requiredBackoff = backoffDuration(attemptCount: attemptCount);
    final elapsed = now.difference(lastAttemptedAt);
    return elapsed >= requiredBackoff;
  }

  /// Computes the backoff duration for a given attempt count.
  ///
  /// Returns [Duration.zero] for zero attempts (never attempted).
  /// Uses exponential backoff: `baseDelay * 2^(attemptCount - 1)`, capped at
  /// [maxBackoff].
  Duration backoffDuration({required int attemptCount}) {
    if (attemptCount <= 0) {
      return Duration.zero;
    }

    final exponent = attemptCount - 1;
    final multiplier = math.pow(2, exponent).toInt();
    final uncappedMs = baseDelay.inMilliseconds * multiplier;
    final cappedMs = math.min(uncappedMs, maxBackoff.inMilliseconds);
    return Duration(milliseconds: cappedMs);
  }
}

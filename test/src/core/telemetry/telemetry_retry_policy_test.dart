import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/core/telemetry/domain/telemetry_retry_policy.dart';

void main() {
  group('TelemetryRetryPolicy', () {
    const policy = TelemetryRetryPolicy();

    group('shouldTombstone', () {
      test('returns true when attemptCount equals maxAttempts', () {
        expect(
          policy.shouldTombstone(
            attemptCount: TelemetryRetryPolicy.maxAttempts,
          ),
          isTrue,
        );
      });

      test('returns true when attemptCount exceeds maxAttempts', () {
        expect(
          policy.shouldTombstone(
            attemptCount: TelemetryRetryPolicy.maxAttempts + 1,
          ),
          isTrue,
        );
      });

      test('returns false when attemptCount is below maxAttempts', () {
        expect(
          policy.shouldTombstone(
            attemptCount: TelemetryRetryPolicy.maxAttempts - 1,
          ),
          isFalse,
        );
      });

      test('returns false when attemptCount is zero', () {
        expect(policy.shouldTombstone(attemptCount: 0), isFalse);
      });
    });

    group('isEligible', () {
      test('returns true when lastAttemptedAt is null (never attempted)', () {
        expect(
          policy.isEligible(
            attemptCount: 0,
            lastAttemptedAt: null,
            now: DateTime.utc(2026, 3, 26, 12),
          ),
          isTrue,
        );
      });

      test('returns true when backoff window has elapsed', () {
        final lastAttemptedAt = DateTime.utc(2026, 3, 26, 12);
        // attemptCount=1 → backoff = 30s base delay
        // 31 seconds later → eligible
        final now = lastAttemptedAt.add(const Duration(seconds: 31));

        expect(
          policy.isEligible(
            attemptCount: 1,
            lastAttemptedAt: lastAttemptedAt,
            now: now,
          ),
          isTrue,
        );
      });

      test('returns false when inside backoff window', () {
        final lastAttemptedAt = DateTime.utc(2026, 3, 26, 12);
        // attemptCount=1 → backoff = 30s
        // Only 10 seconds later → not eligible
        final now = lastAttemptedAt.add(const Duration(seconds: 10));

        expect(
          policy.isEligible(
            attemptCount: 1,
            lastAttemptedAt: lastAttemptedAt,
            now: now,
          ),
          isFalse,
        );
      });

      test('exponential backoff doubles per attempt', () {
        final lastAttemptedAt = DateTime.utc(2026, 3, 26, 12);

        // attemptCount=1 → 30s backoff
        expect(
          policy.isEligible(
            attemptCount: 1,
            lastAttemptedAt: lastAttemptedAt,
            now: lastAttemptedAt.add(const Duration(seconds: 30)),
          ),
          isTrue,
        );

        // attemptCount=2 → 60s backoff
        expect(
          policy.isEligible(
            attemptCount: 2,
            lastAttemptedAt: lastAttemptedAt,
            now: lastAttemptedAt.add(const Duration(seconds: 59)),
          ),
          isFalse,
        );
        expect(
          policy.isEligible(
            attemptCount: 2,
            lastAttemptedAt: lastAttemptedAt,
            now: lastAttemptedAt.add(const Duration(seconds: 60)),
          ),
          isTrue,
        );

        // attemptCount=3 → 120s backoff
        expect(
          policy.isEligible(
            attemptCount: 3,
            lastAttemptedAt: lastAttemptedAt,
            now: lastAttemptedAt.add(const Duration(seconds: 119)),
          ),
          isFalse,
        );
        expect(
          policy.isEligible(
            attemptCount: 3,
            lastAttemptedAt: lastAttemptedAt,
            now: lastAttemptedAt.add(const Duration(seconds: 120)),
          ),
          isTrue,
        );
      });

      test('backoff caps at maxBackoff regardless of attempt count', () {
        final lastAttemptedAt = DateTime.utc(2026, 3, 26, 12);
        // With base=30s, cap=300s (5min), attempt 10 would be 30*2^9 = 15360s
        // but should be capped at 300s
        final justBeforeCap = lastAttemptedAt.add(const Duration(seconds: 299));
        final atCap = lastAttemptedAt.add(const Duration(seconds: 300));

        expect(
          policy.isEligible(
            attemptCount: 10,
            lastAttemptedAt: lastAttemptedAt,
            now: justBeforeCap,
          ),
          isFalse,
        );
        expect(
          policy.isEligible(
            attemptCount: 10,
            lastAttemptedAt: lastAttemptedAt,
            now: atCap,
          ),
          isTrue,
        );
      });
    });

    group('backoffDuration', () {
      test('returns base delay for first attempt', () {
        expect(
          policy.backoffDuration(attemptCount: 1),
          TelemetryRetryPolicy.baseDelay,
        );
      });

      test('returns zero for zero attempts (never attempted)', () {
        expect(
          policy.backoffDuration(attemptCount: 0),
          Duration.zero,
        );
      });

      test('doubles per attempt from base', () {
        expect(
          policy.backoffDuration(attemptCount: 2),
          const Duration(seconds: 60),
        );
        expect(
          policy.backoffDuration(attemptCount: 3),
          const Duration(seconds: 120),
        );
        expect(
          policy.backoffDuration(attemptCount: 4),
          const Duration(seconds: 240),
        );
      });

      test('caps at maxBackoff', () {
        expect(
          policy.backoffDuration(attemptCount: 10),
          TelemetryRetryPolicy.maxBackoff,
        );
      });
    });
  });
}

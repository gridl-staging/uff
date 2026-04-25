import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/core/telemetry/service/telemetry_flush_scheduler.dart';

/// ## Test Scenarios
/// - [positive] start() triggers an immediate flush
/// - [positive] start() arms a one-shot timer when flush returns a non-null duration
/// - [positive] triggerFlush() triggers an immediate flush (app resume)
/// - [positive] one-shot timer fires and triggers another flush
/// - [negative] overlapping flushes are suppressed while one is in-flight
/// - [negative] triggerFlush() during in-flight flush does not start a second flush
/// - [edge] flush returning null does not arm a timer
/// - [edge] timer from previous flush is cancelled when a new flush starts
/// - [error] flush throwing an exception is swallowed and clears in-flight guard
/// - [error] dispose cancels pending timer

void main() {
  group('TelemetryFlushScheduler', () {
    group('start()', () {
      test('triggers an immediate flush', () {
        fakeAsync((FakeAsync async) {
          var flushCallCount = 0;
          final scheduler = TelemetryFlushScheduler(
            flush: () async {
              flushCallCount += 1;
              return null;
            },
          );

          scheduler.start();
          async.flushMicrotasks();

          expect(flushCallCount, 1);
        });
      });

      test('arms a one-shot timer when flush returns a non-null duration', () {
        fakeAsync((FakeAsync async) {
          var flushCallCount = 0;
          final scheduler = TelemetryFlushScheduler(
            flush: () async {
              flushCallCount += 1;
              // First flush: come back in 30 seconds. Subsequent: no more.
              return flushCallCount == 1 ? const Duration(seconds: 30) : null;
            },
          );

          scheduler.start();
          async.flushMicrotasks();
          expect(flushCallCount, 1);

          // Timer fires at 30s, triggering a second flush.
          async.elapse(const Duration(seconds: 30));
          expect(flushCallCount, 2);
        });
      });

      test('does not arm a timer when flush returns null', () {
        fakeAsync((FakeAsync async) {
          var flushCallCount = 0;
          final scheduler = TelemetryFlushScheduler(
            flush: () async {
              flushCallCount += 1;
              return null;
            },
          );

          scheduler.start();
          async.flushMicrotasks();
          expect(flushCallCount, 1);

          // Elapse well beyond any plausible timer — count should not change.
          async.elapse(const Duration(minutes: 10));
          expect(flushCallCount, 1);
        });
      });
    });

    group('triggerFlush()', () {
      test('triggers an immediate flush for app resume', () {
        fakeAsync((FakeAsync async) {
          var flushCallCount = 0;
          final scheduler = TelemetryFlushScheduler(
            flush: () async {
              flushCallCount += 1;
              return null;
            },
          );

          scheduler.triggerFlush();
          async.flushMicrotasks();

          expect(flushCallCount, 1);
        });
      });

      test('cancels pending timer from previous flush', () {
        fakeAsync((FakeAsync async) {
          var flushCallCount = 0;
          final scheduler = TelemetryFlushScheduler(
            flush: () async {
              flushCallCount += 1;
              // Always request a 60s timer.
              return const Duration(seconds: 60);
            },
          );

          scheduler.start();
          async.flushMicrotasks();
          expect(flushCallCount, 1);

          // At 10s, trigger a resume flush — should cancel the 60s timer.
          async.elapse(const Duration(seconds: 10));
          scheduler.triggerFlush();
          async.flushMicrotasks();
          expect(flushCallCount, 2);

          // Original 60s timer would have fired at t=60s. At t=60s only the
          // new timer (from flush #2) should be pending at t=70s.
          async.elapse(const Duration(seconds: 50));
          // If old timer was NOT cancelled we'd see an extra flush at t=60.
          // Instead, the next flush fires at t=70 (10 + 60).
          expect(flushCallCount, 2);

          async.elapse(const Duration(seconds: 10));
          expect(flushCallCount, 3);
        });
      });
    });

    group('in-flight guard', () {
      test('suppresses overlapping flushes', () {
        fakeAsync((FakeAsync async) {
          var flushCallCount = 0;
          final flushCompleters = <Completer<Duration?>>[];

          final scheduler = TelemetryFlushScheduler(
            flush: () {
              flushCallCount += 1;
              final completer = Completer<Duration?>();
              flushCompleters.add(completer);
              return completer.future;
            },
          );

          scheduler.start();
          async.flushMicrotasks();
          expect(flushCallCount, 1);

          // Second call while first is in-flight — should be suppressed.
          scheduler.triggerFlush();
          async.flushMicrotasks();
          expect(flushCallCount, 1);

          // Complete first flush — guard clears.
          flushCompleters.first.complete(null);
          async.flushMicrotasks();

          // Now a new trigger should work.
          scheduler.triggerFlush();
          async.flushMicrotasks();
          expect(flushCallCount, 2);
        });
      });

      test('triggerFlush during in-flight schedules a deferred flush', () {
        fakeAsync((FakeAsync async) {
          var flushCallCount = 0;
          final flushCompleters = <Completer<Duration?>>[];

          final scheduler = TelemetryFlushScheduler(
            flush: () {
              flushCallCount += 1;
              final completer = Completer<Duration?>();
              flushCompleters.add(completer);
              return completer.future;
            },
          );

          // Start flush #1.
          scheduler.start();
          async.flushMicrotasks();
          expect(flushCallCount, 1);

          // Resume while in-flight — the scheduler should remember and flush
          // again after the current one completes.
          scheduler.triggerFlush();
          async.flushMicrotasks();
          expect(flushCallCount, 1);

          // Complete flush #1.
          flushCompleters[0].complete(null);
          async.flushMicrotasks();

          // Deferred flush should have fired.
          expect(flushCallCount, 2);
        });
      });
    });

    group('error handling', () {
      test('flush exception is swallowed and clears in-flight guard', () {
        fakeAsync((FakeAsync async) {
          var flushCallCount = 0;
          final scheduler = TelemetryFlushScheduler(
            flush: () async {
              flushCallCount += 1;
              if (flushCallCount == 1) {
                throw StateError('network failure');
              }
              return null;
            },
          );

          // First flush throws — should be swallowed.
          scheduler.start();
          async.flushMicrotasks();
          expect(flushCallCount, 1);

          // Guard should be cleared so a new flush can start.
          scheduler.triggerFlush();
          async.flushMicrotasks();
          expect(flushCallCount, 2);
        });
      });
    });

    group('dispose()', () {
      test('cancels pending timer', () {
        fakeAsync((FakeAsync async) {
          var flushCallCount = 0;
          final scheduler = TelemetryFlushScheduler(
            flush: () async {
              flushCallCount += 1;
              return const Duration(seconds: 30);
            },
          );

          scheduler.start();
          async.flushMicrotasks();
          expect(flushCallCount, 1);

          scheduler.dispose();

          // Timer should have been cancelled.
          async.elapse(const Duration(seconds: 60));
          expect(flushCallCount, 1);
        });
      });

      test(
        'does not arm a new timer after disposal while a flush is in flight',
        () {
          fakeAsync((FakeAsync async) {
            var flushCallCount = 0;
            final flushCompleter = Completer<Duration?>();
            final scheduler = TelemetryFlushScheduler(
              flush: () {
                flushCallCount += 1;
                return flushCompleter.future;
              },
            );

            scheduler.start();
            async.flushMicrotasks();
            expect(flushCallCount, 1);

            scheduler.dispose();
            flushCompleter.complete(const Duration(seconds: 30));
            async.flushMicrotasks();

            async.elapse(const Duration(seconds: 30));
            expect(flushCallCount, 1);
          });
        },
      );
    });
  });
}

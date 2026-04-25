import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/utils/app_logger.dart';

void main() {
  group('AppLogger.logEvent', () {
    test('emits only the allowed structured event fields', () {
      final events = <Map<String, Object?>>[];
      AppLogger(sink: events.add).logEvent(
        eventType: 'sync.queue.enqueue',
        outcome: 'queued',
        duration: const Duration(milliseconds: 125),
        identifiers: const {
          'session_id': 99,
          'retry_count': 0,
          'source': 'queue_for_sync',
        },
      );

      expect(events, hasLength(1));
      expect(
        events.single.keys.toSet(),
        {'event_type', 'outcome', 'duration_ms', 'identifiers'},
      );
      expect(events.single['event_type'], 'sync.queue.enqueue');
      expect(events.single['outcome'], 'queued');
      expect(events.single['duration_ms'], 125);
      expect(events.single['identifiers'], {
        'session_id': 99,
        'retry_count': 0,
        'source': 'queue_for_sync',
      });
    });

    test('rejects non-primitive identifier values', () {
      final logger = AppLogger();

      expect(
        () => logger.logEvent(
          eventType: 'sync.queue.enqueue',
          outcome: 'queued',
          identifiers: const {
            'session_id': 1,
            'unsupported': <String>['nested-values-are-not-stable'],
          },
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-finite numeric identifier values', () {
      final logger = AppLogger();

      expect(
        () => logger.logEvent(
          eventType: 'sync.queue.enqueue',
          outcome: 'queued',
          identifiers: const {'session_id': double.nan},
        ),
        throwsArgumentError,
      );
      expect(
        () => logger.logEvent(
          eventType: 'sync.queue.enqueue',
          outcome: 'queued',
          identifiers: const {'session_id': double.infinity},
        ),
        throwsArgumentError,
      );
    });
  });

  group('AppLogger.runWithTiming', () {
    test('captures duration for successful operations', () async {
      final events = <Map<String, Object?>>[];
      var now = DateTime.utc(2026, 3, 19, 12);
      final logger = AppLogger(
        sink: events.add,
        now: () => now,
      );

      final result = await logger.runWithTiming(
        eventType: 'import.pipeline.run',
        successOutcome: 'success',
        failureOutcome: 'failure',
        identifiers: const {'file_type': 'fit'},
        operation: () async {
          now = now.add(const Duration(milliseconds: 47));
          return 42;
        },
      );

      expect(result, 42);
      expect(events, hasLength(1));
      expect(events.single['event_type'], 'import.pipeline.run');
      expect(events.single['outcome'], 'success');
      expect(events.single['duration_ms'], 47);
      expect(events.single['identifiers'], {'file_type': 'fit'});
    });

    test(
      'captures duration and failure outcome for thrown operations',
      () async {
        final events = <Map<String, Object?>>[];
        var now = DateTime.utc(2026, 3, 19, 12, 0, 10);
        final logger = AppLogger(
          sink: events.add,
          now: () => now,
        );

        await expectLater(
          () => logger.runWithTiming<void>(
            eventType: 'auth.sign_in',
            successOutcome: 'success',
            failureOutcome: 'failure',
            identifiers: const {'provider': 'password'},
            operation: () async {
              now = now.add(const Duration(milliseconds: 12));
              throw StateError('nope');
            },
          ),
          throwsStateError,
        );

        expect(events, hasLength(1));
        expect(events.single['event_type'], 'auth.sign_in');
        expect(events.single['outcome'], 'failure');
        expect(events.single['duration_ms'], 12);
        expect(events.single['identifiers'], {'provider': 'password'});
      },
    );
  });
}

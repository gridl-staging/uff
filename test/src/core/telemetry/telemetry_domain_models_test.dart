import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/core/telemetry/domain/telemetry_breadcrumb.dart';
import 'package:uff/src/core/telemetry/domain/telemetry_context.dart';
import 'package:uff/src/core/telemetry/domain/telemetry_event.dart';

void main() {
  group('TelemetryContextEnvelope', () {
    test('toJson emits only app/build/platform envelope keys', () {
      const envelope = TelemetryContextEnvelope(
        appVersion: '1.2.3',
        buildNumber: '456',
        platform: 'ios',
      );

      expect(envelope.toJson(), <String, Object?>{
        'appVersion': '1.2.3',
        'buildNumber': '456',
        'platform': 'ios',
      });
    });
  });

  group('TelemetryBreadcrumb', () {
    test('serializes message, capturedAt, and metadata', () {
      final breadcrumb = TelemetryBreadcrumb(
        message: 'opened-settings',
        capturedAt: DateTime.utc(2026, 3, 25, 15, 30),
        metadata: const <String, Object?>{'screen': 'settings', 'step': 2},
      );

      expect(breadcrumb.toJson(), <String, Object?>{
        'message': 'opened-settings',
        'capturedAt': '2026-03-25T15:30:00.000Z',
        'metadata': const <String, Object?>{'screen': 'settings', 'step': 2},
      });
    });
  });

  group('QueuedTelemetryEvent', () {
    test(
      'forUnhandled applies row defaults and retains the newest 25 breadcrumbs',
      () {
        final breadcrumbs = List<TelemetryBreadcrumb>.generate(30, (int index) {
          return TelemetryBreadcrumb(
            message: 'crumb-$index',
            capturedAt: DateTime.utc(2026, 3, 25, 15, 0, index),
            metadata: <String, Object?>{'index': index},
          );
        });

        final event = QueuedTelemetryEvent.forUnhandled(
          eventId: 'event-0001',
          capturedAt: DateTime.utc(2026, 3, 25, 16),
          context: const TelemetryContextEnvelope(
            appVersion: '1.2.3',
            buildNumber: '456',
            platform: 'android',
          ),
          metadata: const <String, Object?>{'reason': 'retention-check'},
          breadcrumbs: breadcrumbs,
        );

        final row = event.toJson();
        expect(row.keys, <String>{
          'eventId',
          'capturedAt',
          'context',
          'metadata',
          'breadcrumbs',
          'attemptCount',
          'lastAttemptStatus',
          'lastAttemptedAt',
        });
        expect(row['attemptCount'], 0);
        expect(row['lastAttemptStatus'], 'never_attempted');
        expect(row['lastAttemptedAt'], isNull);

        final serializedBreadcrumbs = (row['breadcrumbs']! as List<Object?>)
            .cast<Map<String, Object?>>();
        final messages = serializedBreadcrumbs
            .map(
              (Map<String, Object?> breadcrumb) =>
                  breadcrumb['message']! as String,
            )
            .toList(growable: false);

        expect(messages, hasLength(25));
        expect(
          messages,
          equals(
            List<String>.generate(25, (int offset) => 'crumb-${offset + 5}'),
          ),
        );
      },
    );

    test(
      'toJson serializes non-null lastAttemptedAt in UTC ISO8601 format',
      () {
        final event = QueuedTelemetryEvent(
          eventId: 'event-0002',
          capturedAt: DateTime.utc(2026, 3, 25, 16, 5),
          context: const TelemetryContextEnvelope(
            appVersion: '1.2.3',
            buildNumber: '456',
            platform: 'ios',
          ),
          metadata: const <String, Object?>{'reason': 'retry'},
          breadcrumbs: const <TelemetryBreadcrumb>[],
          attemptCount: 2,
          lastAttemptStatus: 'failed',
          lastAttemptedAt: DateTime.utc(2026, 3, 25, 16, 4, 30),
        );

        final row = event.toJson();
        expect(row['lastAttemptedAt'], '2026-03-25T16:04:30.000Z');
      },
    );
  });
}

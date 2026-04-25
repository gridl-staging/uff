import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionException, FunctionResponse;
import 'package:uff/src/core/telemetry/data/supabase_telemetry_uploader.dart';

import 'telemetry_test_support.dart';

void main() {
  group('SupabaseTelemetryUploader.upload', () {
    test('returns true when invoke returns 200 with success true', () async {
      final uploader = SupabaseTelemetryUploader(
        invoke: (String name, {Object? body}) async {
          return FunctionResponse(
            status: 200,
            data: const <String, Object?>{'success': true},
          );
        },
      );
      final row = buildQueuedEventRow(
        eventId: 'event-success',
        capturedAt: '2026-03-26T00:00:00.000Z',
        breadcrumbs: const <JsonMap>[],
        metadata: const <String, Object?>{'message': 'ok'},
      );

      final uploaded = await uploader.upload(row);

      expect(uploaded, isTrue);
    });

    test('returns false when invoke returns 200 with success false', () async {
      final uploader = SupabaseTelemetryUploader(
        invoke: (String name, {Object? body}) async {
          return FunctionResponse(
            status: 200,
            data: const <String, Object?>{'success': false},
          );
        },
      );
      final row = buildQueuedEventRow(
        eventId: 'event-success-false',
        capturedAt: '2026-03-26T00:00:00.000Z',
        breadcrumbs: const <JsonMap>[],
        metadata: const <String, Object?>{'message': 'success-false'},
      );

      final uploaded = await uploader.upload(row);

      expect(uploaded, isFalse);
    });

    test('returns false when invoke returns non-200 status', () async {
      final uploader = SupabaseTelemetryUploader(
        invoke: (String name, {Object? body}) async {
          return FunctionResponse(
            status: 500,
            data: const <String, Object?>{'success': false},
          );
        },
      );
      final row = buildQueuedEventRow(
        eventId: 'event-non-200',
        capturedAt: '2026-03-26T00:00:00.000Z',
        breadcrumbs: const <JsonMap>[],
        metadata: const <String, Object?>{'message': 'non-200'},
      );

      final uploaded = await uploader.upload(row);

      expect(uploaded, isFalse);
    });

    test('returns false when invoke throws FunctionException', () async {
      final uploader = SupabaseTelemetryUploader(
        invoke: (String name, {Object? body}) async {
          throw const FunctionException(
            status: 500,
            details: <String, Object?>{'error': 'server'},
          );
        },
      );
      final row = buildQueuedEventRow(
        eventId: 'event-function-exception',
        capturedAt: '2026-03-26T00:00:00.000Z',
        breadcrumbs: const <JsonMap>[],
        metadata: const <String, Object?>{'message': 'function-exception'},
      );

      final uploaded = await uploader.upload(row);

      expect(uploaded, isFalse);
    });

    test('returns false when invoke throws arbitrary Exception', () async {
      final uploader = SupabaseTelemetryUploader(
        invoke: (String name, {Object? body}) async {
          throw Exception('network-down');
        },
      );
      final row = buildQueuedEventRow(
        eventId: 'event-generic-exception',
        capturedAt: '2026-03-26T00:00:00.000Z',
        breadcrumbs: const <JsonMap>[],
        metadata: const <String, Object?>{'message': 'generic-exception'},
      );

      final uploaded = await uploader.upload(row);

      expect(uploaded, isFalse);
    });

    test('invokes ingest-telemetry with the exact row as body', () async {
      String? capturedName;
      Object? capturedBody;
      final uploader = SupabaseTelemetryUploader(
        invoke: (String name, {Object? body}) async {
          capturedName = name;
          capturedBody = body;
          return FunctionResponse(
            status: 200,
            data: const <String, Object?>{'success': true},
          );
        },
      );
      final row = buildQueuedEventRow(
        eventId: 'event-args',
        capturedAt: '2026-03-26T00:00:00.000Z',
        breadcrumbs: const <JsonMap>[],
        metadata: const <String, Object?>{'message': 'args'},
      );

      final uploaded = await uploader.upload(row);

      expect(uploaded, isTrue);
      expect(capturedName, 'ingest-telemetry');
      expect(capturedBody, same(row));
    });
  });
}

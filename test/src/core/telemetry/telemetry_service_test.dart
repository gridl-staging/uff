import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/core/telemetry/domain/telemetry_scrubber.dart'
    show TelemetryScrubber;

import 'telemetry_test_support.dart';

void main() {
  group('TelemetryService.captureUnhandled', () {
    test(
      'persists one event row with eventId, capturedAt, shared context, and scrubbed scalar metadata',
      () async {
        final clock = FakeClock(DateTime.utc(2026, 3, 25, 14, 30));
        final store = FakeTelemetryStore();
        final uploader = FakeTelemetryUploader();
        final contextSource = FakeAppBuildPlatformContextSource(
          appVersion: '1.2.3',
          buildNumber: '456',
          platform: 'ios',
        );
        final scrubber = FakeTelemetryScrubber(
          scrubbedMetadata: <String, Object?>{
            'screen': 'run_tracking',
            'retryCount': 2,
            'isForeground': true,
          },
        );

        final service = buildTelemetryService(
          now: clock.now,
          eventIdFactory: buildEventIdGenerator(),
          store: store,
          uploader: uploader,
          contextSource: contextSource,
          scrubMetadata: scrubber.scrub,
          isTelemetryEnabled: () => true,
          isAuthAvailable: () => true,
        );

        await service.captureUnhandled(
          error: StateError('GPS lost near bridge'),
          stackTrace: StackTrace.fromString('stack line 1\nstack line 2'),
          metadata: <String, Object?>{
            'screen': 'run_tracking',
            'token': 'should_not_reach_store',
            'retryCount': 2,
            'debugPayload': <String, Object?>{'nested': 'blocked'},
          },
        );

        expect(store.enqueuedRows, hasLength(1));

        final eventRow = store.enqueuedRows.single;
        expect(eventRow['eventId'], 'event-0001');
        expect(eventRow['capturedAt'], '2026-03-25T14:30:00.000Z');
        expect(
          eventRow['context'],
          hasSharedContextEnvelope(
            appVersion: '1.2.3',
            buildNumber: '456',
            platform: 'ios',
          ),
        );

        final persistedMetadata = eventRow['metadata']! as Map<String, Object?>;
        expect(scrubber.invocations, hasLength(1));
        final scrubberInput = scrubber.invocations.single;
        expect(
          scrubberInput,
          containsPair('token', 'should_not_reach_store'),
        );
        expect(
          scrubberInput,
          containsPair(
            'debugPayload',
            <String, Object?>{'nested': 'blocked'},
          ),
        );
        expect(persistedMetadata, hasOnlyFiniteScalarValues());
        expect(persistedMetadata, equals(scrubber.scrubbedMetadata));
      },
    );

    test(
      'preserves service-owned error fields when caller metadata uses the same keys',
      () async {
        final clock = FakeClock(DateTime.utc(2026, 3, 25, 14, 35));
        final store = FakeTelemetryStore();
        final scrubber = FakeTelemetryScrubber(
          scrubbedMetadata: <String, Object?>{
            'errorType': 'StateError',
            'exceptionMessage': 'Bad state: GPS lost near bridge',
            'stackTrace': 'stack line 1\nstack line 2',
            'screen': 'run_tracking',
          },
        );
        final service = buildTelemetryService(
          now: clock.now,
          eventIdFactory: buildEventIdGenerator(),
          store: store,
          uploader: FakeTelemetryUploader(),
          contextSource: FakeAppBuildPlatformContextSource(
            appVersion: '1.2.3',
            buildNumber: '456',
            platform: 'ios',
          ),
          scrubMetadata: scrubber.scrub,
          isTelemetryEnabled: () => true,
          isAuthAvailable: () => true,
        );

        await service.captureUnhandled(
          error: StateError('GPS lost near bridge'),
          stackTrace: StackTrace.fromString('stack line 1\nstack line 2'),
          metadata: <String, Object?>{
            'errorType': 'spoofed',
            'exceptionMessage': 'spoofed',
            'stackTrace': 'spoofed',
            'screen': 'run_tracking',
          },
        );

        expect(scrubber.invocations, hasLength(1));
        expect(
          scrubber.invocations.single,
          <String, Object?>{
            'errorType': 'StateError',
            'exceptionMessage': 'Bad state: GPS lost near bridge',
            'stackTrace': 'stack line 1\nstack line 2',
            'screen': 'run_tracking',
          },
        );
        expect(
          store.enqueuedRows.single['metadata'],
          equals(scrubber.scrubbedMetadata),
        );
      },
    );

    test(
      'redacts credential fragments from exception and stack-trace strings before enqueueing telemetry',
      () async {
        final clock = FakeClock(DateTime.utc(2026, 3, 25, 14, 40));
        final store = FakeTelemetryStore();
        final service = buildTelemetryService(
          now: clock.now,
          eventIdFactory: buildEventIdGenerator(),
          store: store,
          uploader: FakeTelemetryUploader(),
          contextSource: FakeAppBuildPlatformContextSource(
            appVersion: '1.2.3',
            buildNumber: '456',
            platform: 'ios',
          ),
          scrubMetadata: TelemetryScrubber().scrubContext,
          isTelemetryEnabled: () => true,
          isAuthAvailable: () => true,
        );

        await service.captureUnhandled(
          error: StateError('Authorization: Bearer super-secret-token'),
          stackTrace: StackTrace.fromString(
            'GET /callback?refresh_token=abc123 session_id=xyz789',
          ),
          metadata: const <String, Object?>{},
        );

        final metadata =
            store.enqueuedRows.single['metadata']! as Map<String, Object?>;
        expect(
          metadata['exceptionMessage'],
          'Bad state: Authorization: [REDACTED]',
        );
        expect(
          metadata['stackTrace'],
          'GET /callback?refresh_token=[REDACTED] session_id=[REDACTED]',
        );
      },
    );
  });

  group('TelemetryService disabled state', () {
    test(
      'captureUnhandled, recordBreadcrumb, and flushPending are no-ops while telemetry is disabled',
      () async {
        final store = FakeTelemetryStore();
        store.pendingRows.add(
          buildQueuedEventRow(
            eventId: 'event-disabled-0001',
            capturedAt: '2026-03-25T18:30:00.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'already-queued'},
          ),
        );
        final uploader = FakeTelemetryUploader(uploadOutcomes: <bool>[true]);
        final scrubber = FakeTelemetryScrubber(
          scrubbedMetadata: const <String, Object?>{'kept': 'value'},
        );
        final service = buildTelemetryService(
          now: () => DateTime.utc(2026, 3, 25, 18, 35),
          eventIdFactory: buildEventIdGenerator(),
          store: store,
          uploader: uploader,
          contextSource: FakeAppBuildPlatformContextSource(
            appVersion: '1.2.3',
            buildNumber: '456',
            platform: 'ios',
          ),
          scrubMetadata: scrubber.scrub,
          isTelemetryEnabled: () => false,
          isAuthAvailable: () => true,
        );

        await service.recordBreadcrumb(
          message: 'should-not-be-recorded',
          metadata: const <String, Object?>{'token': 'secret'},
        );
        await service.captureUnhandled(
          error: StateError('should-not-be-captured'),
          stackTrace: StackTrace.fromString('stack'),
          metadata: const <String, Object?>{'phase': 'disabled'},
        );
        await service.flushPending();

        expect(scrubber.invocations, isEmpty);
        expect(store.enqueuedRows, isEmpty);
        expect(store.deletedEventIds, isEmpty);
        expect(store.attemptUpdates, isEmpty);
        expect(uploader.uploadedEventIds, isEmpty);
        expect(store.pendingRows, hasLength(1));
        expect(
          store.pendingRows.single['eventId'],
          'event-disabled-0001',
        );
      },
    );
  });

  group('TelemetryService.recordBreadcrumb', () {
    test(
      'persists only the newest 25 breadcrumbs in insertion order inside captured event snapshots',
      () async {
        final clock = FakeClock(DateTime.utc(2026, 3, 25, 15));
        final store = FakeTelemetryStore();
        final service = buildTelemetryService(
          now: clock.now,
          eventIdFactory: buildEventIdGenerator(),
          store: store,
          uploader: FakeTelemetryUploader(),
          contextSource: FakeAppBuildPlatformContextSource(
            appVersion: '1.2.3',
            buildNumber: '456',
            platform: 'android',
          ),
          scrubMetadata: (JsonMap metadata) => metadata,
          isTelemetryEnabled: () => true,
          isAuthAvailable: () => true,
        );

        for (var index = 0; index < 30; index += 1) {
          await service.recordBreadcrumb(
            message: 'crumb-$index',
            metadata: <String, Object?>{'index': index},
          );
          clock.advance(const Duration(seconds: 1));
        }

        await service.captureUnhandled(
          error: StateError('force event snapshot'),
          stackTrace: StackTrace.fromString('stack'),
          metadata: const <String, Object?>{'reason': 'retention-check'},
        );

        final eventRow = store.enqueuedRows.single;
        final messages = breadcrumbMessagesFromEvent(eventRow);

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
      'routes breadcrumb metadata through the central scrubber before persisting event snapshots',
      () async {
        final clock = FakeClock(DateTime.utc(2026, 3, 25, 15, 30));
        final store = FakeTelemetryStore();
        final scrubberInputs = <JsonMap>[];
        final service = buildTelemetryService(
          now: clock.now,
          eventIdFactory: buildEventIdGenerator(),
          store: store,
          uploader: FakeTelemetryUploader(),
          contextSource: FakeAppBuildPlatformContextSource(
            appVersion: '1.2.3',
            buildNumber: '456',
            platform: 'ios',
          ),
          scrubMetadata: (JsonMap metadata) {
            scrubberInputs.add(deepCopyJsonMap(metadata));

            if (metadata.containsKey('token')) {
              return <String, Object?>{
                'screen': 'settings',
                'step': 2,
              };
            }

            return metadata;
          },
          isTelemetryEnabled: () => true,
          isAuthAvailable: () => true,
        );

        await service.recordBreadcrumb(
          message: 'opened-settings',
          metadata: <String, Object?>{
            'screen': 'settings',
            'token': 'secret',
            'step': 2,
            'debugPayload': <String, Object?>{'nested': true},
          },
        );
        await service.captureUnhandled(
          error: StateError('force breadcrumb snapshot'),
          stackTrace: StackTrace.fromString('stack'),
          metadata: const <String, Object?>{'reason': 'snapshot'},
        );

        final breadcrumbScrubberInput = scrubberInputs.singleWhere(
          (JsonMap input) => input.containsKey('token'),
        );
        expect(breadcrumbScrubberInput, containsPair('token', 'secret'));
        expect(
          breadcrumbScrubberInput,
          containsPair(
            'debugPayload',
            <String, Object?>{'nested': true},
          ),
        );

        final eventRow = store.enqueuedRows.single;
        final breadcrumbs = (eventRow['breadcrumbs']! as List<Object?>)
            .cast<Map<String, Object?>>();
        final breadcrumb = breadcrumbs.single;
        final persistedMetadata =
            breadcrumb['metadata']! as Map<String, Object?>;

        expect(persistedMetadata, hasOnlyFiniteScalarValues());
        expect(
          persistedMetadata,
          equals(<String, Object?>{'screen': 'settings', 'step': 2}),
        );
      },
    );

    test(
      'clearBreadcrumbs drops in-memory breadcrumb history before the next captured event',
      () async {
        final clock = FakeClock(DateTime.utc(2026, 3, 25, 15, 45));
        final store = FakeTelemetryStore();
        final service = buildTelemetryService(
          now: clock.now,
          eventIdFactory: buildEventIdGenerator(),
          store: store,
          uploader: FakeTelemetryUploader(),
          contextSource: FakeAppBuildPlatformContextSource(
            appVersion: '1.2.3',
            buildNumber: '456',
            platform: 'ios',
          ),
          scrubMetadata: (JsonMap metadata) => metadata,
          isTelemetryEnabled: () => true,
          isAuthAvailable: () => true,
        );

        await service.recordBreadcrumb(
          message: 'stale-before-disable',
          metadata: const <String, Object?>{'step': 1},
        );
        service.clearBreadcrumbs();
        await service.captureUnhandled(
          error: StateError('post-disable event'),
          stackTrace: StackTrace.fromString('stack'),
          metadata: const <String, Object?>{'reason': 'reenable'},
        );

        final eventRow = store.enqueuedRows.single;
        final breadcrumbs = eventRow['breadcrumbs']! as List<Object?>;
        expect(breadcrumbs, isEmpty);
      },
    );
  });

  group('TelemetryService.flushPending', () {
    test(
      'uploads rows in store queue order and increments retry bookkeeping once per attempt',
      () async {
        final store = FakeTelemetryStore();
        store.pendingRows.addAll(<JsonMap>[
          buildQueuedEventRow(
            eventId: 'event-z',
            capturedAt: '2026-03-25T16:00:00.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'second'},
          ),
          buildQueuedEventRow(
            eventId: 'event-a',
            capturedAt: '2026-03-25T16:00:01.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'first'},
            attemptCount: 2,
            lastAttemptStatus: 'failed',
          ),
          buildQueuedEventRow(
            eventId: 'event-0003',
            capturedAt: '2026-03-25T16:00:02.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'third'},
          ),
        ]);

        final uploader = FakeTelemetryUploader(
          uploadOutcomes: <bool>[true, true, true],
        );
        final service = buildTelemetryService(
          now: () => DateTime.utc(2026, 3, 25, 16, 5),
          eventIdFactory: buildEventIdGenerator(),
          store: store,
          uploader: uploader,
          contextSource: FakeAppBuildPlatformContextSource(
            appVersion: '1.2.3',
            buildNumber: '456',
            platform: 'ios',
          ),
          scrubMetadata: (JsonMap metadata) => metadata,
          isTelemetryEnabled: () => true,
          isAuthAvailable: () => true,
        );

        await service.flushPending();

        expect(
          uploader.uploadedEventIds,
          equals(<String>['event-z', 'event-a', 'event-0003']),
        );
        String summarizeAttempt(AttemptBookkeepingUpdate update) =>
            '${update.eventId}:${update.attemptCount}:${update.lastAttemptStatus}';
        expect(
          store.attemptUpdates.map(summarizeAttempt).toList(growable: false),
          equals(<String>[
            'event-z:1:uploaded',
            'event-a:3:uploaded',
            'event-0003:1:uploaded',
          ]),
        );
        expect(
          store.attemptUpdates
              .where(
                (AttemptBookkeepingUpdate update) =>
                    update.eventId == 'event-a',
              )
              .single
              .attemptCount,
          3,
        );
      },
    );

    test(
      'deletes rows only after successful uploads and keeps failed rows queued',
      () async {
        final store = FakeTelemetryStore();
        store.pendingRows.addAll(<JsonMap>[
          buildQueuedEventRow(
            eventId: 'event-0001',
            capturedAt: '2026-03-25T17:00:00.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'first'},
            attemptCount: 1,
            lastAttemptStatus: 'failed',
          ),
          buildQueuedEventRow(
            eventId: 'event-0002',
            capturedAt: '2026-03-25T17:00:01.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'second'},
          ),
        ]);

        final uploader = FakeTelemetryUploader(
          uploadOutcomes: <bool>[false, true],
        );
        final service = buildTelemetryService(
          now: () => DateTime.utc(2026, 3, 25, 17, 5),
          eventIdFactory: buildEventIdGenerator(),
          store: store,
          uploader: uploader,
          contextSource: FakeAppBuildPlatformContextSource(
            appVersion: '1.2.3',
            buildNumber: '456',
            platform: 'ios',
          ),
          scrubMetadata: (JsonMap metadata) => metadata,
          isTelemetryEnabled: () => true,
          isAuthAvailable: () => true,
        );

        await service.flushPending();

        expect(store.deletedEventIds, equals(<String>['event-0002']));
        String summarizeAttempt(AttemptBookkeepingUpdate update) =>
            '${update.eventId}:${update.attemptCount}:${update.lastAttemptStatus}';
        expect(
          store.attemptUpdates.map(summarizeAttempt).toList(growable: false),
          equals(<String>[
            'event-0001:2:failed',
            'event-0002:1:uploaded',
          ]),
        );
        expect(
          store.pendingRows.any(
            (JsonMap row) => row['eventId'] == 'event-0001',
          ),
          isTrue,
        );
        expect(
          store.pendingRows.any(
            (JsonMap row) => row['eventId'] == 'event-0002',
          ),
          isFalse,
        );
      },
    );

    test(
      'treats thrown uploader errors as failed attempts and continues draining later rows',
      () async {
        final store = FakeTelemetryStore();
        store.pendingRows.addAll(<JsonMap>[
          buildQueuedEventRow(
            eventId: 'event-0001',
            capturedAt: '2026-03-25T17:10:00.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'first'},
            attemptCount: 1,
            lastAttemptStatus: 'failed',
          ),
          buildQueuedEventRow(
            eventId: 'event-0002',
            capturedAt: '2026-03-25T17:10:01.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'second'},
          ),
        ]);

        final uploader = FakeTelemetryUploader(
          uploadResponses: <Object>[StateError('network down'), true],
        );
        final service = buildTelemetryService(
          now: () => DateTime.utc(2026, 3, 25, 17, 15),
          eventIdFactory: buildEventIdGenerator(),
          store: store,
          uploader: uploader,
          contextSource: FakeAppBuildPlatformContextSource(
            appVersion: '1.2.3',
            buildNumber: '456',
            platform: 'ios',
          ),
          scrubMetadata: (JsonMap metadata) => metadata,
          isTelemetryEnabled: () => true,
          isAuthAvailable: () => true,
        );

        await service.flushPending();

        expect(
          uploader.uploadedEventIds,
          equals(<String>['event-0001', 'event-0002']),
        );
        String summarizeAttempt(AttemptBookkeepingUpdate update) =>
            '${update.eventId}:${update.attemptCount}:${update.lastAttemptStatus}';
        expect(
          store.attemptUpdates.map(summarizeAttempt).toList(growable: false),
          equals(<String>[
            'event-0001:2:failed',
            'event-0002:1:uploaded',
          ]),
        );
        expect(store.deletedEventIds, equals(<String>['event-0002']));
        expect(
          store.pendingRows.any(
            (JsonMap row) => row['eventId'] == 'event-0001',
          ),
          isTrue,
        );
      },
    );
  });
}

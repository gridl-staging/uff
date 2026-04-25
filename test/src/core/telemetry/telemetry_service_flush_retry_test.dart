import 'package:flutter_test/flutter_test.dart';

import 'telemetry_test_support.dart';

void main() {
  group('TelemetryService.flushPending auth gating', () {
    test(
      'skips upload and does not update retry bookkeeping when auth is unavailable',
      () async {
        final store = FakeTelemetryStore();
        store.pendingRows.addAll(<JsonMap>[
          buildQueuedEventRow(
            eventId: 'event-0001',
            capturedAt: '2026-03-25T18:00:00.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'queued'},
          ),
        ]);

        final uploader = FakeTelemetryUploader();
        final service = buildTelemetryService(
          now: () => DateTime.utc(2026, 3, 25, 18, 5),
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
          isAuthAvailable: () => false,
        );

        await service.flushPending();

        expect(uploader.uploadedEventIds, isEmpty);
        expect(store.attemptUpdates, isEmpty);
        expect(store.deletedEventIds, isEmpty);
        expect(store.pendingRows, hasLength(1));
      },
    );
  });

  group('TelemetryService.flushPending retry policy', () {
    test(
      'skips row inside backoff window without upload or attempt increment',
      () async {
        // Row attempted 15s ago at attempt 1 — backoff is 30s, so still cooling.
        final now = DateTime.utc(2026, 3, 25, 18, 0, 15);
        final store = FakeTelemetryStore();
        store.pendingRows.addAll(<JsonMap>[
          buildQueuedEventRow(
            eventId: 'event-backoff',
            capturedAt: '2026-03-25T17:59:00.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'in-backoff'},
            attemptCount: 1,
            lastAttemptStatus: 'failed',
            lastAttemptedAt: '2026-03-25T18:00:00.000Z',
          ),
        ]);

        final uploader = FakeTelemetryUploader(uploadOutcomes: <bool>[true]);
        final service = buildTelemetryService(
          now: () => now,
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

        expect(uploader.uploadedEventIds, isEmpty);
        expect(store.attemptUpdates, isEmpty);
        expect(store.deletedEventIds, isEmpty);
        expect(store.pendingRows, hasLength(1));
      },
    );

    test(
      'tombstones row exceeding max attempts by deleting without upload',
      () async {
        final store = FakeTelemetryStore();
        store.pendingRows.addAll(<JsonMap>[
          buildQueuedEventRow(
            eventId: 'event-tombstone',
            capturedAt: '2026-03-25T17:00:00.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'exhausted'},
            attemptCount: 5,
            lastAttemptStatus: 'failed',
            lastAttemptedAt: '2026-03-25T17:50:00.000Z',
          ),
        ]);

        final uploader = FakeTelemetryUploader(uploadOutcomes: <bool>[true]);
        final service = buildTelemetryService(
          now: () => DateTime.utc(2026, 3, 25, 18),
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

        expect(uploader.uploadedEventIds, isEmpty);
        expect(store.attemptUpdates, isEmpty);
        expect(store.deletedEventIds, equals(<String>['event-tombstone']));
        expect(store.pendingRows, isEmpty);
      },
    );

    test(
      'eligible row proceeds with upload and records lastAttemptedAt timestamp',
      () async {
        // Row attempted 35 minutes ago at attempt 1 — backoff is 30s, so eligible.
        final now = DateTime.utc(2026, 3, 25, 18, 5);
        final store = FakeTelemetryStore();
        store.pendingRows.addAll(<JsonMap>[
          buildQueuedEventRow(
            eventId: 'event-eligible',
            capturedAt: '2026-03-25T17:00:00.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'ready'},
            attemptCount: 1,
            lastAttemptStatus: 'failed',
            lastAttemptedAt: '2026-03-25T17:30:00.000Z',
          ),
        ]);

        final uploader = FakeTelemetryUploader(uploadOutcomes: <bool>[true]);
        final service = buildTelemetryService(
          now: () => now,
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

        expect(uploader.uploadedEventIds, equals(<String>['event-eligible']));
        expect(store.deletedEventIds, equals(<String>['event-eligible']));
        expect(store.attemptUpdates, hasLength(1));
        final update = store.attemptUpdates.single;
        expect(update.eventId, 'event-eligible');
        expect(update.attemptCount, 2);
        expect(update.lastAttemptStatus, 'uploaded');
        expect(update.lastAttemptedAt, now.toUtc());
      },
    );

    test(
      'mixed batch: tombstones exhausted, skips in-backoff, uploads eligible',
      () async {
        final now = DateTime.utc(2026, 3, 25, 18, 5);
        final store = FakeTelemetryStore();
        store.pendingRows.addAll(<JsonMap>[
          // Tombstone: 5 attempts (at max).
          buildQueuedEventRow(
            eventId: 'event-exhausted',
            capturedAt: '2026-03-25T16:00:00.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'exhausted'},
            attemptCount: 5,
            lastAttemptStatus: 'failed',
            lastAttemptedAt: '2026-03-25T17:00:00.000Z',
          ),
          // In backoff: 1 attempt, 10s ago (backoff is 30s).
          buildQueuedEventRow(
            eventId: 'event-cooling',
            capturedAt: '2026-03-25T16:00:01.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'cooling'},
            attemptCount: 1,
            lastAttemptStatus: 'failed',
            lastAttemptedAt: '2026-03-25T18:04:55.000Z',
          ),
          // Eligible: never attempted.
          buildQueuedEventRow(
            eventId: 'event-fresh',
            capturedAt: '2026-03-25T16:00:02.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'fresh'},
          ),
        ]);

        final uploader = FakeTelemetryUploader(uploadOutcomes: <bool>[true]);
        final service = buildTelemetryService(
          now: () => now,
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

        // Only the fresh row was uploaded.
        expect(uploader.uploadedEventIds, equals(<String>['event-fresh']));
        // Exhausted row tombstoned, fresh row deleted after successful upload.
        expect(store.deletedEventIds, contains('event-exhausted'));
        expect(store.deletedEventIds, contains('event-fresh'));
        // Cooling row neither uploaded nor deleted.
        expect(store.deletedEventIds, isNot(contains('event-cooling')));
        // Only the fresh row got an attempt update.
        expect(store.attemptUpdates, hasLength(1));
        expect(store.attemptUpdates.single.eventId, 'event-fresh');
      },
    );

    test(
      'returns the shortest remaining backoff across skipped rows',
      () async {
        // Row 1: 1 attempt, 10s ago. Backoff is 30s, so 20s remaining.
        // Row 2: 2 attempts, 50s ago. Backoff is 60s, so 10s remaining.
        // Row 3: never attempted — eligible, uploaded successfully.
        final now = DateTime.utc(2026, 3, 25, 18, 5);
        final store = FakeTelemetryStore();
        store.pendingRows.addAll(<JsonMap>[
          buildQueuedEventRow(
            eventId: 'event-backoff-20s',
            capturedAt: '2026-03-25T16:00:00.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'cooling-20'},
            attemptCount: 1,
            lastAttemptStatus: 'failed',
            lastAttemptedAt: '2026-03-25T18:04:50.000Z',
          ),
          buildQueuedEventRow(
            eventId: 'event-backoff-10s',
            capturedAt: '2026-03-25T16:00:01.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'cooling-10'},
            attemptCount: 2,
            lastAttemptStatus: 'failed',
            lastAttemptedAt: '2026-03-25T18:04:10.000Z',
          ),
          buildQueuedEventRow(
            eventId: 'event-fresh',
            capturedAt: '2026-03-25T16:00:02.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'fresh'},
          ),
        ]);

        final uploader = FakeTelemetryUploader(uploadOutcomes: <bool>[true]);
        final service = buildTelemetryService(
          now: () => now,
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

        final nextEligible = await service.flushPending();

        // Shortest remaining backoff is 10s (from event-backoff-10s).
        expect(nextEligible, const Duration(seconds: 10));
        // Only the fresh row was uploaded.
        expect(uploader.uploadedEventIds, equals(<String>['event-fresh']));
      },
    );

    test(
      'returns null when all rows are uploaded or tombstoned',
      () async {
        final now = DateTime.utc(2026, 3, 25, 18, 5);
        final store = FakeTelemetryStore();
        store.pendingRows.addAll(<JsonMap>[
          buildQueuedEventRow(
            eventId: 'event-fresh',
            capturedAt: '2026-03-25T16:00:00.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'fresh'},
          ),
        ]);

        final uploader = FakeTelemetryUploader(uploadOutcomes: <bool>[true]);
        final service = buildTelemetryService(
          now: () => now,
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

        final nextEligible = await service.flushPending();

        expect(nextEligible, isNull);
      },
    );

    test(
      'treats malformed lastAttemptedAt as never attempted so one bad row does not abort the batch',
      () async {
        final now = DateTime.utc(2026, 3, 25, 18, 5);
        final store = FakeTelemetryStore();
        store.pendingRows.addAll(<JsonMap>[
          buildQueuedEventRow(
            eventId: 'event-bad-timestamp',
            capturedAt: '2026-03-25T16:00:00.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'bad-timestamp'},
            attemptCount: 2,
            lastAttemptStatus: 'failed',
            lastAttemptedAt: 'not-a-timestamp',
          ),
          buildQueuedEventRow(
            eventId: 'event-after-bad-timestamp',
            capturedAt: '2026-03-25T16:00:01.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'after-bad-timestamp'},
          ),
        ]);

        final uploader = FakeTelemetryUploader(
          uploadOutcomes: <bool>[false, true],
        );
        final service = buildTelemetryService(
          now: () => now,
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
          equals(<String>[
            'event-bad-timestamp',
            'event-after-bad-timestamp',
          ]),
        );
        expect(store.attemptUpdates, hasLength(2));
        expect(store.attemptUpdates.first.eventId, 'event-bad-timestamp');
        expect(store.attemptUpdates.first.attemptCount, 3);
        expect(store.attemptUpdates.first.lastAttemptStatus, 'failed');
        expect(store.attemptUpdates.last.eventId, 'event-after-bad-timestamp');
        expect(store.attemptUpdates.last.attemptCount, 1);
        expect(store.attemptUpdates.last.lastAttemptStatus, 'uploaded');
        expect(
          store.deletedEventIds,
          equals(<String>['event-after-bad-timestamp']),
        );
      },
    );
  });
}

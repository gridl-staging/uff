import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uff/src/core/telemetry/data/supabase_telemetry_uploader.dart';
import 'package:uff/src/core/telemetry/telemetry_enablement.dart';

import 'telemetry_test_support.dart';

class _RecordingTelemetryEnablementOwner extends TelemetryEnablementOwner {
  _RecordingTelemetryEnablementOwner({
    required bool hydratedValue,
  }) : _hydratedValue = hydratedValue,
       super(
         readPersisted: () async => null,
         writePersisted: ({required bool isEnabled}) async {},
         clearPendingTelemetry: () async {},
         clearInMemoryTelemetry: () {},
       );

  final bool _hydratedValue;

  int hydrateCallCount = 0;
  int setTelemetryEnabledCallCount = 0;
  final List<bool> setTelemetryEnabledValues = <bool>[];

  @override
  Future<void> hydrate() async {
    hydrateCallCount += 1;
    await super.setTelemetryEnabled(isEnabled: _hydratedValue);
  }

  @override
  Future<void> setTelemetryEnabled({required bool isEnabled}) async {
    setTelemetryEnabledCallCount += 1;
    setTelemetryEnabledValues.add(isEnabled);
    await super.setTelemetryEnabled(isEnabled: isEnabled);
  }
}

class _TelemetryServiceSeamProbe {
  _TelemetryServiceSeamProbe({
    required FakeTelemetryStore store,
    required bool Function() isTelemetryEnabled,
  }) : _store = store,
       _isTelemetryEnabled = isTelemetryEnabled;

  final FakeTelemetryStore _store;
  final bool Function() _isTelemetryEnabled;
  int _nextEventNumber = 0;

  Future<void> recordBreadcrumb({
    required String message,
    required JsonMap metadata,
  }) async {
    if (!_isTelemetryEnabled()) {
      return;
    }

    _nextEventNumber += 1;
    await _store.enqueue(
      buildQueuedEventRow(
        eventId: 'probe-${_nextEventNumber.toString().padLeft(4, '0')}',
        capturedAt: '2026-03-25T19:00:00.000Z',
        breadcrumbs: <JsonMap>[
          <String, Object?>{'message': message, 'metadata': metadata},
        ],
        metadata: const <String, Object?>{'source': 'recordBreadcrumb'},
      ),
    );
  }

  Future<void> captureUnhandled({
    required Object error,
    required StackTrace stackTrace,
    required JsonMap metadata,
  }) async {
    if (!_isTelemetryEnabled()) {
      return;
    }

    _nextEventNumber += 1;
    await _store.enqueue(
      buildQueuedEventRow(
        eventId: 'probe-${_nextEventNumber.toString().padLeft(4, '0')}',
        capturedAt: '2026-03-25T19:00:01.000Z',
        breadcrumbs: const <JsonMap>[],
        metadata: <String, Object?>{
          'errorType': error.runtimeType.toString(),
          ...metadata,
        },
      ),
    );
  }
}

class _BlockingClearTelemetryStore extends FakeTelemetryStore {
  final Completer<void> clearStarted = Completer<void>();
  final Completer<void> _finishClear = Completer<void>();

  @override
  Future<void> clear() async {
    clearCallCount += 1;
    if (!clearStarted.isCompleted) {
      clearStarted.complete();
    }

    await _finishClear.future;
    pendingRows.clear();
    enqueuedRows.clear();
  }

  void allowClearToFinish() {
    if (!_finishClear.isCompleted) {
      _finishClear.complete();
    }
  }
}

Future<void> _waitForTelemetryEnabled(
  ProviderContainer container, {
  required bool expectedValue,
}) async {
  final completer = Completer<void>();
  final subscription = container.listen<bool>(
    telemetryEnablementProvider,
    (previous, next) {
      if (next == expectedValue && !completer.isCompleted) {
        completer.complete();
      }
    },
    fireImmediately: true,
  );

  await completer.future.timeout(const Duration(seconds: 1));
  subscription.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TelemetryEnablementOwner', () {
    test(
      'defaults enabled and hydrates persisted disabled state after recreation',
      () async {
        final persistence = FakeTelemetryEnablementPersistence(
          persistedValue: false,
        );
        final ownerA = TelemetryEnablementOwner(
          readPersisted: persistence.read,
          writePersisted: persistence.write,
          clearPendingTelemetry: persistence.clearQueue,
          clearInMemoryTelemetry: () {},
        );

        expect(ownerA.isEnabled, isTrue);

        await ownerA.hydrate();
        expect(ownerA.isEnabled, isFalse);

        final ownerB = TelemetryEnablementOwner(
          readPersisted: persistence.read,
          writePersisted: persistence.write,
          clearPendingTelemetry: persistence.clearQueue,
          clearInMemoryTelemetry: () {},
        );

        expect(ownerB.isEnabled, isTrue);
        await ownerB.hydrate();
        expect(ownerB.isEnabled, isFalse);
      },
    );

    test(
      'keeps in-memory value when persistence read and write fail',
      () async {
        final persistence = FakeTelemetryEnablementPersistence(
          readError: StateError('read failed'),
          writeError: StateError('write failed'),
        );
        final owner = TelemetryEnablementOwner(
          readPersisted: persistence.read,
          writePersisted: persistence.write,
          clearPendingTelemetry: persistence.clearQueue,
          clearInMemoryTelemetry: () {},
        );

        expect(owner.isEnabled, isTrue);
        await owner.hydrate();
        expect(owner.isEnabled, isTrue);

        await owner.setTelemetryEnabled(isEnabled: false);
        expect(owner.isEnabled, isFalse);
      },
    );

    test(
      'setTelemetryEnabled(false) still clears queued rows when persistence write fails',
      () async {
        final persistence = FakeTelemetryEnablementPersistence(
          persistedValue: true,
          writeError: StateError('write failed'),
        );
        final store = FakeTelemetryStore();
        await store.enqueue(
          buildQueuedEventRow(
            eventId: 'event-persist-write-failure',
            capturedAt: '2026-03-25T18:58:00.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'queued-before-fail'},
          ),
        );
        final owner = TelemetryEnablementOwner(
          readPersisted: persistence.read,
          writePersisted: persistence.write,
          clearPendingTelemetry: store.clear,
          clearInMemoryTelemetry: () {},
        );
        final serviceSeam = _TelemetryServiceSeamProbe(
          store: store,
          isTelemetryEnabled: () => owner.isEnabled,
        );

        await owner.setTelemetryEnabled(isEnabled: false);

        expect(owner.isEnabled, isFalse);
        expect(store.clearCallCount, 1);
        expect(store.enqueuedRows, isEmpty);
        expect(store.pendingRows, isEmpty);

        await serviceSeam.captureUnhandled(
          error: StateError('blocked after failed persistence write'),
          stackTrace: StackTrace.fromString('stack'),
          metadata: const <String, Object?>{'blocked': true},
        );
        expect(store.enqueuedRows, isEmpty);
        expect(store.pendingRows, isEmpty);
      },
    );

    test(
      'setTelemetryEnabled(false) remains disabled and clears queued rows when in-memory clearing throws',
      () async {
        final persistence = FakeTelemetryEnablementPersistence(
          persistedValue: true,
        );
        final store = FakeTelemetryStore();
        await store.enqueue(
          buildQueuedEventRow(
            eventId: 'event-clear-in-memory-failure',
            capturedAt: '2026-03-25T18:58:30.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{
              'message': 'queued-before-in-memory-clear-failure',
            },
          ),
        );
        final owner = TelemetryEnablementOwner(
          readPersisted: persistence.read,
          writePersisted: persistence.write,
          clearPendingTelemetry: store.clear,
          clearInMemoryTelemetry: () {
            throw StateError('clear in-memory failed');
          },
        );

        await owner.setTelemetryEnabled(isEnabled: false);

        expect(owner.isEnabled, isFalse);
        expect(store.clearCallCount, 1);
        expect(store.enqueuedRows, isEmpty);
        expect(store.pendingRows, isEmpty);
      },
    );

    test(
      'setTelemetryEnabled(false) clears queued rows and blocks new service writes until re-enabled',
      () async {
        final persistence = FakeTelemetryEnablementPersistence(
          persistedValue: true,
        );
        final store = FakeTelemetryStore();
        await store.enqueue(
          buildQueuedEventRow(
            eventId: 'event-queued',
            capturedAt: '2026-03-25T18:59:00.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{
              'message': 'queued-before-disable',
            },
          ),
        );
        final owner = TelemetryEnablementOwner(
          readPersisted: persistence.read,
          writePersisted: persistence.write,
          clearPendingTelemetry: store.clear,
          clearInMemoryTelemetry: () {},
        );
        final serviceSeam = _TelemetryServiceSeamProbe(
          store: store,
          isTelemetryEnabled: () => owner.isEnabled,
        );

        await owner.hydrate();
        expect(owner.isEnabled, isTrue);

        await owner.setTelemetryEnabled(isEnabled: false);
        expect(owner.isEnabled, isFalse);
        expect(store.clearCallCount, 1);
        expect(store.pendingRows, isEmpty);
        expect(store.enqueuedRows, isEmpty);

        await serviceSeam.recordBreadcrumb(
          message: 'should-not-persist',
          metadata: const <String, Object?>{'blocked': true},
        );
        await serviceSeam.captureUnhandled(
          error: StateError('blocked while disabled'),
          stackTrace: StackTrace.fromString('stack'),
          metadata: const <String, Object?>{'blocked': true},
        );
        expect(store.enqueuedRows, isEmpty);
        expect(store.pendingRows, isEmpty);

        await owner.setTelemetryEnabled(isEnabled: true);
        expect(owner.isEnabled, isTrue);

        await serviceSeam.captureUnhandled(
          error: StateError('allowed after enable'),
          stackTrace: StackTrace.fromString('stack'),
          metadata: const <String, Object?>{'allowed': true},
        );
        expect(store.enqueuedRows, hasLength(1));
        expect(store.pendingRows, hasLength(1));
      },
    );

    test(
      'setTelemetryEnabled(false) clears service breadcrumbs so re-enabled captures start fresh',
      () async {
        final clock = FakeClock(DateTime.utc(2026, 3, 25, 19, 15));
        final store = FakeTelemetryStore();
        late TelemetryEnablementOwner owner;
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
          isAuthAvailable: () => true,
          isTelemetryEnabled: () => owner.isEnabled,
        );
        owner = TelemetryEnablementOwner(
          readPersisted: () async => true,
          writePersisted: ({required bool isEnabled}) async {},
          clearPendingTelemetry: store.clear,
          clearInMemoryTelemetry: service.clearBreadcrumbs,
        );

        await service.recordBreadcrumb(
          message: 'stale-breadcrumb',
          metadata: const <String, Object?>{'step': 1},
        );

        await owner.setTelemetryEnabled(isEnabled: false);
        await owner.setTelemetryEnabled(isEnabled: true);
        await service.captureUnhandled(
          error: StateError('after-reenable'),
          stackTrace: StackTrace.fromString('stack'),
          metadata: const <String, Object?>{'source': 'test'},
        );

        final eventRow = store.enqueuedRows.single;
        final breadcrumbs = eventRow['breadcrumbs']! as List<Object?>;
        expect(breadcrumbs, isEmpty);
      },
    );
  });

  group('telemetryEnablementProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('defaults enabled until persisted hydration updates state', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'telemetry_enabled': false,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(telemetryEnablementProvider), isTrue);

      await _waitForTelemetryEnabled(container, expectedValue: false);

      expect(container.read(telemetryEnablementProvider), isFalse);
      final isTelemetryEnabled = container.read(
        telemetryIsEnabledReaderProvider,
      );
      expect(isTelemetryEnabled(), isFalse);
    });

    test(
      'setTelemetryEnabled persists values across container restarts',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container
            .read(telemetryEnablementProvider.notifier)
            .setTelemetryEnabled(isEnabled: false);
        expect(container.read(telemetryEnablementProvider), isFalse);

        final restartedContainer = ProviderContainer();
        addTearDown(restartedContainer.dispose);
        await _waitForTelemetryEnabled(
          restartedContainer,
          expectedValue: false,
        );
        expect(restartedContainer.read(telemetryEnablementProvider), isFalse);
      },
    );

    test(
      'delegates setTelemetryEnabled through telemetryEnablementOwnerProvider',
      () async {
        final owner = _RecordingTelemetryEnablementOwner(hydratedValue: false);
        final container = ProviderContainer(
          overrides: [
            telemetryEnablementOwnerProvider.overrideWith((ref) => owner),
          ],
        );
        addTearDown(container.dispose);

        container.read(telemetryEnablementProvider);
        await _waitForTelemetryEnabled(container, expectedValue: false);
        expect(owner.hydrateCallCount, 1);

        await container
            .read(telemetryEnablementProvider.notifier)
            .setTelemetryEnabled(isEnabled: true);

        expect(owner.setTelemetryEnabledCallCount, 1);
        expect(owner.setTelemetryEnabledValues, <bool>[true]);
        final isTelemetryEnabled = container.read(
          telemetryIsEnabledReaderProvider,
        );
        expect(isTelemetryEnabled(), isTrue);
      },
    );

    test(
      'runtime graph clears queued telemetry and stale breadcrumbs on disable',
      () async {
        final store = FakeTelemetryStore();
        final container = ProviderContainer(
          overrides: [
            telemetryStoreProvider.overrideWithValue(store),
            telemetryUploaderProvider.overrideWithValue(
              FakeTelemetryUploader(),
            ),
            telemetryContextSourceProvider.overrideWithValue(
              FakeAppBuildPlatformContextSource(
                appVersion: '1.2.3',
                buildNumber: '456',
                platform: 'ios',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final service = container.read(telemetryServiceProvider);

        await service.recordBreadcrumb(
          message: 'stale-breadcrumb',
          metadata: const <String, Object?>{},
        );
        await service.captureUnhandled(
          error: StateError('queued-before-disable'),
          stackTrace: StackTrace.current,
          metadata: const <String, Object?>{
            'phase': 'before-disable',
          },
        );
        expect(store.pendingRows, hasLength(1));
        expect(
          breadcrumbMessagesFromEvent(store.pendingRows.single),
          <String>['stale-breadcrumb'],
        );

        await container
            .read(telemetryEnablementProvider.notifier)
            .setTelemetryEnabled(isEnabled: false);

        expect(store.clearCallCount, 1);
        expect(store.pendingRows, isEmpty);

        await service.captureUnhandled(
          error: StateError('ignored-while-disabled'),
          stackTrace: StackTrace.current,
          metadata: const <String, Object?>{
            'phase': 'while-disabled',
          },
        );
        expect(store.pendingRows, isEmpty);

        await container
            .read(telemetryEnablementProvider.notifier)
            .setTelemetryEnabled(isEnabled: true);
        await service.captureUnhandled(
          error: StateError('queued-after-reenable'),
          stackTrace: StackTrace.current,
          metadata: const <String, Object?>{
            'phase': 'after-reenable',
          },
        );

        expect(store.pendingRows, hasLength(1));
        expect(
          breadcrumbMessagesFromEvent(store.pendingRows.single),
          isEmpty,
        );
      },
    );

    test(
      're-enable waits for an in-flight disable clear before runtime capture resumes',
      () async {
        final store = _BlockingClearTelemetryStore();
        final container = ProviderContainer(
          overrides: [
            telemetryStoreProvider.overrideWithValue(store),
            telemetryUploaderProvider.overrideWithValue(
              FakeTelemetryUploader(),
            ),
            telemetryContextSourceProvider.overrideWithValue(
              FakeAppBuildPlatformContextSource(
                appVersion: '1.2.3',
                buildNumber: '456',
                platform: 'ios',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(telemetryEnablementProvider.notifier);
        final service = container.read(telemetryServiceProvider);

        await service.captureUnhandled(
          error: StateError('queued-before-disable'),
          stackTrace: StackTrace.current,
          metadata: const <String, Object?>{
            'phase': 'before-disable',
          },
        );
        expect(store.pendingRows, hasLength(1));

        final disableFuture = notifier.setTelemetryEnabled(isEnabled: false);
        await store.clearStarted.future.timeout(const Duration(seconds: 1));
        expect(container.read(telemetryEnablementProvider), isFalse);

        final enableFuture = notifier.setTelemetryEnabled(isEnabled: true);
        expect(
          container.read(telemetryEnablementProvider),
          isFalse,
          reason: 'Re-enable should wait for disable-time clear completion.',
        );

        await service.captureUnhandled(
          error: StateError('blocked-until-clear-finishes'),
          stackTrace: StackTrace.current,
          metadata: const <String, Object?>{
            'phase': 'blocked-until-clear-finishes',
          },
        );
        expect(
          store.pendingRows,
          hasLength(1),
          reason:
              'Runtime capture must stay blocked until the queued clear finishes.',
        );

        store.allowClearToFinish();
        await disableFuture;
        await enableFuture;

        expect(container.read(telemetryEnablementProvider), isTrue);
        expect(store.pendingRows, isEmpty);

        await service.captureUnhandled(
          error: StateError('queued-after-enable-settled'),
          stackTrace: StackTrace.current,
          metadata: const <String, Object?>{
            'phase': 'after-enable-settled',
          },
        );
        expect(store.pendingRows, hasLength(1));
        expect(
          (store.pendingRows.single['metadata']!
              as Map<String, Object?>)['phase'],
          'after-enable-settled',
        );
      },
    );

    test(
      'flushPending remains non-fatal through provider graph when uploader invoke throws',
      () async {
        final store = FakeTelemetryStore();
        store.pendingRows.addAll(<JsonMap>[
          buildQueuedEventRow(
            eventId: 'event-upload-failure',
            capturedAt: '2026-03-26T01:00:00.000Z',
            breadcrumbs: const <JsonMap>[],
            metadata: const <String, Object?>{'message': 'queued-for-upload'},
          ),
        ]);

        final container = ProviderContainer(
          overrides: [
            telemetryStoreProvider.overrideWithValue(store),
            telemetryUploaderProvider.overrideWithValue(
              SupabaseTelemetryUploader(
                invoke: (String name, {Object? body}) async {
                  throw Exception('invoke failed');
                },
              ),
            ),
            telemetryAuthAvailabilityProvider.overrideWithValue(() => true),
          ],
        );
        addTearDown(container.dispose);

        final service = container.read(telemetryServiceProvider);

        final earliestNextEligible = await service.flushPending();

        expect(earliestNextEligible, isNull);
        expect(store.pendingRows, hasLength(1));
        expect(store.deletedEventIds, isEmpty);
        expect(store.attemptUpdates, hasLength(1));
        expect(store.attemptUpdates.single.eventId, 'event-upload-failure');
        expect(store.attemptUpdates.single.attemptCount, 1);
        expect(store.attemptUpdates.single.lastAttemptStatus, 'failed');
      },
    );
  });

  group('telemetryFlushSchedulerProvider', () {
    test(
      'creates a scheduler wired to service.flushPending that uploads pending rows on start',
      () {
        fakeAsync((FakeAsync async) {
          final store = FakeTelemetryStore();
          store.pendingRows.addAll(<JsonMap>[
            buildQueuedEventRow(
              eventId: 'event-0001',
              capturedAt: '2026-03-25T18:00:00.000Z',
              breadcrumbs: const <JsonMap>[],
              metadata: const <String, Object?>{'message': 'queued'},
            ),
          ]);
          final uploader = FakeTelemetryUploader(
            uploadOutcomes: <bool>[true],
          );
          final container = ProviderContainer(
            overrides: [
              telemetryStoreProvider.overrideWithValue(store),
              telemetryUploaderProvider.overrideWithValue(uploader),
              telemetryContextSourceProvider.overrideWithValue(
                FakeAppBuildPlatformContextSource(
                  appVersion: '1.2.3',
                  buildNumber: '456',
                  platform: 'ios',
                ),
              ),
              telemetryAuthAvailabilityProvider.overrideWithValue(() => true),
            ],
          );
          addTearDown(container.dispose);

          container.read(telemetryFlushSchedulerProvider).start();
          async.flushMicrotasks();

          expect(
            uploader.uploadedEventIds,
            equals(<String>['event-0001']),
          );
        });
      },
    );

    test(
      'disposes scheduler when container is disposed',
      () {
        // Verifying that the provider's onDispose hook calls scheduler.dispose
        // (which cancels pending timers) by checking no timers leak.
        fakeAsync((FakeAsync async) {
          final store = FakeTelemetryStore();
          final uploader = FakeTelemetryUploader();
          // Reading the provider creates the scheduler.
          // Disposing the container should dispose the scheduler cleanly.
          ProviderContainer(
              overrides: [
                telemetryStoreProvider.overrideWithValue(store),
                telemetryUploaderProvider.overrideWithValue(uploader),
                telemetryContextSourceProvider.overrideWithValue(
                  FakeAppBuildPlatformContextSource(
                    appVersion: '1.2.3',
                    buildNumber: '456',
                    platform: 'ios',
                  ),
                ),
                telemetryAuthAvailabilityProvider.overrideWithValue(() => true),
              ],
            )
            ..read(telemetryFlushSchedulerProvider)
            ..dispose();

          // If the scheduler weren't disposed, pending timers would leak.
          // fakeAsync would complain about pending timers if any existed.
          async.flushTimers();
        });
      },
    );
  });
}

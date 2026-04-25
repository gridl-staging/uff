import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/sync_status_provider.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';

import 'tracking_controller_test_support.dart';

bool _isSyncIndicatorVisible(AsyncValue<SyncQueueStatus> statusValue) {
  return statusValue.when(
    data: (status) => switch (status) {
      SyncQueueStatus.queued ||
      SyncQueueStatus.processing ||
      SyncQueueStatus.failed => true,
      SyncQueueStatus.idle || SyncQueueStatus.successful => false,
    },
    loading: () => false,
    error: (Object _, StackTrace __) => false,
  );
}

void main() {
  late StreamController<SyncQueueStatus> syncStatusController;
  late ProviderContainer container;

  setUp(() {
    syncStatusController = StreamController<SyncQueueStatus>.broadcast();
    container = ProviderContainer(
      overrides: [
        syncServiceProvider.overrideWithValue(
          FakeSyncService(syncStatusStream: syncStatusController.stream),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await syncStatusController.close();
  });

  test('loading state stays hidden before first stream emission', () {
    final statusValue = container.read(syncStatusProvider);

    expect(statusValue, const AsyncLoading<SyncQueueStatus>());
    expect(_isSyncIndicatorVisible(statusValue), isFalse);
  });

  test('queued status is visible', () async {
    final subscription = container.listen<AsyncValue<SyncQueueStatus>>(
      syncStatusProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    syncStatusController.add(SyncQueueStatus.queued);
    await pumpEventQueue();

    final statusValue = subscription.read();

    expect(statusValue.value, SyncQueueStatus.queued);
    expect(_isSyncIndicatorVisible(statusValue), isTrue);
  });

  test('processing status is visible', () async {
    final subscription = container.listen<AsyncValue<SyncQueueStatus>>(
      syncStatusProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    syncStatusController.add(SyncQueueStatus.processing);
    await pumpEventQueue();

    final statusValue = subscription.read();

    expect(statusValue.value, SyncQueueStatus.processing);
    expect(_isSyncIndicatorVisible(statusValue), isTrue);
  });

  test('failed status is visible', () async {
    final subscription = container.listen<AsyncValue<SyncQueueStatus>>(
      syncStatusProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    syncStatusController.add(SyncQueueStatus.failed);
    await pumpEventQueue();

    final statusValue = subscription.read();

    expect(statusValue.value, SyncQueueStatus.failed);
    expect(_isSyncIndicatorVisible(statusValue), isTrue);
  });

  test('idle status stays hidden', () async {
    final subscription = container.listen<AsyncValue<SyncQueueStatus>>(
      syncStatusProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    syncStatusController.add(SyncQueueStatus.idle);
    await pumpEventQueue();

    final statusValue = subscription.read();

    expect(statusValue.value, SyncQueueStatus.idle);
    expect(_isSyncIndicatorVisible(statusValue), isFalse);
  });

  test('successful status stays hidden', () async {
    final subscription = container.listen<AsyncValue<SyncQueueStatus>>(
      syncStatusProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    syncStatusController.add(SyncQueueStatus.successful);
    await pumpEventQueue();

    final statusValue = subscription.read();

    expect(statusValue.value, SyncQueueStatus.successful);
    expect(_isSyncIndicatorVisible(statusValue), isFalse);
  });

  test('stream error state stays hidden', () async {
    final subscription = container.listen<AsyncValue<SyncQueueStatus>>(
      syncStatusProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    syncStatusController.addError(StateError('sync stream failed'));
    await pumpEventQueue();

    final statusValue = subscription.read();

    expect(statusValue.hasError, isTrue);
    expect(_isSyncIndicatorVisible(statusValue), isFalse);
  });
}

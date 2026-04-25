import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'sync_service_test_support.dart';

typedef SyncQueryBuilderFactory =
    FakeSyncQueryBuilder Function(
      String table, {
      bool throwOnUpsert,
      List<Map<String, dynamic>> selectRows,
      Object? selectError,
    });

void registerDeleteRemoteActivityTests({
  required MockTrackingRepository Function() repository,
  required MockSupabaseClient Function() supabaseClient,
  required List<RecordedOperation> Function() operations,
  required StreamController<List<ConnectivityResult>> Function()
  connectivityController,
  required SyncQueryBuilderFactory builderForTable,
}) {
  group('SupabaseSyncService.deleteRemoteActivity', () {
    test(
      'throws before any remote calls when no authenticated user exists',
      () async {
        final service = SupabaseSyncService(
          repository: repository(),
          supabaseClient: supabaseClient(),
          connectivityChanges: connectivityController().stream,
          checkConnectivity: () async => [ConnectivityResult.none],
          currentUserIdProvider: () => null,
        );
        addTearDown(service.dispose);

        await expectLater(
          service.deleteRemoteActivity('remote-missing-user'),
          throwsStateError,
        );

        verifyNever(() => supabaseClient().from(any()));
        verifyNever(() => supabaseClient().storage);
      },
    );

    test('deletes the activity row for an authenticated user', () async {
      final storageBucket = FakeStorageBucketApi(
        bucketName: 'activity-photos',
        operations: operations(),
      );
      when(
        () => supabaseClient().storage,
      ).thenReturn(
        FakeSupabaseStorageClient({'activity-photos': storageBucket}),
      );
      when(() => supabaseClient().from(any())).thenAnswer((invocation) {
        final table = invocation.positionalArguments.first as String;
        if (table == 'activity_photos') {
          return builderForTable(
            table,
            selectRows: [
              {
                'storage_path': 'user-1/remote-1/photo-a.jpg',
                'thumbnail_path': 'user-1/remote-1/photo-a_thumb.jpg',
              },
            ],
          );
        }
        return builderForTable(table);
      });
      final service = SupabaseSyncService(
        repository: repository(),
        supabaseClient: supabaseClient(),
        connectivityChanges: connectivityController().stream,
        checkConnectivity: () async => [ConnectivityResult.none],
        currentUserIdProvider: () => 'user-1',
      );
      addTearDown(service.dispose);

      await service.deleteRemoteActivity('remote-1');

      expect(
        operations().where(
          (operation) =>
              operation.table == 'activity_photos' &&
              operation.kind == 'select',
        ),
        hasLength(1),
      );
      expect(
        operations().where(
          (operation) =>
              operation.table == 'activity_photos' &&
              operation.kind == 'eq' &&
              operation.eqColumn == 'activity_id' &&
              operation.eqValue == 'remote-1',
        ),
        hasLength(1),
      );
      expect(
        operations().where(
          (operation) =>
              operation.table == 'activity_photos' &&
              operation.kind == 'eq' &&
              operation.eqColumn == 'user_id' &&
              operation.eqValue == 'user-1',
        ),
        hasLength(1),
      );
      expect(
        operations().where(
          (operation) =>
              operation.table == 'activities' && operation.kind == 'delete',
        ),
        hasLength(1),
      );
      expect(
        operations().where(
          (operation) =>
              operation.table == 'activities' &&
              operation.kind == 'eq' &&
              operation.eqColumn == 'id' &&
              operation.eqValue == 'remote-1',
        ),
        hasLength(1),
      );
      expect(
        operations().where(
          (operation) =>
              operation.table == 'activities' &&
              operation.kind == 'eq' &&
              operation.eqColumn == 'user_id' &&
              operation.eqValue == 'user-1',
        ),
        hasLength(1),
      );
      expect(
        operations().where(
          (operation) =>
              operation.table == 'track_points' && operation.kind == 'delete',
        ),
        isEmpty,
      );
      expect(
        operations().where(
          (operation) =>
              operation.table == 'splits' && operation.kind == 'delete',
        ),
        isEmpty,
      );
      expect(
        operations().where(
          (operation) =>
              operation.table == 'kudos' && operation.kind == 'delete',
        ),
        isEmpty,
      );
      expect(
        operations().where(
          (operation) =>
              operation.table == 'comments' && operation.kind == 'delete',
        ),
        isEmpty,
      );
      expect(
        operations().where(
          (operation) =>
              operation.table == 'activity_photos' &&
              operation.kind == 'delete',
        ),
        isEmpty,
      );
    });

    test(
      'removes deduplicated storage paths before deleting the activity row',
      () async {
        final storageBucket = FakeStorageBucketApi(
          bucketName: 'activity-photos',
          operations: operations(),
        );
        when(
          () => supabaseClient().storage,
        ).thenReturn(
          FakeSupabaseStorageClient({'activity-photos': storageBucket}),
        );
        when(() => supabaseClient().from(any())).thenAnswer((invocation) {
          final table = invocation.positionalArguments.first as String;
          if (table == 'activity_photos') {
            return builderForTable(
              table,
              selectRows: [
                {
                  'storage_path': 'user-1/remote-2/photo-a.jpg',
                  'thumbnail_path': 'user-1/remote-2/photo-a_thumb.jpg',
                },
                {
                  'storage_path': 'user-1/remote-2/photo-a.jpg',
                  'thumbnail_path': '',
                },
                {
                  'storage_path': 'user-1/remote-2/photo-b.jpg',
                  'thumbnail_path': 'user-1/remote-2/photo-a_thumb.jpg',
                },
              ],
            );
          }
          return builderForTable(table);
        });
        final service = SupabaseSyncService(
          repository: repository(),
          supabaseClient: supabaseClient(),
          connectivityChanges: connectivityController().stream,
          checkConnectivity: () async => [ConnectivityResult.none],
          currentUserIdProvider: () => 'user-1',
        );
        addTearDown(service.dispose);

        await service.deleteRemoteActivity('remote-2');

        final storageRemoveOperationIndex = operations().indexWhere(
          (operation) =>
              operation.table == 'activity-photos' &&
              operation.kind == 'storage_remove',
        );
        final activityDeleteOperationIndex = operations().indexWhere(
          (operation) =>
              operation.table == 'activities' && operation.kind == 'delete',
        );
        expect(storageRemoveOperationIndex, greaterThanOrEqualTo(0));
        expect(activityDeleteOperationIndex, greaterThanOrEqualTo(0));
        expect(
          storageRemoveOperationIndex,
          lessThan(activityDeleteOperationIndex),
        );

        final storageOperation = operations().firstWhere(
          (operation) =>
              operation.table == 'activity-photos' &&
              operation.kind == 'storage_remove',
        );
        expect(
          storageOperation.payload,
          <String>[
            'user-1/remote-2/photo-a.jpg',
            'user-1/remote-2/photo-a_thumb.jpg',
            'user-1/remote-2/photo-b.jpg',
          ],
        );
      },
    );

    test(
      'ignores storage paths that are not owned by the current user activity',
      () async {
        final storageBucket = FakeStorageBucketApi(
          bucketName: 'activity-photos',
          operations: operations(),
        );
        when(
          () => supabaseClient().storage,
        ).thenReturn(
          FakeSupabaseStorageClient({'activity-photos': storageBucket}),
        );
        when(() => supabaseClient().from(any())).thenAnswer((invocation) {
          final table = invocation.positionalArguments.first as String;
          if (table == 'activity_photos') {
            return builderForTable(
              table,
              selectRows: [
                {
                  'storage_path': 'user-1/remote-5/photo-a.jpg',
                  'thumbnail_path': 'user-1/remote-5/photo-a_thumb.jpg',
                },
                {
                  'storage_path': 'user-1/remote-other/photo-b.jpg',
                  'thumbnail_path': 'user-2/remote-5/photo-b_thumb.jpg',
                },
                {
                  'storage_path': '  ',
                  'thumbnail_path': '/remote-5/photo-c_thumb.jpg',
                },
              ],
            );
          }
          return builderForTable(table);
        });
        final service = SupabaseSyncService(
          repository: repository(),
          supabaseClient: supabaseClient(),
          connectivityChanges: connectivityController().stream,
          checkConnectivity: () async => [ConnectivityResult.none],
          currentUserIdProvider: () => 'user-1',
        );
        addTearDown(service.dispose);

        await service.deleteRemoteActivity('remote-5');

        final storageOperation = operations().firstWhere(
          (operation) =>
              operation.table == 'activity-photos' &&
              operation.kind == 'storage_remove',
        );
        expect(
          storageOperation.payload,
          <String>[
            'user-1/remote-5/photo-a.jpg',
            'user-1/remote-5/photo-a_thumb.jpg',
          ],
        );
        expect(
          operations().where(
            (operation) =>
                operation.table == 'activities' && operation.kind == 'delete',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'skips storage cleanup when no persisted activity photos exist',
      () async {
        final storageBucket = FakeStorageBucketApi(
          bucketName: 'activity-photos',
          operations: operations(),
        );
        when(
          () => supabaseClient().storage,
        ).thenReturn(
          FakeSupabaseStorageClient({'activity-photos': storageBucket}),
        );
        when(() => supabaseClient().from(any())).thenAnswer((invocation) {
          final table = invocation.positionalArguments.first as String;
          if (table == 'activity_photos') {
            return builderForTable(table, selectRows: const []);
          }
          return builderForTable(table);
        });
        final service = SupabaseSyncService(
          repository: repository(),
          supabaseClient: supabaseClient(),
          connectivityChanges: connectivityController().stream,
          checkConnectivity: () async => [ConnectivityResult.none],
          currentUserIdProvider: () => 'user-1',
        );
        addTearDown(service.dispose);

        await service.deleteRemoteActivity('remote-3');

        expect(
          operations().where(
            (operation) =>
                operation.table == 'activity-photos' &&
                operation.kind == 'storage_remove',
          ),
          isEmpty,
        );
        expect(
          operations().where(
            (operation) =>
                operation.table == 'activities' && operation.kind == 'delete',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'swallows storage cleanup failures and still deletes the activity row',
      () async {
        final storageBucket = FakeStorageBucketApi(
          bucketName: 'activity-photos',
          operations: operations(),
          removeError: StateError('simulated storage failure'),
        );
        when(
          () => supabaseClient().storage,
        ).thenReturn(
          FakeSupabaseStorageClient({'activity-photos': storageBucket}),
        );
        when(() => supabaseClient().from(any())).thenAnswer((invocation) {
          final table = invocation.positionalArguments.first as String;
          if (table == 'activity_photos') {
            return builderForTable(
              table,
              selectRows: [
                {
                  'storage_path': 'user-1/remote-4/photo-a.jpg',
                  'thumbnail_path': null,
                },
              ],
            );
          }
          return builderForTable(table);
        });
        final service = SupabaseSyncService(
          repository: repository(),
          supabaseClient: supabaseClient(),
          connectivityChanges: connectivityController().stream,
          checkConnectivity: () async => [ConnectivityResult.none],
          currentUserIdProvider: () => 'user-1',
        );
        addTearDown(service.dispose);

        await service.deleteRemoteActivity('remote-4');

        expect(
          operations().where(
            (operation) =>
                operation.table == 'activities' && operation.kind == 'delete',
          ),
          hasLength(1),
        );
      },
    );
  });
}

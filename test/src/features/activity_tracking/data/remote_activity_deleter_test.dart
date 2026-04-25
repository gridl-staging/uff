import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/activity_tracking/data/remote_activity_deleter.dart';
import 'package:uff/src/utils/app_logger.dart';

import 'sync_service_test_support.dart';

// ## Test Scenarios
// - [negative] Throws StateError when no authenticated user ID is available
// - [positive] Deletes owned storage paths before deleting the activity row
// - [negative] Skips storage paths not owned by the current user activity
// - [error] Swallows storage cleanup failures and still deletes the activity row
// - [edge] Skips storage remove when there are no persisted activity photos
void main() {
  late MockSupabaseClient supabaseClient;
  late List<RecordedOperation> operations;

  FakeSyncQueryBuilder builderForTable(
    String table, {
    List<Map<String, dynamic>> selectRows = const <Map<String, dynamic>>[],
    Object? selectError,
  }) {
    return FakeSyncQueryBuilder(
      table: table,
      operations: operations,
      selectRows: selectRows,
      selectError: selectError,
    );
  }

  setUp(() {
    supabaseClient = MockSupabaseClient();
    operations = <RecordedOperation>[];
  });

  group('RemoteActivityDeleter.deleteRemoteActivity', () {
    test('throws StateError when user ID is null', () async {
      final deleter = RemoteActivityDeleter(
        supabaseClient: supabaseClient,
        currentUserIdProvider: () => null,
        logger: AppLogger(),
      );

      await expectLater(
        deleter.deleteRemoteActivity('remote-missing-user'),
        throwsStateError,
      );

      verifyNever(() => supabaseClient.from(any()));
      verifyNever(() => supabaseClient.storage);
    });

    test(
      'deletes owned storage paths before deleting the activity row',
      () async {
        final storageBucket = FakeStorageBucketApi(
          bucketName: 'activity-photos',
          operations: operations,
        );
        when(
          () => supabaseClient.storage,
        ).thenReturn(
          FakeSupabaseStorageClient({'activity-photos': storageBucket}),
        );
        when(() => supabaseClient.from(any())).thenAnswer((invocation) {
          final table = invocation.positionalArguments.first as String;
          if (table == 'activity_photos') {
            return builderForTable(
              table,
              selectRows: [
                {
                  'storage_path': 'user-1/remote-1/photo-a.jpg',
                  'thumbnail_path': 'user-1/remote-1/photo-a_thumb.jpg',
                },
                {
                  'storage_path': 'user-1/remote-1/photo-a.jpg',
                  'thumbnail_path': '',
                },
              ],
            );
          }
          return builderForTable(table);
        });

        final deleter = RemoteActivityDeleter(
          supabaseClient: supabaseClient,
          currentUserIdProvider: () => 'user-1',
          logger: AppLogger(),
        );

        await deleter.deleteRemoteActivity('remote-1');

        final storageRemoveOperationIndex = operations.indexWhere(
          (operation) =>
              operation.table == 'activity-photos' &&
              operation.kind == 'storage_remove',
        );
        final activityDeleteOperationIndex = operations.indexWhere(
          (operation) =>
              operation.table == 'activities' && operation.kind == 'delete',
        );
        expect(storageRemoveOperationIndex, greaterThanOrEqualTo(0));
        expect(activityDeleteOperationIndex, greaterThanOrEqualTo(0));
        expect(
          storageRemoveOperationIndex,
          lessThan(activityDeleteOperationIndex),
        );

        final storageOperation = operations.firstWhere(
          (operation) =>
              operation.table == 'activity-photos' &&
              operation.kind == 'storage_remove',
        );
        expect(
          storageOperation.payload,
          <String>[
            'user-1/remote-1/photo-a.jpg',
            'user-1/remote-1/photo-a_thumb.jpg',
          ],
        );

        expect(
          operations.where(
            (operation) =>
                operation.table == 'activities' &&
                operation.kind == 'eq' &&
                operation.eqColumn == 'id' &&
                operation.eqValue == 'remote-1',
          ),
          hasLength(1),
        );
        expect(
          operations.where(
            (operation) =>
                operation.table == 'activities' &&
                operation.kind == 'eq' &&
                operation.eqColumn == 'user_id' &&
                operation.eqValue == 'user-1',
          ),
          hasLength(1),
        );
      },
    );

    test('skips unowned storage paths and only removes owned paths', () async {
      final storageBucket = FakeStorageBucketApi(
        bucketName: 'activity-photos',
        operations: operations,
      );
      when(
        () => supabaseClient.storage,
      ).thenReturn(
        FakeSupabaseStorageClient({'activity-photos': storageBucket}),
      );
      when(() => supabaseClient.from(any())).thenAnswer((invocation) {
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

      final deleter = RemoteActivityDeleter(
        supabaseClient: supabaseClient,
        currentUserIdProvider: () => 'user-1',
        logger: AppLogger(),
      );

      await deleter.deleteRemoteActivity('remote-5');

      final storageOperation = operations.firstWhere(
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
        operations.where(
          (operation) =>
              operation.table == 'activities' && operation.kind == 'delete',
        ),
        hasLength(1),
      );
    });

    test(
      'swallows storage cleanup failures and still deletes activity row',
      () async {
        final storageBucket = FakeStorageBucketApi(
          bucketName: 'activity-photos',
          operations: operations,
          removeError: StateError('simulated storage failure'),
        );
        when(
          () => supabaseClient.storage,
        ).thenReturn(
          FakeSupabaseStorageClient({'activity-photos': storageBucket}),
        );
        when(() => supabaseClient.from(any())).thenAnswer((invocation) {
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

        final deleter = RemoteActivityDeleter(
          supabaseClient: supabaseClient,
          currentUserIdProvider: () => 'user-1',
          logger: AppLogger(),
        );

        await deleter.deleteRemoteActivity('remote-4');

        expect(
          operations.where(
            (operation) =>
                operation.table == 'activities' && operation.kind == 'delete',
          ),
          hasLength(1),
        );
      },
    );

    test('skips storage remove call when no activity photos exist', () async {
      final storageBucket = FakeStorageBucketApi(
        bucketName: 'activity-photos',
        operations: operations,
      );
      when(
        () => supabaseClient.storage,
      ).thenReturn(
        FakeSupabaseStorageClient({'activity-photos': storageBucket}),
      );
      when(() => supabaseClient.from(any())).thenAnswer((invocation) {
        final table = invocation.positionalArguments.first as String;
        if (table == 'activity_photos') {
          return builderForTable(table);
        }
        return builderForTable(table);
      });

      final deleter = RemoteActivityDeleter(
        supabaseClient: supabaseClient,
        currentUserIdProvider: () => 'user-1',
        logger: AppLogger(),
      );

      await deleter.deleteRemoteActivity('remote-3');

      expect(
        operations.where(
          (operation) =>
              operation.table == 'activity-photos' &&
              operation.kind == 'storage_remove',
        ),
        isEmpty,
      );
      expect(
        operations.where(
          (operation) =>
              operation.table == 'activities' && operation.kind == 'delete',
        ),
        hasLength(1),
      );
    });
  });
}

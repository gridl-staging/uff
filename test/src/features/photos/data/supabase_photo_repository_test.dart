import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/photos/data/supabase_photo_repository.dart';

import '../../../test_helpers/supabase_query_test_doubles.dart';

// ## Test Scenarios
// - [positive] `loadActivityPhotos()` applies activity scoping, sort order,
//   and signed-url mapping from persisted rows.
// - [positive] `uploadPhoto()` builds canonical storage paths, uploads bytes,
//   and returns persisted metadata.
// - [positive] `uploadPhoto()` inserts latitude/longitude exactly as provided,
//   including explicit null.
// - [negative] Upload/delete operations reject missing auth and foreign-owner
//   delete attempts.
// - [error] Upload and signed-url failures surface deterministic fallback
//   behavior and cleanup semantics.
// - [edge] Delete path deduplication and persisted-path preference prevent
//   forged caller paths from controlling storage deletes.
// - [isolation] Separate users keep repository writes and deletes isolated.
class MockSupabaseStorageClient extends Mock implements SupabaseStorageClient {}

class MockStorageFileApi extends Mock implements StorageFileApi {}

Map<String, dynamic> _photoRow({
  String id = 'photo-1',
  String activityId = 'activity-1',
  String userId = 'user-1',
  String storagePath = 'user-1/activity-1/photo-1.jpg',
  String? thumbnailPath = 'user-1/activity-1/photo-1-thumb.jpg',
  int sortOrder = 0,
  String createdAt = '2026-03-17T12:30:00Z',
}) => {
  'id': id,
  'activity_id': activityId,
  'user_id': userId,
  'storage_path': storagePath,
  'thumbnail_path': thumbnailPath,
  'sort_order': sortOrder,
  'created_at': createdAt,
};

void main() {
  late MockSupabaseClient mockClient;
  late MockSupabaseStorageClient mockStorageClient;
  late MockStorageFileApi mockStorageFileApi;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const FileOptions());
  });

  setUp(() {
    mockClient = MockSupabaseClient();
    mockStorageClient = MockSupabaseStorageClient();
    mockStorageFileApi = MockStorageFileApi();

    when(() => mockClient.storage).thenReturn(mockStorageClient);
    when(
      () => mockStorageClient.from('activity-photos'),
    ).thenReturn(mockStorageFileApi);
    when(
      () => mockStorageFileApi.uploadBinary(
        any(),
        any(),
        fileOptions: any(named: 'fileOptions'),
      ),
    ).thenAnswer(
      (invocation) async => invocation.positionalArguments[0]! as String,
    );
    when(
      () => mockStorageFileApi.createSignedUrl(any(), any()),
    ).thenAnswer((invocation) async {
      final path = invocation.positionalArguments[0]! as String;
      return 'signed:$path';
    });
    when(() => mockStorageFileApi.remove(any())).thenAnswer((_) async => []);
    when(() => mockClient.from('activities')).thenAnswer(
      (_) => RecordingSupabaseQueryBuilder(
        selectRows: const [
          {'id': 'activity-1', 'user_id': 'user-1'},
        ],
      ),
    );
  });

  group('SupabasePhotoRepository', () {
    test('scopes list query by activity id and ascending sort order', () async {
      final fakeBuilder = RecordingSupabaseQueryBuilder(
        selectRows: [_photoRow(id: 'photo-ordered')],
      );
      when(
        () => mockClient.from('activity_photos'),
      ).thenAnswer((_) => fakeBuilder);
      final repository = SupabasePhotoRepository(
        mockClient,
        currentUserIdProvider: () => 'user-1',
      );

      await repository.loadActivityPhotos('activity-42');

      expect(
        fakeBuilder.selectBuilder.eqCalls,
        contains(
          isA<EqFilterCall>()
              .having((call) => call.column, 'column', 'activity_id')
              .having((call) => call.value, 'value', 'activity-42'),
        ),
      );
      expect(fakeBuilder.selectBuilder.lastOrderedColumn, 'sort_order');
      expect(fakeBuilder.selectBuilder.lastOrderAscending, isTrue);
    });

    test(
      'throws when upload is attempted without an authenticated user',
      () async {
        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => null,
        );

        await expectLater(
          repository.uploadPhoto(
            activityId: 'activity-1',
            bytes: Uint8List.fromList([9, 8, 7]),
            fileName: 'finish-line.jpg',
            sortOrder: 0,
          ),
          throwsStateError,
        );

        verifyNever(() => mockStorageClient.from('activity-photos'));
        verifyNever(() => mockClient.from('activity_photos'));
      },
    );

    test(
      'throws when delete is attempted without an authenticated user',
      () async {
        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => null,
        );

        await expectLater(
          repository.deletePhoto(activityPhotoFromJson(_photoRow())),
          throwsStateError,
        );

        verifyNever(() => mockClient.from('activity_photos'));
        verifyNever(() => mockStorageFileApi.remove(any()));
      },
    );

    test(
      'builds storage and thumbnail paths using user/activity/uuid',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          insertRows: [_photoRow(id: 'photo-created')],
        );
        when(
          () => mockClient.from('activity_photos'),
        ).thenAnswer((_) => fakeBuilder);

        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'generated-uuid',
          compressPhotoBytes: (bytes) async => bytes,
          createThumbnailBytes: (bytes) async => Uint8List.fromList([1, 2, 3]),
        );

        final photo = await repository.uploadPhoto(
          activityId: 'activity-1',
          bytes: Uint8List.fromList([9, 8, 7]),
          fileName: 'finish-line.png',
          sortOrder: 7,
        );

        expect(photo.id, 'photo-created');
        expect(
          fakeBuilder.lastInsertPayload!['storage_path'],
          'user-1/activity-1/generated-uuid.png',
        );
        expect(
          fakeBuilder.lastInsertPayload!['thumbnail_path'],
          'user-1/activity-1/generated-uuid_thumb.png',
        );
        expect(fakeBuilder.lastInsertPayload!['activity_id'], 'activity-1');
        expect(fakeBuilder.lastInsertPayload!['user_id'], 'user-1');
        expect(fakeBuilder.lastInsertPayload!['sort_order'], 7);
      },
    );

    test(
      'verifies the activity belongs to the signed-in user before upload',
      () async {
        final activityBuilder = RecordingSupabaseQueryBuilder(
          selectRows: const [
            {'id': 'activity-1', 'user_id': 'user-1'},
          ],
        );
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          insertRows: [_photoRow(id: 'photo-created')],
        );
        when(
          () => mockClient.from('activities'),
        ).thenAnswer((_) => activityBuilder);
        when(
          () => mockClient.from('activity_photos'),
        ).thenAnswer((_) => fakeBuilder);

        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'generated-uuid',
          compressPhotoBytes: (bytes) async => bytes,
          createThumbnailBytes: (_) async => null,
        );

        await repository.uploadPhoto(
          activityId: 'activity-1',
          bytes: Uint8List.fromList([9, 8, 7]),
          fileName: 'finish-line.jpg',
          sortOrder: 0,
        );

        expect(activityBuilder.lastSelectColumns, 'id,user_id');
        expect(
          activityBuilder.selectBuilder.eqCalls,
          contains(
            isA<EqFilterCall>()
                .having((call) => call.column, 'column', 'id')
                .having((call) => call.value, 'value', 'activity-1'),
          ),
        );
      },
    );

    test(
      'throws when upload targets an activity owned by another user',
      () async {
        final activityBuilder = RecordingSupabaseQueryBuilder(
          selectRows: const [
            {'id': 'activity-1', 'user_id': 'other-user'},
          ],
        );
        when(
          () => mockClient.from('activities'),
        ).thenAnswer((_) => activityBuilder);

        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'generated-uuid',
          compressPhotoBytes: (bytes) async => bytes,
          createThumbnailBytes: (_) async => null,
        );

        await expectLater(
          repository.uploadPhoto(
            activityId: 'activity-1',
            bytes: Uint8List.fromList([9, 8, 7]),
            fileName: 'finish-line.jpg',
            sortOrder: 0,
          ),
          throwsStateError,
        );

        verifyNever(
          () => mockStorageFileApi.uploadBinary(
            any(),
            any(),
            fileOptions: any(named: 'fileOptions'),
          ),
        );
        verifyNever(() => mockClient.from('activity_photos'));
      },
    );

    test('includes explicit latitude/longitude in insert payload', () async {
      final fakeBuilder = RecordingSupabaseQueryBuilder(
        insertRows: [_photoRow(id: 'photo-with-coordinates')],
      );
      when(
        () => mockClient.from('activity_photos'),
      ).thenAnswer((_) => fakeBuilder);

      final repository = SupabasePhotoRepository(
        mockClient,
        currentUserIdProvider: () => 'user-1',
        uuidGenerator: () => 'generated-uuid',
        compressPhotoBytes: (bytes) async => bytes,
        createThumbnailBytes: (_) async => null,
      );

      await repository.uploadPhoto(
        activityId: 'activity-1',
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'finish-line.jpg',
        sortOrder: 1,
        latitude: 40.7128,
        longitude: -74.006,
      );

      expect(fakeBuilder.lastInsertPayload!['latitude'], 40.7128);
      expect(fakeBuilder.lastInsertPayload!['longitude'], -74.006);
    });

    test(
      'includes null latitude/longitude in insert payload when absent',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          insertRows: [_photoRow(id: 'photo-null-coordinates')],
        );
        when(
          () => mockClient.from('activity_photos'),
        ).thenAnswer((_) => fakeBuilder);

        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'generated-uuid',
          compressPhotoBytes: (bytes) async => bytes,
          createThumbnailBytes: (_) async => null,
        );

        await repository.uploadPhoto(
          activityId: 'activity-1',
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'finish-line.jpg',
          sortOrder: 1,
        );

        expect(fakeBuilder.lastInsertPayload!.containsKey('latitude'), isTrue);
        expect(fakeBuilder.lastInsertPayload!['latitude'], isNull);
        expect(fakeBuilder.lastInsertPayload!.containsKey('longitude'), isTrue);
        expect(fakeBuilder.lastInsertPayload!['longitude'], isNull);
      },
    );

    test(
      'falls back to .jpg when filename extension sanitizes to empty',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          insertRows: [_photoRow(id: 'photo-default-extension')],
        );
        when(
          () => mockClient.from('activity_photos'),
        ).thenAnswer((_) => fakeBuilder);
        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'generated-uuid',
          compressPhotoBytes: (bytes) async => bytes,
          createThumbnailBytes: (_) async => null,
        );

        await repository.uploadPhoto(
          activityId: 'activity-1',
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'camera.!!!',
          sortOrder: 0,
        );

        expect(
          fakeBuilder.lastInsertPayload!['storage_path'],
          'user-1/activity-1/generated-uuid.jpg',
        );
        verify(
          () => mockStorageFileApi.uploadBinary(
            'user-1/activity-1/generated-uuid.jpg',
            any(),
            fileOptions: any(named: 'fileOptions'),
          ),
        ).called(1);
      },
    );

    test(
      'falls back to original bytes when compressor returns null-like data',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          insertRows: [_photoRow(id: 'photo-compression-fallback')],
        );
        when(
          () => mockClient.from('activity_photos'),
        ).thenAnswer((_) => fakeBuilder);
        final originalBytes = Uint8List.fromList([9, 8, 7, 6]);

        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'generated-uuid',
          compressPhotoBytes: (_) async => Uint8List(0),
          createThumbnailBytes: (_) async => null,
        );

        final photo = await repository.uploadPhoto(
          activityId: 'activity-1',
          bytes: originalBytes,
          fileName: 'finish-line.jpg',
          sortOrder: 1,
        );

        expect(photo.id, 'photo-compression-fallback');
        final capturedArguments = verify(
          () => mockStorageFileApi.uploadBinary(
            'user-1/activity-1/generated-uuid.jpg',
            captureAny(),
            fileOptions: any(named: 'fileOptions'),
          ),
        ).captured;
        expect(capturedArguments, hasLength(1));
        expect(capturedArguments.single, orderedEquals(originalBytes));
        verifyNever(
          () => mockStorageFileApi.uploadBinary(
            'user-1/activity-1/generated-uuid_thumb.jpg',
            any(),
            fileOptions: any(named: 'fileOptions'),
          ),
        );
        expect(fakeBuilder.lastInsertPayload!['thumbnail_path'], isNull);
      },
    );

    test(
      'falls back thumbnail signed URL to storage path when thumbnail is null',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _photoRow(
              id: 'photo-no-thumb',
              storagePath: 'user-1/activity-1/photo-main.jpg',
              thumbnailPath: null,
            ),
          ],
        );
        when(
          () => mockClient.from('activity_photos'),
        ).thenAnswer((_) => fakeBuilder);

        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => 'user-1',
        );

        final photos = await repository.loadActivityPhotos('activity-1');

        expect(photos, hasLength(1));
        expect(
          photos.single.signedStorageUrl,
          'signed:user-1/activity-1/photo-main.jpg',
        );
        expect(
          photos.single.signedThumbnailUrl,
          'signed:user-1/activity-1/photo-main.jpg',
        );
        verify(
          () => mockStorageFileApi.createSignedUrl(
            'user-1/activity-1/photo-main.jpg',
            3600,
          ),
        ).called(1);
      },
    );

    test(
      'falls back thumbnail signed URL to storage path when thumbnail path is blank',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _photoRow(
              id: 'photo-empty-thumb',
              storagePath: 'user-1/activity-1/photo-main.jpg',
              thumbnailPath: '',
            ),
          ],
        );
        when(
          () => mockClient.from('activity_photos'),
        ).thenAnswer((_) => fakeBuilder);

        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => 'user-1',
        );

        final photos = await repository.loadActivityPhotos('activity-1');

        expect(photos, hasLength(1));
        expect(
          photos.single.signedThumbnailUrl,
          'signed:user-1/activity-1/photo-main.jpg',
        );
        verify(
          () => mockStorageFileApi.createSignedUrl(
            'user-1/activity-1/photo-main.jpg',
            3600,
          ),
        ).called(1);
      },
    );

    test(
      'delegates signed URL creation for storage and thumbnail paths',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _photoRow(
              storagePath: 'user-1/activity-1/photo-main.jpg',
              thumbnailPath: 'user-1/activity-1/photo-thumb.jpg',
            ),
          ],
        );
        when(
          () => mockClient.from('activity_photos'),
        ).thenAnswer((_) => fakeBuilder);

        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => 'user-1',
        );

        final photos = await repository.loadActivityPhotos('activity-1');

        expect(
          photos.single.signedStorageUrl,
          'signed:user-1/activity-1/photo-main.jpg',
        );
        expect(
          photos.single.signedThumbnailUrl,
          'signed:user-1/activity-1/photo-thumb.jpg',
        );
        verify(
          () => mockStorageFileApi.createSignedUrl(
            'user-1/activity-1/photo-main.jpg',
            3600,
          ),
        ).called(1);
        verify(
          () => mockStorageFileApi.createSignedUrl(
            'user-1/activity-1/photo-thumb.jpg',
            3600,
          ),
        ).called(1);
      },
    );

    test(
      'returns persisted photos when list signed URL creation fails',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _photoRow(
              id: 'photo-sign-failure',
              storagePath: 'user-1/activity-1/photo-main.jpg',
              thumbnailPath: 'user-1/activity-1/photo-thumb.jpg',
            ),
          ],
        );
        when(
          () => mockClient.from('activity_photos'),
        ).thenAnswer((_) => fakeBuilder);
        when(
          () => mockStorageFileApi.createSignedUrl(any(), any()),
        ).thenThrow(StateError('signing failed'));

        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => 'user-1',
        );

        final photos = await repository.loadActivityPhotos('activity-1');

        expect(photos, hasLength(1));
        expect(photos.single.id, 'photo-sign-failure');
        expect(photos.single.storagePath, 'user-1/activity-1/photo-main.jpg');
        expect(
          photos.single.thumbnailPath,
          'user-1/activity-1/photo-thumb.jpg',
        );
        expect(photos.single.signedStorageUrl, isNull);
        expect(photos.single.signedThumbnailUrl, isNull);
      },
    );

    test('removes uploaded objects when metadata insert fails', () async {
      when(
        () => mockClient.from('activity_photos'),
      ).thenThrow(StateError('db insert failed'));

      final repository = SupabasePhotoRepository(
        mockClient,
        currentUserIdProvider: () => 'user-1',
        uuidGenerator: () => 'generated-uuid',
        compressPhotoBytes: (bytes) async => bytes,
        createThumbnailBytes: (bytes) async => Uint8List.fromList([1, 2, 3]),
      );

      await expectLater(
        repository.uploadPhoto(
          activityId: 'activity-1',
          bytes: Uint8List.fromList([9, 8, 7]),
          fileName: 'finish-line.jpg',
          sortOrder: 0,
        ),
        throwsStateError,
      );

      verify(
        () => mockStorageFileApi.remove([
          'user-1/activity-1/generated-uuid.jpg',
          'user-1/activity-1/generated-uuid_thumb.jpg',
        ]),
      ).called(1);
    });

    test(
      'maps Stage 1 photo-limit token to ActivityPhotoLimitExceededException',
      () async {
        when(
          () => mockClient.from('activity_photos'),
        ).thenThrow(StateError('UFF_LIMIT_ACTIVITY_PHOTOS_PER_ACTIVITY'));

        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'generated-uuid',
          compressPhotoBytes: (bytes) async => bytes,
          createThumbnailBytes: (bytes) async => Uint8List.fromList([1, 2, 3]),
        );

        await expectLater(
          repository.uploadPhoto(
            activityId: 'activity-1',
            bytes: Uint8List.fromList([9, 8, 7]),
            fileName: 'finish-line.jpg',
            sortOrder: 0,
          ),
          // Stage 3: ActivityPhotoLimitExceededException is a plain sentinel
          // class with no fields; isA is the most concrete matcher available.
          throwsA(isA<ActivityPhotoLimitExceededException>()),
        );

        verify(
          () => mockStorageFileApi.remove([
            'user-1/activity-1/generated-uuid.jpg',
            'user-1/activity-1/generated-uuid_thumb.jpg',
          ]),
        ).called(1);
      },
    );

    test(
      'deduplicates storage delete paths before removing photo metadata',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _photoRow(
              id: 'photo-delete',
              storagePath: 'user-1/activity-1/photo-delete.jpg',
              thumbnailPath: 'user-1/activity-1/photo-delete.jpg',
            ),
          ],
        );
        when(
          () => mockClient.from('activity_photos'),
        ).thenAnswer((_) => fakeBuilder);
        final photo = activityPhotoFromJson(
          _photoRow(
            id: 'photo-delete',
            storagePath: 'user-1/activity-1/photo-delete.jpg',
            thumbnailPath: 'user-1/activity-1/photo-delete.jpg',
          ),
        );

        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => 'user-1',
        );
        await repository.deletePhoto(photo);

        verify(
          () => mockStorageFileApi.remove([
            'user-1/activity-1/photo-delete.jpg',
          ]),
        ).called(1);
        expect(fakeBuilder.deleteCalled, isTrue);
        expect(fakeBuilder.deleteBuilder.lastEqColumn, 'id');
        expect(fakeBuilder.deleteBuilder.lastEqValue, 'photo-delete');
      },
    );

    test(
      'delete uses persisted storage paths instead of caller-provided paths',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _photoRow(
              id: 'photo-delete',
              storagePath: 'user-1/activity-1/persisted.jpg',
              thumbnailPath: 'user-1/activity-1/persisted_thumb.jpg',
            ),
          ],
        );
        when(
          () => mockClient.from('activity_photos'),
        ).thenAnswer((_) => fakeBuilder);
        final forgedPhoto = activityPhotoFromJson(
          _photoRow(
            id: 'photo-delete',
            storagePath: 'user-1/activity-1/forged.jpg',
            thumbnailPath: 'user-1/activity-1/forged_thumb.jpg',
          ),
        );

        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => 'user-1',
        );
        await repository.deletePhoto(forgedPhoto);

        verify(
          () => mockStorageFileApi.remove([
            'user-1/activity-1/persisted.jpg',
            'user-1/activity-1/persisted_thumb.jpg',
          ]),
        ).called(1);
        expect(fakeBuilder.deleteBuilder.lastEqValue, 'photo-delete');
      },
    );

    test('delete rejects persisted photos owned by another user', () async {
      final fakeBuilder = RecordingSupabaseQueryBuilder(
        selectRows: [
          _photoRow(
            id: 'photo-delete',
            userId: 'user-2',
            storagePath: 'user-2/activity-1/photo-delete.jpg',
          ),
        ],
      );
      when(
        () => mockClient.from('activity_photos'),
      ).thenAnswer((_) => fakeBuilder);

      final repository = SupabasePhotoRepository(
        mockClient,
        currentUserIdProvider: () => 'user-1',
      );

      await expectLater(
        repository.deletePhoto(
          activityPhotoFromJson(
            _photoRow(
              id: 'photo-delete',
              storagePath: 'user-1/activity-1/forged.jpg',
            ),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Cannot delete activity photos owned by another user.',
          ),
        ),
      );

      verifyNever(() => mockStorageFileApi.remove(any()));
      expect(fakeBuilder.deleteCalled, isFalse);
    });

    test(
      'returns persisted photo when signed URL creation fails',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          insertRows: [_photoRow(id: 'photo-created')],
        );
        when(
          () => mockClient.from('activity_photos'),
        ).thenAnswer((_) => fakeBuilder);
        when(
          () => mockStorageFileApi.createSignedUrl(any(), any()),
        ).thenThrow(StateError('signing failed'));

        final repository = SupabasePhotoRepository(
          mockClient,
          currentUserIdProvider: () => 'user-1',
          uuidGenerator: () => 'generated-uuid',
          compressPhotoBytes: (bytes) async => bytes,
          createThumbnailBytes: (bytes) async => Uint8List.fromList([1, 2, 3]),
        );

        final photo = await repository.uploadPhoto(
          activityId: 'activity-1',
          bytes: Uint8List.fromList([9, 8, 7]),
          fileName: 'finish-line.jpg',
          sortOrder: 0,
        );

        expect(photo.id, 'photo-created');
        expect(photo.signedStorageUrl, isNull);
        expect(photo.signedThumbnailUrl, isNull);
        verifyNever(() => mockStorageFileApi.remove(any()));
      },
    );
  });
}

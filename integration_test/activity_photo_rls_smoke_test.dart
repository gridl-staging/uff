import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/photos/data/supabase_photo_repository.dart';

import 'supabase_smoke_helpers.dart';

/// ## Test Scenarios
/// - `[positive]` Owner loads private activity photo metadata in exact sort order.
/// - `[positive]` Owner uploads and downloads private activity storage object bytes at an owned activity path.
/// - `[negative]` Stranger sees zero rows for private and followers-only activity metadata.
/// - `[negative]` Cross-user insert and delete attempts cannot mutate owner metadata rows.
/// - `[negative]` Stranger cannot list, download, delete, or upload objects under owner private activity storage paths.
/// - `[isolation]` Storage object insert policy rejects mismatched user/activity path segments for cross-user writes.
/// - `[isolation]` Followers-only and public visibility paths stay aligned with can_view_activity semantics.
void main() {
  group('Activity photo metadata RLS smoke test', skip: skipReason, () {
    late SmokeTestUser owner;
    late SmokeTestUser follower;
    late SmokeTestUser stranger;
    late SupabasePhotoRepository ownerRepository;
    late SupabasePhotoRepository followerRepository;
    late SupabasePhotoRepository strangerRepository;

    setUp(() async {
      owner = await createSignedInTestUser(displayName: 'Photo Owner');
      follower = await createSignedInTestUser(displayName: 'Photo Follower');
      stranger = await createSignedInTestUser(displayName: 'Photo Stranger');
      ownerRepository = SupabasePhotoRepository(owner.client);
      followerRepository = SupabasePhotoRepository(follower.client);
      strangerRepository = SupabasePhotoRepository(stranger.client);
    });

    tearDown(() async {
      await cleanupSmokeTestUsers([owner, follower, stranger]);
    });

    test(
      'owner reads private metadata in exact order and strangers see none',
      () async {
        final fixture = await _seedOwnerActivitiesAndMetadata(
          owner.client,
          owner.userId,
        );

        final ownerPrivatePhotos = await ownerRepository.loadActivityPhotos(
          fixture.privateActivityId,
        );
        expect(ownerPrivatePhotos.map((photo) => photo.id).toList(), [
          fixture.privateLowSortRow.id,
          fixture.privateHighSortRow.id,
        ]);
        expect(ownerPrivatePhotos.map((photo) => photo.sortOrder).toList(), [
          1,
          3,
        ]);
        expect(
          ownerPrivatePhotos.map((photo) => photo.storagePath).toList(),
          [
            fixture.privateLowSortRow.storagePath,
            fixture.privateHighSortRow.storagePath,
          ],
        );

        final ownerDirectPrivateRows = await _loadPhotoRows(
          owner.client,
          activityId: fixture.privateActivityId,
          columns: 'id,sort_order,storage_path',
        );
        _expectPhotoRows(
          ownerDirectPrivateRows,
          ids: [
            fixture.privateLowSortRow.id,
            fixture.privateHighSortRow.id,
          ],
          sortOrders: [1, 3],
          storagePaths: [
            fixture.privateLowSortRow.storagePath,
            fixture.privateHighSortRow.storagePath,
          ],
        );

        final strangerPrivatePhotos = await strangerRepository
            .loadActivityPhotos(
              fixture.privateActivityId,
            );
        expect(strangerPrivatePhotos, isEmpty);
        final strangerDirectPrivateRows = await _loadPhotoRows(
          stranger.client,
          activityId: fixture.privateActivityId,
          columns: 'id',
        );
        expect(strangerDirectPrivateRows, isEmpty);
      },
    );

    test(
      'followers and public visibility stay aligned with can_view_activity',
      () async {
        final fixture = await _seedOwnerActivitiesAndMetadata(
          owner.client,
          owner.userId,
        );

        final followerFollowersPhotosBeforeFollow = await followerRepository
            .loadActivityPhotos(fixture.followersActivityId);
        expect(followerFollowersPhotosBeforeFollow, isEmpty);

        await seedAcceptedFollow(
          requesterClient: follower.client,
          targetClient: owner.client,
        );

        final followerFollowersPhotosAfterFollow = await followerRepository
            .loadActivityPhotos(fixture.followersActivityId);
        expect(
          followerFollowersPhotosAfterFollow.map((photo) => photo.id).toList(),
          [fixture.followersRow.id],
        );
        expect(
          followerFollowersPhotosAfterFollow
              .map((photo) => photo.sortOrder)
              .toList(),
          [0],
        );
        final followerDirectFollowersRows = await _loadPhotoRows(
          follower.client,
          activityId: fixture.followersActivityId,
          columns: 'id,sort_order',
        );
        _expectPhotoRows(
          followerDirectFollowersRows,
          ids: [fixture.followersRow.id],
          sortOrders: [0],
        );

        final strangerFollowersPhotos = await strangerRepository
            .loadActivityPhotos(
              fixture.followersActivityId,
            );
        expect(strangerFollowersPhotos, isEmpty);
        final strangerDirectFollowersRows = await _loadPhotoRows(
          stranger.client,
          activityId: fixture.followersActivityId,
          columns: 'id',
        );
        expect(strangerDirectFollowersRows, isEmpty);

        final strangerPublicPhotos = await strangerRepository
            .loadActivityPhotos(
              fixture.publicActivityId,
            );
        expect(strangerPublicPhotos.map((photo) => photo.id).toList(), [
          fixture.publicRow.id,
        ]);
        final strangerDirectPublicRows = await _loadPhotoRows(
          stranger.client,
          activityId: fixture.publicActivityId,
          columns: 'id,sort_order',
        );
        _expectPhotoRows(
          strangerDirectPublicRows,
          ids: [fixture.publicRow.id],
          sortOrders: [0],
        );
      },
    );

    test(
      'cross-user insert and delete attempts cannot mutate owner metadata',
      () async {
        final fixture = await _seedOwnerActivitiesAndMetadata(
          owner.client,
          owner.userId,
        );

        await expectLater(
          () => stranger.client.from('activity_photos').insert({
            'activity_id': fixture.privateActivityId,
            'user_id': stranger.userId,
            'storage_path': buildActivityPhotoStorageObjectPath(
              userId: stranger.userId,
              activityId: fixture.privateActivityId,
              fileName: 'cross-user-insert.jpg',
            ),
            'thumbnail_path': null,
            'sort_order': 9,
          }),
          throwsA(
            isA<PostgrestException>().having(
              (error) => error.message,
              'message',
              contains('row-level security'),
            ),
          ),
        );

        await stranger.client
            .from('activity_photos')
            .delete()
            .eq('id', fixture.privateLowSortRow.id);

        final ownerPrivateRowsAfterCrossUserDelete = await _loadPhotoRows(
          owner.client,
          activityId: fixture.privateActivityId,
          columns: 'id,sort_order',
        );
        _expectPhotoRows(
          ownerPrivateRowsAfterCrossUserDelete,
          ids: [fixture.privateLowSortRow.id, fixture.privateHighSortRow.id],
          sortOrders: [1, 3],
        );
      },
    );

    test(
      'owner uploads and downloads private activity object bytes successfully',
      () async {
        final expectedBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
        final seededObject = await _seedOwnedPrivateActivityObject(
          owner: owner,
          startedAt: DateTime.utc(2026, 3, 21, 10),
          title: 'Owner Private Storage Activity',
          fileName: 'test-photo.jpg',
          bytes: expectedBytes,
        );

        final downloadedBytes = await owner.client.storage
            .from('activity-photos')
            .download(seededObject.objectPath);
        expect(downloadedBytes, expectedBytes);
      },
    );

    test(
      'stranger cannot list or download owner private activity objects',
      () async {
        final expectedBytes = Uint8List.fromList([7, 8, 9, 10]);
        final seededObject = await _seedOwnedPrivateActivityObject(
          owner: owner,
          startedAt: DateTime.utc(2026, 3, 21, 11),
          title: 'Owner Private List Download Activity',
          fileName: 'test-photo.jpg',
          bytes: expectedBytes,
        );

        final listedObjects = await stranger.client.storage
            .from('activity-photos')
            .list(path: '${owner.userId}/${seededObject.activityId}');
        expect(listedObjects, <FileObject>[]);

        await expectLater(
          () => stranger.client.storage
              .from('activity-photos')
              .download(
                seededObject.objectPath,
              ),
          throwsA(isA<StorageException>()),
        );
      },
    );

    test(
      'stranger cannot delete owner private activity object',
      () async {
        final expectedBytes = Uint8List.fromList([11, 12, 13, 14]);
        final seededObject = await _seedOwnedPrivateActivityObject(
          owner: owner,
          startedAt: DateTime.utc(2026, 3, 21, 12),
          title: 'Owner Private Delete Activity',
          fileName: 'test-photo.jpg',
          bytes: expectedBytes,
        );

        await stranger.client.storage.from('activity-photos').remove([
          seededObject.objectPath,
        ]);

        final ownerBytesAfterDeleteAttempt = await owner.client.storage
            .from('activity-photos')
            .download(seededObject.objectPath);
        expect(ownerBytesAfterDeleteAttempt, expectedBytes);
      },
    );

    test(
      'stranger cannot insert into owner activity path or mismatched activity path',
      () async {
        final seededObject = await _seedOwnedPrivateActivityObject(
          owner: owner,
          startedAt: DateTime.utc(2026, 3, 21, 13),
          title: 'Owner Private Insert Activity',
          fileName: 'existing-owner-photo.jpg',
          bytes: Uint8List.fromList([99]),
        );
        final ownerPath = buildActivityPhotoStorageObjectPath(
          userId: owner.userId,
          activityId: seededObject.activityId,
          fileName: 'malicious.jpg',
        );
        final mismatchedPath = buildActivityPhotoStorageObjectPath(
          userId: stranger.userId,
          activityId: seededObject.activityId,
          fileName: 'malicious.jpg',
        );
        final maliciousBytes = Uint8List.fromList([15, 16, 17, 18]);

        await expectLater(
          () => stranger.client.storage
              .from('activity-photos')
              .uploadBinary(
                ownerPath,
                maliciousBytes,
                fileOptions: const FileOptions(upsert: true),
              ),
          throwsA(isA<StorageException>()),
        );
        await expectLater(
          () => stranger.client.storage
              .from('activity-photos')
              .uploadBinary(
                mismatchedPath,
                maliciousBytes,
                fileOptions: const FileOptions(upsert: true),
              ),
          throwsA(isA<StorageException>()),
        );
      },
    );
  });
}

Future<List<Map<String, dynamic>>> _loadPhotoRows(
  SupabaseClient client, {
  required String activityId,
  required String columns,
}) async {
  final rows = await client
      .from('activity_photos')
      .select(columns)
      .eq('activity_id', activityId)
      .order('sort_order', ascending: true);

  return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
}

void _expectPhotoRows(
  List<Map<String, dynamic>> rows, {
  required List<String> ids,
  List<int>? sortOrders,
  List<String>? storagePaths,
}) {
  expect(rows.map((row) => row['id'] as String).toList(), ids);
  if (sortOrders != null) {
    expect(
      rows.map((row) => (row['sort_order'] as num).toInt()).toList(),
      sortOrders,
    );
  }
  if (storagePaths != null) {
    expect(
      rows.map((row) => row['storage_path'] as String).toList(),
      storagePaths,
    );
  }
}

class _SeededPhotoMetadata {
  const _SeededPhotoMetadata({
    required this.id,
    required this.storagePath,
  });

  final String id;
  final String storagePath;
}

class _SeededStorageObject {
  const _SeededStorageObject({
    required this.activityId,
    required this.objectPath,
  });

  final String activityId;
  final String objectPath;
}

class _PhotoScenarioFixture {
  const _PhotoScenarioFixture({
    required this.privateActivityId,
    required this.followersActivityId,
    required this.publicActivityId,
    required this.privateHighSortRow,
    required this.privateLowSortRow,
    required this.followersRow,
    required this.publicRow,
  });

  final String privateActivityId;
  final String followersActivityId;
  final String publicActivityId;
  final _SeededPhotoMetadata privateHighSortRow;
  final _SeededPhotoMetadata privateLowSortRow;
  final _SeededPhotoMetadata followersRow;
  final _SeededPhotoMetadata publicRow;
}

Future<_SeededStorageObject> _seedOwnedPrivateActivityObject({
  required SmokeTestUser owner,
  required DateTime startedAt,
  required String title,
  required String fileName,
  required Uint8List bytes,
}) async {
  final activityId = await seedActivityForCurrentUser(
    owner.client,
    visibility: 'private',
    startedAt: startedAt,
    title: title,
  );
  final objectPath = buildActivityPhotoStorageObjectPath(
    userId: owner.userId,
    activityId: activityId,
    fileName: fileName,
  );
  await _uploadActivityPhotoBytes(owner.client, objectPath, bytes);
  return _SeededStorageObject(activityId: activityId, objectPath: objectPath);
}

Future<void> _uploadActivityPhotoBytes(
  SupabaseClient client,
  String objectPath,
  Uint8List bytes,
) {
  return client.storage
      .from('activity-photos')
      .uploadBinary(
        objectPath,
        bytes,
        fileOptions: const FileOptions(upsert: true),
      );
}

Future<_PhotoScenarioFixture> _seedOwnerActivitiesAndMetadata(
  SupabaseClient client,
  String userId,
) async {
  final privateActivityId = await seedActivityForCurrentUser(
    client,
    visibility: 'private',
    startedAt: DateTime.utc(2026, 3, 20, 10),
    title: 'Owner Private Photo Activity',
  );
  final followersActivityId = await seedActivityForCurrentUser(
    client,
    visibility: 'followers',
    startedAt: DateTime.utc(2026, 3, 20, 11),
    title: 'Owner Followers Photo Activity',
  );
  final publicActivityId = await seedActivityForCurrentUser(
    client,
    visibility: 'public',
    startedAt: DateTime.utc(2026, 3, 20, 12),
    title: 'Owner Public Photo Activity',
  );

  final privateHighSortRow = await _seedPhotoMetadata(
    client,
    activityId: privateActivityId,
    userId: userId,
    fileName: 'private-high-sort.jpg',
    sortOrder: 3,
  );
  final privateLowSortRow = await _seedPhotoMetadata(
    client,
    activityId: privateActivityId,
    userId: userId,
    fileName: 'private-low-sort.jpg',
    sortOrder: 1,
  );
  final followersRow = await _seedPhotoMetadata(
    client,
    activityId: followersActivityId,
    userId: userId,
    fileName: 'followers-visible.jpg',
    sortOrder: 0,
  );
  final publicRow = await _seedPhotoMetadata(
    client,
    activityId: publicActivityId,
    userId: userId,
    fileName: 'public-visible.jpg',
    sortOrder: 0,
  );

  return _PhotoScenarioFixture(
    privateActivityId: privateActivityId,
    followersActivityId: followersActivityId,
    publicActivityId: publicActivityId,
    privateHighSortRow: privateHighSortRow,
    privateLowSortRow: privateLowSortRow,
    followersRow: followersRow,
    publicRow: publicRow,
  );
}

Future<_SeededPhotoMetadata> _seedPhotoMetadata(
  SupabaseClient client, {
  required String activityId,
  required String userId,
  required String fileName,
  required int sortOrder,
}) async {
  final storagePath = buildActivityPhotoStorageObjectPath(
    userId: userId,
    activityId: activityId,
    fileName: fileName,
  );
  final inserted = await client
      .from('activity_photos')
      .insert({
        'activity_id': activityId,
        'user_id': userId,
        'storage_path': storagePath,
        'thumbnail_path': null,
        'sort_order': sortOrder,
      })
      .select('id,storage_path')
      .single();
  return _SeededPhotoMetadata(
    id: inserted['id'] as String,
    storagePath: inserted['storage_path'] as String,
  );
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart';
import 'package:uff/src/features/photos/data/photo_repository.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';

// ## Test Scenarios
// - [positive] `activityPhotoListProvider()` loads activity-scoped rows from
//   `PhotoRepository.loadActivityPhotos()`.
// - [positive] Invalidating `activityPhotoListProvider()` triggers a fresh
//   repository reload for the same activity id.
// - [positive] `activityPhotoViewerShareHelperProvider` downloads from the
//   already-resolved viewer URL, writes a deterministic temp filename, and
//   shares that file.
// - [negative] Sharing uses the helper collaborators and never routes through
//   `PhotoRepository`.
// - [negative] Sharing sanitizes caller-provided file labels so temp writes
//   stay inside the temp directory.
// - [negative] Sharing rejects non-https, non-loopback viewer URLs.
// - [isolation] Separate provider containers do not reuse a stale share helper.
class FakePhotoRepository implements PhotoRepository {
  List<ActivityPhoto> photosToReturn = [];
  int loadCallCount = 0;
  int uploadCallCount = 0;
  int deleteCallCount = 0;
  String? lastLoadedActivityId;

  @override
  Future<List<ActivityPhoto>> loadActivityPhotos(String activityId) async {
    loadCallCount++;
    lastLoadedActivityId = activityId;
    return photosToReturn;
  }

  @override
  Future<ActivityPhoto> uploadPhoto({
    required String activityId,
    required Uint8List bytes,
    required String fileName,
    required int sortOrder,
    double? latitude,
    double? longitude,
  }) {
    uploadCallCount++;
    throw UnimplementedError('uploadPhoto should not be called in this test');
  }

  @override
  Future<void> deletePhoto(ActivityPhoto photo) {
    deleteCallCount++;
    throw UnimplementedError('deletePhoto should not be called in this test');
  }
}

ActivityPhoto _testPhoto({
  String id = 'photo-1',
  String activityId = 'activity-1',
  int sortOrder = 0,
}) {
  return ActivityPhoto(
    id: id,
    activityId: activityId,
    userId: 'user-1',
    storagePath: 'user-1/$activityId/$id.jpg',
    thumbnailPath: 'user-1/$activityId/${id}_thumb.jpg',
    sortOrder: sortOrder,
    createdAt: DateTime.utc(2026, 3, 17, 12, sortOrder),
  );
}

ProviderContainer _createContainer(FakePhotoRepository repository) {
  final container = ProviderContainer(
    overrides: [
      photoRepositoryProvider.overrideWithValue(repository),
    ],
  );
  return container;
}

void main() {
  group('activityPhotoListProvider', () {
    test('loads activity-scoped photos from repository', () async {
      final repository = FakePhotoRepository()
        ..photosToReturn = [
          _testPhoto(id: 'photo-a', activityId: 'activity-a'),
        ];
      final container = _createContainer(repository);
      addTearDown(container.dispose);

      final photos = await container.read(
        activityPhotoListProvider('activity-a').future,
      );

      expect(photos.map((photo) => photo.id).toList(), ['photo-a']);
      expect(repository.loadCallCount, 1);
      expect(repository.lastLoadedActivityId, 'activity-a');
    });

    test('reloads when invalidated', () async {
      final repository = FakePhotoRepository()
        ..photosToReturn = [
          _testPhoto(),
        ];
      final container = _createContainer(repository);
      addTearDown(container.dispose);

      await container.read(activityPhotoListProvider('activity-1').future);
      expect(repository.loadCallCount, 1);

      container.invalidate(activityPhotoListProvider('activity-1'));
      await container.read(activityPhotoListProvider('activity-1').future);
      expect(repository.loadCallCount, 2);
      expect(repository.lastLoadedActivityId, 'activity-1');
    });
  });

  group('activityPhotoViewerShareHelperProvider', () {
    test(
      'downloads resolved viewer URL, writes deterministic temp filename, and shares that file',
      () async {
        final repository = FakePhotoRepository();
        final tempDir = await Directory.systemTemp.createTemp(
          'activity_photo_share_helper_test',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final requestedUrls = <String>[];
        final sharedPaths = <String>[];
        final sharedBytes = <List<int>>[];
        final container = ProviderContainer(
          overrides: [
            photoRepositoryProvider.overrideWithValue(repository),
            activityPhotoShareBytesDownloaderProvider.overrideWithValue((url) {
              requestedUrls.add(url);
              return Future<Uint8List>.value(
                Uint8List.fromList(const [11, 22, 33, 44]),
              );
            }),
            activityPhotoShareTempDirectoryProvider.overrideWithValue(
              () => Future<Directory>.value(tempDir),
            ),
            activityPhotoShareActionProvider.overrideWithValue((files) async {
              sharedPaths.addAll(files.map((file) => file.path));
              sharedBytes.add(await File(files.single.path).readAsBytes());
            }),
          ],
        );
        addTearDown(container.dispose);

        final helper = container.read(activityPhotoViewerShareHelperProvider);
        await helper.shareResolvedViewerPhoto(
          resolvedViewerPhotoUrl:
              'https://cdn.example.com/viewer/photo-7.jpg?token=abc',
          fileLabel: 'photo-7.jpg',
        );

        expect(requestedUrls, [
          'https://cdn.example.com/viewer/photo-7.jpg?token=abc',
        ]);
        expect(sharedPaths.length, 1);
        expect(path.basename(sharedPaths.single), 'photo-7.jpg');
        expect(sharedBytes, [
          const [11, 22, 33, 44],
        ]);
        expect(repository.loadCallCount, 0);
        expect(repository.uploadCallCount, 0);
        expect(repository.deleteCallCount, 0);
      },
    );

    test(
      'sanitizes file labels before writing the shared temp file',
      () async {
        final repository = FakePhotoRepository();
        final tempDir = await Directory.systemTemp.createTemp(
          'activity_photo_share_helper_sanitized_label_test',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final sharedPaths = <String>[];
        final container = ProviderContainer(
          overrides: [
            photoRepositoryProvider.overrideWithValue(repository),
            activityPhotoShareBytesDownloaderProvider.overrideWithValue(
              (_) => Future<Uint8List>.value(Uint8List.fromList(const [1, 2])),
            ),
            activityPhotoShareTempDirectoryProvider.overrideWithValue(
              () => Future<Directory>.value(tempDir),
            ),
            activityPhotoShareActionProvider.overrideWithValue((files) async {
              sharedPaths.addAll(files.map((file) => file.path));
            }),
          ],
        );
        addTearDown(container.dispose);

        final helper = container.read(activityPhotoViewerShareHelperProvider);
        await helper.shareResolvedViewerPhoto(
          resolvedViewerPhotoUrl: 'https://cdn.example.com/viewer/photo-8.jpg',
          fileLabel: '../nested/escape.jpg',
        );

        expect(sharedPaths, hasLength(1));
        expect(path.dirname(sharedPaths.single), tempDir.path);
        expect(path.basename(sharedPaths.single), 'escape.jpg');
      },
    );

    test('rejects non-https and non-loopback viewer URLs', () async {
      final repository = FakePhotoRepository();
      var downloadWasCalled = false;
      final container = ProviderContainer(
        overrides: [
          photoRepositoryProvider.overrideWithValue(repository),
          activityPhotoShareBytesDownloaderProvider.overrideWithValue((_) {
            downloadWasCalled = true;
            return Future<Uint8List>.value(Uint8List.fromList(const [1]));
          }),
        ],
      );
      addTearDown(container.dispose);

      final helper = container.read(activityPhotoViewerShareHelperProvider);

      await expectLater(
        helper.shareResolvedViewerPhoto(
          resolvedViewerPhotoUrl: 'ftp://cdn.example.com/viewer/photo-9.jpg',
          fileLabel: 'photo-9.jpg',
        ),
        throwsArgumentError,
      );

      expect(downloadWasCalled, isFalse);
    });
  });
}

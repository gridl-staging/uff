import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart';
import 'package:uff/src/features/photos/data/photo_picker_service.dart';
import 'package:uff/src/features/photos/data/photo_repository.dart';
import 'package:uff/src/features/photos/data/supabase_photo_repository.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';

// ## Test Scenarios
// - [edge] Empty picked-photo batches are ignored without repository writes.
// - [negative] Uploads over the 20-photo cap fail with explicit per-mutation
//   limit messaging.
// - [positive] Successful uploads append after highest existing sort order.
// - [positive] Gallery uploads forward explicit null coordinates so only the
//   mid-run pending-photo path can supply GPS data.
// - [negative] Deleting a photo for one activity does not touch another user's data.
// - [isolation] Separate controller pumps keep upload and delete mutation maps isolated.
class FakePhotoRepository implements PhotoRepository {
  List<ActivityPhoto> photosToReturn = [];
  final Map<String, Completer<ActivityPhoto>> uploadCompletersByFileName = {};
  final Map<String, Completer<void>> deleteCompletersByPhotoId = {};
  final Map<String, Object> deleteErrorsByPhotoId = {};
  final List<int> uploadedSortOrders = [];
  final List<double?> uploadedLatitudes = [];
  final List<double?> uploadedLongitudes = [];
  int uploadCallCount = 0;
  int deleteCallCount = 0;

  @override
  Future<List<ActivityPhoto>> loadActivityPhotos(String activityId) async {
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
    uploadedSortOrders.add(sortOrder);
    uploadedLatitudes.add(latitude);
    uploadedLongitudes.add(longitude);
    final completer = uploadCompletersByFileName[fileName];
    if (completer != null) {
      return completer.future;
    }

    return Future.value(
      _photo(
        id: 'uploaded-$fileName',
        activityId: activityId,
        sortOrder: sortOrder,
      ),
    );
  }

  @override
  Future<void> deletePhoto(ActivityPhoto photo) async {
    deleteCallCount++;
    final deleteError = deleteErrorsByPhotoId[photo.id];
    if (deleteError != null) {
      return Future<void>.error(deleteError);
    }
    final completer = deleteCompletersByPhotoId[photo.id];
    if (completer != null) {
      return completer.future;
    }
  }
}

ActivityPhoto _photo({
  required String id,
  required String activityId,
  required int sortOrder,
}) {
  return ActivityPhoto(
    id: id,
    activityId: activityId,
    userId: 'user-1',
    storagePath: 'user-1/$activityId/$id.jpg',
    sortOrder: sortOrder,
    createdAt: DateTime.utc(2026, 3, 17, 12, sortOrder),
  );
}

PickedPhoto _pickedPhoto(String fileName) {
  return PickedPhoto(
    fileName: fileName,
    bytes: Uint8List.fromList([1, 2, 3]),
  );
}

ProviderContainer _createContainer(FakePhotoRepository repository) {
  final container = ProviderContainer(
    overrides: [
      photoRepositoryProvider.overrideWithValue(repository),
    ],
  );

  final listSubscription = container.listen(
    activityPhotoListProvider('activity-1'),
    (_, __) {},
  );
  addTearDown(listSubscription.close);

  final controllerSubscription = container.listen(
    activityPhotoControllerProvider('activity-1'),
    (_, __) {},
  );
  addTearDown(controllerSubscription.close);

  return container;
}

void main() {
  group('activityPhotoControllerProvider', () {
    test('ignores empty picked-photo batches', () async {
      final repository = FakePhotoRepository();
      final container = _createContainer(repository);
      addTearDown(container.dispose);
      await container.read(activityPhotoListProvider('activity-1').future);

      await container
          .read(activityPhotoControllerProvider('activity-1').notifier)
          .uploadPickedPhotos(const []);

      final state = container.read(
        activityPhotoControllerProvider('activity-1'),
      );
      expect(state.uploadMutationsByLocalId, isEmpty);
      expect(repository.uploadCallCount, 0);
    });

    test('enforces max 20 photos with per-upload failure state', () async {
      final repository = FakePhotoRepository()
        ..photosToReturn = List<ActivityPhoto>.generate(
          20,
          (index) => _photo(
            id: 'photo-$index',
            activityId: 'activity-1',
            sortOrder: index,
          ),
        );
      final container = _createContainer(repository);
      addTearDown(container.dispose);
      await container.read(activityPhotoListProvider('activity-1').future);

      await container
          .read(activityPhotoControllerProvider('activity-1').notifier)
          .uploadPickedPhotos([_pickedPhoto('over-limit.jpg')]);

      final state = container.read(
        activityPhotoControllerProvider('activity-1'),
      );
      final mutation = state.uploadMutationsByLocalId.values.single;
      expect(mutation.status, PhotoMutationStatus.failed);
      expect(mutation.errorMessage, activityPhotoLimitReachedMessage);
      expect(repository.uploadCallCount, 0);
    });

    test('tracks pending then failed upload state per upload', () async {
      final repository = FakePhotoRepository();
      final completer = Completer<ActivityPhoto>();
      repository.uploadCompletersByFileName['broken.jpg'] = completer;

      final container = _createContainer(repository);
      addTearDown(container.dispose);
      await container.read(activityPhotoListProvider('activity-1').future);

      final uploadFuture = container
          .read(activityPhotoControllerProvider('activity-1').notifier)
          .uploadPickedPhotos([_pickedPhoto('broken.jpg')]);

      await Future<void>.delayed(Duration.zero);
      var state = container.read(activityPhotoControllerProvider('activity-1'));
      var mutation = state.uploadMutationsByLocalId.values.single;
      expect(mutation.status, PhotoMutationStatus.pending);
      expect(mutation.errorMessage, isNull);

      completer.completeError(StateError('upload failed'));
      await uploadFuture;

      state = container.read(activityPhotoControllerProvider('activity-1'));
      mutation = state.uploadMutationsByLocalId.values.single;
      expect(mutation.status, PhotoMutationStatus.failed);
      expect(mutation.errorMessage, contains('upload failed'));
    });

    test(
      'maps repository photo-limit failure to the shared limit reached message',
      () async {
        final repository = FakePhotoRepository();
        final completer = Completer<ActivityPhoto>();
        repository.uploadCompletersByFileName['limit.jpg'] = completer;
        final container = _createContainer(repository);
        addTearDown(container.dispose);
        await container.read(activityPhotoListProvider('activity-1').future);

        final uploadFuture = container
            .read(activityPhotoControllerProvider('activity-1').notifier)
            .uploadPickedPhotos([_pickedPhoto('limit.jpg')]);

        await Future<void>.delayed(Duration.zero);
        completer.completeError(const ActivityPhotoLimitExceededException());
        await uploadFuture;

        final state = container.read(
          activityPhotoControllerProvider('activity-1'),
        );
        final mutation = state.uploadMutationsByLocalId.values.single;
        expect(mutation.status, PhotoMutationStatus.failed);
        expect(mutation.errorMessage, activityPhotoLimitReachedMessage);
      },
    );

    test('counts pending uploads against the max-photo cap', () async {
      final repository = FakePhotoRepository()
        ..photosToReturn = List<ActivityPhoto>.generate(
          19,
          (index) => _photo(
            id: 'photo-$index',
            activityId: 'activity-1',
            sortOrder: index,
          ),
        );
      final firstUploadCompleter = Completer<ActivityPhoto>();
      repository.uploadCompletersByFileName['first.jpg'] = firstUploadCompleter;

      final container = _createContainer(repository);
      addTearDown(container.dispose);
      await container.read(activityPhotoListProvider('activity-1').future);

      final firstUploadFuture = container
          .read(activityPhotoControllerProvider('activity-1').notifier)
          .uploadPickedPhotos([_pickedPhoto('first.jpg')]);

      await Future<void>.delayed(Duration.zero);

      await container
          .read(activityPhotoControllerProvider('activity-1').notifier)
          .uploadPickedPhotos([_pickedPhoto('second.jpg')]);

      var state = container.read(activityPhotoControllerProvider('activity-1'));
      final secondUploadEntry = state.uploadMutationsByLocalId.entries
          .singleWhere(
            (entry) => entry.key.startsWith('second.jpg#'),
          );
      expect(secondUploadEntry.value.status, PhotoMutationStatus.failed);
      expect(
        secondUploadEntry.value.errorMessage,
        activityPhotoLimitReachedMessage,
      );
      expect(repository.uploadCallCount, 1);

      firstUploadCompleter.complete(
        _photo(id: 'uploaded-first', activityId: 'activity-1', sortOrder: 19),
      );
      await firstUploadFuture;

      state = container.read(activityPhotoControllerProvider('activity-1'));
      expect(
        state.uploadMutationsByLocalId.keys,
        isNot(contains(startsWith('first.jpg#'))),
      );
    });

    test(
      'assigns distinct mutation IDs when duplicate filenames exceed cap',
      () async {
        final repository = FakePhotoRepository()
          ..photosToReturn = List<ActivityPhoto>.generate(
            19,
            (index) => _photo(
              id: 'photo-$index',
              activityId: 'activity-1',
              sortOrder: index,
            ),
          );
        final container = _createContainer(repository);
        addTearDown(container.dispose);
        await container.read(activityPhotoListProvider('activity-1').future);

        await container
            .read(activityPhotoControllerProvider('activity-1').notifier)
            .uploadPickedPhotos([
              _pickedPhoto('dup.jpg'),
              _pickedPhoto('dup.jpg'),
            ]);

        final state = container.read(
          activityPhotoControllerProvider('activity-1'),
        );
        expect(repository.uploadCallCount, 1);
        expect(state.uploadMutationsByLocalId.keys, ['dup.jpg#1']);
        expect(
          state.uploadMutationsByLocalId['dup.jpg#1']!.status,
          PhotoMutationStatus.failed,
        );
      },
    );

    test('removes successful upload mutations after completion', () async {
      final repository = FakePhotoRepository();
      final container = _createContainer(repository);
      addTearDown(container.dispose);
      await container.read(activityPhotoListProvider('activity-1').future);

      await container
          .read(activityPhotoControllerProvider('activity-1').notifier)
          .uploadPickedPhotos([_pickedPhoto('done.jpg')]);

      final state = container.read(
        activityPhotoControllerProvider('activity-1'),
      );
      expect(state.uploadMutationsByLocalId, isEmpty);
      expect(repository.uploadCallCount, 1);
    });

    test('forwards null coordinates for gallery uploads', () async {
      final repository = FakePhotoRepository();
      final container = _createContainer(repository);
      addTearDown(container.dispose);
      await container.read(activityPhotoListProvider('activity-1').future);

      await container
          .read(activityPhotoControllerProvider('activity-1').notifier)
          .uploadPickedPhotos([_pickedPhoto('gallery.jpg')]);

      expect(repository.uploadCallCount, 1);
      expect(repository.uploadedLatitudes, [null]);
      expect(repository.uploadedLongitudes, [null]);
    });

    test('tracks pending then failed delete state per photo id', () async {
      final repository = FakePhotoRepository();
      final completer = Completer<void>();
      repository.deleteCompletersByPhotoId['photo-1'] = completer;
      final container = _createContainer(repository);
      addTearDown(container.dispose);
      await container.read(activityPhotoListProvider('activity-1').future);
      final photo = _photo(
        id: 'photo-1',
        activityId: 'activity-1',
        sortOrder: 0,
      );

      final deleteFuture = container
          .read(activityPhotoControllerProvider('activity-1').notifier)
          .deleteActivityPhoto(photo);

      await Future<void>.delayed(Duration.zero);
      var state = container.read(activityPhotoControllerProvider('activity-1'));
      var mutation = state.deleteMutationsByPhotoId['photo-1']!;
      expect(mutation.status, PhotoMutationStatus.pending);
      expect(mutation.errorMessage, isNull);

      completer.completeError(StateError('delete failed'));
      await deleteFuture;

      state = container.read(activityPhotoControllerProvider('activity-1'));
      mutation = state.deleteMutationsByPhotoId['photo-1']!;
      expect(mutation.status, PhotoMutationStatus.failed);
      expect(mutation.errorMessage, contains('delete failed'));
      expect(repository.deleteCallCount, 1);
    });

    test('appends uploads after the highest existing sort order', () async {
      final repository = FakePhotoRepository()
        ..photosToReturn = [
          _photo(id: 'photo-0', activityId: 'activity-1', sortOrder: 0),
          _photo(id: 'photo-5', activityId: 'activity-1', sortOrder: 5),
        ];
      final container = _createContainer(repository);
      addTearDown(container.dispose);
      await container.read(activityPhotoListProvider('activity-1').future);

      await container
          .read(activityPhotoControllerProvider('activity-1').notifier)
          .uploadPickedPhotos([_pickedPhoto('next-up.jpg')]);

      expect(repository.uploadedSortOrders, [6]);
    });
  });
}

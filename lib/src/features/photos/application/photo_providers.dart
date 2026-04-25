import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uff/src/features/photos/data/photo_crop_service.dart';
import 'package:uff/src/features/photos/data/photo_picker_service.dart';
import 'package:uff/src/features/photos/data/photo_repository.dart';
import 'package:uff/src/features/photos/data/supabase_photo_repository.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';

part 'photo_providers.g.dart';

const int maxActivityPhotosPerActivity = 20;
const String activityPhotoLimitReachedMessage =
    'Activity photos are limited to '
    '$maxActivityPhotosPerActivity images per activity.';

const PhotoMutation _pendingPhotoMutation = PhotoMutation(
  status: PhotoMutationStatus.pending,
);
const PhotoMutation _succeededPhotoMutation = PhotoMutation(
  status: PhotoMutationStatus.succeeded,
);
const PhotoMutation _limitReachedPhotoMutation = PhotoMutation(
  status: PhotoMutationStatus.failed,
  errorMessage: activityPhotoLimitReachedMessage,
);

typedef ActivityPhotoShareBytesDownloader =
    Future<Uint8List> Function(
      String resolvedViewerPhotoUrl,
    );
typedef ActivityPhotoShareTempDirectoryProvider = Future<Directory> Function();
typedef ActivityPhotoShareAction = Future<void> Function(List<XFile> files);

final activityPhotoShareBytesDownloaderProvider =
    Provider<ActivityPhotoShareBytesDownloader>((ref) {
      return _downloadViewerPhotoBytes;
    });

final activityPhotoShareTempDirectoryProvider =
    Provider<ActivityPhotoShareTempDirectoryProvider>((ref) {
      return getTemporaryDirectory;
    });

final activityPhotoShareActionProvider = Provider<ActivityPhotoShareAction>((
  ref,
) {
  return (files) async {
    await Share.shareXFiles(files);
  };
});

final activityPhotoViewerShareHelperProvider =
    Provider<ActivityPhotoViewerShareHelper>((ref) {
      return DownloadAndShareActivityPhotoViewerShareHelper(
        downloadBytes: ref.read(activityPhotoShareBytesDownloaderProvider),
        resolveTemporaryDirectory: ref.read(
          activityPhotoShareTempDirectoryProvider,
        ),
        shareFiles: ref.read(activityPhotoShareActionProvider),
      );
    });

class ActivityPhotoViewerShareHelper {
  Future<void> shareResolvedViewerPhoto({
    required String resolvedViewerPhotoUrl,
    required String fileLabel,
  }) {
    throw UnimplementedError('shareResolvedViewerPhoto must be implemented');
  }
}

/// TODO: Document DownloadAndShareActivityPhotoViewerShareHelper.
class DownloadAndShareActivityPhotoViewerShareHelper
    implements ActivityPhotoViewerShareHelper {
  DownloadAndShareActivityPhotoViewerShareHelper({
    required ActivityPhotoShareBytesDownloader downloadBytes,
    required ActivityPhotoShareTempDirectoryProvider resolveTemporaryDirectory,
    required ActivityPhotoShareAction shareFiles,
  }) : _downloadBytes = downloadBytes,
       _resolveTemporaryDirectory = resolveTemporaryDirectory,
       _shareFiles = shareFiles;

  final ActivityPhotoShareBytesDownloader _downloadBytes;
  final ActivityPhotoShareTempDirectoryProvider _resolveTemporaryDirectory;
  final ActivityPhotoShareAction _shareFiles;

  @override
  Future<void> shareResolvedViewerPhoto({
    required String resolvedViewerPhotoUrl,
    required String fileLabel,
  }) async {
    final viewerPhotoUri = _validatedViewerPhotoUri(resolvedViewerPhotoUrl);
    final sanitizedFileLabel = _sanitizedSharedFileLabel(fileLabel);

    final bytes = await _downloadBytes(viewerPhotoUri.toString());
    final temporaryDirectory = await _resolveTemporaryDirectory();
    final tempFile = _resolvedSharedTempFile(
      temporaryDirectory: temporaryDirectory,
      fileLabel: sanitizedFileLabel,
    );
    await tempFile.writeAsBytes(bytes, flush: true);
    await _shareFiles([XFile(tempFile.path)]);
  }
}

Future<Uint8List> _downloadViewerPhotoBytes(
  String resolvedViewerPhotoUrl,
) async {
  final viewerPhotoUri = _validatedViewerPhotoUri(resolvedViewerPhotoUrl);
  final httpClient = HttpClient();
  try {
    final request = await httpClient.getUrl(viewerPhotoUri);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Photo download failed with status ${response.statusCode}',
        uri: viewerPhotoUri,
      );
    }
    return consolidateHttpClientResponseBytes(response);
  } finally {
    httpClient.close(force: true);
  }
}

Uri _validatedViewerPhotoUri(String resolvedViewerPhotoUrl) {
  final viewerPhotoUri = Uri.parse(resolvedViewerPhotoUrl);
  if (_isAllowedViewerPhotoUri(viewerPhotoUri)) {
    return viewerPhotoUri;
  }
  throw ArgumentError.value(
    resolvedViewerPhotoUrl,
    'resolvedViewerPhotoUrl',
    'must use https or loopback http',
  );
}

bool _isAllowedViewerPhotoUri(Uri viewerPhotoUri) {
  if (!viewerPhotoUri.hasScheme || viewerPhotoUri.host.isEmpty) {
    return false;
  }
  if (viewerPhotoUri.scheme == 'https') {
    return true;
  }
  if (viewerPhotoUri.scheme != 'http') {
    return false;
  }

  final host = viewerPhotoUri.host.toLowerCase();
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}

String _sanitizedSharedFileLabel(String fileLabel) {
  final trimmedLabel = fileLabel.trim();
  final safeBaseName = path.basename(trimmedLabel);
  if (safeBaseName.isEmpty || safeBaseName == '.' || safeBaseName == '..') {
    throw ArgumentError.value(
      fileLabel,
      'fileLabel',
      'must contain a file name',
    );
  }
  return safeBaseName;
}

File _resolvedSharedTempFile({
  required Directory temporaryDirectory,
  required String fileLabel,
}) {
  final normalizedDirectoryPath = path.normalize(temporaryDirectory.path);
  final resolvedFilePath = path.normalize(
    path.join(normalizedDirectoryPath, fileLabel),
  );
  if (resolvedFilePath != normalizedDirectoryPath &&
      !path.isWithin(normalizedDirectoryPath, resolvedFilePath)) {
    throw StateError('Shared photo path escaped the temporary directory.');
  }
  return File(resolvedFilePath);
}

@riverpod
PhotoPickerService photoPickerService(Ref ref) {
  return ImagePickerPhotoPickerService(photoCropService: PhotoCropService());
}

@riverpod
PhotoRepository photoRepository(Ref ref) {
  return SupabasePhotoRepository(Supabase.instance.client);
}

@riverpod
Future<List<ActivityPhoto>> activityPhotoList(
  Ref ref,
  String activityId,
) async {
  return ref.read(photoRepositoryProvider).loadActivityPhotos(activityId);
}

enum PhotoMutationStatus {
  pending,
  succeeded,
  failed,
}

@immutable
class PhotoMutation {
  const PhotoMutation({
    required this.status,
    this.errorMessage,
  });

  final PhotoMutationStatus status;
  final String? errorMessage;
}

/// Tracks per-photo upload and deletion mutations for the current activity UI.
@immutable
class ActivityPhotoControllerState {
  const ActivityPhotoControllerState({
    this.uploadMutationsByLocalId = const <String, PhotoMutation>{},
    this.deleteMutationsByPhotoId = const <String, PhotoMutation>{},
  });

  final Map<String, PhotoMutation> uploadMutationsByLocalId;
  final Map<String, PhotoMutation> deleteMutationsByPhotoId;

  int get pendingUploadCount => _countMutationsWithStatus(
    uploadMutationsByLocalId,
    PhotoMutationStatus.pending,
  );

  ActivityPhotoControllerState copyWith({
    Map<String, PhotoMutation>? uploadMutationsByLocalId,
    Map<String, PhotoMutation>? deleteMutationsByPhotoId,
  }) {
    return ActivityPhotoControllerState(
      uploadMutationsByLocalId:
          uploadMutationsByLocalId ?? this.uploadMutationsByLocalId,
      deleteMutationsByPhotoId:
          deleteMutationsByPhotoId ?? this.deleteMutationsByPhotoId,
    );
  }
}

/// TODO: Document ActivityPhotoController.
@riverpod
class ActivityPhotoController extends _$ActivityPhotoController {
  late String _activityId;
  int _nextUploadMutationSequence = 0;

  @override
  ActivityPhotoControllerState build(String activityId) {
    _activityId = activityId;
    _nextUploadMutationSequence = 0;
    return const ActivityPhotoControllerState();
  }

  Future<void> uploadPickedPhotos(List<PickedPhoto> pickedPhotos) async {
    if (pickedPhotos.isEmpty) {
      return;
    }

    final photoRepository = ref.read(photoRepositoryProvider);
    final existingPhotos = await ref.read(
      activityPhotoListProvider(_activityId).future,
    );
    var nextSortOrder = _nextSortOrder(existingPhotos);
    final availableSlots =
        maxActivityPhotosPerActivity -
        existingPhotos.length -
        state.pendingUploadCount;

    for (var index = 0; index < pickedPhotos.length; index++) {
      final pickedPhoto = pickedPhotos[index];
      final uploadMutationId = _createUploadMutationId(pickedPhoto.fileName);
      if (index >= availableSlots) {
        _updateUploadMutation(uploadMutationId, _limitReachedPhotoMutation);
        continue;
      }

      _updateUploadMutation(uploadMutationId, _pendingPhotoMutation);

      try {
        // Gallery/post-activity uploads intentionally omit coordinates —
        // only the mid-run pending-photo path supplies GPS data.
        await photoRepository.uploadPhoto(
          activityId: _activityId,
          bytes: pickedPhoto.bytes,
          fileName: pickedPhoto.fileName,
          sortOrder: nextSortOrder,
        );
        nextSortOrder += 1;
        _updateUploadMutation(uploadMutationId, _succeededPhotoMutation);
        _invalidateActivityPhotoList();
      } on Object catch (error) {
        _updateUploadMutation(
          uploadMutationId,
          _uploadFailureMutation(error),
        );
      }
    }
  }

  Future<void> deleteActivityPhoto(ActivityPhoto photo) async {
    final photoRepository = ref.read(photoRepositoryProvider);
    _updateDeleteMutation(photo.id, _pendingPhotoMutation);

    try {
      await photoRepository.deletePhoto(photo);
      _updateDeleteMutation(photo.id, _succeededPhotoMutation);
      _invalidateActivityPhotoList();
    } on Object catch (error) {
      _updateDeleteMutation(photo.id, _failedPhotoMutation(error));
    }
  }

  String _createUploadMutationId(String fileName) {
    final mutationSequence = _nextUploadMutationSequence;
    _nextUploadMutationSequence += 1;
    return '$fileName#$mutationSequence';
  }

  void _updateUploadMutation(String uploadMutationId, PhotoMutation mutation) {
    state = state.copyWith(
      uploadMutationsByLocalId: _updatedMutationMap(
        state.uploadMutationsByLocalId,
        uploadMutationId,
        mutation,
        removeOnSuccess: true,
      ),
    );
  }

  void _updateDeleteMutation(String photoId, PhotoMutation mutation) {
    state = state.copyWith(
      deleteMutationsByPhotoId: _updatedMutationMap(
        state.deleteMutationsByPhotoId,
        photoId,
        mutation,
      ),
    );
  }

  void _invalidateActivityPhotoList() {
    ref.invalidate(activityPhotoListProvider(_activityId));
  }
}

int _countMutationsWithStatus(
  Map<String, PhotoMutation> mutations,
  PhotoMutationStatus status,
) {
  return mutations.values.where((mutation) => mutation.status == status).length;
}

PhotoMutation _failedPhotoMutation(Object error) {
  return PhotoMutation(
    status: PhotoMutationStatus.failed,
    errorMessage: error.toString(),
  );
}

PhotoMutation _uploadFailureMutation(Object error) {
  if (error is ActivityPhotoLimitExceededException) {
    return _limitReachedPhotoMutation;
  }
  return _failedPhotoMutation(error);
}

Map<String, PhotoMutation> _updatedMutationMap(
  Map<String, PhotoMutation> mutations,
  String mutationId,
  PhotoMutation mutation, {
  bool removeOnSuccess = false,
}) {
  final nextMutations = Map<String, PhotoMutation>.from(mutations);
  if (removeOnSuccess && mutation.status == PhotoMutationStatus.succeeded) {
    nextMutations.remove(mutationId);
  } else {
    nextMutations[mutationId] = mutation;
  }
  return nextMutations;
}

int _nextSortOrder(List<ActivityPhoto> photos) {
  var nextSortOrder = 0;
  for (final photo in photos) {
    if (photo.sortOrder >= nextSortOrder) {
      nextSortOrder = photo.sortOrder + 1;
    }
  }
  return nextSortOrder;
}

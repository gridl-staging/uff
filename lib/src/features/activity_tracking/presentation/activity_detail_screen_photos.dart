part of 'activity_detail_screen.dart';

const ActivityPhotoSectionKeyContract
_photoSectionKeyContract = ActivityPhotoSectionKeyContract(
  sectionKey: ActivityDetailScreen.photoSectionKey,
  unsyncedMessageKey: ActivityDetailScreen.photoUnsyncedMessageKey,
  emptyStateKey: ActivityDetailScreen.photoEmptyStateKey,
  addButtonKey: ActivityDetailScreen.photoAddButtonKey,
  viewerKey: ActivityDetailScreen.photoViewerKey,
  viewerUnavailableKey: ActivityDetailScreen.photoViewerUnavailableKey,
  viewerDeleteButtonKey: ActivityDetailScreen.photoViewerDeleteButtonKey,
  viewerShareButtonKey: ActivityDetailScreen.photoViewerShareButtonKey,
  viewerShareLoadingKey: ActivityDetailScreen.photoViewerShareLoadingKey,
  deleteConfirmKey: ActivityDetailScreen.photoDeleteConfirmKey,
  photoThumbnailKey: ActivityDetailScreen.photoThumbnailKey,
  photoUploadMutationTileKey: ActivityDetailScreen.photoUploadMutationTileKey,
  photoUploadMutationErrorKey: ActivityDetailScreen.photoUploadMutationErrorKey,
  photoDeleteMutationErrorKey: ActivityDetailScreen.photoDeleteMutationErrorKey,
  photoViewerImageKey: ActivityDetailScreen.photoViewerImageKey,
);

// TODO(uff): Document _ActivityDetailPhotoSection.
/// TODO: Document _ActivityDetailPhotoSection.
extension _ActivityDetailPhotoSection on _ActivityDetailScreenState {
  /// Resolves the single sorted list of synced photos for the given activity.
  /// Both the gallery section and the map marker adapter consume this output
  /// so that sort order and provider watches happen exactly once.
  _SortedSyncedPhotosResult _resolveSortedSyncedPhotos(
    ActivityDetailData detail,
  ) {
    final syncEntryAsyncValue = ref.watch(
      activitySyncEntryProvider(detail.session.id),
    );
    final renderState = _resolvePhotoGalleryRenderState(
      remoteActivityId: detail.session.remoteId,
      syncEntry: syncEntryAsyncValue.asData?.value,
    );
    if (!renderState.isSynced) {
      return _SortedSyncedPhotosResult.unsynced(renderState.unsyncedMessage);
    }

    final remoteActivityId = renderState.remoteActivityId;
    final photosAsyncValue = ref.watch(
      activityPhotoListProvider(remoteActivityId),
    );
    final controllerState = ref.watch(
      activityPhotoControllerProvider(remoteActivityId),
    );

    final rawPhotos = photosAsyncValue.asData?.value;
    final sortedPhotos = rawPhotos == null
        ? null
        : ([...rawPhotos]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)));

    return _SortedSyncedPhotosResult.synced(
      remoteActivityId: remoteActivityId,
      sortedPhotos: sortedPhotos,
      isLoading: photosAsyncValue.isLoading,
      loadingError: photosAsyncValue.asError?.error,
      controllerState: controllerState,
    );
  }

  /// Derives photo markers for the route map from the pre-sorted photo list.
  List<PhotoMarkerInput> _photoMarkersFromResult(
    _SortedSyncedPhotosResult result,
  ) {
    if (!result.isSynced) return const [];
    final photos = result.sortedPhotos;
    if (photos == null) return const [];

    return photos
        .where((photo) => photo.isMapEligible)
        .map(
          (photo) => PhotoMarkerInput(
            photoId: photo.id,
            latitude: photo.latitude!,
            longitude: photo.longitude!,
            previewUrl: photo.previewUrl,
          ),
        )
        .toList(growable: false);
  }

  Widget _buildPhotoGallerySection(
    BuildContext context,
    _SortedSyncedPhotosResult photoResult,
  ) {
    if (!photoResult.isSynced) {
      return ActivityPhotoGallerySection(
        keys: _photoSectionKeyContract,
        isSynced: false,
        showAddButton: false,
        unsyncedMessage: photoResult.unsyncedMessage,
        controllerState: const ActivityPhotoControllerState(),
      );
    }

    final remoteActivityId = photoResult.remoteActivityId;
    return ActivityPhotoGallerySection(
      keys: _photoSectionKeyContract,
      isSynced: true,
      showAddButton: _isEditingDetails,
      photos: photoResult.sortedPhotos,
      isLoading: photoResult.isLoading,
      loadingError: photoResult.loadingError,
      controllerState: photoResult.controllerState,
      onAddPressed: _isEditingDetails
          ? () {
              _promptPhotoSourceAndUpload(context, remoteActivityId);
            }
          : null,
      onPhotoPressed: (photo) {
        _openPhotoViewer(
          context,
          remoteActivityId,
          photo,
          allowDelete: _isEditingDetails,
        );
      },
    );
  }

  Future<void> _promptPhotoSourceAndUpload(
    BuildContext context,
    String remoteActivityId,
  ) async {
    final selectedSource = await _showPhotoSourcePicker(context);
    if (!mounted || selectedSource == null) {
      return;
    }
    await _pickAndUploadActivityPhotos(remoteActivityId, selectedSource);
  }

  Future<PhotoPickSource?> _showPhotoSourcePicker(BuildContext context) {
    return showModalBottomSheet<PhotoPickSource>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            key: ActivityDetailScreen.photoSourceSheetKey,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ListTile(
                title: Text('Add photo'),
              ),
              ListTile(
                key: ActivityDetailScreen.photoSourceGalleryOptionKey,
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Photo library'),
                onTap: () {
                  Navigator.of(sheetContext).pop(PhotoPickSource.gallery);
                },
              ),
              ListTile(
                key: ActivityDetailScreen.photoSourceCameraOptionKey,
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.of(sheetContext).pop(PhotoPickSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadActivityPhotos(
    String remoteActivityId,
    PhotoPickSource source,
  ) async {
    try {
      final pickedPhotos = await ref
          .read(photoPickerServiceProvider)
          .pickPhotos(
            source: source,
            // ignore: avoid_redundant_argument_values, reason: pass the controller cap explicitly so picker and upload limits share one source of truth
            maxSelection: maxActivityPhotosPerActivity,
            offerCrop: source == PhotoPickSource.gallery,
          );
      if (pickedPhotos.isEmpty) {
        return;
      }

      await ref
          .read(activityPhotoControllerProvider(remoteActivityId).notifier)
          .uploadPickedPhotos(pickedPhotos);
    } on Object {
      if (!mounted) {
        return;
      }
      _showSnackBarMessage('Unable to add photos right now. Please try again.');
    }
  }

  _PhotoGalleryRenderState _resolvePhotoGalleryRenderState({
    required String? remoteActivityId,
    required SyncQueueEntry? syncEntry,
  }) {
    if (remoteActivityId == null) {
      return const _PhotoGalleryRenderState.blocked(
        'Photos will be available after this activity finishes syncing.',
      );
    }

    switch (syncEntry?.status) {
      case SyncQueueEntryStatus.queued:
        return const _PhotoGalleryRenderState.blocked(
          'Activity sync is queued. Photos will be available when sync finishes.',
        );
      case SyncQueueEntryStatus.processing:
        return const _PhotoGalleryRenderState.blocked(
          'Activity sync is in progress. Photos will be available when sync finishes.',
        );
      case SyncQueueEntryStatus.failed:
        return const _PhotoGalleryRenderState.blocked(
          'Activity sync has not succeeded yet. Photos will be available after a successful sync.',
        );
      case SyncQueueEntryStatus.successful:
      case null:
        return _PhotoGalleryRenderState.synced(remoteActivityId);
    }
  }

  void _openPhotoViewer(
    BuildContext context,
    String remoteActivityId,
    ActivityPhoto photo, {
    required bool allowDelete,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ActivityPhotoViewerScreen(
          remoteActivityId: remoteActivityId,
          photo: photo,
          keys: _photoSectionKeyContract,
          allowDelete: allowDelete,
        ),
      ),
    );
  }
}

/// Detail-local render contract for the Activity Detail photo section.
/// This keeps blocked copy and action availability in one source of truth.
class _PhotoGalleryRenderState {
  const _PhotoGalleryRenderState.blocked(this._unsyncedMessage)
    : _remoteActivityId = null;

  const _PhotoGalleryRenderState.synced(this._remoteActivityId)
    : _unsyncedMessage = null;

  final String? _remoteActivityId;
  final String? _unsyncedMessage;

  bool get isSynced => _remoteActivityId != null;

  String get remoteActivityId => _remoteActivityId!;

  String get unsyncedMessage => _unsyncedMessage!;
}

/// Single source of truth for sorted synced photos in the detail flow.
/// Resolved once per build and consumed by both the gallery section and
/// the map-marker adapter, eliminating duplicate provider watches and
/// divergent sort logic.
class _SortedSyncedPhotosResult {
  const _SortedSyncedPhotosResult.unsynced(this._unsyncedMessage)
    : _remoteActivityId = null,
      sortedPhotos = null,
      isLoading = false,
      loadingError = null,
      controllerState = const ActivityPhotoControllerState();

  const _SortedSyncedPhotosResult.synced({
    required String remoteActivityId,
    required this.sortedPhotos,
    required this.isLoading,
    required this.loadingError,
    required this.controllerState,
  }) : _remoteActivityId = remoteActivityId,
       _unsyncedMessage = null;

  final String? _remoteActivityId;
  final String? _unsyncedMessage;
  final List<ActivityPhoto>? sortedPhotos;
  final bool isLoading;
  final Object? loadingError;
  final ActivityPhotoControllerState controllerState;

  bool get isSynced => _remoteActivityId != null;

  String get remoteActivityId => _remoteActivityId!;

  String get unsyncedMessage => _unsyncedMessage!;
}

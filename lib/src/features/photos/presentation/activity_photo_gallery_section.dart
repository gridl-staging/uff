import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:uff/src/core/presentation/copyable_error_text.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';

/// TODO: Document ActivityPhotoSectionKeyContract.
@immutable
class ActivityPhotoSectionKeyContract {
  const ActivityPhotoSectionKeyContract({
    required this.sectionKey,
    required this.unsyncedMessageKey,
    required this.emptyStateKey,
    required this.addButtonKey,
    required this.viewerKey,
    required this.viewerUnavailableKey,
    required this.viewerDeleteButtonKey,
    required this.viewerShareButtonKey,
    required this.viewerShareLoadingKey,
    required this.deleteConfirmKey,
    required this.photoThumbnailKey,
    required this.photoUploadMutationTileKey,
    required this.photoUploadMutationErrorKey,
    required this.photoDeleteMutationErrorKey,
    required this.photoViewerImageKey,
  });

  final Key sectionKey;
  final Key unsyncedMessageKey;
  final Key emptyStateKey;
  final Key addButtonKey;
  final Key viewerKey;
  final Key viewerUnavailableKey;
  final Key viewerDeleteButtonKey;
  final Key viewerShareButtonKey;
  final Key viewerShareLoadingKey;
  final Key deleteConfirmKey;
  final Key Function(String photoId) photoThumbnailKey;
  final Key Function(String uploadMutationId) photoUploadMutationTileKey;
  final Key Function(String uploadMutationId) photoUploadMutationErrorKey;
  final Key Function(String photoId) photoDeleteMutationErrorKey;
  final Key Function(String photoId) photoViewerImageKey;
}

// TODO(uff): Document ActivityPhotoGallerySection.
/// TODO: Document ActivityPhotoGallerySection.
class ActivityPhotoGallerySection extends StatelessWidget {
  const ActivityPhotoGallerySection({
    required this.keys,
    required this.isSynced,
    required this.controllerState,
    this.showAddButton = true,
    this.unsyncedMessage = defaultUnsyncedMessage,
    this.photos,
    this.isLoading = false,
    this.loadingError,
    this.onAddPressed,
    this.onPhotoPressed,
    super.key,
  });

  final ActivityPhotoSectionKeyContract keys;
  final bool isSynced;
  final bool showAddButton;
  final String unsyncedMessage;
  final List<ActivityPhoto>? photos;
  final bool isLoading;
  final Object? loadingError;
  final ActivityPhotoControllerState controllerState;
  final VoidCallback? onAddPressed;
  final ValueChanged<ActivityPhoto>? onPhotoPressed;

  static const defaultUnsyncedMessage =
      'Photos will be available after this activity finishes syncing.';
  static const emptyStateMessage =
      'No photos yet. Add your first photo to this activity.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      key: keys.sectionKey,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Photos',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (isSynced && showAddButton)
                  FilledButton.icon(
                    key: keys.addButtonKey,
                    onPressed: onAddPressed,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Add'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildGalleryContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryContent() {
    if (!isSynced) {
      return Text(
        unsyncedMessage,
        key: keys.unsyncedMessageKey,
      );
    }

    if (isLoading) {
      return const LinearProgressIndicator();
    }

    if (loadingError != null) {
      return const Text('Unable to load photos right now.');
    }

    return _SyncedPhotoGalleryContent(
      keys: keys,
      photos: photos ?? const <ActivityPhoto>[],
      controllerState: controllerState,
      onPhotoPressed: onPhotoPressed,
    );
  }
}

/// TODO: Document _SyncedPhotoGalleryContent.
class _SyncedPhotoGalleryContent extends StatelessWidget {
  const _SyncedPhotoGalleryContent({
    required this.keys,
    required this.photos,
    required this.controllerState,
    this.onPhotoPressed,
  });

  final ActivityPhotoSectionKeyContract keys;
  final List<ActivityPhoto> photos;
  final ActivityPhotoControllerState controllerState;
  final ValueChanged<ActivityPhoto>? onPhotoPressed;

  @override
  Widget build(BuildContext context) {
    // Photos arrive pre-sorted from the detail flow's single source of truth.
    // No local sort — order is the caller's responsibility.
    final uploadMutations = controllerState.uploadMutationsByLocalId.entries
        .toList(
          growable: false,
        );
    final hasAnyContent = photos.isNotEmpty || uploadMutations.isNotEmpty;

    if (!hasAnyContent) {
      return Text(
        ActivityPhotoGallerySection.emptyStateMessage,
        key: keys.emptyStateKey,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (photos.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: photos
                .map(
                  (photo) => _PhotoThumbnailTile(
                    key: keys.photoThumbnailKey(photo.id),
                    photo: photo,
                    onTap: onPhotoPressed == null
                        ? null
                        : () {
                            onPhotoPressed!(photo);
                          },
                    deleteMutation:
                        controllerState.deleteMutationsByPhotoId[photo.id],
                    deleteErrorKey: keys.photoDeleteMutationErrorKey(photo.id),
                  ),
                )
                .toList(growable: false),
          ),
        if (uploadMutations.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...uploadMutations.map(
            (entry) => _UploadMutationRow(
              key: keys.photoUploadMutationTileKey(entry.key),
              mutation: entry.value,
              errorKey: keys.photoUploadMutationErrorKey(entry.key),
            ),
          ),
        ],
      ],
    );
  }
}

// TODO(uff): Document _PhotoThumbnailTile.
/// TODO: Document _PhotoThumbnailTile.
class _PhotoThumbnailTile extends StatelessWidget {
  const _PhotoThumbnailTile({
    required this.photo,
    required this.onTap,
    required this.deleteMutation,
    required this.deleteErrorKey,
    super.key,
  });

  final ActivityPhoto photo;
  final VoidCallback? onTap;
  final PhotoMutation? deleteMutation;
  final Key deleteErrorKey;

  @override
  Widget build(BuildContext context) {
    final isDeletePending = _isPendingMutation(deleteMutation);
    final deleteError = _failedMutationError(deleteMutation);

    return ConstrainedBox(
      constraints: const BoxConstraints.tightFor(width: 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 112,
                    height: 112,
                    child: _PhotoImageOrPlaceholder(
                      url: photo.previewUrl,
                    ),
                  ),
                ),
                if (isDeletePending)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x88000000),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (deleteError != null) ...[
            const SizedBox(height: 4),
            CopyableErrorText(
              deleteError,
              key: deleteErrorKey,
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ],
      ),
    );
  }
}

// TODO(uff): Document _UploadMutationRow.
/// TODO: Document _UploadMutationRow.
class _UploadMutationRow extends StatelessWidget {
  const _UploadMutationRow({
    required this.mutation,
    required this.errorKey,
    super.key,
  });

  final PhotoMutation mutation;
  final Key errorKey;

  @override
  Widget build(BuildContext context) {
    switch (mutation.status) {
      case PhotoMutationStatus.pending:
        return const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('Uploading photo...'),
        );
      case PhotoMutationStatus.succeeded:
        return const SizedBox.shrink();
      case PhotoMutationStatus.failed:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.error_outline, color: Colors.red),
          title: CopyableErrorText(
            mutation.errorMessage ??
                'Unable to upload photo. Please try again.',
            key: errorKey,
            style: const TextStyle(color: Colors.red),
          ),
        );
    }
  }
}

/// NOTE(stuart): Document _PhotoImageOrPlaceholder.
class _PhotoImageOrPlaceholder extends StatelessWidget {
  const _PhotoImageOrPlaceholder({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (_isMissingPhotoUrl(url)) {
      return const _PhotoPlaceholder(icon: Icons.photo_outlined);
    }

    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        return const _PhotoPlaceholder(
          icon: Icons.broken_image_outlined,
        );
      },
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE0E0E0),
      child: Center(child: Icon(icon)),
    );
  }
}

/// NOTE(stuart): Document _PhotoUnavailableMessage.
class _PhotoUnavailableMessage extends StatelessWidget {
  const _PhotoUnavailableMessage({
    required this.icon,
    required this.iconKey,
  });

  final IconData icon;
  final Key iconKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          key: iconKey,
          size: 48,
        ),
        const SizedBox(height: 8),
        const Text('Photo preview is unavailable right now.'),
      ],
    );
  }
}

bool _isPendingMutation(PhotoMutation? mutation) {
  return mutation?.status == PhotoMutationStatus.pending;
}

String? _failedMutationError(PhotoMutation? mutation) {
  if (mutation?.status != PhotoMutationStatus.failed) {
    return null;
  }

  return mutation?.errorMessage;
}

// TODO(uff): Document ActivityPhotoViewerScreen.
/// TODO: Document ActivityPhotoViewerScreen.
class ActivityPhotoViewerScreen extends ConsumerStatefulWidget {
  const ActivityPhotoViewerScreen({
    required this.remoteActivityId,
    required this.photo,
    required this.keys,
    this.allowDelete = true,
    super.key,
  });

  final String remoteActivityId;
  final ActivityPhoto photo;
  final ActivityPhotoSectionKeyContract keys;
  final bool allowDelete;

  @override
  ConsumerState<ActivityPhotoViewerScreen> createState() =>
      _ActivityPhotoViewerScreenState();
}

/// TODO: Document _ActivityPhotoViewerScreenState.
class _ActivityPhotoViewerScreenState
    extends ConsumerState<ActivityPhotoViewerScreen> {
  bool _isSharing = false;
  static const _shareFailureMessage =
      'Unable to share photo right now. Please try again.';

  Future<void> _confirmAndDeletePhoto(
    BuildContext context,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete photo?'),
          content: const Text(
            'This removes the photo from the activity.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: widget.keys.deleteConfirmKey,
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) {
      return;
    }

    await ref
        .read(
          activityPhotoControllerProvider(
            widget.remoteActivityId,
          ).notifier,
        )
        .deleteActivityPhoto(widget.photo);
    if (!context.mounted) {
      return;
    }

    final mutation = ref
        .read(activityPhotoControllerProvider(widget.remoteActivityId))
        .deleteMutationsByPhotoId[widget.photo.id];
    if (mutation?.status == PhotoMutationStatus.succeeded) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _sharePhoto(
    BuildContext context,
    String resolvedViewerPhotoUrl,
  ) async {
    if (_isSharing) {
      return;
    }

    setState(() {
      _isSharing = true;
    });

    try {
      await ref
          .read(activityPhotoViewerShareHelperProvider)
          .shareResolvedViewerPhoto(
            resolvedViewerPhotoUrl: resolvedViewerPhotoUrl,
            fileLabel: _viewerPhotoFileLabel(widget.photo),
          );
    } on Object {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_shareFailureMessage)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(
      activityPhotoControllerProvider(widget.remoteActivityId),
    );
    final deleteMutation =
        controllerState.deleteMutationsByPhotoId[widget.photo.id];
    final isDeletePending = _isPendingMutation(deleteMutation);
    final deleteError = _failedMutationError(deleteMutation);
    final resolvedViewerPhotoUrl = _viewerPhotoUrl(widget.photo);
    final resolvedSharePhotoUrl = _viewerPhotoUrl(
      widget.photo,
      allowThumbnailFallback: false,
    );
    final canShare = !_isMissingPhotoUrl(resolvedSharePhotoUrl);

    return Scaffold(
      key: widget.keys.viewerKey,
      appBar: AppBar(
        title: const Text('Photo'),
        actions: [
          if (canShare)
            IconButton(
              key: widget.keys.viewerShareButtonKey,
              onPressed: _isSharing
                  ? null
                  : () {
                      _sharePhoto(context, resolvedSharePhotoUrl!);
                    },
              icon: _isSharing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        key: widget.keys.viewerShareLoadingKey,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.ios_share_outlined),
            ),
          if (widget.allowDelete)
            IconButton(
              key: widget.keys.viewerDeleteButtonKey,
              onPressed: isDeletePending
                  ? null
                  : () => _confirmAndDeletePhoto(context),
              icon: isDeletePending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: _PhotoViewerContent(
                    fullPhotoUrl: resolvedViewerPhotoUrl,
                    photoId: widget.photo.id,
                    keys: widget.keys,
                  ),
                ),
              ),
              if (deleteError != null) ...[
                const SizedBox(height: 12),
                CopyableErrorText(
                  deleteError,
                  key: widget.keys.photoDeleteMutationErrorKey(widget.photo.id),
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// NOTE(stuart): Document _PhotoViewerContent.
class _PhotoViewerContent extends StatelessWidget {
  const _PhotoViewerContent({
    required this.fullPhotoUrl,
    required this.photoId,
    required this.keys,
  });

  final String? fullPhotoUrl;
  final String photoId;
  final ActivityPhotoSectionKeyContract keys;

  @override
  Widget build(BuildContext context) {
    if (_isMissingPhotoUrl(fullPhotoUrl)) {
      return _PhotoUnavailableMessage(
        icon: Icons.image_not_supported_outlined,
        iconKey: keys.viewerUnavailableKey,
      );
    }

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4,
      child: Image.network(
        fullPhotoUrl!,
        key: keys.photoViewerImageKey(photoId),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) {
          return _PhotoUnavailableMessage(
            icon: Icons.broken_image_outlined,
            iconKey: keys.viewerUnavailableKey,
          );
        },
      ),
    );
  }
}

String? _viewerPhotoUrl(
  ActivityPhoto photo, {
  bool allowThumbnailFallback = true,
}) {
  if (!_isMissingPhotoUrl(photo.signedStorageUrl)) {
    return photo.signedStorageUrl;
  }
  if (!allowThumbnailFallback) {
    return null;
  }
  return photo.signedThumbnailUrl;
}

String _viewerPhotoFileLabel(ActivityPhoto photo) {
  final storageBasename = path.basename(photo.storagePath);
  if (storageBasename.isNotEmpty) {
    return storageBasename;
  }
  return '${photo.id}.jpg';
}

bool _isMissingPhotoUrl(String? url) {
  return url == null || url.isEmpty;
}

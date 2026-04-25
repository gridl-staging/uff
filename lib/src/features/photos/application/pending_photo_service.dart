import 'dart:io';

import 'package:uff/src/features/activity_tracking/data/tracking_database.dart';
import 'package:uff/src/features/photos/data/photo_picker_service.dart';
import 'package:uff/src/features/photos/data/supabase_photo_repository.dart'
    show PhotoBytesCompressor;
import 'package:uff/src/features/photos/domain/pending_photo.dart';

/// Maximum number of pending (not-yet-uploaded) photos allowed per recording
/// session. This mirrors the 20-photo-per-activity limit enforced server-side
/// by SupabasePhotoRepository, applied locally so we can reject early without
/// wasting camera+compression work.
const int maxPendingPhotosPerSession = 20;

/// TODO: Document PendingPhotoService.
class PendingPhotoService {
  PendingPhotoService({
    required TrackingDatabase db,
    required PhotoPickerService photoPickerService,
    required PhotoBytesCompressor compressPhoto,
    required Directory pendingPhotosDirectory,
    required String Function() uuidGenerator,
  }) : _db = db,
       _photoPickerService = photoPickerService,
       _compressPhoto = compressPhoto,
       _pendingPhotosDirectory = pendingPhotosDirectory,
       _uuidGenerator = uuidGenerator;

  final TrackingDatabase _db;
  final PhotoPickerService _photoPickerService;
  final PhotoBytesCompressor _compressPhoto;
  final Directory _pendingPhotosDirectory;
  final String Function() _uuidGenerator;

  /// Captures a photo from the camera, compresses it, saves to local
  /// filesystem, and records it in the pending_photos table.
  ///
  /// Returns the [PendingPhoto] on success, or `null` if:
  /// - The session already has [maxPendingPhotosPerSession] photos (limit
  ///   check happens before launching the camera to avoid wasted effort).
  /// - The user cancelled the camera picker.
  Future<PendingPhoto?> capturePhoto(
    int sessionId, {
    double? latitude,
    double? longitude,
  }) async {
    // 1. Enforce the per-session photo limit before opening the camera.
    final currentCount = await _db.countPendingPhotosForSession(sessionId);
    if (currentCount >= maxPendingPhotosPerSession) {
      return null;
    }

    // 2. Launch the camera picker (single photo).
    final picked = await _photoPickerService.pickPhotos(
      source: PhotoPickSource.camera,
      maxSelection: 1,
      // ignore: avoid_redundant_argument_values, reason: mid-run capture policy is intentionally explicit and test-locked
      offerCrop: false,
    );
    if (picked.isEmpty) {
      // User cancelled — nothing to do.
      return null;
    }

    // 3. Compress the raw bytes (same params as SupabasePhotoRepository:
    //    minWidth 2048, quality 85 — but those are baked into the compressor
    //    callback, not repeated here).
    final compressedBytes = await _compressPhoto(picked.first.bytes);

    // 4. Write compressed bytes to local filesystem.
    //    Path: {pendingPhotosDirectory}/{sessionId}/{uuid}.jpg
    final uuid = _uuidGenerator();
    final sessionDir = Directory('${_pendingPhotosDirectory.path}/$sessionId');
    if (!sessionDir.existsSync()) {
      sessionDir.createSync(recursive: true);
    }
    final localPath = '${sessionDir.path}/$uuid.jpg';
    final file = File(localPath);
    await file.writeAsBytes(compressedBytes);

    // 5. Record the pending photo in the Drift database.
    final capturedAt = DateTime.now();
    final id = await _db.savePendingPhoto(
      sessionId: sessionId,
      localPath: localPath,
      capturedAt: capturedAt,
      latitude: latitude,
      longitude: longitude,
    );

    // 6. Return the domain object. The id comes from the DB insert;
    //    capturedAt is truncated to second precision by the DB (Unix seconds).
    return PendingPhoto(
      id: id,
      sessionId: sessionId,
      localPath: localPath,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        capturedAt.millisecondsSinceEpoch ~/ 1000 * 1000,
      ),
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// Deletes all local photo files and DB rows for [sessionId].
  ///
  /// Called when the user discards a recording. Silently ignores files that
  /// are already missing on disk (e.g., if a previous partial cleanup ran).
  Future<void> discardPendingPhotos(int sessionId) async {
    // 1. Load all pending photos so we know which files to delete.
    final photos = await _db.loadPendingPhotos(sessionId);

    // 2. Delete each file from disk (ignore FileSystemException for missing
    //    files — the file may have been manually deleted or cleaned up by the
    //    OS reclaiming disk space).
    for (final photo in photos) {
      final file = File(photo.localPath);
      try {
        if (file.existsSync()) {
          file.deleteSync();
        }
      } on FileSystemException {
        // Silently ignore — the file is already gone.
      }
    }

    // 3. Remove all DB rows for this session in one batch.
    await _db.deleteAllPendingPhotosForSession(sessionId);
  }
}

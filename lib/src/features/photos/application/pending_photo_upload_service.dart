import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart';
import 'package:uff/src/features/photos/data/photo_repository.dart';
import 'package:uff/src/utils/app_logger.dart';

/// TODO: Document PendingPhotoUploadService.
class PendingPhotoUploadService {
  PendingPhotoUploadService({
    required TrackingDatabase db,
    required PhotoRepository photoRepository,
    AppLogSink? logSink,
  }) : _db = db,
       _photoRepository = photoRepository,
       _logger = AppLogger(sink: logSink);

  final TrackingDatabase _db;
  final PhotoRepository _photoRepository;
  final AppLogger _logger;

  /// Uploads all pending photos for [sessionId] to the remote activity.
  ///
  /// Called after sync assigns a remoteId. Each photo is uploaded via the
  /// existing [PhotoRepository.uploadPhoto], then the local file and DB row
  /// are cleaned up. Photos are assigned ascending sortOrder values based on
  /// their capturedAt ordering (earliest = 0).
  Future<void> uploadPendingPhotos({
    required int sessionId,
    required String remoteActivityId,
  }) async {
    final pendingPhotos = await _db.loadPendingPhotos(sessionId);
    if (pendingPhotos.isEmpty) {
      return;
    }

    var uploadedCount = 0;
    var failedCount = 0;

    for (var i = 0; i < pendingPhotos.length; i++) {
      final photo = pendingPhotos[i];
      final file = File(photo.localPath);

      // If the local file is missing (e.g., OS reclaimed disk space), skip
      // the upload but still clean up the orphaned DB row.
      if (!file.existsSync()) {
        _logger.logEvent(
          eventType: 'photos.pending_upload',
          outcome: 'missing_file',
          identifiers: {
            'session_id': sessionId,
            'photo_id': photo.id,
            'local_path': photo.localPath,
          },
        );
        await _db.deletePendingPhoto(photo.id);
        continue;
      }

      try {
        // Read the compressed bytes from the local file.
        final bytes = await file.readAsBytes();

        // Use the file's basename as the upload filename so the repository
        // can derive the extension and generate a unique storage path.
        final fileName = path.basename(photo.localPath);

        await _photoRepository.uploadPhoto(
          activityId: remoteActivityId,
          bytes: bytes,
          fileName: fileName,
          sortOrder: i,
          latitude: photo.latitude,
          longitude: photo.longitude,
        );

        // Upload succeeded — clean up local file and DB row.
        try {
          file.deleteSync();
        } on FileSystemException {
          // File already gone — harmless.
        }
        await _db.deletePendingPhoto(photo.id);
        uploadedCount++;
      } on Object catch (error) {
        // Individual photo upload failed. Log and continue with the rest so
        // a single flaky upload does not block the entire batch.
        failedCount++;
        _logger.logEvent(
          eventType: 'photos.pending_upload',
          outcome: 'upload_failed',
          identifiers: {
            'session_id': sessionId,
            'photo_id': photo.id,
            'reason': error.runtimeType.toString(),
          },
        );
      }
    }

    _logger.logEvent(
      eventType: 'photos.pending_upload',
      outcome: 'complete',
      identifiers: {
        'session_id': sessionId,
        'remote_activity_id': remoteActivityId,
        'uploaded_count': uploadedCount,
        'failed_count': failedCount,
      },
    );
  }
}

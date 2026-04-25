import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/photos/application/pending_photo_upload_service.dart';
import 'package:uff/src/features/photos/data/photo_repository.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';

/// ## Test Scenarios
/// - [positive] uploads all pending photos for a session sequentially
/// - [positive] deletes local file and DB row after each successful upload
/// - [positive] each photo is uploaded with the correct remoteActivityId
/// - [positive] uploads forward pending-photo latitude/longitude, including
///   null and valid 0.0 coordinates
/// - [edge] no-op for empty pending photos list
/// - [negative] continues uploading remaining photos if one fails
/// - [negative] handles missing local file gracefully (deletes DB row, logs warning)
/// - [isolation] only processes photos for the given sessionId

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Tracks each uploadPhoto call so tests can verify arguments and ordering.
class FakePhotoRepository implements PhotoRepository {
  final List<
    ({
      String activityId,
      String fileName,
      int sortOrder,
      int bytesLength,
      double? latitude,
      double? longitude,
    })
  >
  uploadCalls = [];

  /// If non-null, uploadPhoto throws this on the call at the matching index.
  final Map<int, Object> throwOnCallIndex = {};

  /// Counter for auto-generated photo ids in returned ActivityPhoto objects.
  int _nextPhotoId = 1;

  @override
  Future<ActivityPhoto> uploadPhoto({
    required String activityId,
    required Uint8List bytes,
    required String fileName,
    required int sortOrder,
    double? latitude,
    double? longitude,
  }) async {
    final callIndex = uploadCalls.length;
    uploadCalls.add((
      activityId: activityId,
      fileName: fileName,
      sortOrder: sortOrder,
      bytesLength: bytes.length,
      latitude: latitude,
      longitude: longitude,
    ));

    final error = throwOnCallIndex[callIndex];
    if (error != null) {
      throw error;
    }

    final id = 'photo-${_nextPhotoId++}';
    return ActivityPhoto(
      id: id,
      activityId: activityId,
      userId: 'fake-user',
      storagePath: 'fake/$id.jpg',
      sortOrder: sortOrder,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<List<ActivityPhoto>> loadActivityPhotos(String activityId) async {
    return const [];
  }

  @override
  Future<void> deletePhoto(ActivityPhoto photo) async {}
}

/// Records structured log events for assertion.
class FakeLogSink {
  final List<
    ({
      String eventType,
      String outcome,
      Map<String, Object?> identifiers,
    })
  >
  events = [];

  void call(Map<String, Object?> event) {
    events.add((
      eventType: event['event_type'] as String,
      outcome: event['outcome'] as String,
      identifiers: (event['identifiers'] as Map<String, Object?>?) ?? const {},
    ));
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Inserts a tracking session row so loadPendingPhotos has a meaningful
/// session_id to reference.
Future<int> _insertSession(TrackingDatabase db) async {
  return db.insertSession(
    TrackingSessionsCompanion.insert(
      status: TrackingSessionStatus.recording,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
  );
}

/// Writes fake photo bytes to a temp file and records it in the DB.
Future<({int photoId, String path})> _createPendingPhoto(
  TrackingDatabase db, {
  required int sessionId,
  required Directory dir,
  required String filename,
  required DateTime capturedAt,
  List<int>? bytes,
  double? latitude,
  double? longitude,
}) async {
  final file = File('${dir.path}/$filename');
  file.writeAsBytesSync(bytes ?? [1, 2, 3, 4, 5]);
  final id = await db.savePendingPhoto(
    sessionId: sessionId,
    localPath: file.path,
    capturedAt: capturedAt,
    latitude: latitude,
    longitude: longitude,
  );
  return (photoId: id, path: file.path);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late TrackingDatabase db;
  late FakePhotoRepository fakePhotoRepo;
  late FakeLogSink logSink;
  late Directory tempDir;

  setUp(() async {
    db = TrackingDatabase.forTesting(NativeDatabase.memory());
    fakePhotoRepo = FakePhotoRepository();
    logSink = FakeLogSink();
    tempDir = await Directory.systemTemp.createTemp('pending_upload_test_');
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  PendingPhotoUploadService buildService() {
    return PendingPhotoUploadService(
      db: db,
      photoRepository: fakePhotoRepo,
      logSink: logSink.call,
    );
  }

  group('PendingPhotoUploadService.uploadPendingPhotos', () {
    test('no-op when no pending photos exist for the session', () async {
      final sessionId = await _insertSession(db);
      final service = buildService();

      // Should complete without calling uploadPhoto.
      await service.uploadPendingPhotos(
        sessionId: sessionId,
        remoteActivityId: 'remote-abc',
      );

      expect(fakePhotoRepo.uploadCalls, isEmpty);
    });

    test(
      'uploads all pending photos with correct remoteActivityId and sortOrder',
      () async {
        final sessionId = await _insertSession(db);
        // Create 3 pending photos with ascending capturedAt so sort order is
        // deterministic (0, 1, 2).
        await _createPendingPhoto(
          db,
          sessionId: sessionId,
          dir: tempDir,
          filename: 'a.jpg',
          capturedAt: DateTime(2026, 1, 1, 12, 0),
          bytes: [10, 20],
        );
        await _createPendingPhoto(
          db,
          sessionId: sessionId,
          dir: tempDir,
          filename: 'b.jpg',
          capturedAt: DateTime(2026, 1, 1, 12, 1),
          bytes: [30, 40, 50],
        );
        await _createPendingPhoto(
          db,
          sessionId: sessionId,
          dir: tempDir,
          filename: 'c.jpg',
          capturedAt: DateTime(2026, 1, 1, 12, 2),
          bytes: [60],
        );

        final service = buildService();
        await service.uploadPendingPhotos(
          sessionId: sessionId,
          remoteActivityId: 'remote-xyz',
        );

        // All 3 photos uploaded, each with the correct remote activity id.
        expect(fakePhotoRepo.uploadCalls.length, 3);
        expect(fakePhotoRepo.uploadCalls[0].activityId, 'remote-xyz');
        expect(fakePhotoRepo.uploadCalls[0].sortOrder, 0);
        expect(fakePhotoRepo.uploadCalls[0].bytesLength, 2);
        expect(fakePhotoRepo.uploadCalls[1].activityId, 'remote-xyz');
        expect(fakePhotoRepo.uploadCalls[1].sortOrder, 1);
        expect(fakePhotoRepo.uploadCalls[1].bytesLength, 3);
        expect(fakePhotoRepo.uploadCalls[2].activityId, 'remote-xyz');
        expect(fakePhotoRepo.uploadCalls[2].sortOrder, 2);
        expect(fakePhotoRepo.uploadCalls[2].bytesLength, 1);
      },
    );

    test(
      'forwards pending photo latitude/longitude including null and 0.0 values',
      () async {
        final sessionId = await _insertSession(db);
        await _createPendingPhoto(
          db,
          sessionId: sessionId,
          dir: tempDir,
          filename: 'null-coords.jpg',
          capturedAt: DateTime(2026, 1, 1, 12, 0),
          latitude: null,
          longitude: null,
        );
        await _createPendingPhoto(
          db,
          sessionId: sessionId,
          dir: tempDir,
          filename: 'zero-coords.jpg',
          capturedAt: DateTime(2026, 1, 1, 12, 1),
          latitude: 0.0,
          longitude: 0.0,
        );
        await _createPendingPhoto(
          db,
          sessionId: sessionId,
          dir: tempDir,
          filename: 'point-coords.jpg',
          capturedAt: DateTime(2026, 1, 1, 12, 2),
          latitude: 40.7128,
          longitude: -74.006,
        );

        final service = buildService();
        await service.uploadPendingPhotos(
          sessionId: sessionId,
          remoteActivityId: 'remote-coords',
        );

        expect(fakePhotoRepo.uploadCalls.length, 3);
        expect(fakePhotoRepo.uploadCalls[0].latitude, isNull);
        expect(fakePhotoRepo.uploadCalls[0].longitude, isNull);
        expect(fakePhotoRepo.uploadCalls[1].latitude, 0.0);
        expect(fakePhotoRepo.uploadCalls[1].longitude, 0.0);
        expect(fakePhotoRepo.uploadCalls[2].latitude, 40.7128);
        expect(fakePhotoRepo.uploadCalls[2].longitude, -74.006);
      },
    );

    test(
      'deletes local file and DB row after each successful upload',
      () async {
        final sessionId = await _insertSession(db);
        final photo1 = await _createPendingPhoto(
          db,
          sessionId: sessionId,
          dir: tempDir,
          filename: 'photo1.jpg',
          capturedAt: DateTime(2026, 1, 1, 12, 0),
        );
        final photo2 = await _createPendingPhoto(
          db,
          sessionId: sessionId,
          dir: tempDir,
          filename: 'photo2.jpg',
          capturedAt: DateTime(2026, 1, 1, 12, 1),
        );

        final service = buildService();
        await service.uploadPendingPhotos(
          sessionId: sessionId,
          remoteActivityId: 'remote-1',
        );

        // Local files should be deleted.
        expect(File(photo1.path).existsSync(), isFalse);
        expect(File(photo2.path).existsSync(), isFalse);

        // DB rows should be deleted.
        final remaining = await db.loadPendingPhotos(sessionId);
        expect(remaining, isEmpty);
      },
    );

    test(
      'handles missing local file gracefully — deletes DB row and logs warning',
      () async {
        final sessionId = await _insertSession(db);
        // Save a DB row pointing to a file that does not exist on disk.
        await db.savePendingPhoto(
          sessionId: sessionId,
          localPath: '${tempDir.path}/nonexistent.jpg',
          capturedAt: DateTime(2026, 1, 1, 12, 0),
        );

        final service = buildService();
        await service.uploadPendingPhotos(
          sessionId: sessionId,
          remoteActivityId: 'remote-2',
        );

        // No upload should have been attempted (no bytes to read).
        expect(fakePhotoRepo.uploadCalls, isEmpty);

        // DB row should still be cleaned up.
        final remaining = await db.loadPendingPhotos(sessionId);
        expect(remaining, isEmpty);

        // A warning log event should have been emitted.
        final warningEvents = logSink.events
            .where(
              (e) =>
                  e.eventType == 'photos.pending_upload' &&
                  e.outcome == 'missing_file',
            )
            .toList();
        expect(warningEvents.length, 1);
      },
    );

    test('continues uploading remaining photos if one upload fails', () async {
      final sessionId = await _insertSession(db);
      final photo1 = await _createPendingPhoto(
        db,
        sessionId: sessionId,
        dir: tempDir,
        filename: 'ok1.jpg',
        capturedAt: DateTime(2026, 1, 1, 12, 0),
        bytes: [1],
      );
      await _createPendingPhoto(
        db,
        sessionId: sessionId,
        dir: tempDir,
        filename: 'fail.jpg',
        capturedAt: DateTime(2026, 1, 1, 12, 1),
        bytes: [2],
      );
      final photo3 = await _createPendingPhoto(
        db,
        sessionId: sessionId,
        dir: tempDir,
        filename: 'ok2.jpg',
        capturedAt: DateTime(2026, 1, 1, 12, 2),
        bytes: [3],
      );

      // Make the second upload (index 1) throw.
      fakePhotoRepo.throwOnCallIndex[1] = Exception('network timeout');

      final service = buildService();
      await service.uploadPendingPhotos(
        sessionId: sessionId,
        remoteActivityId: 'remote-3',
      );

      // All 3 uploads were attempted.
      expect(fakePhotoRepo.uploadCalls.length, 3);

      // Photos 1 and 3 had their local files deleted (successful uploads).
      expect(File(photo1.path).existsSync(), isFalse);
      expect(File(photo3.path).existsSync(), isFalse);

      // The failed photo's local file is still on disk for retry.
      // Its DB row is also preserved.
      final remaining = await db.loadPendingPhotos(sessionId);
      expect(remaining.length, 1);
      expect(remaining.first.localPath, contains('fail.jpg'));

      // A failure log event was emitted for the failed upload.
      final failEvents = logSink.events
          .where(
            (e) =>
                e.eventType == 'photos.pending_upload' &&
                e.outcome == 'upload_failed',
          )
          .toList();
      expect(failEvents.length, 1);
    });

    test('uses filename from localPath basename for upload', () async {
      final sessionId = await _insertSession(db);
      await _createPendingPhoto(
        db,
        sessionId: sessionId,
        dir: tempDir,
        filename: 'my-photo-uuid.jpg',
        capturedAt: DateTime(2026, 1, 1, 12, 0),
      );

      final service = buildService();
      await service.uploadPendingPhotos(
        sessionId: sessionId,
        remoteActivityId: 'remote-4',
      );

      expect(fakePhotoRepo.uploadCalls.length, 1);
      expect(fakePhotoRepo.uploadCalls[0].fileName, 'my-photo-uuid.jpg');
    });

    test('only processes photos for the given sessionId', () async {
      final session1 = await _insertSession(db);
      final session2 = await _insertSession(db);

      await _createPendingPhoto(
        db,
        sessionId: session1,
        dir: tempDir,
        filename: 's1.jpg',
        capturedAt: DateTime(2026, 1, 1, 12, 0),
      );
      await _createPendingPhoto(
        db,
        sessionId: session2,
        dir: tempDir,
        filename: 's2.jpg',
        capturedAt: DateTime(2026, 1, 1, 12, 0),
      );

      final service = buildService();
      // Only upload for session1.
      await service.uploadPendingPhotos(
        sessionId: session1,
        remoteActivityId: 'remote-s1',
      );

      // Only 1 upload (for session1).
      expect(fakePhotoRepo.uploadCalls.length, 1);
      expect(fakePhotoRepo.uploadCalls[0].activityId, 'remote-s1');

      // session2's photo still exists in DB.
      final s2Remaining = await db.loadPendingPhotos(session2);
      expect(s2Remaining.length, 1);
    });

    test(
      'logs success event with photo count after completing all uploads',
      () async {
        final sessionId = await _insertSession(db);
        await _createPendingPhoto(
          db,
          sessionId: sessionId,
          dir: tempDir,
          filename: 'x.jpg',
          capturedAt: DateTime(2026, 1, 1, 12, 0),
        );

        final service = buildService();
        await service.uploadPendingPhotos(
          sessionId: sessionId,
          remoteActivityId: 'remote-5',
        );

        final successEvents = logSink.events
            .where(
              (e) =>
                  e.eventType == 'photos.pending_upload' &&
                  e.outcome == 'complete',
            )
            .toList();
        expect(successEvents.length, 1);
        expect(successEvents.first.identifiers['uploaded_count'], 1);
        expect(successEvents.first.identifiers['failed_count'], 0);
      },
    );
  });
}

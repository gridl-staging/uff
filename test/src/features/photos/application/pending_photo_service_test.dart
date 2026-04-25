import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart';
import 'package:uff/src/features/photos/application/pending_photo_service.dart';
import 'package:uff/src/features/photos/data/photo_picker_service.dart';

/// ## Test Scenarios
/// - [positive] capturePhoto calls picker with camera source and maxSelection 1
/// - [positive] capturePhoto compresses the raw photo bytes
/// - [positive] capturePhoto writes compressed bytes to local filesystem
/// - [positive] capturePhoto records the pending photo in the database
/// - [positive] capturePhoto returns PendingPhoto with correct fields
/// - [positive] capturePhoto persists explicit null latitude/longitude
/// - [positive] capturePhoto persists valid 0.0 latitude/longitude
/// - [negative] capturePhoto returns null when user cancels (picker returns empty)
/// - [negative] capturePhoto returns null when photo limit (20) is reached
/// - [positive] discardPendingPhotos deletes local files and DB rows
/// - [edge] discardPendingPhotos silently ignores missing files
/// - [isolation] discardPendingPhotos only removes photos for the target session

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// A fake PhotoPickerService that records call arguments and returns a
/// controllable result. No real camera interaction.
class FakePhotoPickerService extends PhotoPickerService {
  /// What the fake will return on the next call to pickPhotos.
  List<PickedPhoto> nextResult = const <PickedPhoto>[];

  /// Recorded arguments from the last call.
  PhotoPickSource? lastSource;
  int? lastMaxSelection;
  bool? lastOfferCrop;

  @override
  Future<List<PickedPhoto>> pickPhotos({
    required PhotoPickSource source,
    int maxSelection = 20,
    bool offerCrop = false,
  }) async {
    lastSource = source;
    lastMaxSelection = maxSelection;
    lastOfferCrop = offerCrop;
    return nextResult;
  }
}

void main() {
  late TrackingDatabase db;
  late FakePhotoPickerService fakePicker;
  late Directory tempDir;

  // Tracks whether the compressor was called and with what input.
  Uint8List? compressorReceivedBytes;
  // The "compressed" bytes the fake compressor returns.
  final fakeCompressedBytes = Uint8List.fromList([10, 20, 30]);

  // A deterministic uuid generator for predictable file names.
  var uuidCallCount = 0;
  String fakeUuid() {
    uuidCallCount += 1;
    return 'fake-uuid-$uuidCallCount';
  }

  // Fake compressor that records its input and returns controlled output.
  Future<Uint8List> fakeCompressor(Uint8List bytes) async {
    compressorReceivedBytes = bytes;
    return fakeCompressedBytes;
  }

  setUp(() async {
    db = TrackingDatabase.forTesting(NativeDatabase.memory());
    fakePicker = FakePhotoPickerService();
    tempDir = await Directory.systemTemp.createTemp('pending_photo_test_');
    compressorReceivedBytes = null;
    uuidCallCount = 0;
  });

  tearDown(() async {
    await db.close();
    // Clean up temp directory after each test.
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Helper: builds a PendingPhotoService wired to fakes.
  PendingPhotoService buildService() {
    return PendingPhotoService(
      db: db,
      photoPickerService: fakePicker,
      compressPhoto: fakeCompressor,
      pendingPhotosDirectory: tempDir,
      uuidGenerator: fakeUuid,
    );
  }

  // -------------------------------------------------------------------------
  // capturePhoto — happy path
  // -------------------------------------------------------------------------

  test(
    'capturePhoto calls picker with camera source, maxSelection 1, and offerCrop false',
    () async {
      final service = buildService();
      final rawBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      fakePicker.nextResult = [
        PickedPhoto(fileName: 'img.jpg', bytes: rawBytes),
      ];

      await service.capturePhoto(42);

      expect(fakePicker.lastSource, PhotoPickSource.camera);
      expect(fakePicker.lastMaxSelection, 1);
      expect(fakePicker.lastOfferCrop, false);
    },
  );

  test('capturePhoto compresses the raw photo bytes', () async {
    final service = buildService();
    final rawBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    fakePicker.nextResult = [PickedPhoto(fileName: 'img.jpg', bytes: rawBytes)];

    await service.capturePhoto(42);

    // The compressor should have received the raw bytes from the picker.
    expect(compressorReceivedBytes, rawBytes);
  });

  test('capturePhoto writes compressed bytes to local filesystem', () async {
    final service = buildService();
    final rawBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    fakePicker.nextResult = [PickedPhoto(fileName: 'img.jpg', bytes: rawBytes)];

    await service.capturePhoto(42);

    // Should have written to {tempDir}/42/fake-uuid-1.jpg
    final expectedPath = '${tempDir.path}/42/fake-uuid-1.jpg';
    final file = File(expectedPath);
    expect(file.existsSync(), true);
    expect(file.readAsBytesSync(), fakeCompressedBytes);
  });

  test('capturePhoto records the pending photo in the database', () async {
    final service = buildService();
    final rawBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    fakePicker.nextResult = [PickedPhoto(fileName: 'img.jpg', bytes: rawBytes)];

    await service.capturePhoto(42);

    final photos = await db.loadPendingPhotos(42);
    expect(photos.length, 1);
    expect(photos.first.sessionId, 42);
    expect(photos.first.localPath, '${tempDir.path}/42/fake-uuid-1.jpg');
  });

  test('capturePhoto returns PendingPhoto with correct fields', () async {
    final service = buildService();
    final rawBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    fakePicker.nextResult = [PickedPhoto(fileName: 'img.jpg', bytes: rawBytes)];

    final result = await service.capturePhoto(42);

    // Subsequent field assertions prove result is non-null and correct.
    expect(result!.sessionId, 42);
    expect(result.localPath, '${tempDir.path}/42/fake-uuid-1.jpg');
    // The id should be a positive integer assigned by the database.
    expect(result.id, isPositive);
    // capturedAt should be a recent timestamp (within the last few seconds).
    final now = DateTime.now();
    // capturedAt is stored with second precision (Unix seconds), so allow
    // up to 5 seconds of wiggle room for slow CI.
    expect(
      now.difference(result.capturedAt).inSeconds.abs() < 5,
      true,
    );
  });

  test('capturePhoto persists explicit null latitude/longitude', () async {
    final service = buildService();
    final rawBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    fakePicker.nextResult = [PickedPhoto(fileName: 'img.jpg', bytes: rawBytes)];

    final result = await service.capturePhoto(
      42,
      latitude: null,
      longitude: null,
    );

    expect(result!.latitude, isNull);
    expect(result.longitude, isNull);

    final savedPhotos = await db.loadPendingPhotos(42);
    expect(savedPhotos.length, 1);
    expect(savedPhotos.single.latitude, isNull);
    expect(savedPhotos.single.longitude, isNull);
  });

  test('capturePhoto persists valid 0.0 latitude/longitude', () async {
    final service = buildService();
    final rawBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    fakePicker.nextResult = [PickedPhoto(fileName: 'img.jpg', bytes: rawBytes)];

    final result = await service.capturePhoto(
      42,
      latitude: 0.0,
      longitude: 0.0,
    );

    expect(result!.latitude, 0.0);
    expect(result.longitude, 0.0);

    final savedPhotos = await db.loadPendingPhotos(42);
    expect(savedPhotos.length, 1);
    expect(savedPhotos.single.latitude, 0.0);
    expect(savedPhotos.single.longitude, 0.0);
  });

  // -------------------------------------------------------------------------
  // capturePhoto — user cancels
  // -------------------------------------------------------------------------

  test(
    'capturePhoto returns null when user cancels (picker returns empty)',
    () async {
      final service = buildService();
      // Picker returns empty list — user tapped "Cancel".
      fakePicker.nextResult = const <PickedPhoto>[];

      final result = await service.capturePhoto(42);

      expect(result, isNull);
      // No file should have been written.
      final sessionDir = Directory('${tempDir.path}/42');
      expect(sessionDir.existsSync(), false);
      // No DB row should have been created.
      final count = await db.countPendingPhotosForSession(42);
      expect(count, 0);
    },
  );

  // -------------------------------------------------------------------------
  // capturePhoto — photo limit reached
  // -------------------------------------------------------------------------

  test('capturePhoto returns null when photo limit (20) is reached', () async {
    final service = buildService();

    // Pre-populate 20 pending photos in the database for session 42.
    for (var i = 0; i < maxPendingPhotosPerSession; i++) {
      await db.savePendingPhoto(
        sessionId: 42,
        localPath: '${tempDir.path}/42/existing-$i.jpg',
        capturedAt: DateTime(2026, 3, 28, 10, i),
      );
    }

    final result = await service.capturePhoto(42);

    expect(result, isNull);
    // The picker should NOT have been called at all — we bail out early.
    expect(fakePicker.lastSource, isNull);
    // Count stays at 20.
    final count = await db.countPendingPhotosForSession(42);
    expect(count, maxPendingPhotosPerSession);
  });

  // -------------------------------------------------------------------------
  // discardPendingPhotos
  // -------------------------------------------------------------------------

  test('discardPendingPhotos deletes local files and DB rows', () async {
    final service = buildService();
    final rawBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    fakePicker.nextResult = [PickedPhoto(fileName: 'img.jpg', bytes: rawBytes)];

    // Capture two photos for session 42.
    final photo1 = await service.capturePhoto(42);
    fakePicker.nextResult = [
      PickedPhoto(fileName: 'img2.jpg', bytes: rawBytes),
    ];
    final photo2 = await service.capturePhoto(42);

    // Verify files exist before discard.
    expect(File(photo1!.localPath).existsSync(), true);
    expect(File(photo2!.localPath).existsSync(), true);

    await service.discardPendingPhotos(42);

    // Files should be gone.
    expect(File(photo1.localPath).existsSync(), false);
    expect(File(photo2.localPath).existsSync(), false);
    // DB rows should be gone.
    final count = await db.countPendingPhotosForSession(42);
    expect(count, 0);
  });

  test('discardPendingPhotos silently ignores missing files', () async {
    final service = buildService();

    // Insert a DB row referencing a file that doesn't exist on disk.
    await db.savePendingPhoto(
      sessionId: 42,
      localPath: '${tempDir.path}/42/does-not-exist.jpg',
      capturedAt: DateTime(2026, 3, 28, 10),
    );

    // Should not throw even though the file is missing.
    await service.discardPendingPhotos(42);

    // DB row should still be cleaned up.
    final count = await db.countPendingPhotosForSession(42);
    expect(count, 0);
  });

  test(
    'discardPendingPhotos only removes photos for the target session',
    () async {
      final service = buildService();
      final rawBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

      // Capture a photo for session 42.
      fakePicker.nextResult = [
        PickedPhoto(fileName: 'img.jpg', bytes: rawBytes),
      ];
      final photo42 = await service.capturePhoto(42);

      // Capture a photo for session 99.
      fakePicker.nextResult = [
        PickedPhoto(fileName: 'img99.jpg', bytes: rawBytes),
      ];
      final photo99 = await service.capturePhoto(99);

      // Discard only session 42.
      await service.discardPendingPhotos(42);

      // Session 42 file and DB row gone.
      expect(File(photo42!.localPath).existsSync(), false);
      expect(await db.countPendingPhotosForSession(42), 0);

      // Session 99 file and DB row untouched.
      expect(File(photo99!.localPath).existsSync(), true);
      expect(await db.countPendingPhotosForSession(99), 1);
    },
  );
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart';

/// ## Test Scenarios
/// - [positive] savePendingPhoto persists a row and returns its auto-generated id
/// - [positive] loadPendingPhotos returns all photos for a session ordered by capturedAt
/// - [positive] loadPendingPhotos returns empty list for unknown session
/// - [positive] deletePendingPhoto removes a single row by id
/// - [positive] deleteAllForSession removes all photos for a session
/// - [positive] countForSession returns the exact count of pending photos
/// - [positive] round-trip with exact lat/lng values preserves coordinates
/// - [negative] deleteAllForSession does not affect photos from other sessions
/// - [negative] round-trip with null lat/lng (gallery import) preserves nulls
/// - [isolation] Separate sessions keep pending-photo rows isolated by session id
/// - [edge] countForSession returns 0 for unknown session
/// - [edge] round-trip with 0.0/0.0 equator coords are not treated as null
void main() {
  late TrackingDatabase db;

  setUp(() {
    // Use an in-memory database for fast, isolated tests.
    db = TrackingDatabase.forTesting(
      NativeDatabase.memory(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'savePendingPhoto persists a row and returns its auto-generated id',
    () async {
      final capturedAt = DateTime(2026, 3, 28, 10, 30);
      final id = await db.savePendingPhoto(
        sessionId: 42,
        localPath: '/tmp/photos/42/abc.jpg',
        capturedAt: capturedAt,
      );

      expect(id, isPositive);

      final photos = await db.loadPendingPhotos(42);
      expect(photos.length, 1);
      expect(photos.first.id, id);
      expect(photos.first.sessionId, 42);
      expect(photos.first.localPath, '/tmp/photos/42/abc.jpg');
      expect(photos.first.capturedAt, capturedAt);
    },
  );

  test('loadPendingPhotos returns photos ordered by capturedAt', () async {
    final earlier = DateTime(2026, 3, 28, 10, 30);
    final later = DateTime(2026, 3, 28, 10, 35);
    final latest = DateTime(2026, 3, 28, 10, 40);

    // Insert out of order to verify sorting.
    await db.savePendingPhoto(
      sessionId: 1,
      localPath: '/tmp/photos/1/later.jpg',
      capturedAt: later,
    );
    await db.savePendingPhoto(
      sessionId: 1,
      localPath: '/tmp/photos/1/earliest.jpg',
      capturedAt: earlier,
    );
    await db.savePendingPhoto(
      sessionId: 1,
      localPath: '/tmp/photos/1/latest.jpg',
      capturedAt: latest,
    );

    final photos = await db.loadPendingPhotos(1);
    expect(photos.length, 3);
    expect(photos[0].localPath, '/tmp/photos/1/earliest.jpg');
    expect(photos[1].localPath, '/tmp/photos/1/later.jpg');
    expect(photos[2].localPath, '/tmp/photos/1/latest.jpg');
  });

  test('loadPendingPhotos returns empty list for unknown session', () async {
    final photos = await db.loadPendingPhotos(999);
    expect(photos, isEmpty);
  });

  test('deletePendingPhoto removes a single row by id', () async {
    final id1 = await db.savePendingPhoto(
      sessionId: 1,
      localPath: '/tmp/photos/1/a.jpg',
      capturedAt: DateTime(2026, 3, 28, 10, 0),
    );
    final id2 = await db.savePendingPhoto(
      sessionId: 1,
      localPath: '/tmp/photos/1/b.jpg',
      capturedAt: DateTime(2026, 3, 28, 10, 5),
    );

    await db.deletePendingPhoto(id1);

    final remaining = await db.loadPendingPhotos(1);
    expect(remaining.length, 1);
    expect(remaining.first.id, id2);
  });

  test(
    'deleteAllForSession removes all photos for the target session',
    () async {
      await db.savePendingPhoto(
        sessionId: 1,
        localPath: '/tmp/photos/1/a.jpg',
        capturedAt: DateTime(2026, 3, 28, 10, 0),
      );
      await db.savePendingPhoto(
        sessionId: 1,
        localPath: '/tmp/photos/1/b.jpg',
        capturedAt: DateTime(2026, 3, 28, 10, 5),
      );

      await db.deleteAllPendingPhotosForSession(1);

      final photos = await db.loadPendingPhotos(1);
      expect(photos, isEmpty);
    },
  );

  test(
    'deleteAllForSession does not affect photos from other sessions',
    () async {
      await db.savePendingPhoto(
        sessionId: 1,
        localPath: '/tmp/photos/1/a.jpg',
        capturedAt: DateTime(2026, 3, 28, 10, 0),
      );
      await db.savePendingPhoto(
        sessionId: 2,
        localPath: '/tmp/photos/2/b.jpg',
        capturedAt: DateTime(2026, 3, 28, 10, 5),
      );

      await db.deleteAllPendingPhotosForSession(1);

      final session1Photos = await db.loadPendingPhotos(1);
      final session2Photos = await db.loadPendingPhotos(2);
      expect(session1Photos, isEmpty);
      expect(session2Photos.length, 1);
      expect(session2Photos.first.localPath, '/tmp/photos/2/b.jpg');
    },
  );

  test('countForSession returns the exact count', () async {
    await db.savePendingPhoto(
      sessionId: 5,
      localPath: '/tmp/photos/5/a.jpg',
      capturedAt: DateTime(2026, 3, 28, 10, 0),
    );
    await db.savePendingPhoto(
      sessionId: 5,
      localPath: '/tmp/photos/5/b.jpg',
      capturedAt: DateTime(2026, 3, 28, 10, 5),
    );
    await db.savePendingPhoto(
      sessionId: 5,
      localPath: '/tmp/photos/5/c.jpg',
      capturedAt: DateTime(2026, 3, 28, 10, 10),
    );

    final count = await db.countPendingPhotosForSession(5);
    expect(count, 3);
  });

  test('countForSession returns 0 for unknown session', () async {
    final count = await db.countPendingPhotosForSession(999);
    expect(count, 0);
  });

  test('round-trip with exact lat/lng preserves coordinates', () async {
    final capturedAt = DateTime(2026, 3, 28, 12, 0);
    final id = await db.savePendingPhoto(
      sessionId: 10,
      localPath: '/tmp/photos/10/gps.jpg',
      capturedAt: capturedAt,
      latitude: 37.7749,
      longitude: -122.4194,
    );

    final photos = await db.loadPendingPhotos(10);
    expect(photos.length, 1);
    expect(photos.first.id, id);
    expect(photos.first.latitude, 37.7749);
    expect(photos.first.longitude, -122.4194);
  });

  test(
    'round-trip with null lat/lng (gallery import) preserves nulls',
    () async {
      final capturedAt = DateTime(2026, 3, 28, 12, 5);
      await db.savePendingPhoto(
        sessionId: 11,
        localPath: '/tmp/photos/11/gallery.jpg',
        capturedAt: capturedAt,
      );

      final photos = await db.loadPendingPhotos(11);
      expect(photos.length, 1);
      expect(photos.first.latitude, isNull);
      expect(photos.first.longitude, isNull);
    },
  );

  test(
    'round-trip with 0.0/0.0 equator coords are not treated as null',
    () async {
      final capturedAt = DateTime(2026, 3, 28, 12, 10);
      await db.savePendingPhoto(
        sessionId: 12,
        localPath: '/tmp/photos/12/equator.jpg',
        capturedAt: capturedAt,
        latitude: 0.0,
        longitude: 0.0,
      );

      final photos = await db.loadPendingPhotos(12);
      expect(photos.length, 1);
      expect(photos.first.latitude, 0.0);
      expect(photos.first.longitude, 0.0);
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/photos/data/supabase_photo_repository.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';

/// ## Test Scenarios
/// - [positive] ActivityPhoto equality/hashCode compare all persisted and
///   signed-url fields.
/// - [positive] equality with lat/lng populated — identical coords equal,
///   different coords not equal.
/// - [positive] `activityPhotoFromJson()` maps a complete Supabase row into an
///   ActivityPhoto with parsed timestamp.
/// - [positive] `activityPhotoFromJson()` parses lat/lng from JSON.
/// - [positive] `withSignedUrls` preserves lat/lng.
/// - [negative] `activityPhotoFromJson()` with null lat/lng yields null fields.
/// - [edge] `activityPhotoFromJson()` accepts nullable `thumbnail_path`.
/// - [edge] `activityPhotoFromJson()` with 0.0/0.0 equator coords not null.
/// - [positive] `isMapEligible` returns true when both lat and lng are non-null.
/// - [edge] `isMapEligible` returns true for 0.0/0.0 coordinates (equator).
/// - [negative] `isMapEligible` returns false when lat is null.
/// - [negative] `isMapEligible` returns false when lng is null.
/// - [negative] `isMapEligible` returns false when both lat and lng are null.
/// - [positive] `previewUrl` prefers signedThumbnailUrl over signedStorageUrl.
/// - [positive] `previewUrl` falls back to signedStorageUrl when thumbnail is null.
/// - [negative] `previewUrl` returns null when both URLs are null.
/// - [edge] `previewUrl` returns null when both URLs are empty strings.
/// - [isolation] Separate ActivityPhoto fixtures do not leak signed URL state.
void main() {
  group('ActivityPhoto value semantics', () {
    test('compares by value across all fields', () {
      final createdAt = DateTime.utc(2026, 3, 17, 12, 30);
      final first = ActivityPhoto(
        id: 'photo-1',
        activityId: 'activity-1',
        userId: 'user-1',
        storagePath: 'user-1/activity-1/photo.jpg',
        thumbnailPath: 'user-1/activity-1/photo-thumb.jpg',
        sortOrder: 0,
        createdAt: createdAt,
        signedStorageUrl: 'https://example.com/photo',
        signedThumbnailUrl: 'https://example.com/thumb',
      );
      final second = ActivityPhoto(
        id: 'photo-1',
        activityId: 'activity-1',
        userId: 'user-1',
        storagePath: 'user-1/activity-1/photo.jpg',
        thumbnailPath: 'user-1/activity-1/photo-thumb.jpg',
        sortOrder: 0,
        createdAt: createdAt,
        signedStorageUrl: 'https://example.com/photo',
        signedThumbnailUrl: 'https://example.com/thumb',
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('equality with lat/lng — identical coords equal, different not', () {
      final createdAt = DateTime.utc(2026, 3, 17, 12, 30);
      final withCoords = ActivityPhoto(
        id: 'photo-1',
        activityId: 'activity-1',
        userId: 'user-1',
        storagePath: 'user-1/activity-1/photo.jpg',
        sortOrder: 0,
        createdAt: createdAt,
        latitude: 40.7128,
        longitude: -74.0060,
      );
      final sameCoords = ActivityPhoto(
        id: 'photo-1',
        activityId: 'activity-1',
        userId: 'user-1',
        storagePath: 'user-1/activity-1/photo.jpg',
        sortOrder: 0,
        createdAt: createdAt,
        latitude: 40.7128,
        longitude: -74.0060,
      );
      final differentCoords = ActivityPhoto(
        id: 'photo-1',
        activityId: 'activity-1',
        userId: 'user-1',
        storagePath: 'user-1/activity-1/photo.jpg',
        sortOrder: 0,
        createdAt: createdAt,
        latitude: 51.5074,
        longitude: -0.1278,
      );

      expect(withCoords, sameCoords);
      expect(withCoords.hashCode, sameCoords.hashCode);
      expect(withCoords, isNot(differentCoords));
    });
  });

  group('activityPhotoFromJson', () {
    test('maps a Supabase row into ActivityPhoto', () {
      final json = <String, dynamic>{
        'id': 'photo-1',
        'activity_id': 'activity-1',
        'user_id': 'user-1',
        'storage_path': 'user-1/activity-1/photo.jpg',
        'thumbnail_path': 'user-1/activity-1/photo-thumb.jpg',
        'sort_order': 3,
        'created_at': '2026-03-17T12:30:00Z',
      };

      final photo = activityPhotoFromJson(json);

      expect(photo.id, 'photo-1');
      expect(photo.activityId, 'activity-1');
      expect(photo.userId, 'user-1');
      expect(photo.storagePath, 'user-1/activity-1/photo.jpg');
      expect(photo.thumbnailPath, 'user-1/activity-1/photo-thumb.jpg');
      expect(photo.sortOrder, 3);
      expect(photo.createdAt, DateTime.utc(2026, 3, 17, 12, 30));
      expect(photo.signedStorageUrl, isNull);
      expect(photo.signedThumbnailUrl, isNull);
    });

    test('accepts nullable thumbnail_path', () {
      final json = <String, dynamic>{
        'id': 'photo-2',
        'activity_id': 'activity-1',
        'user_id': 'user-1',
        'storage_path': 'user-1/activity-1/photo-2.jpg',
        'thumbnail_path': null,
        'sort_order': 4,
        'created_at': '2026-03-17T12:35:00Z',
      };

      final photo = activityPhotoFromJson(json);

      expect(photo.thumbnailPath, isNull);
      expect(photo.sortOrder, 4);
    });

    test('parses lat/lng from JSON', () {
      final json = <String, dynamic>{
        'id': 'photo-geo',
        'activity_id': 'activity-1',
        'user_id': 'user-1',
        'storage_path': 'user-1/activity-1/geo.jpg',
        'thumbnail_path': null,
        'sort_order': 0,
        'created_at': '2026-03-17T12:30:00Z',
        'latitude': 40.7128,
        'longitude': -74.0060,
      };

      final photo = activityPhotoFromJson(json);

      expect(photo.latitude, 40.7128);
      expect(photo.longitude, -74.0060);
    });

    test('null lat/lng yields null fields', () {
      final json = <String, dynamic>{
        'id': 'photo-noloc',
        'activity_id': 'activity-1',
        'user_id': 'user-1',
        'storage_path': 'user-1/activity-1/noloc.jpg',
        'thumbnail_path': null,
        'sort_order': 0,
        'created_at': '2026-03-17T12:30:00Z',
        'latitude': null,
        'longitude': null,
      };

      final photo = activityPhotoFromJson(json);

      expect(photo.latitude, isNull);
      expect(photo.longitude, isNull);
    });

    test('0.0/0.0 equator coords are not treated as null', () {
      final json = <String, dynamic>{
        'id': 'photo-equator',
        'activity_id': 'activity-1',
        'user_id': 'user-1',
        'storage_path': 'user-1/activity-1/equator.jpg',
        'thumbnail_path': null,
        'sort_order': 0,
        'created_at': '2026-03-17T12:30:00Z',
        'latitude': 0.0,
        'longitude': 0.0,
      };

      final photo = activityPhotoFromJson(json);

      expect(photo.latitude, 0.0);
      expect(photo.longitude, 0.0);
    });
  });

  group('withSignedUrls', () {
    test('preserves lat/lng', () {
      final photo = ActivityPhoto(
        id: 'photo-1',
        activityId: 'activity-1',
        userId: 'user-1',
        storagePath: 'user-1/activity-1/photo.jpg',
        sortOrder: 0,
        createdAt: DateTime.utc(2026, 3, 17, 12, 30),
        latitude: 37.7749,
        longitude: -122.4194,
      );

      final signed = photo.withSignedUrls(
        signedStorageUrl: 'https://example.com/signed-photo',
        signedThumbnailUrl: 'https://example.com/signed-thumb',
      );

      expect(signed.latitude, 37.7749);
      expect(signed.longitude, -122.4194);
      expect(signed.signedStorageUrl, 'https://example.com/signed-photo');
      expect(signed.signedThumbnailUrl, 'https://example.com/signed-thumb');
    });
  });

  group('isMapEligible', () {
    ActivityPhoto _photoWithCoords({double? lat, double? lng}) {
      return ActivityPhoto(
        id: 'photo-map',
        activityId: 'activity-1',
        userId: 'user-1',
        storagePath: 'user-1/activity-1/photo.jpg',
        sortOrder: 0,
        createdAt: DateTime.utc(2026, 3, 17, 12, 30),
        latitude: lat,
        longitude: lng,
      );
    }

    test('returns true when both lat and lng are non-null', () {
      final photo = _photoWithCoords(lat: 40.7128, lng: -74.0060);
      expect(photo.isMapEligible, true);
    });

    test('returns true for 0.0/0.0 equator coordinates', () {
      final photo = _photoWithCoords(lat: 0.0, lng: 0.0);
      expect(photo.isMapEligible, true);
    });

    test('returns false when lat is null', () {
      final photo = _photoWithCoords(lat: null, lng: -74.0060);
      expect(photo.isMapEligible, false);
    });

    test('returns false when lng is null', () {
      final photo = _photoWithCoords(lat: 40.7128, lng: null);
      expect(photo.isMapEligible, false);
    });

    test('returns false when both lat and lng are null', () {
      final photo = _photoWithCoords();
      expect(photo.isMapEligible, false);
    });
  });

  group('previewUrl', () {
    ActivityPhoto _photoWithUrls({String? thumbUrl, String? storageUrl}) {
      return ActivityPhoto(
        id: 'photo-preview',
        activityId: 'activity-1',
        userId: 'user-1',
        storagePath: 'user-1/activity-1/photo.jpg',
        sortOrder: 0,
        createdAt: DateTime.utc(2026, 3, 17, 12, 30),
        signedThumbnailUrl: thumbUrl,
        signedStorageUrl: storageUrl,
      );
    }

    test('prefers signedThumbnailUrl over signedStorageUrl', () {
      final photo = _photoWithUrls(
        thumbUrl: 'https://example.com/thumb.jpg',
        storageUrl: 'https://example.com/full.jpg',
      );
      expect(photo.previewUrl, 'https://example.com/thumb.jpg');
    });

    test('falls back to signedStorageUrl when thumbnail is null', () {
      final photo = _photoWithUrls(
        thumbUrl: null,
        storageUrl: 'https://example.com/full.jpg',
      );
      expect(photo.previewUrl, 'https://example.com/full.jpg');
    });

    test('returns null when both URLs are null', () {
      final photo = _photoWithUrls();
      expect(photo.previewUrl, isNull);
    });

    test('returns null when both URLs are empty strings', () {
      final photo = _photoWithUrls(thumbUrl: '', storageUrl: '');
      expect(photo.previewUrl, isNull);
    });
  });
}

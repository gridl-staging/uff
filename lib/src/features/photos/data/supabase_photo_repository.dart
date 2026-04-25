import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/utils/uuid.dart'
    show generateUuidV4; // 2026-03-18 merge: moved out of sync_service.dart
import 'package:uff/src/features/photos/data/photo_repository.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';

typedef PhotoBytesCompressor = Future<Uint8List> Function(Uint8List bytes);
typedef ThumbnailBytesCreator = Future<Uint8List?> Function(Uint8List bytes);
typedef UserIdProvider = String? Function();
const _activityPhotosPerActivityLimitToken =
    'UFF_LIMIT_ACTIVITY_PHOTOS_PER_ACTIVITY';

class ActivityPhotoLimitExceededException implements Exception {
  const ActivityPhotoLimitExceededException();

  @override
  String toString() {
    return 'ActivityPhotoLimitExceededException';
  }
}

/// TODO: Document SupabasePhotoRepository.
class SupabasePhotoRepository implements PhotoRepository {
  SupabasePhotoRepository(
    this._client, {
    UserIdProvider? currentUserIdProvider,
    String Function()? uuidGenerator,
    PhotoBytesCompressor? compressPhotoBytes,
    ThumbnailBytesCreator? createThumbnailBytes,
    int signedUrlLifetimeSeconds = 3600,
  }) : _currentUserIdProvider =
           currentUserIdProvider ?? (() => _client.auth.currentUser?.id),
       _uuidGenerator = uuidGenerator ?? generateUuidV4,
       _compressPhotoBytes = compressPhotoBytes ?? _defaultCompressPhotoBytes,
       _createThumbnailBytes =
           createThumbnailBytes ?? _defaultCreateThumbnailBytes,
       _signedUrlLifetimeSeconds = signedUrlLifetimeSeconds;

  final SupabaseClient _client;
  final UserIdProvider _currentUserIdProvider;
  final String Function() _uuidGenerator;
  final PhotoBytesCompressor _compressPhotoBytes;
  final ThumbnailBytesCreator _createThumbnailBytes;
  final int _signedUrlLifetimeSeconds;

  static const _photoBucketName = 'activity-photos';
  static final _fileSeparatorPattern = RegExp(r'[\\/]');
  static final _extensionSanitizer = RegExp('[^A-Za-z0-9]');

  @override
  Future<List<ActivityPhoto>> loadActivityPhotos(String activityId) async {
    final rows = await _client
        .from('activity_photos')
        .select()
        .eq('activity_id', activityId)
        .order('sort_order', ascending: true);

    final photos = rows.map(activityPhotoFromJson).toList(growable: false);
    final signedPhotos = <ActivityPhoto>[];
    for (final photo in photos) {
      signedPhotos.add(await _withSignedUrlsOrOriginal(photo));
    }
    return signedPhotos;
  }

  @override
  Future<ActivityPhoto> uploadPhoto({
    required String activityId,
    required Uint8List bytes,
    required String fileName,
    required int sortOrder,
    double? latitude,
    double? longitude,
  }) async {
    final userId = _requireCurrentUserId('upload');
    await _ensureActivityOwnedByCurrentUser(
      activityId: activityId,
      currentUserId: userId,
    );

    final extension = _normalizedFileExtension(fileName);
    final photoId = _uuidGenerator();
    final storagePath = '$userId/$activityId/$photoId$extension';
    final thumbnailPath = '$userId/$activityId/${photoId}_thumb$extension';

    final compressedPhotoBytes = await _compressPhotoBytesSafely(bytes);
    final thumbnailBytes = await _createThumbnailBytesSafely(
      compressedPhotoBytes,
    );

    final storageBucketApi = _client.storage.from(_photoBucketName);
    final uploadedPaths = <String>[storagePath];
    String? storedThumbnailPath;
    late ActivityPhoto photo;
    try {
      await storageBucketApi.uploadBinary(
        storagePath,
        compressedPhotoBytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );

      if (thumbnailBytes != null) {
        uploadedPaths.add(thumbnailPath);
        await storageBucketApi.uploadBinary(
          thumbnailPath,
          thumbnailBytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
        storedThumbnailPath = thumbnailPath;
      }

      final insertedRow = await _client
          .from('activity_photos')
          .insert({
            'activity_id': activityId,
            'user_id': userId,
            'storage_path': storagePath,
            'thumbnail_path': storedThumbnailPath,
            'sort_order': sortOrder,
            'latitude': latitude,
            'longitude': longitude,
          })
          .select()
          .single();

      photo = activityPhotoFromJson(insertedRow);
    } on Object catch (error, stackTrace) {
      final normalizedError = _normalizeUploadFailure(error);
      try {
        await storageBucketApi.remove(uploadedPaths);
      } on Object {
        // Keep the original upload failure as the surfaced error.
      }
      Error.throwWithStackTrace(normalizedError, stackTrace);
    }

    return _withSignedUrlsOrOriginal(photo);
  }

  Future<void> _ensureActivityOwnedByCurrentUser({
    required String activityId,
    required String currentUserId,
  }) async {
    final row = await _client
        .from('activities')
        .select('id,user_id')
        .eq('id', activityId)
        .single();
    if (row['user_id'] != currentUserId) {
      throw StateError(
        'Cannot upload activity photos for an activity owned by another user.',
      );
    }
  }

  Future<Uint8List> _compressPhotoBytesSafely(Uint8List bytes) async {
    try {
      final compressedBytes = await _compressPhotoBytes(bytes);
      if (compressedBytes.isEmpty) {
        return bytes;
      }
      return compressedBytes;
    } on Object {
      return bytes;
    }
  }

  Future<Uint8List?> _createThumbnailBytesSafely(Uint8List bytes) async {
    try {
      final thumbnailBytes = await _createThumbnailBytes(bytes);
      if (thumbnailBytes == null || thumbnailBytes.isEmpty) {
        return null;
      }
      return thumbnailBytes;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> deletePhoto(ActivityPhoto photo) async {
    final currentUserId = _requireCurrentUserId('delete');

    final persistedPhoto = await _loadOwnedPhoto(
      photoId: photo.id,
      currentUserId: currentUserId,
    );
    final storageBucketApi = _client.storage.from(_photoBucketName);
    final paths = <String>{persistedPhoto.storagePath};
    final thumbnailPath = persistedPhoto.thumbnailPath;
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      paths.add(thumbnailPath);
    }

    await storageBucketApi.remove(paths.toList(growable: false));
    await _client.from('activity_photos').delete().eq('id', persistedPhoto.id);
  }

  Future<ActivityPhoto> _withSignedUrls(ActivityPhoto photo) async {
    final signedStorageUrl = await _createSignedUrl(photo.storagePath);
    final thumbnailPath = photo.thumbnailPath;
    final signedThumbnailUrl =
        thumbnailPath == null ||
            thumbnailPath.isEmpty ||
            thumbnailPath == photo.storagePath
        ? signedStorageUrl
        : await _createSignedUrl(thumbnailPath);

    return photo.withSignedUrls(
      signedStorageUrl: signedStorageUrl,
      signedThumbnailUrl: signedThumbnailUrl,
    );
  }

  Future<ActivityPhoto> _withSignedUrlsOrOriginal(ActivityPhoto photo) async {
    try {
      return await _withSignedUrls(photo);
    } on Object {
      // Upload succeeded; let list reloads retry signed URL generation later.
      return photo;
    }
  }

  Future<String> _createSignedUrl(String storagePath) {
    return _client.storage
        .from(_photoBucketName)
        .createSignedUrl(storagePath, _signedUrlLifetimeSeconds);
  }

  Future<ActivityPhoto> _loadOwnedPhoto({
    required String photoId,
    required String currentUserId,
  }) async {
    final row = await _client
        .from('activity_photos')
        .select()
        .eq('id', photoId)
        .single();
    final persistedPhoto = activityPhotoFromJson(row);
    if (persistedPhoto.userId != currentUserId) {
      throw StateError(
        'Cannot delete activity photos owned by another user.',
      );
    }
    return persistedPhoto;
  }

  String _normalizedFileExtension(String fileName) {
    final baseName = fileName.split(_fileSeparatorPattern).last;
    final separatorIndex = baseName.lastIndexOf('.');
    if (separatorIndex == -1 || separatorIndex == baseName.length - 1) {
      return '.jpg';
    }

    final rawExtension = baseName.substring(separatorIndex + 1).toLowerCase();
    final sanitizedExtension = rawExtension.replaceAll(_extensionSanitizer, '');
    if (sanitizedExtension.isEmpty) {
      return '.jpg';
    }

    return '.$sanitizedExtension';
  }

  Object _normalizeUploadFailure(Object error) {
    if (error.toString().contains(_activityPhotosPerActivityLimitToken)) {
      return const ActivityPhotoLimitExceededException();
    }
    return error;
  }

  String _requireCurrentUserId(String action) {
    final userId = _currentUserIdProvider();
    if (userId != null) {
      return userId;
    }
    throw StateError(
      'Cannot $action activity photos without an authenticated user.',
    );
  }

  static Future<Uint8List> _defaultCompressPhotoBytes(Uint8List bytes) async {
    try {
      return await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 2048,
        minHeight: 2048,
        quality: 85,
      );
    } on Object {
      return bytes;
    }
  }

  static Future<Uint8List?> _defaultCreateThumbnailBytes(
    Uint8List bytes,
  ) async {
    try {
      return FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 720,
        minHeight: 720,
        quality: 70,
      );
    } on Object {
      return null;
    }
  }
}

/// Deserializes a Supabase activity_photos row into an [ActivityPhoto].
ActivityPhoto activityPhotoFromJson(Map<String, dynamic> json) {
  return ActivityPhoto(
    id: json['id'] as String,
    activityId: json['activity_id'] as String,
    userId: json['user_id'] as String,
    storagePath: json['storage_path'] as String,
    thumbnailPath: json['thumbnail_path'] as String?,
    sortOrder: (json['sort_order'] as num).toInt(),
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
  );
}

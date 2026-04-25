import 'package:meta/meta.dart';

/// TODO: Document ActivityPhoto.
@immutable
class ActivityPhoto {
  const ActivityPhoto({
    required this.id,
    required this.activityId,
    required this.userId,
    required this.storagePath,
    required this.sortOrder,
    required this.createdAt,
    this.thumbnailPath,
    this.signedStorageUrl,
    this.signedThumbnailUrl,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String activityId;
  final String userId;
  final String storagePath;
  final String? thumbnailPath;
  final int sortOrder;
  final DateTime createdAt;
  final String? signedStorageUrl;
  final String? signedThumbnailUrl;

  /// GPS latitude where the photo was captured. Null for gallery imports
  /// or when location was unavailable. Note: 0.0 is valid (equator).
  final double? latitude;

  /// GPS longitude where the photo was captured. Null for gallery imports
  /// or when location was unavailable. Note: 0.0 is valid (prime meridian).
  final double? longitude;

  /// Whether this photo has valid GPS coordinates for map marker placement.
  /// Both latitude and longitude must be non-null. 0.0 is valid (equator/prime meridian).
  bool get isMapEligible => latitude != null && longitude != null;

  /// Best available preview URL for thumbnail display. Prefers the smaller
  /// signed thumbnail over the full-size signed storage URL. Returns null
  /// when neither URL is available or both are empty.
  String? get previewUrl {
    if (signedThumbnailUrl != null && signedThumbnailUrl!.isNotEmpty) {
      return signedThumbnailUrl;
    }
    if (signedStorageUrl != null && signedStorageUrl!.isNotEmpty) {
      return signedStorageUrl;
    }
    return null;
  }

  ActivityPhoto withSignedUrls({
    required String signedStorageUrl,
    required String signedThumbnailUrl,
  }) {
    return ActivityPhoto(
      id: id,
      activityId: activityId,
      userId: userId,
      storagePath: storagePath,
      thumbnailPath: thumbnailPath,
      sortOrder: sortOrder,
      createdAt: createdAt,
      signedStorageUrl: signedStorageUrl,
      signedThumbnailUrl: signedThumbnailUrl,
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityPhoto &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          activityId == other.activityId &&
          userId == other.userId &&
          storagePath == other.storagePath &&
          thumbnailPath == other.thumbnailPath &&
          sortOrder == other.sortOrder &&
          createdAt == other.createdAt &&
          signedStorageUrl == other.signedStorageUrl &&
          signedThumbnailUrl == other.signedThumbnailUrl &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => Object.hash(
    id,
    activityId,
    userId,
    storagePath,
    thumbnailPath,
    sortOrder,
    createdAt,
    signedStorageUrl,
    signedThumbnailUrl,
    latitude,
    longitude,
  );
}

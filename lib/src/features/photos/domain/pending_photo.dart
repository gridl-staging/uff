import 'package:meta/meta.dart';

/// TODO: Document PendingPhoto.
@immutable
class PendingPhoto {
  const PendingPhoto({
    required this.id,
    required this.sessionId,
    required this.localPath,
    required this.capturedAt,
    this.latitude,
    this.longitude,
  });

  /// Auto-incremented primary key from the local Drift database.
  final int id;

  /// The local tracking session ID this photo belongs to. Used to associate
  /// the photo with the correct activity for post-sync upload.
  final int sessionId;

  /// Absolute path to the compressed photo file in the app's documents
  /// directory. Cleaned up after successful upload or activity discard.
  final String localPath;

  /// When the photo was captured. Used for ordering photos within an
  /// activity (earlier photos get lower sort order on upload).
  final DateTime capturedAt;

  /// GPS latitude where the photo was captured. Null for gallery imports
  /// or when location was unavailable. Note: 0.0 is valid (equator).
  final double? latitude;

  /// GPS longitude where the photo was captured. Null for gallery imports
  /// or when location was unavailable. Note: 0.0 is valid (prime meridian).
  final double? longitude;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingPhoto &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          sessionId == other.sessionId &&
          localPath == other.localPath &&
          capturedAt == other.capturedAt &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode =>
      Object.hash(id, sessionId, localPath, capturedAt, latitude, longitude);

  @override
  String toString() =>
      'PendingPhoto(id: $id, sessionId: $sessionId, localPath: $localPath, '
      'capturedAt: $capturedAt, latitude: $latitude, longitude: $longitude)';
}

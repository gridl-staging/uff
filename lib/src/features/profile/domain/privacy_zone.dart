import 'package:meta/meta.dart';

/// NOTE(stuart): Document PrivacyZone.
@immutable
class PrivacyZone {
  const PrivacyZone({
    required this.id,
    required this.userId,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  factory PrivacyZone.fromJson(Map<String, dynamic> json) {
    return PrivacyZone(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      label: json['label'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: json['radius_meters'] as int,
    );
  }

  final String id;
  final String userId;
  final String label;
  final double latitude;
  final double longitude;
  final int radiusMeters;
}

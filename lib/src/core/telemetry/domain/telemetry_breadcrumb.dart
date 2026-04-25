typedef JsonMap = Map<String, Object?>;

/// Immutable telemetry breadcrumb payload.
class TelemetryBreadcrumb {
  TelemetryBreadcrumb({
    required this.message,
    required this.capturedAt,
    required JsonMap metadata,
  }) : metadata = Map<String, Object?>.unmodifiable(
         Map<String, Object?>.from(metadata),
       );

  final String message;
  final DateTime capturedAt;
  final JsonMap metadata;

  JsonMap toJson() {
    return <String, Object?>{
      'message': message,
      'capturedAt': capturedAt.toUtc().toIso8601String(),
      'metadata': Map<String, Object?>.from(metadata),
    };
  }
}

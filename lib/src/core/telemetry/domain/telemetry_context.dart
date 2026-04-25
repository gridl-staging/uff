typedef JsonMap = Map<String, Object?>;

/// Immutable app context envelope attached to telemetry events.
class TelemetryContextEnvelope {
  const TelemetryContextEnvelope({
    required this.appVersion,
    required this.buildNumber,
    required this.platform,
  });

  final String appVersion;
  final String buildNumber;
  final String platform;

  JsonMap toJson() {
    return <String, Object?>{
      'appVersion': appVersion,
      'buildNumber': buildNumber,
      'platform': platform,
    };
  }
}

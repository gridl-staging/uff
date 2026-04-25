typedef JsonMap = Map<String, Object?>;

// ignore: one_member_abstracts, reason: Upload seam is intentionally minimal.
abstract class TelemetryUploader {
  Future<bool> upload(JsonMap row);
}

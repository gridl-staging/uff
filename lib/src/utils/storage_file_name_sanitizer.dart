final _pathSegmentPattern = RegExp('[^A-Za-z0-9._-]');
final _fileSeparatorPattern = RegExp(r'[\\/]');
final _leadingDotsPattern = RegExp(r'^\.+');

String sanitizeStorageFileName(
  String fileName, {
  required String fallbackName,
}) {
  final baseName = fileName.split(_fileSeparatorPattern).last;
  final sanitized = baseName.replaceAll(_pathSegmentPattern, '_');
  final withoutLeadingDots = sanitized.replaceFirst(_leadingDotsPattern, '');
  if (withoutLeadingDots.isNotEmpty) {
    return withoutLeadingDots;
  }
  return fallbackName;
}

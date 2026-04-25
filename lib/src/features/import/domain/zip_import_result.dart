import 'package:meta/meta.dart';

/// Aggregated result of importing a Strava ZIP export file.
///
/// Each activity file (.fit, .gpx, .fit.gz) in the ZIP is processed
/// independently — individual failures do not abort the batch.
@immutable
class ZipImportResult {
  const ZipImportResult({
    required this.successCount,
    required this.failureCount,
    required this.importedSessionIds,
    required this.errors,
  });

  /// Number of activity files that were successfully imported.
  final int successCount;

  /// Number of activity files that failed to import.
  final int failureCount;

  /// Local session IDs for each successfully imported activity.
  final List<int> importedSessionIds;

  /// Human-readable descriptions of each failure (e.g. "morning_run.fit: Invalid FIT header").
  final List<String> errors;
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:uff/src/core/telemetry/telemetry_enablement.dart';
import 'package:uff/src/features/import/application/import_pipeline.dart';
import 'package:uff/src/features/import/domain/zip_import_result.dart';
import 'package:uff/src/utils/app_logger.dart';

// TODO(uff): Document StravaZipImporter.
/// TODO: Document StravaZipImporter.
class StravaZipImporter {
  StravaZipImporter({
    required ImportPipeline pipeline,
    AppLogger? logger,
    TelemetryBreadcrumbRecorder? breadcrumbRecorder,
  }) : _pipeline = pipeline,
       _logger = logger ?? AppLogger(),
       _breadcrumbRecorder =
           breadcrumbRecorder ?? noopTelemetryBreadcrumbRecorder;

  final ImportPipeline _pipeline;
  final AppLogger _logger;
  final TelemetryBreadcrumbRecorder _breadcrumbRecorder;

  static const _activityExtensions = {'.fit', '.gpx', '.fit.gz'};
  static const _errorPrefixes = [
    'Exception: ',
    'Bad state: ',
    'Invalid argument(s): ',
  ];
  static const _endOfCentralDirectorySignature = [
    0x50,
    0x4B,
    0x05,
    0x06,
  ];

  /// Import all activity files from a Strava ZIP export.
  ///
  /// Returns a [ZipImportResult] summarizing successes and failures.
  /// If [onProgress] is provided, it is called with `(0, totalActivityFiles)`
  /// before the first file attempt and again after each file attempt.
  Future<ZipImportResult> importZip(
    Uint8List zipBytes, {
    void Function(int current, int total)? onProgress,
  }) async {
    recordBoundaryTelemetryBreadcrumb(
      _breadcrumbRecorder,
      boundary: 'strava_zip_importer',
      operation: 'import_zip',
      message: 'import.zip.import',
    );
    final batchStartedAt = DateTime.now();
    try {
      final archive = _decodeArchive(zipBytes);
      final activityFiles = _activityFilesFrom(archive);
      final totalFiles = activityFiles.length;
      _logger.logEvent(
        eventType: 'import.zip.batch',
        outcome: 'start',
        identifiers: {'total_files': totalFiles},
      );
      if (totalFiles > 0) {
        onProgress?.call(0, totalFiles);
      }

      final importedSessionIds = <int>[];
      final errors = <String>[];
      var processed = 0;

      for (final file in activityFiles) {
        final filename = _basename(file.name);
        final fileType = _fileTypeForLog(filename);
        try {
          final sessionId = await _logger.runWithTiming<int>(
            eventType: 'import.zip.file',
            successOutcome: 'success',
            failureOutcome: 'failure',
            identifiers: {
              'file_type': fileType,
              'file_index': processed + 1,
            },
            successIdentifiers: (value) => {'session_id': value},
            operation: () async {
              final bytes = _prepareBytes(file);
              final strippedName = _stripGzSuffix(filename);
              return _pipeline.run(bytes, strippedName);
            },
          );
          importedSessionIds.add(sessionId);
        } on Object catch (e) {
          errors.add('$filename: ${_errorMessage(e)}');
        }
        processed++;
        onProgress?.call(processed, totalFiles);
      }

      final result = ZipImportResult(
        successCount: importedSessionIds.length,
        failureCount: errors.length,
        importedSessionIds: importedSessionIds,
        errors: errors,
      );
      _logger.logEvent(
        eventType: 'import.zip.batch',
        outcome: 'complete',
        duration: DateTime.now().difference(batchStartedAt),
        identifiers: {
          'total_files': result.successCount + result.failureCount,
          'success_count': result.successCount,
          'failure_count': result.failureCount,
        },
      );
      return result;
    } on Object catch (error) {
      _logger.logEvent(
        eventType: 'import.zip.batch',
        outcome: 'failure',
        duration: DateTime.now().difference(batchStartedAt),
        identifiers: {'reason': _batchFailureReason(error)},
      );
      rethrow;
    }
  }

  List<ArchiveFile> _activityFilesFrom(Archive archive) {
    return archive.files
        .where((file) => file.isFile && _isActivityFile(file.name))
        .toList();
  }

  Archive _decodeArchive(Uint8List zipBytes) {
    if (!_hasEndOfCentralDirectorySignature(zipBytes)) {
      throw const FormatException('Invalid ZIP archive');
    }

    try {
      return ZipDecoder().decodeBytes(zipBytes);
    } on Object {
      throw const FormatException('Invalid ZIP archive');
    }
  }

  bool _hasEndOfCentralDirectorySignature(Uint8List zipBytes) {
    if (zipBytes.length < _endOfCentralDirectorySignature.length) {
      return false;
    }

    // ZIP comments can push the EOCD record away from the final bytes, but it
    // is still constrained to the tail of the archive.
    final searchStart = math.max(0, zipBytes.length - 65557);
    for (
      var index = zipBytes.length - _endOfCentralDirectorySignature.length;
      index >= searchStart;
      index--
    ) {
      if (_matchesSignatureAt(zipBytes, index)) {
        return true;
      }
    }
    return false;
  }

  bool _matchesSignatureAt(Uint8List zipBytes, int index) {
    for (
      var offset = 0;
      offset < _endOfCentralDirectorySignature.length;
      offset++
    ) {
      if (zipBytes[index + offset] != _endOfCentralDirectorySignature[offset]) {
        return false;
      }
    }
    return true;
  }

  bool _isActivityFile(String name) {
    final lower = name.toLowerCase();
    return _activityExtensions.any(lower.endsWith);
  }

  Uint8List _prepareBytes(ArchiveFile file) {
    final content = file.content;
    if (file.name.toLowerCase().endsWith('.fit.gz')) {
      return const GZipDecoder().decodeBytes(content);
    }
    return Uint8List.fromList(content);
  }

  String _stripGzSuffix(String filename) {
    if (filename.toLowerCase().endsWith('.fit.gz')) {
      return filename.substring(0, filename.length - 3);
    }
    return filename;
  }

  String _errorMessage(Object error) {
    final description = error.toString();
    final runtimeTypePrefix = '${error.runtimeType}: ';
    if (description.startsWith(runtimeTypePrefix)) {
      return description.substring(runtimeTypePrefix.length);
    }

    for (final prefix in _errorPrefixes) {
      if (description.startsWith(prefix)) {
        return description.substring(prefix.length);
      }
    }

    return description;
  }

  String _fileTypeForLog(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.fit.gz') || lower.endsWith('.fit')) {
      return 'fit';
    }
    if (lower.endsWith('.gpx')) {
      return 'gpx';
    }
    return 'unknown';
  }

  String _batchFailureReason(Object error) {
    if (error is FormatException) {
      return 'invalid_zip';
    }
    return 'unknown';
  }

  String _basename(String path) => path.split('/').last;
}

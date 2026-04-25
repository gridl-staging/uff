import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:uff/src/core/telemetry/telemetry_enablement.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_repository.dart';
import 'package:uff/src/features/import/data/fit_importer.dart';
import 'package:uff/src/features/import/data/gpx_importer.dart';
import 'package:uff/src/features/import/domain/import_normalizer.dart';
import 'package:uff/src/features/import/domain/imported_activity.dart';
import 'package:uff/src/utils/app_logger.dart';

// TODO(uff): Document ImportPipeline.
/// TODO: Document ImportPipeline.
class ImportPipeline {
  ImportPipeline({
    required TrackingRepository repository,
    required SyncService syncService,
    AppLogger? logger,
    TelemetryBreadcrumbRecorder? breadcrumbRecorder,
  }) : _repository = repository,
       _syncService = syncService,
       _logger = logger ?? AppLogger(),
       _breadcrumbRecorder =
           breadcrumbRecorder ?? noopTelemetryBreadcrumbRecorder;

  final TrackingRepository _repository;
  final SyncService _syncService;
  final AppLogger _logger;
  final TelemetryBreadcrumbRecorder _breadcrumbRecorder;

  /// Parses [bytes] as a FIT or GPX file (determined by [filename] extension),
  /// normalizes, persists to the local database, and queues for sync.
  ///
  /// Returns the local session ID.
  ///
  /// Throws [FormatException] if the file extension is not recognized or the
  /// file content is invalid.
  Future<int> run(Uint8List bytes, String filename) async {
    final fileType = _fileTypeForLogging(filename);
    recordBoundaryTelemetryBreadcrumb(
      _breadcrumbRecorder,
      boundary: 'import_pipeline',
      operation: 'run',
      message: 'import.pipeline.run',
      metadata: <String, Object?>{'file_type': fileType},
    );
    _logger.logEvent(
      eventType: 'import.pipeline.run',
      outcome: 'start',
      identifiers: {'file_type': fileType},
    );
    return _logger.runWithTiming(
      eventType: 'import.pipeline.run',
      successOutcome: 'success',
      failureOutcome: 'failure',
      identifiers: {'file_type': fileType},
      successIdentifiers: (sessionId) => {'session_id': sessionId},
      operation: () async {
        final parsed = _parse(bytes, filename);
        final normalized = normalizeImportedActivity(parsed);
        final session = _buildSession(normalized);
        final sessionId = await _repository.saveImportedSession(
          session,
          normalized.cleanedPoints,
        );
        await _syncService.queueForSync(sessionId);
        return sessionId;
      },
    );
  }

  ParsedActivityData _parse(Uint8List bytes, String filename) {
    final extension = _extractExtension(filename);
    _logger.logEvent(
      eventType: 'import.pipeline.parse',
      outcome: 'selected',
      identifiers: {'file_type': extension},
    );
    switch (extension) {
      case 'fit':
        return FitImporter.parse(bytes);
      case 'gpx':
        return GpxImporter.parse(utf8.decode(bytes));
      default:
        throw FormatException('Unrecognized file format: .$extension');
    }
  }

  String _fileTypeForLogging(String filename) {
    try {
      return _extractExtension(filename);
    } on FormatException {
      return 'unknown';
    }
  }

  String _extractExtension(String filename) {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == filename.length - 1) {
      throw const FormatException('Unrecognized file format');
    }
    return filename.substring(dotIndex + 1).toLowerCase();
  }

  TrackingSessionRecord _buildSession(ImportedActivity normalized) {
    return TrackingSessionRecord(
      id: 0,
      status: TrackingSessionStatus.saved,
      createdAt: normalized.startedAt,
      updatedAt: normalized.startedAt,
      startedAt: normalized.startedAt,
      stoppedAt: normalized.finishedAt,
      sportType: normalized.sportType,
      title: normalized.title,
      distanceMeters: normalized.metrics.trackSummary.distanceMeters,
      movingTimeSeconds: normalized.metrics.trackSummary.movingTime.inSeconds,
      elevationGainMeters: normalized.metrics.trackSummary.elevationGainMeters,
      // Imported activities have no UI step before sync, so default to private.
      // Without this, null visibility causes buildActivityPayload() to omit the
      // key and the backend applies DEFAULT 'public' — a P0 privacy leak.
      visibility: privateTrackingSessionVisibility,
    );
  }
}

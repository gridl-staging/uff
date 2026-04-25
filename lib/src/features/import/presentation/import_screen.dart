import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/core/telemetry/telemetry_enablement.dart';
import 'package:uff/src/core/presentation/copyable_error_text.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_routes.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/import/application/import_pipeline.dart';
import 'package:uff/src/features/import/data/strava_zip_importer.dart';
import 'package:uff/src/features/import/domain/zip_import_result.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';

final importPipelineProvider = Provider<ImportPipeline>((ref) {
  return ImportPipeline(
    repository: ref.read(trackingRepositoryProvider),
    syncService: ref.read(syncServiceProvider),
    breadcrumbRecorder: ref.read(telemetryBreadcrumbRecorderProvider),
  );
});

final stravaZipImporterProvider = Provider<StravaZipImporter>((ref) {
  return StravaZipImporter(
    pipeline: ref.read(importPipelineProvider),
    breadcrumbRecorder: ref.read(telemetryBreadcrumbRecorderProvider),
  );
});

enum ImportScreenStatus { idle, importing, success, error }

const _zipImportStartFeedbackDelay = Duration(milliseconds: 300);

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  static const backButtonKey = Key('import_back_button');
  static const pickFileButtonKey = Key('import_pick_file_button');
  static const successSummaryKey = Key('import_success_summary');
  static const zipSuccessSummaryKey = Key('import_zip_success_summary');
  static const errorMessageKey = Key('import_error_message');
  static const errorBackButtonKey = Key('import_error_back_button');

  @override
  ConsumerState<ImportScreen> createState() => ImportScreenState();
}

// TODO(stuart): Document ImportScreenState.
/// TODO: Document ImportScreenState.
@visibleForTesting
class ImportScreenState extends ConsumerState<ImportScreen> {
  ImportScreenStatus _status = ImportScreenStatus.idle;
  String? _errorMessage;
  _ImportResult? _result;
  _ZipImportProgress? _zipProgress;
  _ZipImportSummary? _zipSummary;
  bool _isZipImportInFlight = false;

  Future<void> _pickAndImport() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['fit', 'gpx', 'zip'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    await _importPickedFile(picked.files.single);
  }

  Future<void> _importPickedFile(PlatformFile file) async {
    final bytes = _validatePickedFileBytes(file);
    if (bytes == null) return;

    if (_isZipFilename(file.name)) {
      await _runZipImport(bytes, file.name);
      return;
    }

    await runImport(bytes, file.name);
  }

  Uint8List? _validatePickedFileBytes(PlatformFile file) {
    final bytes = file.bytes;
    if (bytes == null) {
      _showError('Unable to read the selected file. Please try another file.');
      return null;
    }
    return bytes;
  }

  bool _isZipFilename(String name) => name.toLowerCase().endsWith('.zip');

  Future<void> _runZipImport(Uint8List bytes, String filename) async {
    if (_status == ImportScreenStatus.importing) {
      return;
    }

    _showImportingState(isZipImportInFlight: true);

    // Keep the initial importing state visible long enough for the user to
    // register that the ZIP batch started before work begins.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await Future<void>.delayed(_zipImportStartFeedbackDelay);
    if (!mounted) return;

    try {
      final importer = ref.read(stravaZipImporterProvider);
      final zipResult = await importer.importZip(
        bytes,
        onProgress: (current, total) {
          if (!mounted) return;
          setState(() {
            _zipProgress = _ZipImportProgress(current: current, total: total);
          });
        },
      );

      if (!mounted) return;
      if (zipResult.successCount > 0) {
        ref.invalidate(savedActivitiesProvider);
      }

      if (_zipProgress != null) {
        await WidgetsBinding.instance.endOfFrame;
      }
      if (!mounted) return;

      _showSuccessState(
        zipSummary: _ZipImportSummary.fromResult(result: zipResult),
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      _showError(
        e.message.isEmpty ? 'Invalid ZIP archive: $filename' : e.message,
      );
    } on Object {
      if (!mounted) return;
      _showError('An error occurred during import. Please try again.');
    }
  }

  /// Parses and persists a file. Public for testability via [ImportScreenState].
  @visibleForTesting
  Future<void> runImport(Uint8List bytes, String filename) async {
    if (_status == ImportScreenStatus.importing) {
      return;
    }

    _showImportingState(isZipImportInFlight: false);

    try {
      final pipeline = ref.read(importPipelineProvider);
      final sessionId = await pipeline.run(bytes, filename);

      final repo = ref.read(trackingRepositoryProvider);
      final session = await repo.loadSession(sessionId);
      if (session == null) {
        throw const _ImportBoundaryException(
          'Imported activity could not be loaded.',
        );
      }

      if (!mounted) return;
      ref.invalidate(savedActivitiesProvider);
      _showSuccessState(
        result: _ImportResult(
          sessionId: sessionId,
          sportType: session.sportType,
          distanceMeters: session.distanceMeters,
          movingTimeSeconds: session.movingTimeSeconds,
        ),
      );
    } on _ImportBoundaryException catch (error) {
      if (!mounted) return;
      _showError(error.message);
    } on FormatException catch (e) {
      if (!mounted) return;
      _showError(
        e.message.contains('Unrecognized')
            ? e.message
            : 'Unrecognized file format',
      );
    } on Object {
      if (!mounted) return;
      _showError('An error occurred during import. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final canNavigatorPop = Navigator.of(context).canPop();
    final isImportInFlight = _status == ImportScreenStatus.importing;
    final shouldShowBackButton = canNavigatorPop && !isImportInFlight;

    return PopScope(
      canPop: !isImportInFlight,
      child: Scaffold(
        appBar: AppBar(
          leading: shouldShowBackButton
              ? const BackButton(key: ImportScreen.backButtonKey)
              : null,
          title: const Text('Import Activity'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case ImportScreenStatus.idle:
        return _buildPickerPrompt();
      case ImportScreenStatus.importing:
        return _buildImportingState();
      case ImportScreenStatus.success:
        if (_zipSummary != null) {
          return _buildZipSuccessSummary();
        }
        return _buildSuccessSummary();
      case ImportScreenStatus.error:
        return _buildErrorView();
    }
  }

  Widget _buildPickerPrompt() {
    return Center(
      child: ElevatedButton.icon(
        key: ImportScreen.pickFileButtonKey,
        onPressed: _pickAndImport,
        icon: const Icon(Icons.file_upload),
        label: const Text('Select FIT, GPX, or ZIP File'),
      ),
    );
  }

  Widget _buildImportingState() {
    final progress = _zipProgress;
    if (progress == null) {
      return _buildCenteredProgressIndicator(
        message: _isZipImportInFlight ? 'Importing activities...' : null,
      );
    }

    return _buildCenteredProgressIndicator(
      message:
          'Importing ${progress.current} of ${progress.total} activities...',
    );
  }

  Widget _buildSuccessSummary() {
    final result = _result!;
    final preferredUnits = ref
        .watch(profileProvider)
        .asData
        ?.value
        ?.preferredUnits;
    final distanceLabel = formatDistance(
      result.distanceMeters,
      preferredUnits: preferredUnits,
    );
    final durationLabel = _formatDurationLabel(result.movingTimeSeconds);
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        key: ImportScreen.successSummaryKey,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            size: 64,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 16),
          const Text(
            'Import Successful',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (result.sportType != null) Text('Sport: ${result.sportType}'),
          Text('Distance: $distanceLabel'),
          Text('Duration: $durationLabel'),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.push(
              ActivityRoutes.activityDetailPath(result.sessionId),
            ),
            child: const Text('View Activity'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _resetToIdle,
            child: const Text('Import Another'),
          ),
        ],
      ),
    );
  }

  Widget _buildZipSuccessSummary() {
    final summary = _zipSummary!;
    final visibleErrors = summary.errors.take(5).toList();
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = summary.failureCount == 0
        ? colorScheme.primary
        : colorScheme.tertiary;

    return Center(
      child: SingleChildScrollView(
        child: Column(
          key: ImportScreen.zipSuccessSummaryKey,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              summary.failureCount == 0
                  ? Icons.check_circle
                  : Icons.info_outline,
              size: 64,
              color: statusColor,
            ),
            const SizedBox(height: 16),
            const Text(
              'ZIP Import Complete',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(summary.primaryMessage),
            if (summary.failureCount > 0) ...[
              const SizedBox(height: 12),
              Text('Failed imports: ${summary.failureCount}'),
            ],
            if (visibleErrors.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Errors',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final error in visibleErrors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    error,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
            const SizedBox(height: 24),
            TextButton(
              onPressed: _resetToIdle,
              child: const Text('Import Another'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    final colorScheme = Theme.of(context).colorScheme;
    final canPop = Navigator.of(context).canPop();

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: colorScheme.error,
          ),
          const SizedBox(height: 16),
          CopyableErrorText(
            _errorMessage ?? 'An error occurred',
            key: ImportScreen.errorMessageKey,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _resetToIdle,
            child: const Text('Try Again'),
          ),
          if (canPop) ...[
            const SizedBox(height: 8),
            TextButton(
              key: ImportScreen.errorBackButtonKey,
              onPressed: () => context.pop(),
              child: const Text('Back'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCenteredProgressIndicator({required String? message}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message != null) ...[
            Text(message),
            const SizedBox(height: 12),
          ],
          const CircularProgressIndicator(),
        ],
      ),
    );
  }

  String _formatDurationLabel(int? movingTimeSeconds) {
    if (movingTimeSeconds == null) {
      return '--:--';
    }

    final duration = Duration(seconds: movingTimeSeconds);
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '${duration.inMinutes}:$seconds';
  }

  void _showImportingState({required bool isZipImportInFlight}) {
    setState(() {
      _status = ImportScreenStatus.importing;
      _errorMessage = null;
      _result = null;
      _zipProgress = null;
      _zipSummary = null;
      _isZipImportInFlight = isZipImportInFlight;
    });
  }

  void _showSuccessState({
    _ImportResult? result,
    _ZipImportSummary? zipSummary,
  }) {
    setState(() {
      _status = ImportScreenStatus.success;
      _errorMessage = null;
      _result = result;
      _zipProgress = null;
      _zipSummary = zipSummary;
      _isZipImportInFlight = false;
    });
  }

  void _resetToIdle() {
    setState(() {
      _status = ImportScreenStatus.idle;
      _errorMessage = null;
      _result = null;
      _zipProgress = null;
      _zipSummary = null;
      _isZipImportInFlight = false;
    });
  }

  void _showError(String message) {
    setState(() {
      _status = ImportScreenStatus.error;
      _errorMessage = message;
      _result = null;
      _zipProgress = null;
      _zipSummary = null;
      _isZipImportInFlight = false;
    });
  }
}

class _ImportBoundaryException implements Exception {
  const _ImportBoundaryException(this.message);

  final String message;
}

class _ImportResult {
  _ImportResult({
    required this.sessionId,
    this.sportType,
    this.distanceMeters,
    this.movingTimeSeconds,
  });

  final int sessionId;
  final String? sportType;
  final double? distanceMeters;
  final int? movingTimeSeconds;
}

class _ZipImportProgress {
  const _ZipImportProgress({required this.current, required this.total});

  final int current;
  final int total;
}

/// NOTE(stuart): Document _ZipImportSummary.
class _ZipImportSummary {
  const _ZipImportSummary({
    required this.primaryMessage,
    required this.failureCount,
    required this.errors,
  });

  factory _ZipImportSummary.fromResult({
    required ZipImportResult result,
  }) {
    final total = result.successCount + result.failureCount;
    if (total == 0) {
      return const _ZipImportSummary(
        primaryMessage: 'No supported activity files were found in this ZIP.',
        failureCount: 0,
        errors: [],
      );
    }

    return _ZipImportSummary(
      primaryMessage: 'Imported ${result.successCount} of $total activities.',
      failureCount: result.failureCount,
      errors: result.errors,
    );
  }

  final String primaryMessage;
  final int failureCount;
  final List<String> errors;
}

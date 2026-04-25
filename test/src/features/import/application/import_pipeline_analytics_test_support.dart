import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fit_tool/fit_tool.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart'
    as tracking_database;
import 'package:uff/src/features/activity_tracking/data/tracking_repository.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/analytics/application/analytics_providers.dart';
import 'package:uff/src/features/analytics/domain/fitness_profile.dart';
import 'package:uff/src/features/import/application/import_pipeline.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';

import '../data/fit_test_helpers.dart';

const double importAnalyticsFixedThresholdPaceSecsPerKm = 300;
const int importAnalyticsFixedFtpWatts = 250;

Profile buildImportAnalyticsTestProfile({int? lthrBpm}) {
  return Profile(
    userId: 'import-analytics-test-user',
    preferredUnits: 'metric',
    defaultActivityVisibility: 'public',
    onboardingCompleted: true,
    sportPreferences: const <String>['running'],
    lthrBpm: lthrBpm,
  );
}

/// Creates an isolated import pipeline with fixed profile inputs so analytics
/// assertions stay deterministic across tests.
class ImportPipelineAnalyticsHarness {
  ImportPipelineAnalyticsHarness._({
    required this.databaseDirectory,
    required this.database,
    required this.repository,
    required this.syncService,
    required this.container,
    required this.pipeline,
    required this.fixedFitnessProfile,
  });

  final Directory databaseDirectory;
  final tracking_database.TrackingDatabase database;
  final DriftTrackingRepository repository;
  final RecordingSyncService syncService;
  final ProviderContainer container;
  final ImportPipeline pipeline;
  final FitnessProfile fixedFitnessProfile;

  static Future<ImportPipelineAnalyticsHarness> create({
    Profile? profile,
    FitnessProfile? fitnessProfile,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'import_pipeline_analytics_',
    );
    final database = tracking_database.TrackingDatabase.forTesting(
      NativeDatabase(File('${directory.path}/analytics.sqlite')),
    );
    final repository = DriftTrackingRepository(database);
    final syncService = RecordingSyncService();
    final resolvedProfile = profile ?? buildImportAnalyticsTestProfile();
    final resolvedFitnessProfile =
        fitnessProfile ??
        FitnessProfile(
          thresholdPaceSecsPerKm: importAnalyticsFixedThresholdPaceSecsPerKm,
          lthr: resolvedProfile.lthrBpm,
          ftpWatts: importAnalyticsFixedFtpWatts,
        );

    final container = ProviderContainer(
      overrides: [
        trackingRepositoryProvider.overrideWithValue(repository),
        profileProvider.overrideWith(
          () => _FixedProfileNotifier(resolvedProfile),
        ),
        fitnessProfileProvider.overrideWith(
          (ref) async => resolvedFitnessProfile,
        ),
      ],
    );
    final pipeline = ImportPipeline(
      repository: repository,
      syncService: syncService,
    );

    return ImportPipelineAnalyticsHarness._(
      databaseDirectory: directory,
      database: database,
      repository: repository,
      syncService: syncService,
      container: container,
      pipeline: pipeline,
      fixedFitnessProfile: resolvedFitnessProfile,
    );
  }

  Future<int> importFit({
    required List<FitTestRecord> records,
    Sport sport = Sport.running,
    String filename = 'activity.fit',
  }) {
    final fitBytes = buildFitBytes(records: records, sport: sport);
    return pipeline.run(fitBytes, filename);
  }

  Future<TrackingSessionRecord> loadSessionOrThrow(int sessionId) async {
    final session = await repository.loadSession(sessionId);
    if (session == null) {
      throw StateError('Expected imported session $sessionId to exist');
    }
    return session;
  }

  Future<List<TrackingPoint>> loadPoints(int sessionId) {
    return repository.loadPointsForSession(sessionId);
  }

  Future<void> dispose() async {
    container.dispose();
    await syncService.dispose();
    await database.close();
    if (databaseDirectory.existsSync()) {
      databaseDirectory.deleteSync(recursive: true);
    }
  }
}

/// Test sync service that records queue/delete calls for assertions.
class RecordingSyncService implements SyncService {
  final List<int> queuedSessionIds = <int>[];
  final List<String> deletedRemoteActivityIds = <String>[];
  final StreamController<SyncQueueStatus> _syncStatusController =
      StreamController<SyncQueueStatus>.broadcast();

  @override
  Stream<SyncQueueStatus> get syncStatus => _syncStatusController.stream;

  @override
  Future<void> queueForSync(int sessionId) async {
    queuedSessionIds.add(sessionId);
    _syncStatusController.add(SyncQueueStatus.queued);
  }

  @override
  Future<void> processQueue() async {}

  @override
  Future<void> deleteRemoteActivity(String remoteActivityId) async {
    deletedRemoteActivityIds.add(remoteActivityId);
  }

  Future<void> dispose() => _syncStatusController.close();
}

class _FixedProfileNotifier extends ProfileNotifier {
  _FixedProfileNotifier(this._profile);

  final Profile? _profile;

  @override
  FutureOr<Profile?> build() {
    return _profile;
  }
}

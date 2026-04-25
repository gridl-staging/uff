import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uff/src/features/activity_tracking/data/activity_gear_assignment_repository.dart';
import 'package:uff/src/features/activity_tracking/data/permission_service.dart';
import 'package:uff/src/features/activity_tracking/data/tracelet_tracking_engine.dart';
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart'
    as tracking_database;
import 'package:uff/src/features/activity_tracking/data/tracking_repository.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_engine.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_repository.dart';

final Provider<tracking_database.TrackingDatabase> trackingDatabaseProvider =
    Provider<tracking_database.TrackingDatabase>(
      (ref) => tracking_database.TrackingDatabase(),
    );

final Provider<TrackingRepository> trackingRepositoryProvider =
    Provider<TrackingRepository>(
      (ref) => DriftTrackingRepository(ref.read(trackingDatabaseProvider)),
    );

final Provider<ActivityGearAssignmentRepository>
activityGearAssignmentRepositoryProvider =
    Provider<ActivityGearAssignmentRepository>(
      (ref) =>
          SupabaseActivityGearAssignmentRepository(Supabase.instance.client),
    );

/// Callback that clears all user-scoped rows from the local Drift database.
///
/// Called by the auth provider on sign-out to prevent data leakage between
/// users. Override with a no-op in unit tests that don't have a real Drift DB.
typedef LocalDataCleanup = Future<void> Function();

final Provider<LocalDataCleanup> localDataCleanupProvider =
    Provider<LocalDataCleanup>((ref) {
      return () async {
        final db = ref.read(trackingDatabaseProvider);
        await db.customStatement('DELETE FROM tracking_points');
        await db.customStatement('DELETE FROM tracking_sessions');
        // Also clear pending photos captured during recording to prevent
        // the next user from seeing or uploading the previous user's photos.
        await db.customStatement('DELETE FROM pending_photos');
      };
    });

final Provider<TrackingPermissionService> trackingPermissionServiceProvider =
    Provider<TrackingPermissionService>((_) => TrackingPermissionService());

final Provider<TrackingEngine> trackingEngineProvider =
    Provider<TrackingEngine>((ref) {
      final engine = TraceletTrackingEngine();
      ref.onDispose(engine.dispose);
      return engine;
    });

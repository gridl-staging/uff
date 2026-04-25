import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_deletion_helper.dart';

import '../application/tracking_controller_test_support.dart';
import '../../../test_helpers/saved_activities_probe.dart';

void main() {
  testWidgets(
    'performActivityDeletion deletes remote before local when remoteId exists',
    (tester) async {
      final operationLog = <String>[];
      final repository = RecordingDeleteTrackingRepository(operationLog);
      final syncService = RecordingDeleteSyncService(operationLog);
      final session = _buildSavedSession(id: 21, remoteId: 'remote-21');
      repository.sessionsById[session.id] = session;

      final deletionResult = Completer<bool>();
      var savedActivitiesLoadCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
            syncServiceProvider.overrideWithValue(syncService),
            savedActivitiesProvider.overrideWith((ref) async {
              savedActivitiesLoadCount += 1;
              return repository.loadSavedSessions();
            }),
          ],
          child: MaterialApp(
            home: _DeletionHarness(
              session: session,
              onDeletionComplete: deletionResult.complete,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialLoadCount = savedActivitiesLoadCount;

      await tester.tap(find.byKey(_DeletionHarness.deleteButtonKey));
      await tester.pumpAndSettle();

      expect(await deletionResult.future, isTrue);
      expect(operationLog, ['remote:remote-21', 'local:21']);
      expect(repository.sessionsById.containsKey(21), isFalse);
      expect(savedActivitiesLoadCount, greaterThan(initialLoadCount));
    },
  );

  testWidgets(
    'performActivityDeletion still runs local delete when remoteId is null',
    (tester) async {
      final operationLog = <String>[];
      final repository = RecordingDeleteTrackingRepository(operationLog);
      final syncService = RecordingDeleteSyncService(operationLog);
      final session = _buildSavedSession(id: 22);
      repository.sessionsById[session.id] = session;

      final deletionResult = Completer<bool>();
      var savedActivitiesLoadCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
            syncServiceProvider.overrideWithValue(syncService),
            savedActivitiesProvider.overrideWith((ref) async {
              savedActivitiesLoadCount += 1;
              return repository.loadSavedSessions();
            }),
          ],
          child: MaterialApp(
            home: _DeletionHarness(
              session: session,
              onDeletionComplete: deletionResult.complete,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialLoadCount = savedActivitiesLoadCount;

      await tester.tap(find.byKey(_DeletionHarness.deleteButtonKey));
      await tester.pumpAndSettle();

      expect(await deletionResult.future, isTrue);
      expect(operationLog, ['local:22']);
      expect(syncService.deletedRemoteActivityIds, isEmpty);
      expect(repository.sessionsById.containsKey(22), isFalse);
      expect(savedActivitiesLoadCount, greaterThan(initialLoadCount));
    },
  );
}

class _DeletionHarness extends ConsumerWidget {
  const _DeletionHarness({
    required this.session,
    required this.onDeletionComplete,
  });

  static const deleteButtonKey = Key('activity_deletion_helper_delete_button');

  final TrackingSessionRecord session;
  final ValueChanged<bool> onDeletionComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: ElevatedButton(
              key: deleteButtonKey,
              onPressed: () async {
                final didDelete = await performActivityDeletion(ref, session);
                onDeletionComplete(didDelete);
              },
              child: const Text('Delete'),
            ),
          ),
          const SavedActivitiesProbe(),
        ],
      ),
    );
  }
}

class RecordingDeleteTrackingRepository extends FakeTrackingRepository {
  RecordingDeleteTrackingRepository(this.operationLog);

  final List<String> operationLog;

  @override
  Future<void> deleteActivity(int sessionId) async {
    operationLog.add('local:$sessionId');
    await super.deleteActivity(sessionId);
  }
}

class RecordingDeleteSyncService extends FakeSyncService {
  RecordingDeleteSyncService(this.operationLog);

  final List<String> operationLog;

  @override
  Future<void> deleteRemoteActivity(String remoteActivityId) async {
    operationLog.add('remote:$remoteActivityId');
    await super.deleteRemoteActivity(remoteActivityId);
  }
}

TrackingSessionRecord _buildSavedSession({required int id, String? remoteId}) {
  final startedAt = DateTime(2025);
  final stoppedAt = startedAt.add(const Duration(minutes: 30));
  return TrackingSessionRecord(
    id: id,
    status: TrackingSessionStatus.saved,
    createdAt: startedAt,
    updatedAt: stoppedAt,
    startedAt: startedAt,
    stoppedAt: stoppedAt,
    remoteId: remoteId,
  );
}

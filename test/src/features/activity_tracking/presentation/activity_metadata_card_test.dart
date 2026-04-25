import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_metadata_card.dart';

import '../application/tracking_controller_test_support.dart';
import 'activity_detail_screen_test_support.dart';

/// ## Test Scenarios
/// - `[positive]` Metadata card renders title and description from ActivityDetailData.
/// - `[positive]` Metadata card reflects persisted visibility in segmented controls.
/// - `[positive]` Editing metadata marks pending changes and notifies parent callback.
/// - `[statemachine]` Save toggles in-flight state and completes with parent callback.
/// - `[edge]` Null persisted visibility defaults to public in segmented controls.
/// - `[negative]` Save callback does not fire before repository save completes.
/// - `[isolation]` Metadata widget state is owned per-widget via GlobalKey state access.
void main() {
  configureActivityDetailScreenTests();

  group('ActivityMetadataCard', () {
    testWidgets('renders title and description from detail data', (
      tester,
    ) async {
      final detail = buildTestActivityDetailData(activityId: activityId);

      await _pumpMetadataCard(tester, detail: detail);

      final titleField = tester.widget<TextField>(
        find.byKey(ActivityMetadataCard.titleFieldKey),
      );
      final descriptionField = tester.widget<TextField>(
        find.byKey(ActivityMetadataCard.descriptionFieldKey),
      );

      expect(titleField.controller?.text, 'Morning Tempo');
      expect(
        descriptionField.controller?.text,
        'Steady effort with final push.',
      );
    });

    testWidgets('visibility segmented button reflects persisted value', (
      tester,
    ) async {
      final detail = buildTestActivityDetailData(
        activityId: activityId,
        visibility: followersTrackingSessionVisibility,
      );

      await _pumpMetadataCard(tester, detail: detail);

      final segmentedButton = tester.widget<SegmentedButton<String>>(
        find.byKey(ActivityMetadataCard.visibilitySegmentedButtonKey),
      );
      expect(segmentedButton.selected, {followersTrackingSessionVisibility});
    });

    testWidgets('editing title sets pending changes and notifies callback', (
      tester,
    ) async {
      final detail = buildTestActivityDetailData(activityId: activityId);
      final metadataKey = GlobalKey<ActivityMetadataCardState>();
      final pendingChangesNotifications = <bool>[];

      await _pumpMetadataCard(
        tester,
        detail: detail,
        metadataKey: metadataKey,
        onPendingChangesChanged: pendingChangesNotifications.add,
      );

      await tester.enterText(
        find.byKey(ActivityMetadataCard.titleFieldKey),
        'Updated run title',
      );
      await tester.pump();

      expect(metadataKey.currentState?.hasPendingChanges, true);
      expect(pendingChangesNotifications.last, true);
    });

    testWidgets(
      'save calls repository and onSaved with in-flight state toggles',
      (
        tester,
      ) async {
        final repository = DelayedMetadataSaveTrackingRepository();
        final detail = buildTestActivityDetailData(activityId: activityId);
        repository.sessionsById[activityId] = detail.session;
        repository.points.addAll(detail.cleanedPoints);
        final metadataKey = GlobalKey<ActivityMetadataCardState>();
        final pendingChangesNotifications = <bool>[];
        var onSavedCallCount = 0;

        await _pumpMetadataCard(
          tester,
          detail: detail,
          repository: repository,
          metadataKey: metadataKey,
          onSaved: () => onSavedCallCount += 1,
          onPendingChangesChanged: pendingChangesNotifications.add,
        );

        await tester.enterText(
          find.byKey(ActivityMetadataCard.titleFieldKey),
          'Saved title',
        );
        await tester.pump();

        await tester.tap(find.byKey(ActivityMetadataCard.saveButtonKey));
        await tester.pump();

        expect(repository.saveStartedCount, 1);
        expect(metadataKey.currentState?.isSaving, true);
        expect(onSavedCallCount, 0);

        repository.completeSave();
        await tester.pumpAndSettle();

        expect(repository.saveSessionCallCount, 1);
        expect(repository.sessionsById[activityId]?.title, 'Saved title');
        expect(onSavedCallCount, 1);
        expect(metadataKey.currentState?.isSaving, false);
        expect(pendingChangesNotifications.last, false);
      },
    );

    testWidgets('defaults to public visibility when persisted value is null', (
      tester,
    ) async {
      final detail = buildTestActivityDetailData(activityId: activityId);

      await _pumpMetadataCard(tester, detail: detail);

      final segmentedButton = tester.widget<SegmentedButton<String>>(
        find.byKey(ActivityMetadataCard.visibilitySegmentedButtonKey),
      );
      expect(segmentedButton.selected, {publicTrackingSessionVisibility});
    });
  });
}

Future<void> _pumpMetadataCard(
  WidgetTester tester, {
  required ActivityDetailData detail,
  FakeTrackingRepository? repository,
  GlobalKey<ActivityMetadataCardState>? metadataKey,
  VoidCallback? onSaved,
  ValueChanged<bool>? onPendingChangesChanged,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trackingRepositoryProvider.overrideWithValue(
          repository ?? FakeTrackingRepository(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ActivityMetadataCard(
            key: metadataKey,
            detail: detail,
            onSaved: onSaved ?? () {},
            onPendingChangesChanged: onPendingChangesChanged ?? (_) {},
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

class DelayedMetadataSaveTrackingRepository extends FakeTrackingRepository {
  int saveStartedCount = 0;
  final Completer<void> _saveCompleter = Completer<void>();

  @override
  Future<void> saveSession(TrackingSessionRecord session) async {
    saveStartedCount += 1;
    await _saveCompleter.future;
    await super.saveSession(session);
  }

  void completeSave() {
    if (_saveCompleter.isCompleted) {
      return;
    }
    _saveCompleter.complete();
  }
}

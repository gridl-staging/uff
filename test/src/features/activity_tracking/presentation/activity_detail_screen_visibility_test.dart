import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_review_screen.dart';

import '../application/tracking_controller_test_support.dart';
import 'activity_detail_screen_test_support.dart';

/// ## Test Scenarios
/// - `[positive]` Visibility controls load persisted selection from saved activity metadata.
/// - `[positive]` Changing visibility enables save and persists the new value.
/// - `[edge]` Successful saves clear pop guards while failed saves keep guard prompts active.
/// - `[statemachine]` Back-navigation stays blocked while save mutations are in flight.
/// - `[statemachine]` Stopped-draft save calls saveSession before finalizeSession and preserves user-selected visibility.
/// - `[negative]` Stopped-draft with null visibility preserves null through finalize when only non-visibility metadata changes.
/// - `[isolation]` Initial stopped-draft screen load triggers no saveSession, finalizeSession, or queueForSync calls.
void main() {
  configureActivityDetailScreenTests();

  Future<void> pumpActivityReviewScreen(
    WidgetTester tester, {
    required ActivityDetailData detail,
    List<Override> overrides = const <Override>[],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...defaultActivityDetailTestOverrides(),
          ...overrides,
        ],
        child: MaterialApp(home: ActivityReviewScreen(detail: detail)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollToReviewKey(WidgetTester tester, Key key) {
    return tester.scrollUntilVisible(
      find.byKey(key),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }

  testWidgets('renders followers visibility selection from saved activity', (
    tester,
  ) async {
    final detailLoader = CountingActivityDetailLoader(
      buildTestActivityDetailData(
        activityId: activityId,
        visibility: 'followers',
      ),
    );

    await pumpActivityDetailScreen(
      tester,
      overrides: [
        activityDetailProvider(
          activityId,
        ).overrideWith((_) => detailLoader()),
      ],
    );

    await enterActivityDetailEditMode(tester);
    final segmentedButtonFinder = find.byKey(
      ActivityDetailScreen.visibilitySegmentedButtonKey,
    );
    await scrollToVisibilitySelector(tester);

    final visibilitySegmentedButton = tester.widget<SegmentedButton<String>>(
      segmentedButtonFinder,
    );
    expect(visibilitySegmentedButton.selected, {'followers'});
  });

  testWidgets('defaults visibility selection to public when session is null', (
    tester,
  ) async {
    final detailLoader = CountingActivityDetailLoader(
      buildTestActivityDetailData(activityId: activityId),
    );

    await pumpActivityDetailScreen(
      tester,
      overrides: [
        activityDetailProvider(
          activityId,
        ).overrideWith((_) => detailLoader()),
      ],
    );

    await enterActivityDetailEditMode(tester);
    final segmentedButtonFinder = find.byKey(
      ActivityDetailScreen.visibilitySegmentedButtonKey,
    );
    await scrollToVisibilitySelector(tester);

    final visibilitySegmentedButton = tester.widget<SegmentedButton<String>>(
      segmentedButtonFinder,
    );
    expect(visibilitySegmentedButton.selected, {'public'});
  });

  testWidgets(
    'falls back to public when persisted visibility is unrecognized',
    (tester) async {
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          visibility: 'team-only',
        ),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
        ],
      );

      await enterActivityDetailEditMode(tester);
      final segmentedButtonFinder = find.byKey(
        ActivityDetailScreen.visibilitySegmentedButtonKey,
      );
      final saveButtonFinder = find.byKey(ActivityDetailScreen.saveButtonKey);
      await scrollToReviewKey(
        tester,
        ActivityDetailScreen.visibilitySegmentedButtonKey,
      );

      final visibilitySegmentedButton = tester.widget<SegmentedButton<String>>(
        segmentedButtonFinder,
      );
      expect(visibilitySegmentedButton.selected, {'public'});
      await scrollToSaveButton(tester);
      expect(tester.widget<ElevatedButton>(saveButtonFinder).onPressed, isNull);
    },
  );

  testWidgets(
    'changing visibility enables save when title and description are unchanged',
    (tester) async {
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          visibility: 'public',
        ),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
        ],
      );

      await enterActivityDetailEditMode(tester);
      final saveButtonFinder = find.byKey(ActivityDetailScreen.saveButtonKey);
      final segmentedButtonFinder = find.byKey(
        ActivityDetailScreen.visibilitySegmentedButtonKey,
      );
      await scrollToReviewKey(
        tester,
        ActivityDetailScreen.visibilitySegmentedButtonKey,
      );

      tester
          .widget<SegmentedButton<String>>(segmentedButtonFinder)
          .onSelectionChanged
          ?.call(<String>{'followers'});
      await tester.pump();

      await scrollToSaveButton(tester);
      expect(tester.widget<ElevatedButton>(saveButtonFinder).enabled, isTrue);
    },
  );

  testWidgets(
    'returning to public after changing a null visibility still enables save',
    (tester) async {
      final repository = FakeTrackingRepository();
      final detailData = buildTestActivityDetailData(activityId: activityId);
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          trackingRepositoryProvider.overrideWithValue(repository),
        ],
      );

      await enterActivityDetailEditMode(tester);
      final saveButtonFinder = find.byKey(ActivityDetailScreen.saveButtonKey);
      final segmentedButtonFinder = find.byKey(
        ActivityDetailScreen.visibilitySegmentedButtonKey,
      );
      await scrollToReviewKey(
        tester,
        ActivityDetailScreen.visibilitySegmentedButtonKey,
      );

      tester
          .widget<SegmentedButton<String>>(segmentedButtonFinder)
          .onSelectionChanged
          ?.call(<String>{'followers'});
      await tester.pump();
      tester
          .widget<SegmentedButton<String>>(segmentedButtonFinder)
          .onSelectionChanged
          ?.call(<String>{'public'});
      await tester.pump();

      await scrollToSaveButton(tester);
      expect(tester.widget<ElevatedButton>(saveButtonFinder).enabled, isTrue);

      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      expect(repository.saveSessionCallCount, 1);
      expect(repository.sessionsById[activityId]?.visibility, 'public');
    },
  );

  testWidgets(
    'saving a visibility change persists it and re-disables the save button',
    (tester) async {
      final repository = FakeTrackingRepository();
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        visibility: 'public',
      );
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          trackingRepositoryProvider.overrideWithValue(repository),
        ],
      );

      await enterActivityDetailEditMode(tester);
      final saveButtonFinder = find.byKey(ActivityDetailScreen.saveButtonKey);
      final segmentedButtonFinder = find.byKey(
        ActivityDetailScreen.visibilitySegmentedButtonKey,
      );
      await scrollToReviewKey(
        tester,
        ActivityDetailScreen.visibilitySegmentedButtonKey,
      );

      tester
          .widget<SegmentedButton<String>>(segmentedButtonFinder)
          .onSelectionChanged
          ?.call(<String>{'private'});
      await tester.pump();

      await scrollToSaveButton(tester);
      expect(tester.widget<ElevatedButton>(saveButtonFinder).enabled, isTrue);

      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      expect(repository.saveSessionCallCount, 1);
      expect(repository.sessionsById[activityId]?.visibility, 'private');
      expect(find.byKey(ActivityDetailScreen.saveButtonKey), findsNothing);
    },
  );

  testWidgets(
    'saving title edits preserves null visibility when selection is untouched',
    (tester) async {
      final repository = FakeTrackingRepository();
      final detailData = buildTestActivityDetailData(activityId: activityId);
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          trackingRepositoryProvider.overrideWithValue(repository),
        ],
      );

      await enterActivityDetailEditMode(tester);
      await scrollToTitleField(tester);
      await tester.enterText(
        find.byKey(ActivityDetailScreen.titleFieldKey),
        'Updated title',
      );
      await tester.pump();

      final saveButtonFinder = find.byKey(ActivityDetailScreen.saveButtonKey);
      await scrollToSaveButton(tester);
      await tester.ensureVisible(saveButtonFinder);
      await tester.pumpAndSettle();
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      expect(repository.saveSessionCallCount, 1);
      expect(repository.sessionsById[activityId]?.title, 'Updated title');
      expect(repository.sessionsById[activityId]?.visibility, isNull);
    },
  );

  testWidgets('successful visibility save clears pop guard for back exits', (
    tester,
  ) async {
    final repository = FakeTrackingRepository();
    final detailData = buildTestActivityDetailData(
      activityId: activityId,
      visibility: 'public',
    );
    repository.sessionsById[activityId] = detailData.session;
    repository.points.addAll(detailData.cleanedPoints);

    await tester.pumpWidget(
      buildPoppableActivityDetailScreen(
        overrides: [
          trackingRepositoryProvider.overrideWithValue(repository),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await enterActivityDetailEditMode(tester);
    final segmentedButtonFinder = find.byKey(
      ActivityDetailScreen.visibilitySegmentedButtonKey,
    );
    await scrollToVisibilitySelector(tester);
    tester
        .widget<SegmentedButton<String>>(segmentedButtonFinder)
        .onSelectionChanged
        ?.call(<String>{'followers'});
    await tester.pump();

    await scrollToSaveButton(tester);
    await tester.tap(find.byKey(ActivityDetailScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(repository.saveSessionCallCount, 1);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text(activityDetailExitRouteText), findsOneWidget);
    expect(find.text('Discard changes?'), findsNothing);
  });

  testWidgets('failed visibility save leaves pop guard active on back', (
    tester,
  ) async {
    final repository = SaveAttemptTrackingRepository();
    final detailData = buildTestActivityDetailData(
      activityId: activityId,
      visibility: 'public',
    );
    repository.sessionsById[activityId] = detailData.session;
    repository.points.addAll(detailData.cleanedPoints);

    await tester.pumpWidget(
      buildPoppableActivityDetailScreen(
        overrides: [
          trackingRepositoryProvider.overrideWithValue(repository),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await enterActivityDetailEditMode(tester);
    final segmentedButtonFinder = find.byKey(
      ActivityDetailScreen.visibilitySegmentedButtonKey,
    );
    await scrollToVisibilitySelector(tester);
    tester
        .widget<SegmentedButton<String>>(segmentedButtonFinder)
        .onSelectionChanged
        ?.call(<String>{'followers'});
    await tester.pump();

    await scrollToSaveButton(tester);
    await tester.tap(find.byKey(ActivityDetailScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(repository.saveAttemptCount, 1);
    expect(
      find.text('Unable to save activity details. Please try again.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.byType(ActivityDetailScreen), findsOneWidget);
    expect(find.text(activityDetailExitRouteText), findsNothing);
  });

  testWidgets(
    'back navigation is ignored while metadata save is still in flight',
    (tester) async {
      final repository = DelayedSaveTrackingRepository();
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        visibility: 'public',
      );
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await tester.pumpWidget(
        buildPoppableActivityDetailScreen(
          overrides: [
            trackingRepositoryProvider.overrideWithValue(repository),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await enterActivityDetailEditMode(tester);
      final segmentedButtonFinder = find.byKey(
        ActivityDetailScreen.visibilitySegmentedButtonKey,
      );
      await scrollToVisibilitySelector(tester);
      tester
          .widget<SegmentedButton<String>>(segmentedButtonFinder)
          .onSelectionChanged
          ?.call(<String>{'followers'});
      await tester.pump();

      await scrollToSaveButton(tester);
      await tester.tap(find.byKey(ActivityDetailScreen.saveButtonKey));
      await tester.pump();

      expect(repository.saveStartedCount, 1);

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(ActivityDetailScreen), findsOneWidget);
      expect(find.text(activityDetailExitRouteText), findsNothing);

      repository.completeSave();
      await tester.pumpAndSettle();
    },
  );

  // --- Stage 2: Recording-path sequencing regressions ---

  testWidgets(
    'stopped draft save calls saveSession before finalizeSession '
    'and preserves user-selected visibility',
    (tester) async {
      final repository = SequencingSpyRepository();
      final syncService = SequencingSpySyncService(repository.callLog);
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        status: TrackingSessionStatus.stopped,
        visibility: null,
      );
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await pumpActivityReviewScreen(
        tester,
        detail: detailData,
        overrides: [
          trackingRepositoryProvider.overrideWithValue(repository),
          syncServiceProvider.overrideWithValue(syncService),
        ],
      );

      // Clear the provider-init calls so we only assert on save-triggered calls.
      repository.callLog.clear();

      // User selects 'followers' visibility.
      final segmentedButtonFinder = find.byKey(
        ActivityDetailScreen.visibilitySegmentedButtonKey,
      );
      await scrollToReviewKey(
        tester,
        ActivityDetailScreen.visibilitySegmentedButtonKey,
      );
      tester
          .widget<SegmentedButton<String>>(segmentedButtonFinder)
          .onSelectionChanged
          ?.call(<String>{'followers'});
      await tester.pump();

      // Tap "Save activity" on the draft review card.
      await scrollToReviewKey(tester, ActivityReviewScreen.draftSaveButtonKey);
      await tester.tap(find.byKey(ActivityReviewScreen.draftSaveButtonKey));
      await tester.pumpAndSettle();

      // Extract the save-triggered call sequence (first 5 entries).
      final methods = repository.callLog.map((r) => r.method).toList();
      expect(methods[0], 'saveSession'); // metadata persist
      expect(methods[1], 'loadSession'); // refresh before finalize
      expect(methods[2], 'saveSession'); // finalize summary write
      expect(methods[3], 'finalizeSession');
      expect(methods[4], 'queueForSync');

      // The metadata-persist saveSession must carry the user-chosen visibility.
      expect(repository.callLog[0].session?.visibility, 'followers');
      // The refreshed session returned by loadSession preserves visibility.
      expect(repository.callLog[1].session?.visibility, 'followers');
      // The finalize summary saveSession preserves visibility via copyWith.
      expect(repository.callLog[2].session?.visibility, 'followers');
    },
  );

  testWidgets(
    'stopped draft with null visibility preserves null through finalize '
    'when only title changes',
    (tester) async {
      final repository = SequencingSpyRepository();
      final syncService = SequencingSpySyncService(repository.callLog);
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        status: TrackingSessionStatus.stopped,
        visibility: null,
      );
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await pumpActivityReviewScreen(
        tester,
        detail: detailData,
        overrides: [
          trackingRepositoryProvider.overrideWithValue(repository),
          syncServiceProvider.overrideWithValue(syncService),
        ],
      );

      repository.callLog.clear();

      // Edit only the title — do not touch the visibility selector.
      await scrollToReviewKey(tester, ActivityDetailScreen.titleFieldKey);
      await tester.enterText(
        find.byKey(ActivityDetailScreen.titleFieldKey),
        'Updated Title',
      );
      await tester.pump();

      // Tap "Save activity" on the draft review card.
      await scrollToReviewKey(tester, ActivityReviewScreen.draftSaveButtonKey);
      await tester.tap(find.byKey(ActivityReviewScreen.draftSaveButtonKey));
      await tester.pumpAndSettle();

      // Every saveSession call must carry null visibility — no auto-write of
      // 'public' or any other default.
      final saveCalls = repository.callLog
          .where((r) => r.method == 'saveSession')
          .toList();
      expect(saveCalls.length, 2);
      expect(saveCalls[0].session?.visibility, isNull);
      expect(saveCalls[1].session?.visibility, isNull);

      // The persisted session must still have null visibility.
      expect(repository.sessionsById[activityId]?.visibility, isNull);
    },
  );

  testWidgets(
    'initial stopped draft screen load triggers no saveSession, '
    'finalizeSession, or queueForSync',
    (tester) async {
      final repository = SequencingSpyRepository();
      final syncService = SequencingSpySyncService(repository.callLog);
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        status: TrackingSessionStatus.stopped,
        visibility: null,
      );
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await pumpActivityReviewScreen(
        tester,
        detail: detailData,
        overrides: [
          trackingRepositoryProvider.overrideWithValue(repository),
          syncServiceProvider.overrideWithValue(syncService),
        ],
      );

      // Only loadSession (from activityDetailProvider) should have fired.
      // No write or sync calls should occur on bare screen entry.
      final saveCalls = repository.callLog
          .where((r) => r.method == 'saveSession')
          .toList();
      final finalizeCalls = repository.callLog
          .where((r) => r.method == 'finalizeSession')
          .toList();
      final syncCalls = repository.callLog
          .where((r) => r.method == 'queueForSync')
          .toList();

      expect(saveCalls, <SequencingCallRecord>[]);
      expect(finalizeCalls, <SequencingCallRecord>[]);
      expect(syncCalls, <SequencingCallRecord>[]);

      // Visibility must remain untouched at null.
      expect(repository.sessionsById[activityId]?.visibility, isNull);
    },
  );
}

class DelayedSaveTrackingRepository extends FakeTrackingRepository {
  int saveStartedCount = 0;
  final Completer<void> saveCompleter = Completer<void>();

  @override
  Future<void> saveSession(TrackingSessionRecord session) async {
    saveStartedCount += 1;
    await saveCompleter.future;
    await super.saveSession(session);
  }

  void completeSave() {
    if (saveCompleter.isCompleted) {
      return;
    }
    saveCompleter.complete();
  }
}

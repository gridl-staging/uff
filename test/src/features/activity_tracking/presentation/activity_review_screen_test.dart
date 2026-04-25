import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_metadata_card.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_review_screen.dart';
import 'package:uff/src/features/maps/presentation/map_view.dart';
import 'package:uff/src/features/photos/application/pending_photo_providers.dart';
import 'package:uff/src/features/photos/application/pending_photo_service.dart';

import '../application/tracking_controller_test_support.dart';
import 'activity_detail_screen_test_support.dart';

/// ## Test Scenarios
/// - `[positive]` Review renders map, metadata card without inline-save button, summary metrics, and draft review actions.
/// - `[positive]` Summary metrics and draft review actions share the same review scroll body.
/// - `[positive]` Save action persists metadata changes, finalizes the draft session, and queues sync.
/// - `[positive]` Save Run exposes a stable semantics id and label for release-smoke selectors.
/// - `[positive]` Discard action confirms intent, discards session data, clears pending photos, and navigates to activity home.
/// - `[negative]` Persisted `saving` status disables both Save and Discard actions.
/// - `[error]` Save failure shows `Unable to save. Please try again.` and re-enables actions.
/// - `[error]` Discard still exits after the draft is deleted even if pending-photo cleanup fails.
/// - `[edge]` PopScope blocks back navigation and routes back attempts through discard confirmation.
/// - `[isolation]` Rebuilding with a different `ActivityDetailData` resets review-screen form state.

const _exitRouteText = 'Review Exit Route';

Future<void> pumpReviewScreen(
  WidgetTester tester, {
  required ActivityDetailData detail,
  List<Override> overrides = const <Override>[],
  bool settle = true,
  bool poppable = false,
}) async {
  final app = poppable
      ? MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/review',
            routes: [
              GoRoute(
                path: '/',
                builder: (_, __) => const Scaffold(body: Text(_exitRouteText)),
              ),
              GoRoute(
                path: '/review',
                builder: (_, __) => ActivityReviewScreen(detail: detail),
              ),
              GoRoute(
                path: '/home/activity',
                builder: (_, __) => const Scaffold(body: Text(_exitRouteText)),
              ),
            ],
          ),
        )
      : MaterialApp(home: ActivityReviewScreen(detail: detail));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [...defaultActivityDetailTestOverrides(), ...overrides],
      child: app,
    ),
  );

  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> scrollToReviewKey(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: find.byType(Scrollable).first,
  );
}

void main() {
  configureActivityDetailScreenTests();

  testWidgets(
    'review renders map, metadata card, summary metrics, and draft actions',
    (tester) async {
      final repository = FakeTrackingRepository();
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        status: TrackingSessionStatus.stopped,
      );
      repository.activeSession = detailData.session;
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await pumpReviewScreen(
        tester,
        detail: detailData,
        overrides: [trackingRepositoryProvider.overrideWithValue(repository)],
      );

      expect(find.text('Review Run'), findsOneWidget);
      expect(find.byType(MapView), findsOneWidget);
      expect(find.byType(ActivityMetadataCard), findsOneWidget);
      expect(find.text('Save details'), findsNothing);
      await scrollToReviewKey(tester, ActivityReviewScreen.draftSaveButtonKey);
      expect(find.text('Save Run'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(
        find.byKey(ActivityReviewScreen.draftReviewNoteKey),
        findsOneWidget,
      );
      await scrollToReviewKey(
        tester,
        ActivityReviewScreen.distanceValueTextKey,
      );
      expect(
        find.byKey(ActivityReviewScreen.distanceValueTextKey),
        findsOneWidget,
      );
      expect(
        find.byKey(ActivityReviewScreen.durationValueTextKey),
        findsOneWidget,
      );
      expect(find.byKey(ActivityReviewScreen.paceValueTextKey), findsOneWidget);
      expect(
        find.byKey(ActivityReviewScreen.elevationValueTextKey),
        findsOneWidget,
      );
    },
  );

  testWidgets('save run exposes a stable semantics id and label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = FakeTrackingRepository();
    final detailData = buildTestActivityDetailData(
      activityId: activityId,
      status: TrackingSessionStatus.stopped,
    );
    repository.activeSession = detailData.session;
    repository.sessionsById[activityId] = detailData.session;
    repository.points.addAll(detailData.cleanedPoints);

    try {
      await pumpReviewScreen(
        tester,
        detail: detailData,
        overrides: [trackingRepositoryProvider.overrideWithValue(repository)],
      );

      await scrollToReviewKey(tester, ActivityReviewScreen.draftSaveButtonKey);

      // This only proves the Flutter semantics contract. DeviceCloud still
      // provides the end-to-end proof that iOS release accessibility exposes
      // the selector the way Maestro sees it.
      expect(
        find.bySemanticsIdentifier(
          ActivityReviewScreen.draftSaveButtonSemanticsId,
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Save Run'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('persisted saving status disables both draft action buttons', (
    tester,
  ) async {
    final repository = FakeTrackingRepository();
    final detailData = buildTestActivityDetailData(
      activityId: activityId,
      status: TrackingSessionStatus.saving,
    );
    repository.activeSession = detailData.session;
    repository.sessionsById[activityId] = detailData.session;
    repository.points.addAll(detailData.cleanedPoints);

    await pumpReviewScreen(
      tester,
      detail: detailData,
      overrides: [trackingRepositoryProvider.overrideWithValue(repository)],
    );

    await scrollToReviewKey(tester, ActivityReviewScreen.draftSaveButtonKey);
    final discardButton = tester.widget<OutlinedButton>(
      find.byKey(ActivityReviewScreen.discardDraftButtonKey),
    );
    final saveButton = tester.widget<ElevatedButton>(
      find.byKey(ActivityReviewScreen.draftSaveButtonKey),
    );

    expect(discardButton.enabled, isFalse);
    expect(saveButton.enabled, isFalse);
  });

  group('review CTA placement', () {
    Future<void> pumpDraftReview(WidgetTester tester) async {
      final repository = FakeTrackingRepository();
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        status: TrackingSessionStatus.stopped,
      );
      repository.activeSession = detailData.session;
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await pumpReviewScreen(
        tester,
        detail: detailData,
        overrides: [trackingRepositoryProvider.overrideWithValue(repository)],
      );
    }

    testWidgets(
      'summary metrics and Save share the same review Scrollable',
      (tester) async {
        await pumpDraftReview(tester);
        await scrollToReviewKey(
          tester,
          ActivityReviewScreen.draftSaveButtonKey,
        );

        final summaryScrollable = find.ancestor(
          of: find.byKey(ActivityReviewScreen.distanceValueTextKey),
          matching: find.byType(Scrollable),
        );
        final saveScrollable = find.ancestor(
          of: find.byKey(ActivityReviewScreen.draftSaveButtonKey),
          matching: find.byType(Scrollable),
        );

        expect(
          summaryScrollable,
          findsOneWidget,
        );
        expect(
          saveScrollable,
          findsOneWidget,
          reason:
              'Save should render inside the same review Scrollable as summary metrics',
        );
        expect(
          tester.element(saveScrollable),
          same(tester.element(summaryScrollable)),
          reason:
              'Save and summary metrics should share one review Scrollable ancestor',
        );
      },
    );

    testWidgets('Save button scrolls with the review body', (
      tester,
    ) async {
      await pumpDraftReview(tester);
      await scrollToReviewKey(tester, ActivityReviewScreen.draftSaveButtonKey);

      final initialSaveRect = tester.getRect(
        find.byKey(ActivityReviewScreen.draftSaveButtonKey),
      );
      final initialSummaryRect = tester.getRect(
        find.byKey(ActivityReviewScreen.distanceValueTextKey),
      );

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
      await tester.pumpAndSettle();

      final saveRectAfterScroll = tester.getRect(
        find.byKey(ActivityReviewScreen.draftSaveButtonKey),
      );
      final summaryRectAfterScroll = tester.getRect(
        find.byKey(ActivityReviewScreen.distanceValueTextKey),
      );

      expect(
        saveRectAfterScroll.center.dy,
        lessThan(initialSaveRect.center.dy),
        reason: 'Save should move up as the review list scrolls',
      );
      expect(
        summaryRectAfterScroll.center.dy,
        lessThan(initialSummaryRect.center.dy),
        reason: 'Summary should move with the same review scroll movement',
      );
    });

    testWidgets(
      'Save button is positioned above Discard button (vertical layout)',
      (tester) async {
        await pumpDraftReview(tester);
        await scrollToReviewKey(
          tester,
          ActivityReviewScreen.draftSaveButtonKey,
        );

        final saveRect = tester.getRect(
          find.byKey(ActivityReviewScreen.draftSaveButtonKey),
        );
        final discardRect = tester.getRect(
          find.byKey(ActivityReviewScreen.discardDraftButtonKey),
        );

        expect(
          saveRect.center.dy,
          lessThan(discardRect.center.dy),
          reason:
              'Save should be positioned above Discard in a vertical layout',
        );
      },
    );

    testWidgets('Save button spans the draft action content width', (
      tester,
    ) async {
      await pumpDraftReview(tester);
      await scrollToReviewKey(tester, ActivityReviewScreen.draftSaveButtonKey);

      final saveRect = tester.getRect(
        find.byKey(ActivityReviewScreen.draftSaveButtonKey),
      );
      final noteRect = tester.getRect(
        find.byKey(ActivityReviewScreen.draftReviewNoteKey),
      );

      expect(
        saveRect.width / noteRect.width,
        greaterThanOrEqualTo(0.95),
        reason: 'Save button should span the full content width, not half',
      );
    });

    testWidgets('Save and Discard do not share the same Row ancestor', (
      tester,
    ) async {
      await pumpDraftReview(tester);
      await scrollToReviewKey(tester, ActivityReviewScreen.draftSaveButtonKey);

      final saveElement = tester.element(
        find.byKey(ActivityReviewScreen.draftSaveButtonKey),
      );
      final discardElement = tester.element(
        find.byKey(ActivityReviewScreen.discardDraftButtonKey),
      );

      final saveRowAncestors = <Element>{};
      saveElement.visitAncestorElements((ancestor) {
        if (ancestor.widget is Row) {
          saveRowAncestors.add(ancestor);
        }
        return true;
      });

      final sharedRowAncestors = <Element>{};
      discardElement.visitAncestorElements((ancestor) {
        if (ancestor.widget is Row && saveRowAncestors.contains(ancestor)) {
          sharedRowAncestors.add(ancestor);
        }
        return true;
      });

      expect(
        sharedRowAncestors,
        isEmpty,
        reason:
            'Save and Discard should not share a Row ancestor; '
            'they should be in a vertical Column layout',
      );
    });
  });

  testWidgets(
    'save persists metadata, finalizes the session, and queues sync',
    (tester) async {
      final repository = FakeTrackingRepository();
      final syncService = FakeSyncService();
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        status: TrackingSessionStatus.stopped,
        visibility: 'public',
      );
      repository.activeSession = detailData.session;
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await pumpReviewScreen(
        tester,
        detail: detailData,
        overrides: [
          trackingRepositoryProvider.overrideWithValue(repository),
          syncServiceProvider.overrideWithValue(syncService),
        ],
      );

      await tester.enterText(
        find.byKey(ActivityMetadataCard.titleFieldKey),
        'Draft review title',
      );
      await tester.pump();

      final visibilityControl = tester.widget<SegmentedButton<String>>(
        find.byKey(ActivityMetadataCard.visibilitySegmentedButtonKey),
      );
      visibilityControl.onSelectionChanged?.call(<String>{'followers'});
      await tester.pump();

      await scrollToReviewKey(tester, ActivityReviewScreen.draftSaveButtonKey);
      await tester.tap(find.byKey(ActivityReviewScreen.draftSaveButtonKey));
      await tester.pumpAndSettle();

      expect(
        repository.sessionsById[activityId]?.status,
        TrackingSessionStatus.saved,
      );
      expect(repository.sessionsById[activityId]?.title, 'Draft review title');
      expect(repository.sessionsById[activityId]?.visibility, 'followers');
      expect(syncService.queuedSessionIds, [activityId]);
    },
  );

  testWidgets(
    'discard confirmation discards session, clears pending photos, and exits',
    (tester) async {
      final repository = FakeTrackingRepository();
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        status: TrackingSessionStatus.stopped,
      );
      final discardSpy = DiscardSpyPendingPhotoService();
      repository.activeSession = detailData.session;
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await pumpReviewScreen(
        tester,
        detail: detailData,
        poppable: true,
        overrides: [
          trackingRepositoryProvider.overrideWithValue(repository),
          pendingPhotoServiceProvider.overrideWith(
            (ref) => Future<PendingPhotoService>.value(discardSpy),
          ),
        ],
      );

      await scrollToReviewKey(
        tester,
        ActivityReviewScreen.discardDraftButtonKey,
      );
      await tester.ensureVisible(
        find.byKey(ActivityReviewScreen.discardDraftButtonKey),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ActivityReviewScreen.discardDraftButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Discard this run?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Discard').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        repository.sessionsById[activityId]?.status,
        TrackingSessionStatus.discarded,
      );
      expect(discardSpy.discardCallCount, 1);
      expect(discardSpy.discardedSessionIds, [activityId]);
      expect(find.text(_exitRouteText), findsOneWidget);
    },
  );

  testWidgets(
    'discard still exits when pending-photo cleanup fails after draft deletion',
    (tester) async {
      final repository = FakeTrackingRepository();
      final detailData = buildTestActivityDetailData(
        activityId: activityId,
        status: TrackingSessionStatus.stopped,
      );
      repository.activeSession = detailData.session;
      repository.sessionsById[activityId] = detailData.session;
      repository.points.addAll(detailData.cleanedPoints);

      await pumpReviewScreen(
        tester,
        detail: detailData,
        poppable: true,
        overrides: [
          trackingRepositoryProvider.overrideWithValue(repository),
          pendingPhotoServiceProvider.overrideWith(
            (ref) => Future<PendingPhotoService>.error(
              StateError('pending photo cleanup failed'),
            ),
          ),
        ],
      );

      await scrollToReviewKey(
        tester,
        ActivityReviewScreen.discardDraftButtonKey,
      );
      await tester.ensureVisible(
        find.byKey(ActivityReviewScreen.discardDraftButtonKey),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ActivityReviewScreen.discardDraftButtonKey));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Discard').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        repository.sessionsById[activityId]?.status,
        TrackingSessionStatus.discarded,
      );
      expect(
        find.text('Run discarded, but pending photos could not be cleared.'),
        findsOneWidget,
      );
      expect(find.text(_exitRouteText), findsOneWidget);
    },
  );

  testWidgets('save failure shows error snackbar and keeps save enabled', (
    tester,
  ) async {
    final repository = FakeTrackingRepository(throwOnSaveSession: true);
    final detailData = buildTestActivityDetailData(
      activityId: activityId,
      status: TrackingSessionStatus.stopped,
    );
    repository.activeSession = detailData.session;
    repository.sessionsById[activityId] = detailData.session;
    repository.points.addAll(detailData.cleanedPoints);

    await pumpReviewScreen(
      tester,
      detail: detailData,
      overrides: [trackingRepositoryProvider.overrideWithValue(repository)],
    );

    await scrollToReviewKey(tester, ActivityReviewScreen.draftSaveButtonKey);
    await tester.tap(find.byKey(ActivityReviewScreen.draftSaveButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Unable to save. Please try again.'), findsOneWidget);
    final saveButton = tester.widget<ElevatedButton>(
      find.byKey(ActivityReviewScreen.draftSaveButtonKey),
    );
    expect(saveButton.enabled, isTrue);
  });

  testWidgets('PopScope blocks back and shows discard confirmation dialog', (
    tester,
  ) async {
    final repository = FakeTrackingRepository();
    final detailData = buildTestActivityDetailData(
      activityId: activityId,
      status: TrackingSessionStatus.stopped,
    );
    repository.activeSession = detailData.session;
    repository.sessionsById[activityId] = detailData.session;
    repository.points.addAll(detailData.cleanedPoints);

    await pumpReviewScreen(
      tester,
      detail: detailData,
      poppable: true,
      overrides: [trackingRepositoryProvider.overrideWithValue(repository)],
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Discard this run?'), findsOneWidget);
    expect(find.text('Review Run'), findsOneWidget);
  });

  testWidgets('rebuild with different detail resets metadata form state', (
    tester,
  ) async {
    final repository = FakeTrackingRepository();
    final firstDetail = buildTestActivityDetailData(
      activityId: activityId,
      status: TrackingSessionStatus.stopped,
      title: 'First run',
    );
    final secondDetail = buildTestActivityDetailData(
      activityId: activityId + 1,
      status: TrackingSessionStatus.stopped,
      title: 'Second run',
    );

    repository.activeSession = firstDetail.session;
    repository.sessionsById[firstDetail.session.id] = firstDetail.session;
    repository.sessionsById[secondDetail.session.id] = secondDetail.session;
    repository.points
      ..addAll(firstDetail.cleanedPoints)
      ..addAll(secondDetail.cleanedPoints);

    final detailValue = ValueNotifier<ActivityDetailData>(firstDetail);
    addTearDown(detailValue.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...defaultActivityDetailTestOverrides(),
          trackingRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<ActivityDetailData>(
            valueListenable: detailValue,
            builder: (context, detail, _) =>
                ActivityReviewScreen(detail: detail),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(ActivityMetadataCard.titleFieldKey), findsOneWidget);
    expect(find.text('First run'), findsOneWidget);

    await tester.enterText(
      find.byKey(ActivityMetadataCard.titleFieldKey),
      'Changed first run',
    );
    await tester.pump();
    expect(find.text('Changed first run'), findsOneWidget);

    detailValue.value = secondDetail;
    await tester.pumpAndSettle();

    expect(find.text('Changed first run'), findsNothing);
    expect(find.text('Second run'), findsOneWidget);
  });
}

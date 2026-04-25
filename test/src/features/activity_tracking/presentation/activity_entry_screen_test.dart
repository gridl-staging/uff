import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_entry_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_review_screen.dart';

import 'activity_detail_screen_test_support.dart';

/// ## Test Scenarios
/// - `[positive]` Wrapper renders review branch when status is `stopped`.
/// - `[positive]` Wrapper renders review branch when status is `saving`.
/// - `[positive]` Wrapper renders detail branch when status is `saved`.
/// - `[positive]` Wrapper shows spinner while provider is loading.
/// - `[positive]` Wrapper keeps `Activity Detail` route chrome while loading.
/// - `[error]` Wrapper shows retryable error UI when provider throws.
/// - `[error]` Wrapper shows not-found recovery when provider resolves null.
/// - `[error]` Wrapper keeps `Activity Detail` route chrome for error and not-found states.
/// - `[edge]` Wrapper shows not-found recovery when status is `idle`.
/// - `[edge]` Wrapper redirects `recording` and `paused` sessions to `/home/record`.
/// - `[edge]` Wrapper redirects discarded drafts to `/home/activity`.
/// - `[statemachine]` `stopped -> saving -> saved` keeps review visible through `saving` and switches to detail after `saved`.
///
/// ## Status Matrix (from TrackingSessionStatus + Stage 1 ownership map)
///   stopped  -> review branch (draft review)
///   saving   -> review branch (finalize in progress)
///   saved    -> detail branch (read-only detail)
///   idle     -> not-found surface
///   recording -> redirect to `/home/record`
///   paused   -> redirect to `/home/record`
///   discarded -> redirect to `/home/activity`

Future<void> pumpActivityEntryScreen(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...defaultActivityDetailTestOverrides(),
        ...overrides,
      ],
      child: const MaterialApp(
        home: ActivityEntryScreen(activityId: activityId),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
    return;
  }
  await tester.pump();
}

Future<void> pumpActivityEntryRoute(
  WidgetTester tester, {
  required TrackingSessionStatus status,
}) async {
  final router = GoRouter(
    initialLocation: '/activity/$activityId',
    routes: [
      GoRoute(
        path: '/activity/:id',
        builder: (_, state) => ActivityEntryScreen(
          activityId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/home/activity',
        builder: (_, __) => const Scaffold(body: Text('Activity home route')),
      ),
      GoRoute(
        path: '/home/record',
        builder: (_, __) => const Scaffold(body: Text('Record home route')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...defaultActivityDetailTestOverrides(),
        activityDetailProvider(activityId).overrideWith(
          (_) async => buildTestActivityDetailData(
            activityId: activityId,
            status: status,
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  configureActivityDetailScreenTests();

  void expectActivityDetailRouteChrome() {
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Activity Detail'), findsOneWidget);
  }

  testWidgets('renders spinner while activity detail provider is loading', (
    tester,
  ) async {
    await pumpActivityEntryScreen(
      tester,
      overrides: [
        activityDetailProvider(
          activityId,
        ).overrideWith((_) => Completer<ActivityDetailData?>().future),
      ],
      settle: false,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expectActivityDetailRouteChrome();
  });

  testWidgets(
    'renders retryable error UI when activity detail loading throws',
    (
      tester,
    ) async {
      await pumpActivityEntryScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith(
            (_) async => throw StateError('failed to load detail'),
          ),
        ],
      );

      expect(
        find.text('Unable to load activity detail. Please try again.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(ElevatedButton, 'Try again'), findsOneWidget);
      expectActivityDetailRouteChrome();
    },
  );

  testWidgets('renders not-found recovery when detail provider resolves null', (
    tester,
  ) async {
    await pumpActivityEntryScreen(
      tester,
      overrides: [
        activityDetailProvider(activityId).overrideWith((_) async => null),
      ],
    );

    expect(find.text('Activity not found.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Try again'), findsOneWidget);
    expectActivityDetailRouteChrome();
  });

  testWidgets('routes stopped status to review branch', (tester) async {
    await pumpActivityEntryScreen(
      tester,
      overrides: [
        activityDetailProvider(activityId).overrideWith(
          (_) async => buildTestActivityDetailData(
            activityId: activityId,
            status: TrackingSessionStatus.stopped,
          ),
        ),
      ],
    );

    expect(find.byKey(ActivityEntryScreen.reviewBranchKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ActivityEntryScreen.reviewBranchKey),
        matching: find.byType(ActivityReviewScreen),
      ),
      findsOneWidget,
    );
  });

  testWidgets('routes saving status to review branch', (tester) async {
    await pumpActivityEntryScreen(
      tester,
      overrides: [
        activityDetailProvider(activityId).overrideWith(
          (_) async => buildTestActivityDetailData(
            activityId: activityId,
            status: TrackingSessionStatus.saving,
          ),
        ),
      ],
      settle: false,
    );
    await tester.pump();

    expect(find.byKey(ActivityEntryScreen.reviewBranchKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ActivityEntryScreen.reviewBranchKey),
        matching: find.byType(ActivityReviewScreen),
      ),
      findsOneWidget,
    );
  });

  testWidgets('routes saved status to detail branch', (tester) async {
    await pumpActivityEntryScreen(
      tester,
      overrides: [
        activityDetailProvider(activityId).overrideWith(
          (_) async => buildTestActivityDetailData(
            activityId: activityId,
          ),
        ),
      ],
    );

    expect(find.byKey(ActivityEntryScreen.detailBranchKey), findsOneWidget);
  });

  testWidgets('routes idle status to not-found recovery', (tester) async {
    await pumpActivityEntryScreen(
      tester,
      overrides: [
        activityDetailProvider(activityId).overrideWith(
          (_) async => buildTestActivityDetailData(
            activityId: activityId,
            status: TrackingSessionStatus.idle,
          ),
        ),
      ],
    );

    expect(find.text('Activity not found.'), findsOneWidget);
    expect(find.byKey(ActivityEntryScreen.reviewBranchKey), findsNothing);
    expect(find.byKey(ActivityEntryScreen.detailBranchKey), findsNothing);
  });

  for (final status in const <TrackingSessionStatus>[
    TrackingSessionStatus.recording,
    TrackingSessionStatus.paused,
  ]) {
    testWidgets('redirects $status status to record home', (tester) async {
      await pumpActivityEntryRoute(tester, status: status);

      expect(find.text('Record home route'), findsOneWidget);
      expect(find.byType(ActivityEntryScreen), findsNothing);
    });
  }

  testWidgets('redirects discarded status to activity home', (tester) async {
    await pumpActivityEntryRoute(
      tester,
      status: TrackingSessionStatus.discarded,
    );

    expect(find.text('Activity home route'), findsOneWidget);
    expect(find.byType(ActivityEntryScreen), findsNothing);
  });

  testWidgets(
    'transitions stopped to saving to saved across wrapper dispatch',
    (
      tester,
    ) async {
      final statusProvider =
          NotifierProvider<_TestStatusNotifier, TrackingSessionStatus>(
            _TestStatusNotifier.new,
          );
      final container = ProviderContainer(
        overrides: [
          ...defaultActivityDetailTestOverrides(),
          activityDetailProvider(activityId).overrideWith((ref) async {
            final status = ref.watch(statusProvider);
            return buildTestActivityDetailData(
              activityId: activityId,
              status: status,
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ActivityEntryScreen(activityId: activityId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ActivityEntryScreen.reviewBranchKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ActivityEntryScreen.reviewBranchKey),
          matching: find.byType(ActivityReviewScreen),
        ),
        findsOneWidget,
      );

      container.read(statusProvider.notifier).state =
          TrackingSessionStatus.saving;
      await tester.pump();
      await tester.pump();

      expect(find.byKey(ActivityEntryScreen.reviewBranchKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ActivityEntryScreen.reviewBranchKey),
          matching: find.byType(ActivityReviewScreen),
        ),
        findsOneWidget,
      );

      container.read(statusProvider.notifier).state =
          TrackingSessionStatus.saved;
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(ActivityEntryScreen.detailBranchKey), findsOneWidget);
    },
  );
}

class _TestStatusNotifier extends Notifier<TrackingSessionStatus> {
  @override
  TrackingSessionStatus build() => TrackingSessionStatus.stopped;
}

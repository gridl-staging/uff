import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_analytics_section.dart';
import 'package:uff/src/features/analytics/application/analytics_providers.dart';
import 'package:uff/src/features/analytics/domain/training_stress.dart';

void main() {
  const activityId = 77;

  testWidgets('shows loading state while analytics providers are pending', (
    tester,
  ) async {
    final tssCompleter = Completer<TrainingStressResult?>();

    await _pumpSection(
      tester,
      activityId: activityId,
      overrides: [
        activityTssProvider(
          activityId,
        ).overrideWith((_) => tssCompleter.future),
        activityIntervalSummaryProvider(
          activityId,
        ).overrideWith((_) async => null),
      ],
      settle: false,
    );

    expect(find.text('Loading analytics...'), findsOneWidget);
  });

  testWidgets('shows safe error state when analytics loading fails', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      activityId: activityId,
      overrides: [
        activityTssProvider(
          activityId,
        ).overrideWith((_) async => throw StateError('failed to load')),
        activityIntervalSummaryProvider(
          activityId,
        ).overrideWith((_) async => null),
      ],
    );

    expect(find.text('Unable to load analytics right now.'), findsOneWidget);
  });

  testWidgets('shows empty state when analytics are unavailable', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      activityId: activityId,
      overrides: [
        activityTssProvider(activityId).overrideWith((_) async => null),
        activityIntervalSummaryProvider(
          activityId,
        ).overrideWith((_) async => null),
      ],
    );

    expect(
      find.text('No per-activity analytics available yet.'),
      findsOneWidget,
    );
  });

  testWidgets('shows cards when both tss and interval data are available', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      activityId: activityId,
      overrides: [
        activityTssProvider(activityId).overrideWith(
          (_) async => const TrainingStressResult(
            tss: 82.4,
            intensityFactor: 0.91,
            method: TssMethod.rTSS,
          ),
        ),
        activityIntervalSummaryProvider(activityId).overrideWith(
          (_) async => const ActivityIntervalSummary(
            totalIntervals: 5,
            hardIntervals: 3,
            easyIntervals: 2,
            averageHardPaceSecsPerKm: 198,
            averageEasyPaceSecsPerKm: 370,
          ),
        ),
      ],
    );

    expect(find.text('rTSS'), findsOneWidget);
    expect(find.text('82'), findsOneWidget);
    expect(find.text('Run stress score'), findsOneWidget);
    expect(find.text('Intervals'), findsOneWidget);
    expect(find.text('Hard 3 • Easy 2'), findsOneWidget);
  });

  testWidgets(
    'shows cycling-specific label and subtitle when cTSS analytics are returned',
    (
      tester,
    ) async {
      await _pumpSection(
        tester,
        activityId: activityId,
        overrides: [
          activityTssProvider(activityId).overrideWith(
            (_) async => const TrainingStressResult(
              tss: 96,
              intensityFactor: 0.85,
              method: TssMethod.cTSS,
            ),
          ),
          activityIntervalSummaryProvider(
            activityId,
          ).overrideWith((_) async => null),
        ],
      );

      expect(find.text('cTSS'), findsOneWidget);
      expect(find.text('rTSS'), findsNothing);
      expect(find.text('96'), findsOneWidget);
      expect(find.text('Cycling stress score'), findsOneWidget);
    },
  );

  testWidgets(
    'shows generic label and subtitle when simple TSS analytics are returned',
    (
      tester,
    ) async {
      await _pumpSection(
        tester,
        activityId: activityId,
        overrides: [
          activityTssProvider(activityId).overrideWith(
            (_) async => const TrainingStressResult(
              tss: 41,
              intensityFactor: 0.72,
              method: TssMethod.simpleTSS,
            ),
          ),
          activityIntervalSummaryProvider(
            activityId,
          ).overrideWith((_) async => null),
        ],
      );

      expect(find.text('TSS'), findsOneWidget);
      expect(find.text('rTSS'), findsNothing);
      expect(find.text('41'), findsOneWidget);
      expect(find.text('Simple stress estimate'), findsOneWidget);
    },
  );

  testWidgets(
    'keeps resolved metrics visible while remaining analytics are still loading',
    (tester) async {
      final intervalsCompleter = Completer<ActivityIntervalSummary?>();

      await _pumpSection(
        tester,
        activityId: activityId,
        overrides: [
          activityTssProvider(activityId).overrideWith(
            (_) async => const TrainingStressResult(
              tss: 82.4,
              intensityFactor: 0.91,
              method: TssMethod.rTSS,
            ),
          ),
          activityIntervalSummaryProvider(
            activityId,
          ).overrideWith((_) => intervalsCompleter.future),
        ],
        settle: false,
      );

      expect(find.text('rTSS'), findsOneWidget);
      expect(find.text('82'), findsOneWidget);
      expect(find.text('Loading remaining analytics...'), findsOneWidget);
      expect(find.text('Loading analytics...'), findsNothing);
    },
  );

  testWidgets(
    'keeps resolved metrics visible when one analytics provider fails',
    (tester) async {
      await _pumpSection(
        tester,
        activityId: activityId,
        overrides: [
          activityTssProvider(activityId).overrideWith(
            (_) async => const TrainingStressResult(
              tss: 82.4,
              intensityFactor: 0.91,
              method: TssMethod.rTSS,
            ),
          ),
          activityIntervalSummaryProvider(
            activityId,
          ).overrideWith((_) async => throw StateError('failed to load')),
        ],
      );

      expect(find.text('rTSS'), findsOneWidget);
      expect(find.text('82'), findsOneWidget);
      expect(
        find.text('Some analytics are unavailable right now.'),
        findsOneWidget,
      );
      expect(find.text('Unable to load analytics right now.'), findsNothing);
    },
  );
}

Future<void> _pumpSection(
  WidgetTester tester, {
  required int activityId,
  List<Object> overrides = const <Object>[],
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        home: Scaffold(body: ActivityAnalyticsSection(activityId: activityId)),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/analytics/domain/pmc_day.dart';
import 'package:uff/src/features/analytics/presentation/training_load_card.dart';

// ## Test Scenarios
// - [positive] Card renders Fitness/Fatigue/Form metric tiles with rounded values
// - [positive] Form status chip shows correct label for each TSB range
// - [positive] Negative zero TSB displays as +0 (not -0)
// - [negative] Null latestDay does not render the Fitness/Fatigue/Form data tiles
// - [isolation] Stable value keys keep Fitness/Fatigue/Form reads isolated to their own tile
// - [edge] Null latestDay shows empty state with icon and message

const _expectedTrainingLoadEmptyStateMessage =
    'No training load data yet. Record your first run.';

Widget _buildCard(PmcDay? latestDay) {
  return MaterialApp(
    home: Scaffold(
      body: TrainingLoadCard(latestDay: latestDay),
    ),
  );
}

PmcDay _pmcDayWithTsb(double tsb) {
  return PmcDay(
    date: DateTime(2025),
    ctl: 54.2,
    atl: 61.9,
    tsb: tsb,
    tssOnDay: 80,
  );
}

void main() {
  group('TrainingLoadCard', () {
    testWidgets(
      'renders Fitness, Fatigue, and Form tiles with rounded values',
      (
        tester,
      ) async {
        await tester.pumpWidget(_buildCard(_pmcDayWithTsb(4.6)));

        expect(find.byKey(TrainingLoadCard.cardKey), findsOneWidget);
        expect(find.byKey(TrainingLoadCard.dataStateKey), findsOneWidget);
        expect(find.byKey(TrainingLoadCard.emptyStateKey), findsNothing);
        // Labels are present.
        expect(find.text('Fitness'), findsOneWidget);
        expect(find.text('Fatigue'), findsOneWidget);
        expect(find.text('Form'), findsOneWidget);
        // Values are rounded integers (no decimals).
        expect(find.text('54'), findsOneWidget); // CTL 54.2 rounds to 54
        expect(find.text('62'), findsOneWidget); // ATL 61.9 rounds to 62
        expect(find.text('+5'), findsOneWidget); // TSB 4.6 rounds to +5
      },
    );

    testWidgets('exposes stable keys for each rounded metric value', (
      tester,
    ) async {
      await tester.pumpWidget(_buildCard(_pmcDayWithTsb(4.6)));

      expect(
        find.byKey(TrainingLoadCard.fitnessValueTextKey),
        findsOneWidget,
      );
      expect(
        find.byKey(TrainingLoadCard.fatigueValueTextKey),
        findsOneWidget,
      );
      expect(
        find.byKey(TrainingLoadCard.formValueTextKey),
        findsOneWidget,
      );
    });

    testWidgets('normalizes negative zero after rounding TSB to integer', (
      tester,
    ) async {
      await tester.pumpWidget(_buildCard(_pmcDayWithTsb(-0.04)));

      // -0.04 rounds to 0, displayed as "+0" not "-0".
      expect(find.text('+0'), findsOneWidget);
      expect(find.text('-0'), findsNothing);
    });

    testWidgets('shows colored form status chip for each TSB range', (
      tester,
    ) async {
      final labelCases = <MapEntry<double, String>>[
        const MapEntry(-20.1, 'Fatigued'),
        const MapEntry(-20, 'Maintaining'),
        const MapEntry(-10, 'Maintaining'),
        const MapEntry(-5, 'Fresh'),
        const MapEntry(0, 'Fresh'),
        const MapEntry(5, 'Peaking'),
      ];

      for (final entry in labelCases) {
        await tester.pumpWidget(_buildCard(_pmcDayWithTsb(entry.key)));

        // Status label should appear in the chip.
        expect(
          find.byKey(TrainingLoadCard.formStatusChipKey),
          findsOneWidget,
        );
        expect(find.text(entry.value), findsOneWidget);
      }
    });

    testWidgets(
      'renders empty-state with icon and message when latestDay is null',
      (
        tester,
      ) async {
        await tester.pumpWidget(_buildCard(null));

        expect(find.byKey(TrainingLoadCard.cardKey), findsOneWidget);
        expect(find.byKey(TrainingLoadCard.emptyStateKey), findsOneWidget);
        expect(find.byKey(TrainingLoadCard.dataStateKey), findsNothing);
        expect(
          find.text(_expectedTrainingLoadEmptyStateMessage),
          findsOneWidget,
        );
        // Icon should be present in empty state.
        expect(find.byIcon(Icons.show_chart), findsOneWidget);
        // Data labels should not be present.
        expect(find.text('Fitness'), findsNothing);
        expect(find.text('Fatigue'), findsNothing);
        expect(find.text('Form'), findsNothing);
      },
    );
  });
}

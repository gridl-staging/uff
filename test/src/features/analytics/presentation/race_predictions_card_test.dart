import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/analytics/domain/race_prediction.dart';
import 'package:uff/src/features/analytics/presentation/race_predictions_card.dart';

const _expectedNoPredictionsOrVdotMessage =
    'No race prediction data yet. Complete a recent run of at least 5 km.';

const _expectedNoPredictionsWithVdotMessage =
    'This effort is already at or beyond the longest standard race distance we predict.';

Widget _buildCard({
  required List<RacePrediction> predictions,
  required double? vdotEstimate,
}) {
  return MaterialApp(
    home: Scaffold(
      body: RacePredictionsCard(
        predictions: predictions,
        vdotEstimate: vdotEstimate,
      ),
    ),
  );
}

void main() {
  group('RacePredictionsCard', () {
    testWidgets(
      'renders populated predictions and non-null VDOT with pinned time formatting',
      (tester) async {
        const predictions = [
          RacePrediction(
            label: '10 km',
            distanceMeters: 10000,
            predictedTime: Duration(minutes: 42, seconds: 5),
            intensityFactor: 1,
          ),
          RacePrediction(
            label: 'Marathon',
            distanceMeters: 42195,
            predictedTime: Duration(hours: 3, minutes: 7, seconds: 45),
            intensityFactor: 1,
          ),
        ];

        await tester.pumpWidget(
          _buildCard(predictions: predictions, vdotEstimate: 52.34),
        );

        expect(find.byKey(RacePredictionsCard.cardKey), findsOneWidget);
        expect(find.byKey(RacePredictionsCard.dataStateKey), findsOneWidget);
        expect(find.byKey(RacePredictionsCard.emptyStateKey), findsNothing);
        expect(find.text('Race Predictions'), findsOneWidget);
        expect(find.text('VDOT'), findsOneWidget);
        expect(find.text('52.3'), findsOneWidget);
        expect(find.text('10 km'), findsOneWidget);
        expect(find.text('42:05'), findsOneWidget);
        expect(find.text('Marathon'), findsOneWidget);
        expect(find.text('3:07:45'), findsOneWidget);
      },
    );

    testWidgets(
      'renders explicit empty state when predictions are empty and VDOT is null',
      (tester) async {
        await tester.pumpWidget(
          _buildCard(predictions: const [], vdotEstimate: null),
        );

        expect(find.byKey(RacePredictionsCard.cardKey), findsOneWidget);
        expect(find.byKey(RacePredictionsCard.emptyStateKey), findsOneWidget);
        expect(find.byKey(RacePredictionsCard.dataStateKey), findsNothing);
        expect(find.text('Race Predictions'), findsOneWidget);
        expect(find.text(_expectedNoPredictionsOrVdotMessage), findsOneWidget);
        expect(find.text('VDOT'), findsNothing);
      },
    );

    testWidgets(
      'renders populated predictions when VDOT is null without a VDOT metric row',
      (tester) async {
        const predictions = [
          RacePrediction(
            label: '5 km',
            distanceMeters: 5000,
            predictedTime: Duration(minutes: 20, seconds: 30),
            intensityFactor: 1,
          ),
          RacePrediction(
            label: 'Half Marathon',
            distanceMeters: 21097,
            predictedTime: Duration(hours: 1, minutes: 35, seconds: 5),
            intensityFactor: 1,
          ),
        ];

        await tester.pumpWidget(
          _buildCard(predictions: predictions, vdotEstimate: null),
        );

        expect(find.byKey(RacePredictionsCard.cardKey), findsOneWidget);
        expect(find.byKey(RacePredictionsCard.dataStateKey), findsOneWidget);
        expect(find.byKey(RacePredictionsCard.emptyStateKey), findsNothing);
        expect(find.text('Race Predictions'), findsOneWidget);
        expect(find.text('VDOT'), findsNothing);
        expect(find.text('5 km'), findsOneWidget);
        expect(find.text('20:30'), findsOneWidget);
        expect(find.text('Half Marathon'), findsOneWidget);
        expect(find.text('1:35:05'), findsOneWidget);
        expect(find.text(_expectedNoPredictionsOrVdotMessage), findsNothing);
        expect(find.text(_expectedNoPredictionsWithVdotMessage), findsNothing);
      },
    );

    testWidgets(
      'renders empty predictions state while still showing non-null VDOT',
      (tester) async {
        await tester.pumpWidget(
          _buildCard(predictions: const [], vdotEstimate: 48.92),
        );

        expect(find.byKey(RacePredictionsCard.cardKey), findsOneWidget);
        expect(find.byKey(RacePredictionsCard.emptyStateKey), findsOneWidget);
        expect(find.byKey(RacePredictionsCard.dataStateKey), findsNothing);
        expect(find.text('Race Predictions'), findsOneWidget);
        expect(find.text('VDOT'), findsOneWidget);
        expect(find.text('48.9'), findsOneWidget);
        expect(
          find.text(_expectedNoPredictionsWithVdotMessage),
          findsOneWidget,
        );
      },
    );
  });
}

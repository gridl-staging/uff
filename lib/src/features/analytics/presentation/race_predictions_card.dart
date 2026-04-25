import 'package:flutter/material.dart';
import 'package:uff/src/features/analytics/domain/race_prediction.dart';

const _racePredictionsTitle = 'Race Predictions';
const _noPredictionsOrVdotMessage =
    'No race prediction data yet. Complete a recent run of at least 5 km.';
const _noPredictionsWithVdotMessage =
    'This effort is already at or beyond the longest standard race distance we predict.';

/// TODO: Document RacePredictionsCard.
class RacePredictionsCard extends StatelessWidget {
  const RacePredictionsCard({
    required this.predictions,
    required this.vdotEstimate,
    this.showEmptyStateMessage = true,
    super.key,
  });

  static const cardKey = Key('race_predictions_card');
  static const emptyStateKey = Key('race_predictions_card_empty_state');
  static const dataStateKey = Key('race_predictions_card_data_state');
  static const vdotDisplayKey = Key('race_predictions_vdot_display');

  final List<RacePrediction> predictions;
  final double? vdotEstimate;
  final bool showEmptyStateMessage;

  @override
  Widget build(BuildContext context) {
    final hasPredictions = predictions.isNotEmpty;
    final showPredictionsContent = hasPredictions || showEmptyStateMessage;

    return Card(
      key: cardKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _racePredictionsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (vdotEstimate != null) ...[
              const SizedBox(height: 12),
              // VDOT shown in a highlighted tile so it stands out from the
              // prediction rows below.
              _VdotTile(vdot: vdotEstimate!),
            ],
            if (showPredictionsContent) ...[
              const SizedBox(height: 12),
              if (hasPredictions)
                Column(
                  key: dataStateKey,
                  children: [
                    for (final prediction in predictions)
                      _PredictionRow(prediction: prediction),
                  ],
                )
              else
                Text(
                  key: emptyStateKey,
                  vdotEstimate == null
                      ? _noPredictionsOrVdotMessage
                      : _noPredictionsWithVdotMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Highlighted VDOT display tile. Shown above the prediction list to
/// give the VDOT score visual weight — it's the single most important
/// number for a runner and shouldn't be buried in a text row.
class _VdotTile extends StatelessWidget {
  const _VdotTile({required this.vdot});
  final double vdot;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: RacePredictionsCard.vdotDisplayKey,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            Text(
              'VDOT',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const Spacer(),
            Text(
              vdot.toStringAsFixed(1),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual race prediction row with distance label, predicted time,
/// and a thin intensity bar that visually scales with the intensity factor.
/// The bar provides at-a-glance comparison between race distances.
class _PredictionRow extends StatelessWidget {
  const _PredictionRow({required this.prediction});
  final RacePrediction prediction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                prediction.label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                _formatPredictedTime(prediction.predictedTime),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Intensity bar: width proportional to intensityFactor (0..1).
          // Provides visual comparison between race distances — shorter
          // races have lower intensity factors, longer races approach 1.0.
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: prediction.intensityFactor.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatPredictedTime(Duration predictedTime) {
  final totalSeconds = predictedTime.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    return '$hours:${_twoDigits(minutes)}:${_twoDigits(seconds)}';
  }

  return '$minutes:${_twoDigits(seconds)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

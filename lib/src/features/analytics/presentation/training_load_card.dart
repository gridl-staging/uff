import 'package:flutter/material.dart';
import 'package:uff/src/features/analytics/domain/pmc_day.dart';

const _trainingLoadEmptyStateMessage =
    'No training load data yet. Record your first run.';

/// TODO: Document TrainingLoadCard.
class TrainingLoadCard extends StatelessWidget {
  const TrainingLoadCard({required this.latestDay, super.key});

  static const cardKey = Key('training_load_card');
  static const emptyStateKey = Key('training_load_card_empty_state');
  static const dataStateKey = Key('training_load_card_data_state');
  static const formStatusChipKey = Key('training_load_form_status_chip');
  static const fitnessValueTextKey = Key('training_load_fitness_value_text');
  static const fatigueValueTextKey = Key('training_load_fatigue_value_text');
  static const formValueTextKey = Key('training_load_form_value_text');

  final PmcDay? latestDay;

  @override
  Widget build(BuildContext context) {
    final day = latestDay;
    if (day == null) {
      return Card(
        key: cardKey,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            key: emptyStateKey,
            children: [
              Icon(
                Icons.show_chart,
                size: 40,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 8),
              Text(
                _trainingLoadEmptyStateMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final formStatus = _tsbStatus(day.tsb);

    return Card(
      key: cardKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          key: dataStateKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: title + colored form status chip on the right.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Training Load',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                // Colored chip showing the user's current form status
                // (Peaking, Fresh, Maintaining, Fatigued). Color-coded so
                // the training state is visible at a glance.
                Container(
                  key: formStatusChipKey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: formStatus.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    formStatus.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: formStatus.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // One-line guidance text below the status chip so casual runners
            // know what the status means for their training without needing
            // to understand CTL/ATL/TSB. Inspired by Garmin's Training Status.
            Text(
              formStatus.guidance,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // Metric tiles displayed as a row of three equal-width boxes.
            // Each tile shows the metric label, value, and a subtle
            // background to visually group the three values.
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    label: 'Fitness',
                    value: day.ctl.toStringAsFixed(0),
                    valueKey: fitnessValueTextKey,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricTile(
                    label: 'Fatigue',
                    value: day.atl.toStringAsFixed(0),
                    valueKey: fatigueValueTextKey,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricTile(
                    label: 'Form',
                    value: _formatSigned(day.tsb),
                    valueColor: formStatus.color,
                    valueKey: formValueTextKey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats a double value with a leading sign character for display.
/// Converts -0.0 to +0.0 to avoid confusing negative zero.
String _formatSigned(double value) {
  final rounded = value.round();
  if (rounded == 0) return '+0';
  final prefix = rounded < 0 ? '' : '+';
  return '$prefix$rounded';
}

/// TSB status with label, semantic color, and plain-language guidance.
/// The guidance line tells casual runners what the status means for their
/// training without requiring them to understand CTL/ATL/TSB math.
class _TsbStatus {
  const _TsbStatus({
    required this.label,
    required this.color,
    required this.guidance,
  });
  final String label;
  final Color color;
  final String guidance;
}

/// Maps TSB value to a human-readable status, semantic color, and actionable
/// guidance. Thresholds follow standard PMC interpretation:
///   < -20  → Fatigued (red)
///   -20..-5 → Maintaining (orange)
///   -5..5  → Fresh (green)
///   > 5    → Peaking (blue)
_TsbStatus _tsbStatus(double tsb) {
  if (tsb < -20) {
    return const _TsbStatus(
      label: 'Fatigued',
      color: Colors.red,
      guidance: 'High training load. Consider an easy day or rest.',
    );
  }
  if (tsb < -5) {
    return const _TsbStatus(
      label: 'Maintaining',
      color: Colors.orange,
      guidance: 'Steady training. Build gradually or hold here.',
    );
  }
  if (tsb < 5) {
    return const _TsbStatus(
      label: 'Fresh',
      color: Colors.green,
      guidance: 'Well rested. Good for hard efforts or racing.',
    );
  }
  return const _TsbStatus(
    label: 'Peaking',
    color: Colors.blue,
    guidance: 'Great time to race or do a hard workout.',
  );
}

/// Individual metric tile with a subtle background, used in the
/// three-across layout for Fitness / Fatigue / Form.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueKey,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Column(
          children: [
            Text(
              key: valueKey,
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

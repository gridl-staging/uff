import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/analytics/application/analytics_providers.dart';
import 'package:uff/src/features/analytics/domain/training_stress.dart';

/// Renders per-activity analytics cards sourced from analytics providers.
class ActivityAnalyticsSection extends ConsumerWidget {
  const ActivityAnalyticsSection({required this.activityId, super.key});

  // E2E detail flows land on the saved activity screen before this card is in
  // view on compact simulators. Keep a stable key on the card itself so tests
  // can reveal the section through real scrolling before reading exact labels.
  static const cardKey = Key('activity_analytics_card');

  final int activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tssState = ref.watch(activityTssProvider(activityId));
    final intervalSummaryState = ref.watch(
      activityIntervalSummaryProvider(activityId),
    );

    return Card(
      key: cardKey,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Activity analytics',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _buildContent(
              context: context,
              tssState: tssState,
              intervalSummaryState: intervalSummaryState,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent({
    required BuildContext context,
    required AsyncValue<TrainingStressResult?> tssState,
    required AsyncValue<ActivityIntervalSummary?> intervalSummaryState,
  }) {
    final tss = tssState.asData?.value;
    final intervalSummary = intervalSummaryState.asData?.value;
    final hasDisplayableMetrics = tss != null || intervalSummary != null;

    if (!hasDisplayableMetrics &&
        (tssState.isLoading || intervalSummaryState.isLoading)) {
      return const Text('Loading analytics...');
    }

    if (!hasDisplayableMetrics &&
        (tssState.hasError || intervalSummaryState.hasError)) {
      return const Text('Unable to load analytics right now.');
    }

    if (!hasDisplayableMetrics) {
      return const Text('No per-activity analytics available yet.');
    }

    final deferredStatusMessage = _buildDeferredStatusMessage(
      tssState: tssState,
      intervalSummaryState: intervalSummaryState,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tss != null)
          _AnalyticsMetricTile(
            label: _formatTssLabel(tss.method),
            value: tss.tss.toStringAsFixed(0),
            subtitle: _formatTssMethod(tss.method),
          ),
        if (tss != null && intervalSummary != null) const SizedBox(height: 8),
        if (intervalSummary != null)
          _AnalyticsMetricTile(
            label: 'Intervals',
            value: intervalSummary.totalIntervals.toString(),
            subtitle:
                'Hard ${intervalSummary.hardIntervals} • Easy ${intervalSummary.easyIntervals}',
          ),
        if (deferredStatusMessage != null) const SizedBox(height: 8),
        if (deferredStatusMessage != null)
          Text(
            deferredStatusMessage,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
          ),
      ],
    );
  }

  String? _buildDeferredStatusMessage({
    required AsyncValue<TrainingStressResult?> tssState,
    required AsyncValue<ActivityIntervalSummary?> intervalSummaryState,
  }) {
    if (tssState.isLoading || intervalSummaryState.isLoading) {
      return 'Loading remaining analytics...';
    }
    if (tssState.hasError || intervalSummaryState.hasError) {
      return 'Some analytics are unavailable right now.';
    }
    return null;
  }
}

String _formatTssMethod(TssMethod method) {
  switch (method) {
    case TssMethod.rTSS:
      return 'Run stress score';
    case TssMethod.cTSS:
      return 'Cycling stress score';
    case TssMethod.simpleTSS:
      return 'Simple stress estimate';
  }
}

String _formatTssLabel(TssMethod method) {
  switch (method) {
    case TssMethod.rTSS:
      return 'rTSS';
    case TssMethod.cTSS:
      return 'cTSS';
    case TssMethod.simpleTSS:
      return 'TSS';
  }
}

/// Displays a single analytics metric with its label, subtitle, and value.
class _AnalyticsMetricTile extends StatelessWidget {
  const _AnalyticsMetricTile({
    required this.label,
    required this.value,
    required this.subtitle,
  });

  final String label;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

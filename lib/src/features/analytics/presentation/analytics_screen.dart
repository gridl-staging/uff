import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/analytics/application/analytics_providers.dart';
import 'package:uff/src/features/analytics/domain/race_prediction.dart';
import 'package:uff/src/features/analytics/presentation/pmc_chart_widget.dart';
import 'package:uff/src/features/analytics/presentation/race_predictions_card.dart';
import 'package:uff/src/features/analytics/presentation/training_load_card.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/settings/presentation/settings_routes.dart';

const _analyticsLoadErrorMessage =
    'Unable to load analytics data. Please try again.';
const _analyticsEmptyStateMessage =
    'Record some activities to see your training analytics';
const _racePredictionsLoadingMessage = 'Loading race predictions...';
const _vdotEstimateLoadingMessage = 'Loading VDOT estimate...';
const _racePredictionsErrorMessage = 'Unable to load race predictions.';
const _vdotEstimateErrorMessage = 'Unable to load VDOT estimate.';
const _racePredictionsUnavailableMessage =
    'Race predictions are unavailable right now.';
const _hrZonesCtaTitle = 'Set up heart rate zones';
const _hrZonesCtaBody =
    'Add your LTHR to unlock personalized heart-rate analytics.';
const _hrZonesCtaButtonLabel = 'Set up HR zones';

/// TODO: Document AnalyticsScreen.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  static const emptyStateKey = Key('analytics_screen_empty_state');
  static const loadingStateKey = Key('analytics_screen_loading_state');
  static const loadingIndicatorKey = Key('analytics_screen_loading_indicator');
  static const loadErrorStateKey = Key('analytics_screen_load_error_state');
  static const loadErrorRetryButtonKey = Key(
    'analytics_screen_load_error_retry_button',
  );
  static const contentListViewKey = Key('analytics_screen_content_list_view');
  static const raceFallbackStatusKey = Key(
    'analytics_screen_race_fallback_status',
  );
  static const raceDeferredStatusKey = Key(
    'analytics_screen_race_deferred_status',
  );
  static const raceStatusLoadingIndicatorKey = Key(
    'analytics_screen_race_status_loading_indicator',
  );
  static const racePredictionsRetryButtonKey = Key(
    'analytics_screen_race_predictions_retry_button',
  );
  static const vdotRetryButtonKey = Key('analytics_screen_vdot_retry_button');
  static const hrZonesSetupCtaKey = Key('analytics_screen_hr_zones_setup_cta');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pmcAsync = ref.watch(pmcProvider);
    Future<void> refreshPmcOnly() async {
      try {
        final _ = await ref.refresh(pmcProvider.future);
      } on Object {
        // Keep the primary load error state visible until pmc data recovers.
      }
    }

    Future<void> refreshAllAnalytics() async {
      _invalidateAnalyticsProviders(ref);
      try {
        final _ = await Future.wait<void>([
          ref.refresh(pmcProvider.future),
          ref.refresh(racePredictionsProvider.future),
          ref.refresh(vdotEstimateProvider.future),
        ]);
      } on Object {
        // Keep whichever sections still fail in their existing error states.
      }
    }

    // No Scaffold here — the HomeShellScreen provides the outer Scaffold
    // with AppBar (title: "Analytics") and BottomNavigationBar. Wrapping
    // in another Scaffold caused a double-AppBar bug.
    return pmcAsync.when(
      loading: () => const Center(
        key: loadingStateKey,
        child: CircularProgressIndicator(key: loadingIndicatorKey),
      ),
      error: (_, __) => RefreshIndicator(
        onRefresh: refreshPmcOnly,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                key: loadErrorStateKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _analyticsLoadErrorMessage,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      key: loadErrorRetryButtonKey,
                      onPressed: () {
                        ref.invalidate(savedActivitiesProvider);
                        _invalidateAnalyticsProviders(ref);
                      },
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      data: (pmcDays) {
        if (pmcDays.isEmpty) {
          return RefreshIndicator(
            onRefresh: refreshAllAnalytics,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    key: emptyStateKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.directions_run_outlined,
                          size: 48,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _analyticsEmptyStateMessage,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final latestDay = pmcDays.last;
        final racePredictionsAsync = ref.watch(racePredictionsProvider);
        final vdotEstimateAsync = ref.watch(vdotEstimateProvider);
        final profileAsync = ref.watch(profileProvider);
        final shouldShowHrZonesSetupCta = profileAsync.maybeWhen(
          data: (profile) => profile != null && profile.lthrBpm == null,
          orElse: () => false,
        );

        final bottomInset = MediaQuery.of(context).padding.bottom;
        return RefreshIndicator(
          onRefresh: refreshAllAnalytics,
          child: ListView(
            key: contentListViewKey,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottomInset),
            children: [
              TrainingLoadCard(latestDay: latestDay),
              const SizedBox(height: 12),
              PmcChartWidget(pmcDays: pmcDays),
              if (shouldShowHrZonesSetupCta) ...[
                const SizedBox(height: 12),
                // HR zones CTA — styled as a distinct banner so it reads
                // as a setup action, not a data card.
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.favorite_outline,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _hrZonesCtaTitle,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _hrZonesCtaBody,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          key: hrZonesSetupCtaKey,
                          onPressed: () =>
                              context.push(SettingsRoutes.hrZonesPath),
                          child: const Text(_hrZonesCtaButtonLabel),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _buildRacePredictionsSection(
                ref: ref,
                racePredictionsAsync: racePredictionsAsync,
                vdotEstimateAsync: vdotEstimateAsync,
              ),
            ],
          ),
        );
      },
    );
  }
}

void _invalidateAnalyticsProviders(WidgetRef ref) {
  ref
    ..invalidate(pmcProvider)
    ..invalidate(racePredictionsProvider)
    ..invalidate(vdotEstimateProvider);
}

Widget _buildRacePredictionsSection({
  required WidgetRef ref,
  required AsyncValue<List<RacePrediction>> racePredictionsAsync,
  required AsyncValue<double?> vdotEstimateAsync,
}) {
  final hasPredictionsValue = racePredictionsAsync.hasValue;
  final hasPredictionsError = racePredictionsAsync.hasError;
  final isPredictionsLoading = !hasPredictionsValue && !hasPredictionsError;
  final hasVdotValue = vdotEstimateAsync.hasValue;
  final hasVdotError = vdotEstimateAsync.hasError;
  final isVdotLoading = !hasVdotValue && !hasVdotError;
  final resolvedVdotEstimate = hasVdotValue
      ? vdotEstimateAsync.requireValue
      : null;
  final resolvedPredictions = hasPredictionsValue
      ? racePredictionsAsync.requireValue
      : const <RacePrediction>[];
  final shouldShowRaceEmptyStateMessage =
      hasPredictionsValue &&
      (resolvedPredictions.isNotEmpty || (!isVdotLoading && !hasVdotError));
  final hasDisplayableVdot = resolvedVdotEstimate != null;
  final retryActions = _buildRetryActions(
    ref: ref,
    hasPredictionsError: hasPredictionsError,
    hasVdotError: hasVdotError,
  );

  if (!hasPredictionsValue && !hasDisplayableVdot) {
    if (isPredictionsLoading || isVdotLoading) {
      return _StatusCard(
        cardKey: AnalyticsScreen.raceFallbackStatusKey,
        title: 'Race Predictions',
        message: isPredictionsLoading
            ? _racePredictionsLoadingMessage
            : _vdotEstimateLoadingMessage,
        showLoadingIndicator: true,
        loadingIndicatorKey: AnalyticsScreen.raceStatusLoadingIndicatorKey,
        retryActions: retryActions,
      );
    }

    return _StatusCard(
      cardKey: AnalyticsScreen.raceFallbackStatusKey,
      title: 'Race Predictions',
      message: _racePredictionsUnavailableMessage,
      retryActions: retryActions,
    );
  }

  final sectionChildren = <Widget>[
    RacePredictionsCard(
      predictions: resolvedPredictions,
      vdotEstimate: resolvedVdotEstimate,
      showEmptyStateMessage: shouldShowRaceEmptyStateMessage,
    ),
  ];

  if (isPredictionsLoading) {
    _appendDeferredStatusCard(
      sectionChildren: sectionChildren,
      message: _racePredictionsLoadingMessage,
      showLoadingIndicator: true,
      statusCardKey: AnalyticsScreen.raceDeferredStatusKey,
      loadingIndicatorKey: AnalyticsScreen.raceStatusLoadingIndicatorKey,
    );
  }

  if (hasPredictionsError) {
    _appendDeferredStatusCard(
      sectionChildren: sectionChildren,
      message: _racePredictionsErrorMessage,
      retryAction: _racePredictionsRetryAction(ref),
      statusCardKey: AnalyticsScreen.raceDeferredStatusKey,
    );
  }

  if (isVdotLoading) {
    _appendDeferredStatusCard(
      sectionChildren: sectionChildren,
      message: _vdotEstimateLoadingMessage,
      showLoadingIndicator: true,
      statusCardKey: AnalyticsScreen.raceDeferredStatusKey,
      loadingIndicatorKey: AnalyticsScreen.raceStatusLoadingIndicatorKey,
    );
  }

  if (hasVdotError) {
    _appendDeferredStatusCard(
      sectionChildren: sectionChildren,
      message: _vdotEstimateErrorMessage,
      retryAction: _vdotRetryAction(ref),
      statusCardKey: AnalyticsScreen.raceDeferredStatusKey,
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: sectionChildren,
  );
}

List<_RetryAction> _buildRetryActions({
  required WidgetRef ref,
  required bool hasPredictionsError,
  required bool hasVdotError,
}) {
  final retryActions = <_RetryAction>[];
  if (hasPredictionsError) {
    retryActions.add(_racePredictionsRetryAction(ref));
  }
  if (hasVdotError) {
    retryActions.add(_vdotRetryAction(ref));
  }
  return retryActions;
}

void _appendDeferredStatusCard({
  required List<Widget> sectionChildren,
  required String message,
  required Key statusCardKey,
  _RetryAction? retryAction,
  bool showLoadingIndicator = false,
  Key? loadingIndicatorKey,
}) {
  sectionChildren
    ..add(const SizedBox(height: 8))
    ..add(
      _StatusCard(
        cardKey: statusCardKey,
        message: message,
        retryActions: retryAction == null ? const [] : [retryAction],
        showLoadingIndicator: showLoadingIndicator,
        loadingIndicatorKey: loadingIndicatorKey,
      ),
    );
}

_RetryAction _racePredictionsRetryAction(WidgetRef ref) {
  return _RetryAction(
    label: 'Try Again',
    onRetry: () => ref.invalidate(racePredictionsProvider),
    buttonKey: AnalyticsScreen.racePredictionsRetryButtonKey,
  );
}

_RetryAction _vdotRetryAction(WidgetRef ref) {
  return _RetryAction(
    label: 'Try Again',
    onRetry: () => ref.invalidate(vdotEstimateProvider),
    buttonKey: AnalyticsScreen.vdotRetryButtonKey,
  );
}

/// NOTE(stuart): Document _StatusCard.
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.message,
    this.title,
    this.showLoadingIndicator = false,
    this.retryActions = const [],
    this.cardKey,
    this.loadingIndicatorKey,
  });

  final String? title;
  final String message;
  final bool showLoadingIndicator;
  final List<_RetryAction> retryActions;
  final Key? cardKey;
  final Key? loadingIndicatorKey;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: cardKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
            ],
            if (showLoadingIndicator)
              Row(
                children: [
                  SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      key: loadingIndicatorKey,
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(message),
                ],
              )
            else
              Text(message),
            for (final action in retryActions) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                key: action.buttonKey,
                onPressed: action.onRetry,
                child: Text(action.label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RetryAction {
  const _RetryAction({
    required this.label,
    required this.onRetry,
    required this.buttonKey,
  });

  final String label;
  final VoidCallback onRetry;
  final Key buttonKey;
}

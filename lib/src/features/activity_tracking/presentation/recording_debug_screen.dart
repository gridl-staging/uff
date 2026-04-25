import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_controller.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';
import 'package:uff/src/features/maps/presentation/map_view.dart';

class RecordingDebugScreen extends ConsumerStatefulWidget {
  const RecordingDebugScreen({super.key});

  @override
  ConsumerState<RecordingDebugScreen> createState() =>
      _RecordingDebugScreenState();
}

/// NOTE(stuart): Document _RecordingDebugScreenState.
class _RecordingDebugScreenState extends ConsumerState<RecordingDebugScreen> {
  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(recordingControllerProvider);
    final routePoints = controllerState.points
        .map(
          (point) => RoutePoint(
            latitude: point.latitude,
            longitude: point.longitude,
          ),
        )
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Recording Debug')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(context, controllerState),
            const SizedBox(height: 12),
            _buildActionRow(context, controllerState),
            const SizedBox(height: 12),
            Expanded(
              child: MapView(
                followUserLocation: true,
                routePoints: routePoints,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(BuildContext context, RecordingControllerState state) {
    final actions = _RecordingActionAvailability.from(state.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildErrorMessage(context, state.errorMessage),
        _buildRecordingControls(actions),
        const SizedBox(height: 8),
        _buildFinalizeControls(actions),
      ],
    );
  }

  Widget _buildErrorMessage(BuildContext context, String? errorMessage) {
    if (errorMessage == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        errorMessage,
        style:
            Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
      ),
    );
  }

  Widget _buildRecordingControls(_RecordingActionAvailability actions) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: actions.canStart
                ? () => _safeAction(_controller.startRecording)
                : null,
            child: const Text('Start'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: actions.canPause
                ? () => _safeAction(_controller.pauseRecording)
                : null,
            child: const Text('Pause'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: actions.canResume
                ? () => _safeAction(_controller.resumeRecording)
                : null,
            child: const Text('Resume'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: actions.canStop
                ? () => _safeAction(_controller.stopRecording)
                : null,
            child: const Text('Stop'),
          ),
        ),
      ],
    );
  }

  Widget _buildFinalizeControls(_RecordingActionAvailability actions) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: actions.canSave
                ? () => _safeAction(_controller.saveRecording)
                : null,
            child: const Text('Save'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: actions.canDiscard
                ? () => _safeAction(_controller.discardRecording)
                : null,
            child: const Text('Discard'),
          ),
        ),
      ],
    );
  }

  RecordingController get _controller =>
      ref.read(recordingControllerProvider.notifier);

  Widget _buildStatusCard(
    BuildContext context,
    RecordingControllerState state,
  ) {
    final theme = Theme.of(context);
    final elapsed = state.elapsed(now: DateTime.now());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'State: ${state.status.name}',
              style: theme.textTheme.titleMedium,
            ),
            Text('Elapsed: ${_formatDuration(elapsed)}'),
            Text('Points: ${state.pointCount}'),
            Text(
              'Last fix: ${state.lastFixTimestamp == null ? 'n/a' : state.lastFixTimestamp!.toLocal()}',
            ),
            if (state.session != null) ...[
              const SizedBox(height: 4),
              Text('Session: #${state.session!.id}'),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _safeAction(Future<void> Function() action) async {
    final controller = ref.read(recordingControllerProvider.notifier);
    try {
      await action();
    } on InvalidTrackingTransition {
      controller.setErrorMessage('Invalid action for current state.');
    } on Object catch (error) {
      controller.setErrorMessage('Unexpected error: $error');
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    final hours = minutes ~/ 60;
    final remainderMinutes = minutes % 60;

    return '$hours:${remainderMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// NOTE(stuart): Document _RecordingActionAvailability.
class _RecordingActionAvailability {
  const _RecordingActionAvailability({
    required this.canStart,
    required this.canPause,
    required this.canResume,
    required this.canStop,
    required this.canSave,
    required this.canDiscard,
  });

  factory _RecordingActionAvailability.from(TrackingSessionStatus status) {
    final isIdle = status == TrackingSessionStatus.idle;
    final isRecording = status == TrackingSessionStatus.recording;
    final isPaused = status == TrackingSessionStatus.paused;
    final isStopped = status == TrackingSessionStatus.stopped;

    return _RecordingActionAvailability(
      canStart: isIdle,
      canPause: isRecording,
      canResume: isPaused,
      canStop: isRecording || isPaused,
      canSave: isStopped,
      canDiscard: isStopped,
    );
  }

  final bool canStart;
  final bool canPause;
  final bool canResume;
  final bool canStop;
  final bool canSave;
  final bool canDiscard;
}

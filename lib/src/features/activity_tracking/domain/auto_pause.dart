import 'package:meta/meta.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/distance_calculator.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

AutoPauseResult classifyAutoPauseWindows(List<TrackingPoint> cleanedPoints) {
  final segments = _buildMotionSegments(cleanedPoints);
  if (segments.isEmpty) {
    return const AutoPauseResult(
      windows: [],
      totalMovingDuration: Duration.zero,
    );
  }

  final windows = <AutoPauseWindow>[];
  var currentState = AutoPauseState.moving;
  var currentWindowStart = segments.first.startTimestamp;
  DateTime? stopCandidateStart;
  var stopCandidateDuration = Duration.zero;

  void closeWindow(DateTime endTimestamp) {
    if (!endTimestamp.isAfter(currentWindowStart)) {
      return;
    }

    windows.add(
      AutoPauseWindow(
        state: currentState,
        startedAt: currentWindowStart,
        endedAt: endTimestamp,
      ),
    );
  }

  for (final segment in segments) {
    final observedMotion = _classifyObservedMotion(
      segment.speedMetersPerSecond,
    );

    if (currentState == AutoPauseState.moving) {
      if (observedMotion == _ObservedMotion.stopped) {
        stopCandidateStart ??= segment.startTimestamp;
        stopCandidateDuration += segment.duration;

        if (stopCandidateDuration >= minimumAutoPauseDuration) {
          final confirmedStopStart = stopCandidateStart;
          closeWindow(confirmedStopStart);
          currentState = AutoPauseState.stopped;
          currentWindowStart = confirmedStopStart;
          stopCandidateStart = null;
          stopCandidateDuration = Duration.zero;
        }
      } else {
        stopCandidateStart = null;
        stopCandidateDuration = Duration.zero;
      }

      continue;
    }

    if (observedMotion == _ObservedMotion.moving) {
      closeWindow(segment.startTimestamp);
      currentState = AutoPauseState.moving;
      currentWindowStart = segment.startTimestamp;
    }
  }

  closeWindow(segments.last.endTimestamp);

  final totalMovingDuration = windows
      .where((window) => window.state == AutoPauseState.moving)
      .fold(Duration.zero, (total, window) => total + window.duration);

  return AutoPauseResult(
    windows: List<AutoPauseWindow>.unmodifiable(windows),
    totalMovingDuration: totalMovingDuration,
  );
}

List<_MotionSegment> _buildMotionSegments(List<TrackingPoint> points) {
  if (points.length < 2) {
    return const [];
  }

  final segments = <_MotionSegment>[];

  for (var index = 1; index < points.length; index += 1) {
    final start = points[index - 1];
    final end = points[index];
    final duration = end.timestamp.difference(start.timestamp);
    if (duration <= Duration.zero) {
      continue;
    }

    final distanceMeters = calculateGeodesicDistanceMeters(
      start.coordinate,
      end.coordinate,
    );
    final speedMetersPerSecond =
        distanceMeters /
        (duration.inMilliseconds / Duration.millisecondsPerSecond);

    segments.add(
      _MotionSegment(
        startTimestamp: start.timestamp,
        endTimestamp: end.timestamp,
        duration: duration,
        speedMetersPerSecond: speedMetersPerSecond,
      ),
    );
  }

  return segments;
}

_ObservedMotion _classifyObservedMotion(double speedMetersPerSecond) {
  if (speedMetersPerSecond <= autoPauseStopSpeedThresholdMetersPerSecond) {
    return _ObservedMotion.stopped;
  }

  if (speedMetersPerSecond >= autoPauseResumeSpeedThresholdMetersPerSecond) {
    return _ObservedMotion.moving;
  }

  return _ObservedMotion.neutral;
}

@immutable
class _MotionSegment {
  const _MotionSegment({
    required this.startTimestamp,
    required this.endTimestamp,
    required this.duration,
    required this.speedMetersPerSecond,
  });

  final DateTime startTimestamp;
  final DateTime endTimestamp;
  final Duration duration;
  final double speedMetersPerSecond;
}

enum _ObservedMotion {
  moving,
  stopped,
  neutral,
}

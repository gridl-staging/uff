import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/auto_pause.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

const _sessionId = 77;
final _origin = DateTime.utc(2025);

TrackingPoint _pointAtMeters({
  required int seconds,
  required double metersFromOrigin,
  int? timestampSeconds,
}) {
  const metersPerDegreeAtEquator = earthRadiusMeters * (math.pi / 180);

  return TrackingPoint(
    sessionId: _sessionId,
    timestamp: _origin.add(Duration(seconds: timestampSeconds ?? seconds)),
    coordinate: GeoCoordinate(
      latitude: 0,
      longitude: metersFromOrigin / metersPerDegreeAtEquator,
    ),
  );
}

List<TrackingPoint> _buildTrackFromSegments(
  List<({int durationSeconds, double speedMetersPerSecond})> segments,
) {
  final points = <TrackingPoint>[
    _pointAtMeters(seconds: 0, metersFromOrigin: 0),
  ];

  var elapsedSeconds = 0;
  var metersFromOrigin = 0.0;

  for (final segment in segments) {
    elapsedSeconds += segment.durationSeconds;
    metersFromOrigin += segment.durationSeconds * segment.speedMetersPerSecond;

    points.add(
      _pointAtMeters(
        seconds: elapsedSeconds,
        metersFromOrigin: metersFromOrigin,
      ),
    );
  }

  return points;
}

void main() {
  group('classifyAutoPauseWindows edge cases', () {
    test(
      'returns empty windows for empty, single-point, and zero-duration data',
      () {
        final emptyResult = classifyAutoPauseWindows(const []);
        final singleResult = classifyAutoPauseWindows([
          _pointAtMeters(seconds: 0, metersFromOrigin: 0),
        ]);
        final zeroDurationResult = classifyAutoPauseWindows([
          _pointAtMeters(seconds: 0, metersFromOrigin: 0, timestampSeconds: 0),
          _pointAtMeters(seconds: 1, metersFromOrigin: 20, timestampSeconds: 0),
        ]);

        expect(emptyResult.windows, <AutoPauseWindow>[]);
        expect(emptyResult.totalMovingDuration, Duration.zero);
        expect(singleResult.windows, <AutoPauseWindow>[]);
        expect(singleResult.totalMovingDuration, Duration.zero);
        expect(zeroDurationResult.windows, <AutoPauseWindow>[]);
        expect(zeroDurationResult.totalMovingDuration, Duration.zero);
      },
    );

    test('enforces stop/resume thresholds and neutral-zone hysteresis', () {
      final stopBoundaryResult = classifyAutoPauseWindows(
        _buildTrackFromSegments([
          (durationSeconds: 60, speedMetersPerSecond: 0.5),
        ]),
      );
      final neutralBoundaryResult = classifyAutoPauseWindows(
        _buildTrackFromSegments([
          (durationSeconds: 60, speedMetersPerSecond: 0.501),
        ]),
      );
      final hysteresisResult = classifyAutoPauseWindows(
        _buildTrackFromSegments([
          (durationSeconds: 60, speedMetersPerSecond: 0.5),
          (durationSeconds: 30, speedMetersPerSecond: 0.999),
          (durationSeconds: 30, speedMetersPerSecond: 1.0),
        ]),
      );

      expect(stopBoundaryResult.windows.length, 1);
      expect(stopBoundaryResult.windows.single.state, AutoPauseState.stopped);
      expect(
        stopBoundaryResult.windows.single.duration,
        const Duration(seconds: 60),
      );
      expect(stopBoundaryResult.totalMovingDuration, Duration.zero);

      expect(neutralBoundaryResult.windows.length, 1);
      expect(neutralBoundaryResult.windows.single.state, AutoPauseState.moving);
      expect(
        neutralBoundaryResult.windows.single.duration,
        const Duration(seconds: 60),
      );

      expect(hysteresisResult.windows.length, 2);
      expect(hysteresisResult.windows[0].state, AutoPauseState.stopped);
      expect(hysteresisResult.windows[1].state, AutoPauseState.moving);
      expect(hysteresisResult.windows[0].duration, const Duration(seconds: 90));
      expect(hysteresisResult.windows[1].duration, const Duration(seconds: 30));
      expect(hysteresisResult.totalMovingDuration, const Duration(seconds: 30));
    });

    test('distinguishes 59s versus 60s stop duration with fast prefix', () {
      final fiftyNineSecondStopResult = classifyAutoPauseWindows(
        _buildTrackFromSegments([
          (durationSeconds: 10, speedMetersPerSecond: 1.0),
          (durationSeconds: 59, speedMetersPerSecond: 0.5),
        ]),
      );
      final sixtySecondStopResult = classifyAutoPauseWindows(
        _buildTrackFromSegments([
          (durationSeconds: 10, speedMetersPerSecond: 1.0),
          (durationSeconds: 60, speedMetersPerSecond: 0.5),
        ]),
      );

      expect(fiftyNineSecondStopResult.windows.length, 1);
      expect(
        fiftyNineSecondStopResult.windows.single.state,
        AutoPauseState.moving,
      );
      expect(
        fiftyNineSecondStopResult.windows.single.duration,
        const Duration(seconds: 69),
      );
      expect(
        fiftyNineSecondStopResult.totalMovingDuration,
        const Duration(seconds: 69),
      );

      expect(sixtySecondStopResult.windows.length, 2);
      expect(sixtySecondStopResult.windows[0].state, AutoPauseState.moving);
      expect(sixtySecondStopResult.windows[1].state, AutoPauseState.stopped);
      expect(
        sixtySecondStopResult.windows[0].duration,
        const Duration(seconds: 10),
      );
      expect(
        sixtySecondStopResult.windows[1].duration,
        const Duration(seconds: 60),
      );
      expect(
        sixtySecondStopResult.totalMovingDuration,
        const Duration(seconds: 10),
      );
    });

    test(
      'accumulates total moving time across multiple stop-resume cycles',
      () {
        final result = classifyAutoPauseWindows(
          _buildTrackFromSegments([
            (durationSeconds: 30, speedMetersPerSecond: 1.1),
            (durationSeconds: 60, speedMetersPerSecond: 0.49),
            (durationSeconds: 20, speedMetersPerSecond: 1.1),
            (durationSeconds: 60, speedMetersPerSecond: 0.49),
            (durationSeconds: 10, speedMetersPerSecond: 1.1),
          ]),
        );

        expect(result.windows.length, 5);
        expect(
          result.windows.map((window) => window.state).toList(growable: false),
          [
            AutoPauseState.moving,
            AutoPauseState.stopped,
            AutoPauseState.moving,
            AutoPauseState.stopped,
            AutoPauseState.moving,
          ],
        );
        expect(
          result.windows
              .map((window) => window.duration)
              .toList(growable: false),
          [
            const Duration(seconds: 30),
            const Duration(seconds: 60),
            const Duration(seconds: 20),
            const Duration(seconds: 60),
            const Duration(seconds: 10),
          ],
        );
        expect(result.totalMovingDuration, const Duration(seconds: 60));
      },
    );
  });
}

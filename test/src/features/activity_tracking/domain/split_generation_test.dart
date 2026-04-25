import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/split_generation.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

const _sessionId = 77;
final _origin = DateTime.utc(2025);

TrackingPoint _pointAtMeters({
  required int seconds,
  required double metersFromOrigin,
  int? timestampSeconds,
}) {
  const degreesPerRadian = 180 / math.pi;

  return TrackingPoint(
    sessionId: _sessionId,
    timestamp: _origin.add(Duration(seconds: timestampSeconds ?? seconds)),
    coordinate: GeoCoordinate(
      latitude: 0,
      longitude: (metersFromOrigin / earthRadiusMeters) * degreesPerRadian,
    ),
  );
}

void main() {
  group('generateSplits edge cases', () {
    test(
      'returns no splits for empty, single-point, and sub-unit distance',
      () {
        final emptySplits = generateSplits(
          cleanedPoints: const [],
          splitUnit: SplitUnit.kilometer,
        );
        final singlePointSplits = generateSplits(
          cleanedPoints: [_pointAtMeters(seconds: 0, metersFromOrigin: 0)],
          splitUnit: SplitUnit.kilometer,
        );
        final subSplitSplits = generateSplits(
          cleanedPoints: [
            _pointAtMeters(seconds: 0, metersFromOrigin: 0),
            _pointAtMeters(seconds: 300, metersFromOrigin: 500),
          ],
          splitUnit: SplitUnit.kilometer,
        );

        expect(emptySplits, <ActivitySplit>[]);
        expect(singlePointSplits, <ActivitySplit>[]);
        expect(subSplitSplits, <ActivitySplit>[]);
      },
    );

    test('handles exact and epsilon kilometer boundary behavior with pace', () {
      final exactBoundarySplits = generateSplits(
        cleanedPoints: [
          _pointAtMeters(seconds: 0, metersFromOrigin: 0),
          _pointAtMeters(seconds: 300, metersFromOrigin: 1000),
        ],
        splitUnit: SplitUnit.kilometer,
      );
      final epsilonBoundarySplits = generateSplits(
        cleanedPoints: [
          _pointAtMeters(seconds: 0, metersFromOrigin: 0),
          _pointAtMeters(seconds: 300, metersFromOrigin: 999.999),
        ],
        splitUnit: SplitUnit.kilometer,
      );
      final outsideEpsilonSplits = generateSplits(
        cleanedPoints: [
          _pointAtMeters(seconds: 0, metersFromOrigin: 0),
          _pointAtMeters(seconds: 300, metersFromOrigin: 999.998),
        ],
        splitUnit: SplitUnit.kilometer,
      );

      expect(exactBoundarySplits.length, 1);
      expect(exactBoundarySplits.single.cumulativeDistanceMeters, 1000);
      expect(
        exactBoundarySplits.single.splitDuration,
        const Duration(seconds: 300),
      );
      expect(exactBoundarySplits.single.pace, const Duration(seconds: 300));

      expect(epsilonBoundarySplits.length, 1);
      expect(
        epsilonBoundarySplits.single.cumulativeDistanceMeters,
        closeTo(1000, 1e-9),
      );
      expect(
        epsilonBoundarySplits.single.splitDuration,
        const Duration(seconds: 300),
      );
      expect(
        epsilonBoundarySplits.single.pace,
        const Duration(seconds: 300),
      );

      expect(outsideEpsilonSplits.length, 0);
    });

    test('creates a mile split at 1609.344 cumulative meters', () {
      final splits = generateSplits(
        cleanedPoints: [
          _pointAtMeters(seconds: 0, metersFromOrigin: 0),
          _pointAtMeters(seconds: 300, metersFromOrigin: 1610),
        ],
        splitUnit: SplitUnit.mile,
      );

      expect(splits.length, 1);
      expect(splits.single.unit, SplitUnit.mile);
      expect(splits.single.cumulativeDistanceMeters, metersPerMile);
    });

    test('skips zero-duration and zero-distance segments', () {
      final splits = generateSplits(
        cleanedPoints: [
          _pointAtMeters(seconds: 0, metersFromOrigin: 0),
          _pointAtMeters(seconds: 300, metersFromOrigin: 1000),
          _pointAtMeters(
            seconds: 301,
            timestampSeconds: 300,
            metersFromOrigin: 1500,
          ),
          _pointAtMeters(seconds: 360, metersFromOrigin: 1500),
          _pointAtMeters(seconds: 600, metersFromOrigin: 2500),
        ],
        splitUnit: SplitUnit.kilometer,
      );

      expect(splits.length, 2);
      expect(splits[0].index, 1);
      expect(splits[1].index, 2);
      expect(splits[0].splitDuration, const Duration(seconds: 300));
      expect(splits[1].splitDuration, const Duration(seconds: 300));
    });

    test(
      'produces 42 sequential kilometer splits for marathon-length input',
      () {
        final points = List<TrackingPoint>.generate(
          43,
          (index) => _pointAtMeters(
            seconds: index * 300,
            metersFromOrigin: index * 1000,
          ),
        );

        final splits = generateSplits(
          cleanedPoints: points,
          splitUnit: SplitUnit.kilometer,
        );

        expect(splits.length, 42);
        expect(
          splits.map((split) => split.index).toList(growable: false),
          List<int>.generate(42, (index) => index + 1),
        );
        expect(splits.last.cumulativeDistanceMeters, 42000);
      },
    );
  });
}

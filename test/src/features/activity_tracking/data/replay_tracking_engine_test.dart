import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/data/replay_tracking_engine.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_engine.dart';

List<TrackingPoint> _buildPoints(int count, {int sessionId = 0}) {
  final base = DateTime.utc(2026, 3, 15, 10);
  return List.generate(count, (i) {
    return TrackingPoint(
      sessionId: sessionId,
      timestamp: base.add(Duration(seconds: i * 5)),
      coordinate: GeoCoordinate(
        latitude: 60 + i * 0.0001,
        longitude: 24 + i * 0.0001,
      ),
      elevation: 10 + i * 0.1,
      accuracy: 5,
      speed: 3 + i * 0.01,
    );
  });
}

void main() {
  group('ReplayTrackingEngine lifecycle status', () {
    late ReplayTrackingEngine engine;

    setUp(() {
      engine = ReplayTrackingEngine(
        points: _buildPoints(10),
      );
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('start emits running on statusStream', () async {
      final statuses = <TrackingEngineStatus>[];
      engine.statusStream.listen(statuses.add);

      await engine.start(1);

      expect(statuses, contains(TrackingEngineStatus.running));
    });

    test('pause emits paused on statusStream', () async {
      final statuses = <TrackingEngineStatus>[];
      engine.statusStream.listen(statuses.add);

      await engine.start(1);
      await engine.pause();

      expect(statuses, [
        TrackingEngineStatus.running,
        TrackingEngineStatus.paused,
      ]);
    });

    test('resume emits running on statusStream', () async {
      final statuses = <TrackingEngineStatus>[];
      engine.statusStream.listen(statuses.add);

      await engine.start(1);
      await engine.pause();
      await engine.resume();

      expect(statuses, [
        TrackingEngineStatus.running,
        TrackingEngineStatus.paused,
        TrackingEngineStatus.running,
      ]);
    });

    test('resume after stop does not emit running', () async {
      final statuses = <TrackingEngineStatus>[];
      engine.statusStream.listen(statuses.add);

      await engine.start(1);
      await engine.stop();
      await engine.resume();

      expect(statuses, [
        TrackingEngineStatus.running,
        TrackingEngineStatus.stopped,
      ]);
    });

    test('stop emits stopped on statusStream', () async {
      final statuses = <TrackingEngineStatus>[];
      engine.statusStream.listen(statuses.add);

      await engine.start(1);
      await engine.stop();

      expect(statuses, [
        TrackingEngineStatus.running,
        TrackingEngineStatus.stopped,
      ]);
    });

    test('streams remain open after stop', () async {
      await engine.start(1);
      await engine.stop();

      var sampleDone = false;
      var statusDone = false;
      engine.sampleStream.listen(null, onDone: () => sampleDone = true);
      engine.statusStream.listen(null, onDone: () => statusDone = true);

      // Give microtasks a chance to flush.
      await Future<void>.delayed(Duration.zero);

      expect(sampleDone, isFalse, reason: 'sampleStream should stay open');
      expect(statusDone, isFalse, reason: 'statusStream should stay open');
    });

    test('dispose closes both streams', () async {
      var sampleDone = false;
      var statusDone = false;
      engine.sampleStream.listen(null, onDone: () => sampleDone = true);
      engine.statusStream.listen(null, onDone: () => statusDone = true);

      await engine.dispose();

      expect(sampleDone, isTrue, reason: 'sampleStream should close');
      expect(statusDone, isTrue, reason: 'statusStream should close');
    });

    test('throws StateError when used after dispose', () async {
      await engine.dispose();

      expect(() => engine.start(1), throwsStateError);
      expect(() => engine.pause(), throwsStateError);
      expect(() => engine.resume(), throwsStateError);
      expect(() => engine.stop(), throwsStateError);
    });
  });

  group('ReplayTrackingEngine timed emission', () {
    test('emits points at configured interval after start', () {
      fakeAsync((clock) {
        final engine = ReplayTrackingEngine(
          points: _buildPoints(5),
          emissionInterval: const Duration(milliseconds: 100),
        );
        final emitted = <TrackingPoint>[];
        engine.sampleStream.listen(emitted.add);

        engine.start(42);
        clock.flushMicrotasks();
        expect(emitted, isEmpty);

        clock.elapse(const Duration(milliseconds: 500));
        expect(emitted, hasLength(5));
        for (final point in emitted) {
          expect(point.sessionId, 42);
        }

        engine.dispose();
        clock.flushMicrotasks();
      });
    });

    test('pause suspends emission', () {
      fakeAsync((clock) {
        final engine = ReplayTrackingEngine(
          points: _buildPoints(10),
          emissionInterval: const Duration(milliseconds: 100),
        );
        final emitted = <TrackingPoint>[];
        engine.sampleStream.listen(emitted.add);

        engine.start(1);
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 300));
        expect(emitted, hasLength(3));

        engine.pause();
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 500));
        expect(emitted, hasLength(3));

        engine.dispose();
        clock.flushMicrotasks();
      });
    });

    test('resume continues from next unplayed point', () {
      fakeAsync((clock) {
        final points = _buildPoints(10);
        final engine = ReplayTrackingEngine(
          points: points,
          emissionInterval: const Duration(milliseconds: 100),
        );
        final emitted = <TrackingPoint>[];
        engine.sampleStream.listen(emitted.add);

        engine.start(1);
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 300));
        expect(emitted, hasLength(3));

        engine.pause();
        clock.flushMicrotasks();

        engine.resume();
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 200));
        expect(emitted, hasLength(5));
        expect(emitted[3].coordinate.latitude, points[3].coordinate.latitude);

        engine.dispose();
        clock.flushMicrotasks();
      });
    });

    test('stop halts emission permanently', () {
      fakeAsync((clock) {
        final engine = ReplayTrackingEngine(
          points: _buildPoints(10),
          emissionInterval: const Duration(milliseconds: 100),
        );
        final emitted = <TrackingPoint>[];
        engine.sampleStream.listen(emitted.add);

        engine.start(1);
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 300));
        expect(emitted, hasLength(3));

        engine.stop();
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 700));
        expect(emitted, hasLength(3));

        engine.dispose();
        clock.flushMicrotasks();
      });
    });

    test('stops emitting when all points exhausted', () {
      fakeAsync((clock) {
        final engine = ReplayTrackingEngine(
          points: _buildPoints(3),
          emissionInterval: const Duration(milliseconds: 100),
        );
        final emitted = <TrackingPoint>[];
        engine.sampleStream.listen(emitted.add);

        engine.start(1);
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 1000));
        expect(emitted, hasLength(3));

        engine.dispose();
        clock.flushMicrotasks();
      });
    });

    test('resume while already running does not create duplicate timers', () {
      fakeAsync((clock) {
        final engine = ReplayTrackingEngine(
          points: _buildPoints(10),
          emissionInterval: const Duration(milliseconds: 100),
        );
        final emitted = <TrackingPoint>[];
        engine.sampleStream.listen(emitted.add);

        engine.start(1);
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 200));
        expect(emitted, hasLength(2));

        engine.resume();
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 100));
        expect(emitted, hasLength(3));

        engine.dispose();
        clock.flushMicrotasks();
      });
    });

    test('start while already running restarts without duplicate timers', () {
      fakeAsync((clock) {
        final engine = ReplayTrackingEngine(
          points: _buildPoints(10),
          emissionInterval: const Duration(milliseconds: 100),
        );
        final emitted = <TrackingPoint>[];
        engine.sampleStream.listen(emitted.add);

        engine.start(1);
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 200));
        expect(emitted, hasLength(2));

        engine.start(1);
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 100));
        expect(emitted, hasLength(3));
        expect(emitted.last.timestamp, _buildPoints(1).single.timestamp);

        engine.dispose();
        clock.flushMicrotasks();
      });
    });
  });

  group('ReplayTrackingEngine recoverPersistedSamples', () {
    test('returns all points emitted so far', () {
      fakeAsync((clock) {
        final engine = ReplayTrackingEngine(
          points: _buildPoints(10),
          emissionInterval: const Duration(milliseconds: 100),
        );
        engine.sampleStream.listen((_) {});

        engine.start(1);
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 500));

        expect(engine.recoverPersistedSamples(1), completion(hasLength(5)));

        engine.dispose();
        clock.flushMicrotasks();
      });
    });

    test('filters by afterTimestamp', () {
      fakeAsync((clock) {
        final points = _buildPoints(10);
        final engine = ReplayTrackingEngine(
          points: points,
          emissionInterval: const Duration(milliseconds: 100),
        );
        engine.sampleStream.listen((_) {});

        engine.start(1);
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 500));

        // Points at indices 3 and 4 are after cutoff (index 2's timestamp).
        final cutoff = points[2].timestamp;
        final recovered = engine.recoverPersistedSamples(
          1,
          afterTimestamp: cutoff,
        );
        expect(recovered, completion(hasLength(2)));

        engine.dispose();
        clock.flushMicrotasks();
      });
    });

    test('returns empty list when no points emitted', () async {
      final engine = ReplayTrackingEngine(
        points: _buildPoints(5),
        emissionInterval: const Duration(milliseconds: 100),
      );

      final recovered = await engine.recoverPersistedSamples(1);
      expect(recovered, isEmpty);

      await engine.dispose();
    });

    test('returns empty list for non-matching session ID', () {
      fakeAsync((clock) {
        final engine = ReplayTrackingEngine(
          points: _buildPoints(10),
          emissionInterval: const Duration(milliseconds: 100),
        );
        engine.sampleStream.listen((_) {});

        engine.start(1);
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 300));

        expect(engine.recoverPersistedSamples(2), completion(isEmpty));

        engine.dispose();
        clock.flushMicrotasks();
      });
    });
  });
}

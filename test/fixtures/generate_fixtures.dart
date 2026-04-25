// Deterministic fixture generator for analytics accuracy testing.
//
// Produces GPS route fixtures with known characteristics and writes them
// as JSON to e2e_test/test_data/generated/. Also writes a shared
// expected-metrics manifest at e2e_test/test_data/expected_metrics.json.
//
// Run: dart run test/fixtures/generate_fixtures.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Constants matching production thresholds (not imported — fixture-intrinsic)
// ---------------------------------------------------------------------------

const double _earthRadiusMeters = 6371000;

/// Minimum per-point elevation delta for elevation gain counting.
const int _minElevationDeltaMeters = 1;

// ---------------------------------------------------------------------------
// Core data structures
// ---------------------------------------------------------------------------

/// A single generated GPS point with optional sensor data.
class FixturePoint {
  FixturePoint({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.elevation,
    required this.accuracy,
    required this.speed,
    this.heartRateBpm,
    this.cadenceRpm,
    this.powerWatts,
  });

  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double elevation;
  final double accuracy;
  final double speed;
  final int? heartRateBpm;
  final double? cadenceRpm;
  final int? powerWatts;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'sessionId': 0,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'latitude': _round(latitude, 7),
      'longitude': _round(longitude, 7),
      'elevation': _round(elevation, 2),
      'accuracy': _round(accuracy, 2),
      'speed': _round(speed, 3),
    };
    if (heartRateBpm != null) map['heartRateBpm'] = heartRateBpm;
    if (cadenceRpm != null) map['cadenceRpm'] = _round(cadenceRpm!, 1);
    if (powerWatts != null) map['powerWatts'] = powerWatts;
    return map;
  }
}

/// Fixture-intrinsic expected metrics (what the generator knows it built).
class FixtureExpectations {
  FixtureExpectations({
    required this.pointCount,
    this.plannedDistanceMeters,
    this.elapsedSeconds,
    this.movingSeconds,
    this.elevationGainMeters,
    this.intervalSegmentCount,
    this.pauseWindowCount,
    this.paceSecondsPerKm,
  });

  final int pointCount;
  final double? plannedDistanceMeters;
  final int? elapsedSeconds;
  final int? movingSeconds;
  final double? elevationGainMeters;
  final int? intervalSegmentCount;
  final int? pauseWindowCount;
  final double? paceSecondsPerKm;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'pointCount': pointCount};
    if (plannedDistanceMeters != null) {
      map['plannedDistanceMeters'] = _round(plannedDistanceMeters!, 1);
    }
    if (elapsedSeconds != null) map['elapsedSeconds'] = elapsedSeconds;
    if (movingSeconds != null) map['movingSeconds'] = movingSeconds;
    if (elevationGainMeters != null) {
      map['elevationGainMeters'] = _round(elevationGainMeters!, 1);
    }
    if (intervalSegmentCount != null) {
      map['intervalSegmentCount'] = intervalSegmentCount;
    }
    if (pauseWindowCount != null) {
      map['pauseWindowCount'] = pauseWindowCount;
    }
    if (paceSecondsPerKm != null) {
      map['paceSecondsPerKm'] = _round(paceSecondsPerKm!, 1);
    }
    return map;
  }
}

// ---------------------------------------------------------------------------
// Geo helpers
// ---------------------------------------------------------------------------

/// Advances a lat/lon by [distanceMeters] along [bearingDegrees].
({double lat, double lon}) advanceCoordinate(
  double lat,
  double lon,
  double distanceMeters,
  double bearingDegrees,
) {
  final latRad = _toRadians(lat);
  final lonRad = _toRadians(lon);
  final bearingRad = _toRadians(bearingDegrees);
  final angularDistance = distanceMeters / _earthRadiusMeters;

  final newLat = math.asin(
    math.sin(latRad) * math.cos(angularDistance) +
        math.cos(latRad) * math.sin(angularDistance) * math.cos(bearingRad),
  );
  final newLon =
      lonRad +
      math.atan2(
        math.sin(bearingRad) * math.sin(angularDistance) * math.cos(latRad),
        math.cos(angularDistance) - math.sin(latRad) * math.sin(newLat),
      );

  return (lat: _toDegrees(newLat), lon: _toDegrees(newLon));
}

double _toRadians(double degrees) => degrees * math.pi / 180;
double _toDegrees(double radians) => radians * 180 / math.pi;
double _round(double value, int decimals) {
  final factor = math.pow(10, decimals);
  return (value * factor).roundToDouble() / factor;
}

// ---------------------------------------------------------------------------
// Route generators
// ---------------------------------------------------------------------------

/// Generates a linear route at constant speed and bearing.
///
/// Returns points spaced [intervalSeconds] apart, traveling at [speedMs]
/// along [bearingDegrees] from the starting coordinate.
List<FixturePoint> generateLinearRoute({
  required DateTime startTime,
  required double startLat,
  required double startLon,
  required double speedMs,
  required int durationSeconds,
  int intervalSeconds = 5,
  double bearingDegrees = 0,
  double baseElevation = 15.0,
  double accuracy = 5.0,
  int? heartRateBpm,
  double? cadenceRpm,
  int? powerWatts,
}) {
  final points = <FixturePoint>[];
  var lat = startLat;
  var lon = startLon;

  for (var t = 0; t <= durationSeconds; t += intervalSeconds) {
    points.add(
      FixturePoint(
        timestamp: startTime.add(Duration(seconds: t)),
        latitude: lat,
        longitude: lon,
        elevation: baseElevation,
        accuracy: accuracy,
        speed: speedMs,
        heartRateBpm: heartRateBpm,
        cadenceRpm: cadenceRpm,
        powerWatts: powerWatts,
      ),
    );

    final advance = advanceCoordinate(
      lat,
      lon,
      speedMs * intervalSeconds,
      bearingDegrees,
    );
    lat = advance.lat;
    lon = advance.lon;
  }

  return points;
}

/// Generates a hilly route with sawtooth (linear ramp) elevation profile.
///
/// Creates [climbCount] climbs, each gaining [climbGainMeters]. Uses a
/// linear ascent/descent so per-point elevation deltas are consistent
/// and exceed [_minElevationDeltaMeters] on every ascending point.
///
/// Ascent occupies [ascentFraction] of each cycle (default 40%), descent
/// the remainder. Shorter ascent → steeper gradient → larger per-point
/// deltas, ensuring they clear the production 1.0m filter.
List<FixturePoint> generateHillyRoute({
  required DateTime startTime,
  required double startLat,
  required double startLon,
  required double speedMs,
  required int durationSeconds,
  int intervalSeconds = 5,
  double bearingDegrees = 45,
  double baseElevation = 20.0,
  int climbCount = 4,
  double climbGainMeters = 50.0,
  double ascentFraction = 0.4,
  double accuracy = 5.0,
}) {
  final points = <FixturePoint>[];
  var lat = startLat;
  var lon = startLon;

  final cycleDuration = durationSeconds / climbCount;
  final ascentDuration = cycleDuration * ascentFraction;

  for (var t = 0; t <= durationSeconds; t += intervalSeconds) {
    final cycleTime = t % cycleDuration;

    // Linear ramp: ascend for ascentFraction, descend for the rest.
    double elevationOffset;
    if (cycleTime <= ascentDuration) {
      // Ascending: linear from 0 to climbGainMeters.
      elevationOffset = (cycleTime / ascentDuration) * climbGainMeters;
    } else {
      // Descending: linear from climbGainMeters back to 0.
      final descentDuration = cycleDuration - ascentDuration;
      final descentTime = cycleTime - ascentDuration;
      elevationOffset = (1 - descentTime / descentDuration) * climbGainMeters;
    }

    points.add(
      FixturePoint(
        timestamp: startTime.add(Duration(seconds: t)),
        latitude: lat,
        longitude: lon,
        elevation: baseElevation + elevationOffset,
        accuracy: accuracy,
        speed: speedMs,
      ),
    );

    final advance = advanceCoordinate(
      lat,
      lon,
      speedMs * intervalSeconds,
      bearingDegrees,
    );
    lat = advance.lat;
    lon = advance.lon;
  }

  return points;
}

/// Generates an interval workout with alternating hard/easy segments.
///
/// Each segment lasts [segmentDurationSeconds] at either [hardSpeedMs]
/// or [easySpeedMs]. HR and pace vary by intensity.
List<FixturePoint> generateIntervalRoute({
  required DateTime startTime,
  required double startLat,
  required double startLon,
  required int segmentCount,
  int segmentDurationSeconds = 120,
  double hardSpeedMs = 4.17, // ~4:00/km
  double easySpeedMs = 2.78, // ~6:00/km
  int hardHrMin = 165,
  int hardHrMax = 175,
  int easyHrMin = 135,
  int easyHrMax = 145,
  int intervalSeconds = 5,
  double bearingDegrees = 90,
  double baseElevation = 15.0,
  double accuracy = 5.0,
}) {
  final points = <FixturePoint>[];
  var lat = startLat;
  var lon = startLon;
  final totalDuration = segmentCount * segmentDurationSeconds;

  for (var t = 0; t <= totalDuration; t += intervalSeconds) {
    final segmentIndex = t ~/ segmentDurationSeconds;
    final isHard = segmentIndex.isEven; // Start with hard.
    final speed = isHard ? hardSpeedMs : easySpeedMs;

    // Deterministic HR within range based on position within segment.
    final segmentProgress =
        (t % segmentDurationSeconds) / segmentDurationSeconds;
    final hrMin = isHard ? hardHrMin : easyHrMin;
    final hrMax = isHard ? hardHrMax : easyHrMax;
    final hr = hrMin + ((hrMax - hrMin) * segmentProgress).round();

    points.add(
      FixturePoint(
        timestamp: startTime.add(Duration(seconds: t)),
        latitude: lat,
        longitude: lon,
        elevation: baseElevation,
        accuracy: accuracy,
        speed: speed,
        heartRateBpm: hr,
      ),
    );

    final advance = advanceCoordinate(
      lat,
      lon,
      speed * intervalSeconds,
      bearingDegrees,
    );
    lat = advance.lat;
    lon = advance.lon;
  }

  return points;
}

/// Generates a route with stationary pause windows between moving segments.
///
/// Stationary segments use speed=0 and identical coordinates; moving
/// segments advance at [movingSpeedMs].
List<FixturePoint> generateAutoPauseRoute({
  required DateTime startTime,
  required double startLat,
  required double startLon,
  required List<PauseScheduleEntry> schedule,
  int intervalSeconds = 5,
  double movingSpeedMs = 3.0,
  double bearingDegrees = 180,
  double baseElevation = 15.0,
  double accuracy = 5.0,
}) {
  final points = <FixturePoint>[];
  var lat = startLat;
  var lon = startLon;
  var elapsed = 0;
  PauseScheduleEntry? lastEntry;

  for (final entry in schedule) {
    lastEntry = entry;
    for (var t = 0; t < entry.durationSeconds; t += intervalSeconds) {
      final speed = entry.isMoving ? movingSpeedMs : 0.0;
      points.add(
        FixturePoint(
          timestamp: startTime.add(Duration(seconds: elapsed + t)),
          latitude: lat,
          longitude: lon,
          elevation: baseElevation,
          accuracy: accuracy,
          speed: speed,
        ),
      );

      if (entry.isMoving) {
        final advance = advanceCoordinate(
          lat,
          lon,
          movingSpeedMs * intervalSeconds,
          bearingDegrees,
        );
        lat = advance.lat;
        lon = advance.lon;
      }
    }
    elapsed += entry.durationSeconds;
  }

  if (lastEntry != null) {
    // Add the terminal sample so the final schedule segment contributes its
    // full duration to downstream elapsed-time and auto-pause calculations.
    points.add(
      FixturePoint(
        timestamp: startTime.add(Duration(seconds: elapsed)),
        latitude: lat,
        longitude: lon,
        elevation: baseElevation,
        accuracy: accuracy,
        speed: lastEntry.isMoving ? movingSpeedMs : 0.0,
      ),
    );
  }

  return points;
}

class PauseScheduleEntry {
  const PauseScheduleEntry({
    required this.isMoving,
    required this.durationSeconds,
  });
  final bool isMoving;
  final int durationSeconds;
}

// ---------------------------------------------------------------------------
// Fixture-intrinsic metric calculations
// ---------------------------------------------------------------------------

/// Calculates total elevation gain using the same >= 1.0m delta filter
/// that production uses, but computed directly from generated points.
double calculateGeneratorElevationGain(List<FixturePoint> points) {
  double? previous;
  var gain = 0.0;
  for (final p in points) {
    if (previous != null) {
      final delta = p.elevation - previous;
      if (delta >= _minElevationDeltaMeters) {
        gain += delta;
      }
    }
    previous = p.elevation;
  }
  return gain;
}

/// Counts the moving duration from the schedule (not from speed analysis).
int calculateScheduleMovingSeconds(List<PauseScheduleEntry> schedule) {
  return schedule
      .where((e) => e.isMoving)
      .fold(0, (sum, e) => sum + e.durationSeconds);
}

/// Counts pause windows from the schedule.
int countSchedulePauseWindows(List<PauseScheduleEntry> schedule) {
  return schedule.where((e) => !e.isMoving).length;
}

// ---------------------------------------------------------------------------
// Fixture generation and file writing
// ---------------------------------------------------------------------------

void main() {
  final outputDir = Directory('e2e_test/test_data/generated')
    ..createSync(recursive: true);

  final manifest = <String, Map<String, dynamic>>{};
  final startTime = DateTime.utc(2026, 3, 20, 8);

  // -- 1) interval_workout.json --
  final intervalPoints = _generateIntervalWorkout(startTime);
  _writeFixture(outputDir, 'interval_workout.json', intervalPoints);
  manifest['interval_workout'] = _intervalExpectations(intervalPoints).toJson();

  // -- 2) hilly_10k.json --
  final hillyPoints = _generateHilly10k(startTime);
  _writeFixture(outputDir, 'hilly_10k.json', hillyPoints);
  manifest['hilly_10k'] = _hilly10kExpectations(hillyPoints).toJson();

  // -- 3) auto_pause_test.json --
  final autoPauseSchedule = _autoPauseSchedule();
  final autoPausePoints = _generateAutoPauseTest(startTime, autoPauseSchedule);
  _writeFixture(outputDir, 'auto_pause_test.json', autoPausePoints);
  manifest['auto_pause_test'] = _autoPauseExpectations(
    autoPausePoints,
    autoPauseSchedule,
  ).toJson();

  // -- 4) long_easy_run.json --
  final longEasyPoints = _generateLongEasyRun(startTime);
  _writeFixture(outputDir, 'long_easy_run.json', longEasyPoints);
  manifest['long_easy_run'] = _longEasyRunExpectations(longEasyPoints).toJson();

  // -- 5k_run expectations (existing fixture, no generation needed) --
  manifest['5k_run'] = {
    'pointCount': 620,
    'elapsedSeconds': 3095,
    // No sensor data, no elevation gain assertions — it's a flat reference.
  };

  // Write shared expected-metrics manifest.
  File('e2e_test/test_data/expected_metrics.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );

  // Summary.
  stdout.writeln('Generated fixtures:');
  for (final entry in manifest.entries) {
    stdout.writeln('  ${entry.key}: ${entry.value['pointCount']} points');
  }
  stdout.writeln('Manifest: e2e_test/test_data/expected_metrics.json');
}

// ---------------------------------------------------------------------------
// Individual fixture builders
// ---------------------------------------------------------------------------

List<FixturePoint> _generateIntervalWorkout(DateTime startTime) {
  // 11 segments × 120s = 1320s (~22min). Hard/easy alternate starting hard.
  return generateIntervalRoute(
    startTime: startTime,
    startLat: 60.17,
    startLon: 24.94,
    segmentCount: 11,
  );
}

FixtureExpectations _intervalExpectations(List<FixturePoint> points) {
  final elapsed = points.last.timestamp.difference(points.first.timestamp);
  // 11 segments: hard-easy-hard-easy-hard-easy-hard-easy-hard-easy-hard
  // 6 hard (even indices) + 5 easy, each 120s.
  // Overall pace from weighted average speed across all segments.
  const hardSpeed = 4.17;
  const easySpeed = 2.78;
  const segDuration = 120;
  const hardDistance = 6 * segDuration * hardSpeed;
  const easyDistance = 5 * segDuration * easySpeed;
  const totalDistance = hardDistance + easyDistance;
  final overallPace = elapsed.inSeconds / (totalDistance / 1000);
  return FixtureExpectations(
    pointCount: points.length,
    elapsedSeconds: elapsed.inSeconds,
    movingSeconds: elapsed.inSeconds,
    intervalSegmentCount: 11,
    paceSecondsPerKm: overallPace,
  );
}

List<FixturePoint> _generateHilly10k(DateTime startTime) {
  // ~10km at ~4.17 m/s (~4:00/km) ≈ 2400s (40min).
  // 4 climbs × 80m gain each = 320m raw elevation gain.
  // With 40% ascent fraction: ascent = 240s/climb → 48 points → delta = 1.67m.
  // Every ascending point clears the 1.0m filter → ~320m qualifying gain.
  const speedMs = 4.17;
  const durationSeconds = 2400;
  return generateHillyRoute(
    startTime: startTime,
    startLat: 60.17,
    startLon: 24.94,
    speedMs: speedMs,
    durationSeconds: durationSeconds,
    climbGainMeters: 80,
  );
}

FixtureExpectations _hilly10kExpectations(List<FixturePoint> points) {
  final elapsed = points.last.timestamp.difference(points.first.timestamp);
  final elevGain = calculateGeneratorElevationGain(points);
  return FixtureExpectations(
    pointCount: points.length,
    plannedDistanceMeters: 4.17 * 2400,
    elapsedSeconds: elapsed.inSeconds,
    movingSeconds: elapsed.inSeconds,
    elevationGainMeters: elevGain,
  );
}

List<PauseScheduleEntry> _autoPauseSchedule() {
  // Move 3min → pause 90s → move 5min → pause 75s → move 2min.
  return const [
    PauseScheduleEntry(isMoving: true, durationSeconds: 180),
    PauseScheduleEntry(isMoving: false, durationSeconds: 90),
    PauseScheduleEntry(isMoving: true, durationSeconds: 300),
    PauseScheduleEntry(isMoving: false, durationSeconds: 75),
    PauseScheduleEntry(isMoving: true, durationSeconds: 120),
  ];
}

List<FixturePoint> _generateAutoPauseTest(
  DateTime startTime,
  List<PauseScheduleEntry> schedule,
) {
  return generateAutoPauseRoute(
    startTime: startTime,
    startLat: 60.17,
    startLon: 24.94,
    schedule: schedule,
  );
}

FixtureExpectations _autoPauseExpectations(
  List<FixturePoint> points,
  List<PauseScheduleEntry> schedule,
) {
  final elapsed = points.last.timestamp.difference(points.first.timestamp);
  final movingSec = calculateScheduleMovingSeconds(schedule);
  final pauseWindows = countSchedulePauseWindows(schedule);
  return FixtureExpectations(
    pointCount: points.length,
    elapsedSeconds: elapsed.inSeconds,
    movingSeconds: movingSec,
    pauseWindowCount: pauseWindows,
  );
}

List<FixturePoint> _generateLongEasyRun(DateTime startTime) {
  // ~60min at ~3.03 m/s (~5:30/km) with HR ~140bpm and power ~200W.
  const speedMs = 3.03;
  const durationSeconds = 3600;
  return generateLinearRoute(
    startTime: startTime,
    startLat: 60.17,
    startLon: 24.94,
    speedMs: speedMs,
    durationSeconds: durationSeconds,
    heartRateBpm: 140,
    cadenceRpm: 85,
    powerWatts: 200,
  );
}

FixtureExpectations _longEasyRunExpectations(List<FixturePoint> points) {
  final elapsed = points.last.timestamp.difference(points.first.timestamp);
  return FixtureExpectations(
    pointCount: points.length,
    plannedDistanceMeters: 3.03 * 3600,
    elapsedSeconds: elapsed.inSeconds,
    movingSeconds: elapsed.inSeconds,
    paceSecondsPerKm: 1000 / 3.03,
    // Sensor data present but expectations for TSS/PMC deferred to later stages.
  );
}

// ---------------------------------------------------------------------------
// File I/O
// ---------------------------------------------------------------------------

void _writeFixture(
  Directory outputDir,
  String filename,
  List<FixturePoint> points,
) {
  final file = File('${outputDir.path}/$filename');
  final json = points.map((p) => p.toJson()).toList();
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  stdout.writeln('  Wrote ${file.path} (${points.length} points)');
}

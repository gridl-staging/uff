import 'dart:typed_data';

import 'package:fit_tool/fit_tool.dart';

/// Known test coordinates for verifying semicircle conversion accuracy.
/// These are set in degrees — fit_tool handles the semicircle encoding
/// internally, so the round-trip verifies the conversion pipeline.
const testLatitude = 40.712800;
const testLongitude = -74.006000;

/// FIT epoch: seconds since 1989-12-31T00:00:00 UTC.
/// fit_tool uses milliseconds since Unix epoch internally.
final int fitBaseTimestamp = DateTime.utc(
  2024,
  1,
  1,
  12,
).millisecondsSinceEpoch;

/// Default point count used by import stress tests.
const int largeFitPointCount = 1200;

typedef FitTestIntOverride = int? Function(int index, int defaultValue);
typedef FitTestDoubleOverride =
    double? Function(int index, double defaultValue);

/// Builds a valid FIT binary containing the specified record messages
/// and an optional session message with sport type.
Uint8List buildFitBytes({
  required List<FitTestRecord> records,
  Sport? sport,
}) {
  final builder = FitFileBuilder();

  final fileIdMessage = FileIdMessage()
    ..type = FileType.activity
    ..manufacturer =
        1 // Garmin
    ..product = 0
    ..serialNumber = 12345;
  builder.add(fileIdMessage);

  for (final record in records) {
    final recordMessage = RecordMessage()..timestamp = record.timestampMs;

    if (record.latitude != null) {
      recordMessage.positionLat = record.latitude;
    }
    if (record.longitude != null) {
      recordMessage.positionLong = record.longitude;
    }
    if (record.altitude != null) {
      recordMessage.altitude = record.altitude;
    }
    if (record.enhancedAltitude != null) {
      recordMessage.enhancedAltitude = record.enhancedAltitude;
    }
    if (record.speed != null) {
      recordMessage.speed = record.speed;
    }
    if (record.enhancedSpeed != null) {
      recordMessage.enhancedSpeed = record.enhancedSpeed;
    }
    if (record.heartRate != null) {
      recordMessage.heartRate = record.heartRate;
    }
    if (record.cadence != null) {
      recordMessage.cadence = record.cadence;
    }
    if (record.cadence256 != null) {
      recordMessage.cadence256 = record.cadence256;
    }
    if (record.fractionalCadence != null) {
      recordMessage.fractionalCadence = record.fractionalCadence;
    }
    if (record.power != null) {
      recordMessage.power = record.power;
    }
    builder.add(recordMessage);
  }

  if (sport != null) {
    final sessionMessage = SessionMessage()
      ..sport = sport
      ..timestamp = records.last.timestampMs;
    builder.add(sessionMessage);
  }

  return builder.build().toBytes();
}

/// Builds deterministic FIT records that remain valid through cleanup.
///
/// The per-point movement and timestamp spacing produce plausible speeds well
/// below the cleanup outlier threshold, so all generated records are retained.
List<FitTestRecord> buildDeterministicFitRecords({
  int pointCount = largeFitPointCount,
  int startTimestampMs = 0,
  double startLatitude = testLatitude,
  double startLongitude = testLongitude,
  int spacingSeconds = 5,
  Map<int, int>? timestampMsOverrides,
  FitTestIntOverride? timestampMsForIndex,
  Map<int, int>? heartRateOverrides,
  FitTestIntOverride? heartRateForIndex,
  Map<int, int>? powerOverrides,
  FitTestIntOverride? powerForIndex,
  Map<int, double>? enhancedAltitudeOverrides,
  FitTestDoubleOverride? enhancedAltitudeForIndex,
}) {
  final resolvedStartTimestamp = startTimestampMs == 0
      ? fitBaseTimestamp
      : startTimestampMs;
  return List.generate(pointCount, (index) {
    final defaultTimestampMs =
        resolvedStartTimestamp + (index * spacingSeconds * 1000);
    final defaultEnhancedAltitudeMeters = (10 + (index % 40)).toDouble();
    final defaultHeartRate = 130 + (index % 35);
    final defaultPower = 180 + (index % 120);

    return FitTestRecord(
      timestampMs:
          timestampMsOverrides?[index] ??
          timestampMsForIndex?.call(index, defaultTimestampMs) ??
          defaultTimestampMs,
      latitude: startLatitude + (index * 0.00005),
      longitude: startLongitude + (index * 0.00005),
      enhancedAltitude:
          enhancedAltitudeOverrides?[index] ??
          enhancedAltitudeForIndex?.call(
            index,
            defaultEnhancedAltitudeMeters,
          ) ??
          defaultEnhancedAltitudeMeters,
      heartRate:
          heartRateOverrides?[index] ??
          heartRateForIndex?.call(index, defaultHeartRate) ??
          defaultHeartRate,
      cadence: 80 + (index % 20),
      power:
          powerOverrides?[index] ??
          powerForIndex?.call(index, defaultPower) ??
          defaultPower,
    );
  });
}

/// Convenience helper for deterministic high-volume FIT fixtures.
Uint8List buildLargeDeterministicFitBytes({
  int pointCount = largeFitPointCount,
  Sport sport = Sport.running,
}) {
  return buildFitBytes(
    records: buildDeterministicFitRecords(pointCount: pointCount),
    sport: sport,
  );
}

/// A test helper record for building FIT test fixtures.
class FitTestRecord {
  const FitTestRecord({
    required this.timestampMs,
    this.latitude,
    this.longitude,
    this.altitude,
    this.enhancedAltitude,
    this.speed,
    this.enhancedSpeed,
    this.heartRate,
    this.cadence,
    this.cadence256,
    this.fractionalCadence,
    this.power,
  });

  final int timestampMs;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final double? enhancedAltitude;
  final double? speed;
  final double? enhancedSpeed;
  final int? heartRate;
  final int? cadence;
  final double? cadence256;
  final double? fractionalCadence;
  final int? power;
}

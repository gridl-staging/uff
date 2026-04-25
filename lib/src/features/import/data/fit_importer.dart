import 'dart:typed_data';

import 'package:fit_tool/fit_tool.dart';
import 'package:uff/src/features/import/domain/imported_activity.dart';

/// Parses Garmin FIT binary files into [ParsedActivityData].
///
/// Extracts GPS records and session metadata. Coordinate conversion
/// (semicircle → degree) and timestamp conversion (FIT epoch → DateTime)
/// are handled by the `fit_tool` library internally.
class FitImporter {
  FitImporter._();

  static ParsedActivityData parse(Uint8List bytes) {
    final FitFile fitFile;
    try {
      fitFile = FitFile.fromBytes(bytes);
    } on Object {
      throw const FormatException(
        'Failed to decode FIT file: file is truncated or corrupted',
      );
    }

    final points = <ImportedPoint>[];
    Sport? sport;

    for (final record in fitFile.records) {
      final message = record.message;

      if (message is RecordMessage) {
        final point = _extractPoint(message);
        if (point != null) {
          points.add(point);
        }
      } else if (message is SessionMessage) {
        sport ??= message.sport;
      }
    }

    if (points.isEmpty) {
      throw const FormatException(
        'FIT file contains no GPS-bearing record messages',
      );
    }

    return ParsedActivityData(
      sportType: _mapSport(sport),
      points: points,
    );
  }

  static ImportedPoint? _extractPoint(RecordMessage message) {
    final lat = message.positionLat;
    final lon = message.positionLong;
    if (lat == null || lon == null) {
      return null;
    }

    final timestampMs = message.timestamp;
    if (timestampMs == null) {
      return null;
    }

    return ImportedPoint(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true),
      elevation: message.enhancedAltitude ?? message.altitude,
      speed: message.enhancedSpeed ?? message.speed,
      heartRateBpm: message.heartRate,
      cadenceRpm: _resolveCadence(message),
      powerWatts: message.power,
    );
  }

  static double? _resolveCadence(RecordMessage message) {
    final cadence256 = message.cadence256;
    if (cadence256 != null) {
      return cadence256;
    }

    final integer = message.cadence;
    final fractional = message.fractionalCadence;
    if (integer != null && fractional != null) {
      return integer + fractional;
    }
    if (integer != null) {
      return integer.toDouble();
    }

    return null;
  }

  static String _mapSport(Sport? sport) {
    return switch (sport) {
      Sport.running => 'run',
      Sport.cycling => 'ride',
      Sport.swimming => 'swim',
      Sport.walking => 'walk',
      Sport.hiking => 'hike',
      _ => 'workout',
    };
  }
}

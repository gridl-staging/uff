import 'package:uff/src/features/import/domain/imported_activity.dart';
import 'package:xml/xml.dart';

/// Parses GPX XML files into [ParsedActivityData].
///
/// Uses the `xml` package directly (instead of geoxml) to correctly handle
/// nested Garmin `TrackPointExtension` elements for heart rate, cadence,
/// and power extraction.
class GpxImporter {
  GpxImporter._();

  static ParsedActivityData parse(String gpxContent) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(gpxContent);
    } on Object {
      throw const FormatException('Failed to parse GPX XML');
    }

    final gpxElement = document.rootElement;
    final points = <ImportedPoint>[];
    String? title;
    String? sportType;

    for (final trk in gpxElement.findAllElements('trk')) {
      title ??= _textOf(trk, 'name');
      sportType ??= _textOf(trk, 'type');

      for (final trkseg in trk.findAllElements('trkseg')) {
        for (final trkpt in trkseg.findElements('trkpt')) {
          final point = _extractPoint(trkpt);
          if (point != null) {
            points.add(point);
          }
        }
      }
    }

    if (points.isEmpty) {
      throw const FormatException(
        'GPX file contains no track points with valid timestamps',
      );
    }

    return ParsedActivityData(
      sportType: _mapSportType(sportType),
      title: title,
      points: points,
    );
  }

  static ImportedPoint? _extractPoint(XmlElement trkpt) {
    final lat = double.tryParse(trkpt.getAttribute('lat') ?? '');
    final lon = double.tryParse(trkpt.getAttribute('lon') ?? '');
    if (lat == null || lon == null) {
      return null;
    }

    final timeText = _textOf(trkpt, 'time');
    if (timeText == null) {
      return null;
    }
    final timestamp = DateTime.tryParse(timeText);
    if (timestamp == null) {
      return null;
    }

    final eleText = _textOf(trkpt, 'ele');
    final elevation = eleText != null ? double.tryParse(eleText) : null;

    final extensions = _parseGarminExtensions(trkpt);

    return ImportedPoint(
      latitude: lat,
      longitude: lon,
      timestamp: timestamp,
      elevation: elevation,
      heartRateBpm: extensions.heartRate,
      cadenceRpm: extensions.cadence,
      powerWatts: extensions.power,
    );
  }

  static _GarminExtensions _parseGarminExtensions(XmlElement trkpt) {
    for (final ext in trkpt.findAllElements('extensions')) {
      // Look for TrackPointExtension in any namespace
      for (final tpe in ext.children.whereType<XmlElement>()) {
        if (tpe.localName.contains('TrackPointExtension')) {
          return _GarminExtensions(
            heartRate: _intFromChildElement(tpe, 'hr'),
            cadence: _intToCadence(tpe, 'cad'),
            power: _intFromChildElement(tpe, 'power'),
          );
        }
      }
    }
    return const _GarminExtensions();
  }

  static int? _intFromChildElement(XmlElement parent, String localName) {
    for (final child in parent.children.whereType<XmlElement>()) {
      if (child.localName == localName) {
        return int.tryParse(child.innerText);
      }
    }
    return null;
  }

  static double? _intToCadence(XmlElement parent, String localName) {
    final value = _intFromChildElement(parent, localName);
    return value?.toDouble();
  }

  static String? _textOf(XmlElement parent, String elementName) {
    final elements = parent.findElements(elementName);
    if (elements.isEmpty) {
      return null;
    }
    final text = elements.first.innerText.trim();
    return text.isEmpty ? null : text;
  }

  static String _mapSportType(String? gpxType) {
    if (gpxType == null) {
      return 'workout';
    }
    return switch (gpxType.toLowerCase()) {
      'running' => 'run',
      'run' => 'run',
      'cycling' => 'ride',
      'ride' => 'ride',
      'biking' => 'ride',
      'swimming' => 'swim',
      'walking' => 'walk',
      'walk' => 'walk',
      'hiking' => 'hike',
      'hike' => 'hike',
      _ => 'workout',
    };
  }
}

class _GarminExtensions {
  const _GarminExtensions({this.heartRate, this.cadence, this.power});

  final int? heartRate;
  final double? cadence;
  final int? power;
}

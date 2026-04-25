import 'package:uff/src/features/maps/data/route_polyline.dart';

// Route previews decode on the UI path, so unexpectedly large route strings
// fail closed to the placeholder renderer instead of spending unbounded work.
const _maxEncodedPolylineLength = 8192;
const _maxDecodedPolylinePoints = 4096;

/// Decodes a Google encoded polyline string into route points.
///
/// Returns an empty list for null, empty, or malformed input.
List<RoutePoint> decodePolyline(String? encoded) {
  if (encoded == null ||
      encoded.isEmpty ||
      encoded.length > _maxEncodedPolylineLength) {
    return const <RoutePoint>[];
  }

  final points = <RoutePoint>[];
  var index = 0;
  var latitude = 0;
  var longitude = 0;

  while (index < encoded.length) {
    final latitudeStep = _decodeStep(encoded, index);
    if (latitudeStep == null) {
      return const <RoutePoint>[];
    }
    index = latitudeStep.nextIndex;
    latitude += latitudeStep.delta;

    final longitudeStep = _decodeStep(encoded, index);
    if (longitudeStep == null) {
      return const <RoutePoint>[];
    }
    index = longitudeStep.nextIndex;
    longitude += longitudeStep.delta;

    points.add(
      RoutePoint(
        latitude: latitude / 1e5,
        longitude: longitude / 1e5,
      ),
    );
    if (points.length > _maxDecodedPolylinePoints) {
      return const <RoutePoint>[];
    }
  }

  return points;
}

_PolylineStep? _decodeStep(String encoded, int startIndex) {
  var index = startIndex;
  var shift = 0;
  var result = 0;

  while (true) {
    if (index >= encoded.length) {
      return null;
    }

    final chunk = encoded.codeUnitAt(index) - 63;
    if (chunk < 0 || chunk > 63) {
      return null;
    }

    result |= (chunk & 0x1F) << shift;
    shift += 5;
    index++;

    if (chunk < 0x20) {
      break;
    }

    // Prevent malformed input from overflowing shifts.
    if (shift > 30) {
      return null;
    }
  }

  final delta = (result & 1) == 1 ? ~(result >> 1) : (result >> 1);
  return _PolylineStep(delta: delta, nextIndex: index);
}

class _PolylineStep {
  const _PolylineStep({
    required this.delta,
    required this.nextIndex,
  });

  final int delta;
  final int nextIndex;
}

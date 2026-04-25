import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:meta/meta.dart';

const _defaultPolylineColor = 0xFFFF5A1F;

/// NOTE(stuart): Document RoutePoint.
@immutable
class RoutePoint {
  const RoutePoint({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RoutePoint &&
            other.latitude == latitude &&
            other.longitude == longitude;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

class RoutePolylineStyle {
  const RoutePolylineStyle({
    this.lineColorArgb = _defaultPolylineColor,
    this.lineWidth = 3.5,
    this.lineCap = LineCap.ROUND,
    this.lineJoin = LineJoin.ROUND,
  });

  final int lineColorArgb;
  final double lineWidth;
  final LineCap lineCap;
  final LineJoin lineJoin;
}

/// NOTE(stuart): Document RoutePolyline.
class RoutePolyline {
  const RoutePolyline._();

  static const defaultStyle = RoutePolylineStyle();

  static Map<String, Object?>? toGeoJsonFeature(List<RoutePoint> points) {
    if (points.length < 2) {
      return null;
    }

    final coordinates = points
        .map((point) => <double>[point.longitude, point.latitude])
        .toList(growable: false);

    return <String, Object?>{
      'type': 'Feature',
      'geometry': <String, Object?>{
        'type': 'LineString',
        'coordinates': coordinates,
      },
      'properties': <String, Object?>{},
    };
  }

  static Future<PolylineAnnotation?> addToMap({
    required MapboxMap mapboxMap,
    required List<RoutePoint> points,
    RoutePolylineStyle style = defaultStyle,
  }) async {
    if (points.length < 2) {
      return null;
    }

    final annotationManager = await mapboxMap.annotations
        .createPolylineAnnotationManager();
    return addToManager(
      annotationManager: annotationManager,
      points: points,
      style: style,
    );
  }

  static Future<PolylineAnnotation?> addToManager({
    required PolylineAnnotationManager annotationManager,
    required List<RoutePoint> points,
    RoutePolylineStyle style = defaultStyle,
  }) async {
    if (points.length < 2) {
      return null;
    }

    await annotationManager.setLineCap(style.lineCap);
    await annotationManager.setLineJoin(style.lineJoin);

    return annotationManager.create(
      PolylineAnnotationOptions(
        geometry: _buildLineString(points),
        lineColor: style.lineColorArgb,
        lineJoin: style.lineJoin,
        lineWidth: style.lineWidth,
      ),
    );
  }

  static LineString _buildLineString(List<RoutePoint> points) {
    final coordinates = points
        .map((point) => Position(point.longitude, point.latitude))
        .toList(growable: false);
    return LineString(coordinates: coordinates);
  }
}

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uff/src/features/maps/data/polyline_codec.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';

/// Sizing presets for static route previews used across social screens.
enum StaticRoutePreviewSizePreset {
  feed,
  detail,
  compact,
}

/// Deterministic static route renderer for feed/detail/profile contexts.
///
/// This widget never uses a live map. It decodes an encoded polyline and draws
/// a route path with [CustomPainter] for fast scrolling performance.
class StaticRoutePreview extends StatelessWidget {
  const StaticRoutePreview({
    this.polylineEncoded,
    this.routePoints,
    this.preset = StaticRoutePreviewSizePreset.feed,
    super.key,
  });

  static const previewKey = Key('static_route_preview');
  static const placeholderKey = Key('static_route_preview_placeholder');
  static const paintKey = Key('static_route_preview_paint');

  static const feedBoxKey = Key('static_route_preview_feed_box');
  static const detailAspectRatioKey = Key(
    'static_route_preview_detail_aspect_ratio',
  );
  static const compactBoxKey = Key('static_route_preview_compact_box');

  final String? polylineEncoded;
  final List<RoutePoint>? routePoints;
  final StaticRoutePreviewSizePreset preset;

  @override
  Widget build(BuildContext context) {
    // When explicit route points are provided, never reconstruct from polyline.
    final points = routePoints ?? decodePolyline(polylineEncoded);
    final hasRenderableRoute = points.length >= 2;
    final routeBody = hasRenderableRoute
        ? CustomPaint(
            key: paintKey,
            painter: _StaticRoutePainter(points: points),
            child: const SizedBox.expand(),
          )
        : const DecoratedBox(
            key: placeholderKey,
            decoration: BoxDecoration(
              color: Color(0xFFD6D6D6),
            ),
            child: SizedBox.expand(),
          );

    final shell = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: const Color(0xFFE8E8E8),
        child: routeBody,
      ),
    );

    final sizedPreview = switch (preset) {
      StaticRoutePreviewSizePreset.feed => SizedBox(
        key: feedBoxKey,
        height: 150,
        width: double.infinity,
        child: shell,
      ),
      StaticRoutePreviewSizePreset.detail => AspectRatio(
        key: detailAspectRatioKey,
        aspectRatio: 16 / 9,
        child: shell,
      ),
      StaticRoutePreviewSizePreset.compact => SizedBox(
        key: compactBoxKey,
        width: 96,
        height: 72,
        child: shell,
      ),
    };

    return KeyedSubtree(
      key: previewKey,
      child: sizedPreview,
    );
  }
}

/// TODO: Document _StaticRoutePainter.
class _StaticRoutePainter extends CustomPainter {
  const _StaticRoutePainter({required this.points});

  final List<RoutePoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.isEmpty) {
      return;
    }

    const padding = 8.0;
    final drawableWidth = math.max(0, size.width - padding * 2);
    final drawableHeight = math.max(0, size.height - padding * 2);
    if (drawableWidth == 0 || drawableHeight == 0) {
      return;
    }

    final bounds = _RouteBounds.fromPoints(points);
    final latitudeSpan = bounds.latitudeSpan == 0 ? 1 : bounds.latitudeSpan;
    final longitudeSpan = bounds.longitudeSpan == 0 ? 1 : bounds.longitudeSpan;

    final xScale = drawableWidth / longitudeSpan;
    final yScale = drawableHeight / latitudeSpan;
    final scale = math.min(xScale, yScale);

    final renderedWidth = longitudeSpan * scale;
    final renderedHeight = latitudeSpan * scale;
    final xOffset = (size.width - renderedWidth) / 2;
    final yOffset = (size.height - renderedHeight) / 2;

    final routePath = Path();
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final x = xOffset + (point.longitude - bounds.minLongitude) * scale;
      // Invert y so northern latitudes render toward the top of the box.
      final y =
          size.height -
          (yOffset + (point.latitude - bounds.minLatitude) * scale);

      if (index == 0) {
        routePath.moveTo(x, y);
      } else {
        routePath.lineTo(x, y);
      }
    }

    final routePaint = Paint()
      ..color = Color(RoutePolyline.defaultStyle.lineColorArgb)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.drawPath(routePath, routePaint);
  }

  @override
  bool shouldRepaint(covariant _StaticRoutePainter oldDelegate) {
    return !listEquals(oldDelegate.points, points);
  }
}

/// TODO: Document _RouteBounds.
class _RouteBounds {
  const _RouteBounds({
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
  });

  factory _RouteBounds.fromPoints(List<RoutePoint> points) {
    var minLatitude = points.first.latitude;
    var maxLatitude = points.first.latitude;
    var minLongitude = points.first.longitude;
    var maxLongitude = points.first.longitude;

    for (var index = 1; index < points.length; index++) {
      final point = points[index];
      minLatitude = math.min(minLatitude, point.latitude);
      maxLatitude = math.max(maxLatitude, point.latitude);
      minLongitude = math.min(minLongitude, point.longitude);
      maxLongitude = math.max(maxLongitude, point.longitude);
    }

    return _RouteBounds(
      minLatitude: minLatitude,
      maxLatitude: maxLatitude,
      minLongitude: minLongitude,
      maxLongitude: maxLongitude,
    );
  }

  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  double get latitudeSpan => maxLatitude - minLatitude;
  double get longitudeSpan => maxLongitude - minLongitude;
}

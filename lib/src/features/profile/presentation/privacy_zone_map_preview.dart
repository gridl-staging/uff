import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:uff/src/features/maps/data/mapbox_channel_errors.dart';

const _defaultCameraLatitude = 40.7128;
const _defaultCameraLongitude = -74.0060;
const _defaultCameraZoom = 14.0;
const _earthRadiusMeters = 6371000.0;
const _zonePolygonSegments = 64;
const _zoneFillColorArgb = 0x335A8DEE;
const _zoneOutlineColorArgb = 0xFF1F5FBF;

/// Interactive map surface used to place and size a privacy zone.
class PrivacyZoneMapPreview extends StatefulWidget {
  const PrivacyZoneMapPreview({
    required this.radiusMeters,
    this.latitude,
    this.longitude,
    this.onCoordinateSelected,
    super.key,
  });

  static const mapSurfaceKey = Key('privacy_zone_map_surface');
  static const emptyPromptKey = Key('privacy_zone_map_empty_prompt');
  static const centerSummaryKey = Key('privacy_zone_map_center_summary');

  final double? latitude;
  final double? longitude;
  final int radiusMeters;

  /// Test and UI seam for every map placement gesture.
  ///
  /// The parent form owns coordinate text controllers, so this widget never
  /// stores a separate editable center. Mapbox taps flow through this callback
  /// and the rebuilt widget receives the selected center from the form.
  final void Function(double latitude, double longitude)? onCoordinateSelected;

  bool get _hasCoordinates => latitude != null && longitude != null;

  @override
  State<PrivacyZoneMapPreview> createState() => _PrivacyZoneMapPreviewState();
}

/// TODO: Document _PrivacyZoneMapPreviewState.
class _PrivacyZoneMapPreviewState extends State<PrivacyZoneMapPreview> {
  MapboxMap? _mapboxMap;
  PolygonAnnotationManager? _polygonAnnotationManager;
  PolygonAnnotation? _zonePolygon;

  @override
  void didUpdateWidget(covariant PrivacyZoneMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final centerChanged =
        oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude;
    final radiusChanged = oldWidget.radiusMeters != widget.radiusMeters;
    if (!centerChanged && !radiusChanged) {
      return;
    }

    // Widget props are the canonical form state. Keep the native map in sync
    // after text-field edits, current-location autofill, and map tap callbacks.
    unawaited(
      _syncMapFromWidgetState(
        moveCamera: centerChanged && widget._hasCoordinates,
      ),
    );
  }

  @override
  void dispose() {
    final annotationManager = _polygonAnnotationManager;
    if (annotationManager != null) {
      // Best-effort cleanup keeps the native annotation layer from outliving
      // this Flutter widget, but disposal must not wait on platform channels.
      unawaited(_deleteAllZonePolygonsBestEffort(annotationManager));
    }
    _mapboxMap = null;
    _polygonAnnotationManager = null;
    _zonePolygon = null;
    super.dispose();
  }

  Future<void> _deleteAllZonePolygonsBestEffort(
    PolygonAnnotationManager annotationManager,
  ) async {
    try {
      await annotationManager.deleteAll();
    } catch (error) {
      if (isRecoverableMapboxChannelError(error)) {
        return;
      }
      rethrow;
    }
  }

  Future<void> _handleMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    // Privacy-zone placement is driven by explicit taps/current location, not
    // by Mapbox's live-location puck. Disable it so the map does not imply
    // that the app is continuously tracking location on this settings screen.
    await mapboxMap.location.updateSettings(
      LocationComponentSettings(enabled: false),
    );
    await _syncMapFromWidgetState(moveCamera: widget._hasCoordinates);
  }

  void _handleMapTapped(MapContentGestureContext context) {
    final coordinates = context.point.coordinates;
    widget.onCoordinateSelected?.call(
      coordinates.lat.toDouble(),
      coordinates.lng.toDouble(),
    );
  }

  Future<void> _syncMapFromWidgetState({required bool moveCamera}) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) {
      return;
    }

    try {
      if (!widget._hasCoordinates) {
        await _clearZonePolygon();
        return;
      }

      final latitude = widget.latitude!;
      final longitude = widget.longitude!;
      if (moveCamera) {
        await _flyToCenter(
          mapboxMap: mapboxMap,
          latitude: latitude,
          longitude: longitude,
        );
      }
      await _renderZonePolygon(
        mapboxMap: mapboxMap,
        latitude: latitude,
        longitude: longitude,
        radiusMeters: widget.radiusMeters,
      );
    } catch (error) {
      if (isRecoverableMapboxChannelError(error)) {
        return;
      }
      rethrow;
    }
  }

  Future<void> _flyToCenter({
    required MapboxMap mapboxMap,
    required double latitude,
    required double longitude,
  }) {
    return mapboxMap.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(longitude, latitude)),
        zoom: _defaultCameraZoom,
      ),
      null,
    );
  }

  Future<void> _renderZonePolygon({
    required MapboxMap mapboxMap,
    required double latitude,
    required double longitude,
    required int radiusMeters,
  }) async {
    final annotationManager =
        _polygonAnnotationManager ??
        await mapboxMap.annotations.createPolygonAnnotationManager();
    _polygonAnnotationManager = annotationManager;

    final polygon = buildPrivacyZoneRadiusPolygon(
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
    final existingPolygon = _zonePolygon;
    if (existingPolygon == null) {
      // Polygon annotations use geographic vertices. This intentionally avoids
      // CircleAnnotation because Mapbox circle radius is in screen pixels, not
      // meters, which would drift as the user zooms.
      _zonePolygon = await annotationManager.create(
        PolygonAnnotationOptions(
          geometry: polygon,
          fillColor: _zoneFillColorArgb,
          fillOpacity: 0.22,
          fillOutlineColor: _zoneOutlineColorArgb,
        ),
      );
      return;
    }

    existingPolygon
      ..geometry = polygon
      ..fillColor = _zoneFillColorArgb
      ..fillOpacity = 0.22
      ..fillOutlineColor = _zoneOutlineColorArgb;
    await annotationManager.update(existingPolygon);
  }

  Future<void> _clearZonePolygon() async {
    final annotationManager = _polygonAnnotationManager;
    if (annotationManager == null || _zonePolygon == null) {
      return;
    }

    await annotationManager.deleteAll();
    _zonePolygon = null;
  }

  CameraOptions _initialCameraOptions() {
    final latitude = widget.latitude ?? _defaultCameraLatitude;
    final longitude = widget.longitude ?? _defaultCameraLongitude;
    return CameraOptions(
      center: Point(coordinates: Position(longitude, latitude)),
      zoom: _defaultCameraZoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: PrivacyZoneMapPreview.mapSurfaceKey,
          height: 240,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: MapWidget(
              cameraOptions: _initialCameraOptions(),
              onMapCreated: _handleMapCreated,
              onTapListener: _handleMapTapped,
              styleUri: MapboxStyles.MAPBOX_STREETS,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget._hasCoordinates
              ? 'Center: ${widget.latitude!.toStringAsFixed(6)}, '
                    '${widget.longitude!.toStringAsFixed(6)}'
              : 'Tap the map, use current location, or enter coordinates.',
          key: widget._hasCoordinates
              ? PrivacyZoneMapPreview.centerSummaryKey
              : PrivacyZoneMapPreview.emptyPromptKey,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Builds a geographic polygon approximating the privacy-zone radius.
///
/// Mapbox's CircleAnnotation radius is pixel-based, so privacy zones use a
/// geodesic polygon. The first vertex is due north of the center, which keeps
/// tests and future visual debugging easy to reason about.
@visibleForTesting
Polygon buildPrivacyZoneRadiusPolygon({
  required double latitude,
  required double longitude,
  required int radiusMeters,
}) {
  final centerLatitudeRadians = _toRadians(latitude);
  final centerLongitudeRadians = _toRadians(longitude);
  final angularDistance = radiusMeters / _earthRadiusMeters;
  final ring = <Position>[];

  for (var index = 0; index <= _zonePolygonSegments; index++) {
    final bearing = (2 * math.pi * index) / _zonePolygonSegments;
    final vertexLatitude = math.asin(
      math.sin(centerLatitudeRadians) * math.cos(angularDistance) +
          math.cos(centerLatitudeRadians) *
              math.sin(angularDistance) *
              math.cos(bearing),
    );
    final vertexLongitude =
        centerLongitudeRadians +
        math.atan2(
          math.sin(bearing) *
              math.sin(angularDistance) *
              math.cos(centerLatitudeRadians),
          math.cos(angularDistance) -
              math.sin(centerLatitudeRadians) * math.sin(vertexLatitude),
        );

    ring.add(Position(_toDegrees(vertexLongitude), _toDegrees(vertexLatitude)));
  }

  return Polygon(coordinates: [ring]);
}

double _toRadians(double degrees) => degrees * (math.pi / 180);

double _toDegrees(double radians) => radians * (180 / math.pi);

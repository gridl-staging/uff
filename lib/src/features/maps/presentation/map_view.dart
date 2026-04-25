import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uff/src/features/maps/data/mapbox_channel_errors.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';

// TODO(uff): Document MapViewInputs.
/// TODO: Document MapViewInputs.
@visibleForTesting
class MapViewInputs {
  const MapViewInputs({
    required this.routePoints,
    required this.photoMarkers,
    required this.followUserLocation,
    required this.cameraMode,
    required this.followUserHeading,
    required this.northUpRequestGeneration,
  });

  factory MapViewInputs.fromWidget(MapView widget) {
    return MapViewInputs(
      routePoints: widget.routePoints,
      photoMarkers: widget.photoMarkers,
      followUserLocation: widget.followUserLocation,
      cameraMode: widget.userLocationCameraMode,
      followUserHeading: widget.followUserHeading,
      northUpRequestGeneration: widget.northUpRequestGeneration,
    );
  }

  final List<RoutePoint> routePoints;
  final List<PhotoMarkerInput> photoMarkers;
  final bool followUserLocation;
  final MapViewUserLocationCameraMode cameraMode;
  final bool followUserHeading;
  final int northUpRequestGeneration;
}

bool _didUserLocationViewportInputsChange({
  required MapViewInputs previousInputs,
  required MapViewInputs nextInputs,
}) {
  return previousInputs.followUserLocation != nextInputs.followUserLocation ||
      previousInputs.cameraMode != nextInputs.cameraMode ||
      previousInputs.followUserHeading != nextInputs.followUserHeading ||
      previousInputs.northUpRequestGeneration !=
          nextInputs.northUpRequestGeneration;
}

@visibleForTesting
bool didMapViewInputsChange({
  required MapViewInputs previousInputs,
  required MapViewInputs nextInputs,
}) {
  return !listEquals(previousInputs.routePoints, nextInputs.routePoints) ||
      !listEquals(previousInputs.photoMarkers, nextInputs.photoMarkers) ||
      _didUserLocationViewportInputsChange(
        previousInputs: previousInputs,
        nextInputs: nextInputs,
      );
}

enum MapViewUserLocationCameraMode { topDown, perspective }

@visibleForTesting
ViewportState? buildUserLocationViewportState({
  required bool followUserLocation,
  required double zoom,
  required MapViewUserLocationCameraMode cameraMode,
  required bool followUserHeading,
}) {
  if (!followUserLocation) {
    return null;
  }

  final bearing = followUserHeading
      ? const FollowPuckViewportStateBearingHeading()
      : const FollowPuckViewportStateBearingConstant(0);
  final pitch = switch (cameraMode) {
    MapViewUserLocationCameraMode.topDown => 0.0,
    MapViewUserLocationCameraMode.perspective => 45.0,
  };

  return FollowPuckViewportState(zoom: zoom, bearing: bearing, pitch: pitch);
}

/// Immutable camera target for route and fallback map states.
class MapViewCameraPosition {
  const MapViewCameraPosition({
    required this.latitude,
    required this.longitude,
    required this.zoom,
  });

  const MapViewCameraPosition.defaultFallback()
    : latitude = 40.7128,
      longitude = -74.0060,
      zoom = 12.0;

  factory MapViewCameraPosition.forRoute(List<RoutePoint> routePoints) {
    if (routePoints.isEmpty) {
      return const MapViewCameraPosition.defaultFallback();
    }

    var minimumLatitude = routePoints.first.latitude;
    var maximumLatitude = routePoints.first.latitude;
    var minimumLongitude = routePoints.first.longitude;
    var maximumLongitude = routePoints.first.longitude;

    for (final routePoint in routePoints.skip(1)) {
      minimumLatitude = math.min(minimumLatitude, routePoint.latitude);
      maximumLatitude = math.max(maximumLatitude, routePoint.latitude);
      minimumLongitude = math.min(minimumLongitude, routePoint.longitude);
      maximumLongitude = math.max(maximumLongitude, routePoint.longitude);
    }

    final routeSpanDegrees = math.max(
      maximumLatitude - minimumLatitude,
      maximumLongitude - minimumLongitude,
    );

    return MapViewCameraPosition(
      latitude: (minimumLatitude + maximumLatitude) / 2,
      longitude: (minimumLongitude + maximumLongitude) / 2,
      zoom: _zoomForRouteSpan(routeSpanDegrees),
    );
  }

  final double latitude;
  final double longitude;
  final double zoom;

  CameraOptions toCameraOptions() {
    return CameraOptions(
      center: Point(coordinates: Position(longitude, latitude)),
      zoom: zoom,
    );
  }

  static double _zoomForRouteSpan(double routeSpanDegrees) {
    if (routeSpanDegrees <= 0.0005) {
      return 16;
    }
    if (routeSpanDegrees <= 0.002) {
      return 15;
    }
    if (routeSpanDegrees <= 0.01) {
      return 14;
    }
    if (routeSpanDegrees <= 0.05) {
      return 12;
    }
    if (routeSpanDegrees <= 0.2) {
      return 10;
    }
    return 8;
  }
}

/// Immutable photo marker input for map placement. Only photos with
/// valid coordinates should be represented as marker inputs.
@immutable
class PhotoMarkerInput {
  const PhotoMarkerInput({
    required this.photoId,
    required this.latitude,
    required this.longitude,
    this.previewUrl,
  });

  final String photoId;
  final double latitude;
  final double longitude;

  /// Best available thumbnail URL for the marker image. Null when no
  /// signed URL is available; the map will render a camera placeholder.
  final String? previewUrl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoMarkerInput &&
          photoId == other.photoId &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          previewUrl == other.previewUrl;

  @override
  int get hashCode => Object.hash(photoId, latitude, longitude, previewUrl);
}

/// TODO: Document MapView.
class MapView extends StatefulWidget {
  const MapView({
    super.key,
    this.initialCameraPosition,
    this.routePoints = const [],
    this.photoMarkers = const [],
    this.followUserLocation = false,
    this.userLocationCameraMode = MapViewUserLocationCameraMode.perspective,
    this.followUserHeading = true,
    this.northUpRequestGeneration = 0,
    this.onMapCreated,
    this.onPhotoMarkerTapped,
    this.onBearingChanged,
    this.showNativeCompass = true,
    this.gestureRecognizers,
  });

  final MapViewCameraPosition? initialCameraPosition;
  final List<RoutePoint> routePoints;
  final List<PhotoMarkerInput> photoMarkers;
  final bool followUserLocation;
  final MapViewUserLocationCameraMode userLocationCameraMode;
  final bool followUserHeading;
  final int northUpRequestGeneration;
  final ValueChanged<MapboxMap>? onMapCreated;

  /// Called when the user taps a photo marker on the map.
  final ValueChanged<String>? onPhotoMarkerTapped;

  /// Called whenever the map camera bearing changes. Bearing is in degrees
  /// clockwise from true north, wrapped to [0, 360). Useful for driving
  /// a custom compass widget outside the map.
  final ValueChanged<double>? onBearingChanged;

  /// Whether to show the native Mapbox compass ornament. Set to false when
  /// the parent provides its own compass overlay (e.g. recording screen).
  final bool showNativeCompass;

  /// Optional gesture contract for the embedded platform view.
  ///
  /// Parents like `ActivityDetailScreen` use this to let the map claim gestures
  /// that start inside the map without mutating ancestor scroll physics.
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  @override
  State<MapView> createState() => _MapViewState();
}

/// Marker bitmap size in logical pixels. Rendered at 2x for device pixel
/// ratio headroom, so the raw bitmap is [_markerSize * 2] px square.
const _markerSize = 32;

/// Cached placeholder bitmap for photo markers that have no preview URL
/// or whose thumbnail download fails. Built once per process.
Uint8List? _cachedPlaceholderBitmap;
Future<PermissionStatus>? _pendingLocationPermissionRequest;

@visibleForTesting
Future<PermissionStatus> requestLocationWhenInUsePermission() {
  final inFlightRequest = _pendingLocationPermissionRequest;
  if (inFlightRequest != null) {
    return inFlightRequest;
  }

  final permissionRequest = Permission.locationWhenInUse.request();
  _pendingLocationPermissionRequest = permissionRequest;
  permissionRequest.whenComplete(() {
    if (identical(_pendingLocationPermissionRequest, permissionRequest)) {
      _pendingLocationPermissionRequest = null;
    }
  });
  return permissionRequest;
}

@visibleForTesting
void resetLocationPermissionRequestState() {
  _pendingLocationPermissionRequest = null;
}

/// TODO: Document _MapViewState.
class _MapViewState extends State<MapView> {
  bool _hasHandledLocationPermission = false;
  bool _isLocationAuthorized = false;
  ViewportState? _viewportState;
  MapboxMap? _mapboxMap;
  PolylineAnnotationManager? _polylineAnnotationManager;
  PointAnnotationManager? _pointAnnotationManager;
  Cancelable? _photoMarkerTapSubscription;

  /// Maps Mapbox annotation IDs to photo IDs so tap callbacks can
  /// identify which photo was tapped.
  final Map<String, String> _annotationIdToPhotoId = {};

  MapViewCameraPosition get _initialCameraPosition {
    if (widget.initialCameraPosition != null) {
      return widget.initialCameraPosition!;
    }
    if (widget.routePoints.isNotEmpty) {
      return MapViewCameraPosition.forRoute(widget.routePoints);
    }
    return const MapViewCameraPosition.defaultFallback();
  }

  ViewportState? get _userLocationViewportState =>
      buildUserLocationViewportState(
        followUserLocation: widget.followUserLocation,
        zoom: _initialCameraPosition.zoom,
        cameraMode: widget.userLocationCameraMode,
        followUserHeading: widget.followUserHeading,
      );

  Future<void> _renderRouteLine() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) {
      return;
    }

    try {
      final annotationManager = await _getOrCreatePolylineAnnotationManager(
        mapboxMap,
      );
      if (!mounted) {
        return;
      }

      await annotationManager.deleteAll();
      if (!mounted || widget.routePoints.length < 2) {
        return;
      }

      await RoutePolyline.addToManager(
        annotationManager: annotationManager,
        points: widget.routePoints,
      );
    } catch (error) {
      if (isRecoverableMapboxChannelError(error)) {
        return;
      }
      rethrow;
    }
  }

  Future<PolylineAnnotationManager> _getOrCreatePolylineAnnotationManager(
    MapboxMap mapboxMap,
  ) async {
    final existingManager = _polylineAnnotationManager;
    if (existingManager != null) {
      return existingManager;
    }

    final annotationManager = await mapboxMap.annotations
        .createPolylineAnnotationManager();
    _polylineAnnotationManager = annotationManager;
    return annotationManager;
  }

  Future<PointAnnotationManager> _getOrCreatePointAnnotationManager(
    MapboxMap mapboxMap,
  ) async {
    final existingManager = _pointAnnotationManager;
    if (existingManager != null) {
      return existingManager;
    }

    final annotationManager = await mapboxMap.annotations
        .createPointAnnotationManager();
    _photoMarkerTapSubscription = annotationManager.tapEvents(
      onTap: (annotation) => _handlePhotoMarkerTapped(annotation.id),
    );
    _pointAnnotationManager = annotationManager;
    return annotationManager;
  }

  Future<void> _renderPhotoMarkers() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) {
      return;
    }

    try {
      _annotationIdToPhotoId.clear();
      final existingManager = _pointAnnotationManager;
      if (widget.photoMarkers.isEmpty) {
        if (existingManager != null) {
          await existingManager.deleteAll();
        }
        return;
      }

      final annotationManager =
          existingManager ??
          await _getOrCreatePointAnnotationManager(mapboxMap);
      if (!mounted) {
        return;
      }

      await annotationManager.deleteAll();
      if (!mounted) {
        return;
      }

      for (final marker in widget.photoMarkers) {
        if (!mounted) {
          return;
        }

        final bitmap = await _resolveBitmap(marker.previewUrl);
        if (!mounted) {
          return;
        }

        final annotation = await annotationManager.create(
          PointAnnotationOptions(
            geometry: Point(
              coordinates: Position(marker.longitude, marker.latitude),
            ),
            image: bitmap,
            iconSize: 1,
          ),
        );
        _annotationIdToPhotoId[annotation.id] = marker.photoId;
      }
    } catch (error) {
      if (isRecoverableMapboxChannelError(error)) {
        return;
      }
      rethrow;
    }
  }

  /// Resolves the marker bitmap for a photo: downloads and circle-crops
  /// the thumbnail if a URL is available, otherwise returns the cached
  /// camera placeholder.
  Future<Uint8List> _resolveBitmap(String? previewUrl) async {
    if (previewUrl != null && previewUrl.isNotEmpty) {
      final thumbnail = await _tryLoadThumbnailBitmap(previewUrl);
      if (thumbnail != null) {
        return thumbnail;
      }
    }
    return _getOrBuildPlaceholderBitmap();
  }

  /// Downloads a thumbnail URL and circle-crops it into a marker bitmap.
  /// Returns null on any network or decode failure.
  static Future<Uint8List?> _tryLoadThumbnailBitmap(String url) async {
    try {
      final httpClient = HttpClient();
      try {
        final request = await httpClient.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          return null;
        }
        final bytes = await response
            .fold<BytesBuilder>(
              BytesBuilder(),
              (builder, chunk) => builder..add(chunk),
            )
            .then((builder) => builder.toBytes());
        return _buildCircularBitmap(bytes);
      } finally {
        httpClient.close();
      }
    } on Object {
      return null;
    }
  }

  /// Sets up a [_markerSize]×2 canvas, calls [draw] to paint the content,
  /// adds a shared white border ring, and converts the result to PNG bytes.
  static Future<Uint8List?> _renderMarkerBitmap(
    void Function(Canvas canvas, Offset center, double radius) draw,
  ) async {
    final recorder = ui.PictureRecorder();
    const size = _markerSize * 2.0;
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
    const center = Offset(size / 2, size / 2);
    const radius = size / 2;

    draw(canvas, center, radius);

    // White border ring shared by all marker styles.
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF),
    );

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(_markerSize * 2, _markerSize * 2);
    final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  /// Decodes raw image bytes and renders them as a circular bitmap
  /// suitable for a Mapbox point annotation icon.
  static Future<Uint8List?> _buildCircularBitmap(Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: _markerSize * 2,
        targetHeight: _markerSize * 2,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;

      return _renderMarkerBitmap((canvas, center, radius) {
        // Clip to circle, then draw the decoded image to fill.
        canvas
          ..clipPath(
            Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
          )
          ..drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            Rect.fromLTWH(0, 0, radius * 2, radius * 2),
            Paint(),
          );
      });
    } on Object {
      return null;
    }
  }

  /// Returns the cached camera placeholder bitmap, building it on first call.
  static Future<Uint8List> _getOrBuildPlaceholderBitmap() async {
    final cached = _cachedPlaceholderBitmap;
    if (cached != null) {
      return cached;
    }

    final bitmap = await _buildCameraPlaceholderBitmap();
    _cachedPlaceholderBitmap = bitmap;
    return bitmap;
  }

  /// Renders a simple camera-icon placeholder as a circular bitmap.
  static Future<Uint8List> _buildCameraPlaceholderBitmap() async {
    const size = _markerSize * 2.0;
    final bytes = await _renderMarkerBitmap((canvas, center, radius) {
      // Grey background circle, camera body, and lens.
      const bodyWidth = size * 0.45;
      const bodyHeight = size * 0.32;
      final bodyRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center.translate(0, size * 0.02),
          width: bodyWidth,
          height: bodyHeight,
        ),
        const Radius.circular(3),
      );
      canvas
        ..drawCircle(center, radius, Paint()..color = const Color(0xFF9E9E9E))
        ..drawRRect(bodyRect, Paint()..color = const Color(0xFFFFFFFF))
        ..drawCircle(
          center.translate(0, size * 0.02),
          bodyHeight * 0.28,
          Paint()..color = const Color(0xFF9E9E9E),
        );
    });
    return bytes!;
  }

  void _handlePhotoMarkerTapped(String annotationId) {
    final photoId = _annotationIdToPhotoId[annotationId];
    if (photoId != null) {
      widget.onPhotoMarkerTapped?.call(photoId);
    }
  }

  Future<void> _configureLiveLocation(MapboxMap mapboxMap) async {
    if (_hasHandledLocationPermission) {
      return;
    }
    _hasHandledLocationPermission = true;

    final permissionStatus = await requestLocationWhenInUsePermission();
    _isLocationAuthorized =
        permissionStatus.isGranted || permissionStatus.isLimited;

    if (_isLocationAuthorized) {
      await mapboxMap.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          puckBearing: PuckBearing.HEADING,
          puckBearingEnabled: true,
        ),
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _viewportState = _userLocationViewportState;
      });
      return;
    }

    await mapboxMap.location.updateSettings(
      LocationComponentSettings(enabled: false),
    );
    await mapboxMap.setCamera(_initialCameraPosition.toCameraOptions());
  }

  Future<void> _focusCameraOnRoute(MapboxMap mapboxMap) async {
    if (widget.routePoints.length < 2) {
      await mapboxMap.setCamera(_initialCameraPosition.toCameraOptions());
      return;
    }

    final routeCoordinates = widget.routePoints
        .map(
          (routePoint) => Point(
            coordinates: Position(routePoint.longitude, routePoint.latitude),
          ),
        )
        .toList(growable: false);
    final routeCamera = await mapboxMap.cameraForCoordinatesPadding(
      routeCoordinates,
      CameraOptions(),
      MbxEdgeInsets(top: 48, left: 48, bottom: 48, right: 48),
      16,
      null,
    );
    await mapboxMap.setCamera(routeCamera);
  }

  /// Forwards camera bearing changes to the parent via [MapView.onBearingChanged].
  /// Uses the MapWidget's onCameraChangeListener callback — each event triggers
  /// an async getCameraState() read, but Dart's single-threaded event loop
  /// naturally limits concurrency so this won't flood the UI.
  void _handleCameraChanged(CameraChangedEventData event) {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null || widget.onBearingChanged == null) {
      return;
    }

    mapboxMap.getCameraState().then((cameraState) {
      if (mounted) {
        widget.onBearingChanged?.call(cameraState.bearing);
      }
    });
  }

  Future<void> _handleMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    widget.onMapCreated?.call(mapboxMap);

    // Hide the native Mapbox compass ornament when the parent provides
    // its own compass overlay (e.g. recording screen). The native compass
    // can't propagate click events to Flutter state, so the recording
    // screen uses a custom Flutter compass button instead.
    if (!widget.showNativeCompass) {
      await mapboxMap.compass.updateSettings(CompassSettings(enabled: false));
    }

    if (widget.followUserLocation) {
      await _configureLiveLocation(mapboxMap);
    } else {
      await mapboxMap.location.updateSettings(
        LocationComponentSettings(enabled: false),
      );
      await _focusCameraOnRoute(mapboxMap);
    }

    await _renderRouteLine();
    await _renderPhotoMarkers();
  }

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) {
      return;
    }

    final previousInputs = MapViewInputs.fromWidget(oldWidget);
    final nextInputs = MapViewInputs.fromWidget(widget);
    if (!didMapViewInputsChange(
      previousInputs: previousInputs,
      nextInputs: nextInputs,
    )) {
      return;
    }

    if (_didUserLocationViewportInputsChange(
      previousInputs: previousInputs,
      nextInputs: nextInputs,
    )) {
      _handleUserLocationViewportInputsChanged(mapboxMap);
    }

    unawaited(_renderRouteLine());
    unawaited(_renderPhotoMarkers());
    if (!widget.followUserLocation) {
      unawaited(_focusCameraOnRoute(mapboxMap));
    }
  }

  void _handleUserLocationViewportInputsChanged(MapboxMap mapboxMap) {
    if (!widget.followUserLocation) {
      _hasHandledLocationPermission = false;
      _isLocationAuthorized = false;
      _viewportState = null;
      unawaited(
        mapboxMap.location.updateSettings(
          LocationComponentSettings(enabled: false),
        ),
      );
      return;
    }

    if (_isLocationAuthorized) {
      setState(() {
        _viewportState = _userLocationViewportState;
      });
      return;
    }

    if (!_hasHandledLocationPermission) {
      unawaited(_configureLiveLocation(mapboxMap));
    }
  }

  @override
  void dispose() {
    _photoMarkerTapSubscription?.cancel();
    _polylineAnnotationManager = null;
    _pointAnnotationManager = null;
    _annotationIdToPhotoId.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: MapWidget(
        cameraOptions: _initialCameraPosition.toCameraOptions(),
        gestureRecognizers: widget.gestureRecognizers,
        onMapCreated: _handleMapCreated,
        onCameraChangeListener: _handleCameraChanged,
        styleUri: MapboxStyles.MAPBOX_STREETS,
        viewport: _viewportState,
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const _permissionMethodChannel = MethodChannel(
  'flutter.baseflow.com/permissions/methods',
);

/// Records point-annotation channel operations so widget tests can verify
/// the create/delete lifecycle without relying on internal MapView state.
class PointAnnotationRecorder {
  int deleteAllCount = 0;
  int createCount = 0;

  /// When true, the create stub throws a recoverable [PlatformException]
  /// instead of returning an annotation. Use this to verify that MapView
  /// handles channel errors gracefully during photo marker rendering.
  bool throwRecoverableOnCreate = false;

  /// Unique annotation IDs returned for each create call.
  final List<String> createdAnnotationIds = [];

  /// Requested point geometries, recorded in create-call order so tests can
  /// verify exact lat/lng values across rebuilds.
  final List<RecordedPointAnnotation> createdPoints = [];

  void reset() {
    deleteAllCount = 0;
    createCount = 0;
    throwRecoverableOnCreate = false;
    createdAnnotationIds.clear();
    createdPoints.clear();
  }
}

/// Records camera-animation channel operations so widget tests can verify
/// re-center and fly-to requests without inspecting MapView internals.
class MapCameraAnimationRecorder {
  int flyToCount = 0;
  RecordedPointAnnotation? lastFlyToCenter;

  void reset() {
    flyToCount = 0;
    lastFlyToCenter = null;
  }
}

/// TODO: Document PolygonAnnotationRecorder.
class PolygonAnnotationRecorder {
  int createCount = 0;
  int deleteAllCount = 0;
  int updateCount = 0;

  /// When true, deleteAll throws the same recoverable channel error Mapbox can
  /// produce after the native platform-view channels have already detached.
  bool throwRecoverableOnDeleteAll = false;

  final List<String> createdAnnotationIds = [];
  final List<RecordedPolygonAnnotation> createdPolygons = [];
  final List<RecordedPolygonAnnotation> updatedPolygons = [];

  void reset() {
    createCount = 0;
    deleteAllCount = 0;
    updateCount = 0;
    throwRecoverableOnDeleteAll = false;
    createdAnnotationIds.clear();
    createdPolygons.clear();
    updatedPolygons.clear();
  }
}

/// TODO: Document RecordedPolygonAnnotation.
@immutable
class RecordedPolygonAnnotation {
  const RecordedPolygonAnnotation({required this.rings});

  final List<List<RecordedPointAnnotation>> rings;

  int get vertexCount => rings.fold(0, (sum, ring) => sum + ring.length);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordedPolygonAnnotation && _ringsEqual(rings, other.rings);

  @override
  int get hashCode => Object.hashAll(rings.expand((ring) => ring));

  static bool _ringsEqual(
    List<List<RecordedPointAnnotation>> a,
    List<List<RecordedPointAnnotation>> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) return false;
      for (var j = 0; j < a[i].length; j++) {
        if (a[i][j] != b[i][j]) return false;
      }
    }
    return true;
  }
}

/// TODO: Document RecordedPointAnnotation.
@immutable
class RecordedPointAnnotation {
  const RecordedPointAnnotation({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordedPointAnnotation &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

void setUpMapboxPlatformChannelStub({
  int channelSuffix = 0,
  PointAnnotationRecorder? pointAnnotationRecorder,
  PolygonAnnotationRecorder? polygonAnnotationRecorder,
  MapCameraAnimationRecorder? mapCameraAnimationRecorder,
}) {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final channelSuffixes = <int>{channelSuffix, 0}.toList(growable: false);
  final mapboxMethodChannels = [
    for (final suffix in channelSuffixes)
      MethodChannel('plugins.flutter.io.$suffix'),
  ];
  final basicHandlers = [
    for (final suffix in channelSuffixes)
      ..._buildBasicChannelStubs(
        suffix,
        pointAnnotationRecorder: pointAnnotationRecorder,
        polygonAnnotationRecorder: polygonAnnotationRecorder,
        mapCameraAnimationRecorder: mapCameraAnimationRecorder,
      ),
  ];
  final annotationTapEventChannels = [
    for (final suffix in channelSuffixes)
      MethodChannel(
        'dev.flutter.pigeon.mapbox_maps_flutter.AnnotationInteractions._annotationInteractionEvents.$suffix/mock-polyline-manager/tap',
      ),
  ];
  final polygonTapEventChannels = [
    for (final suffix in channelSuffixes)
      MethodChannel(
        'dev.flutter.pigeon.mapbox_maps_flutter.AnnotationInteractions._annotationInteractionEvents.$suffix/mock-polygon-manager/tap',
      ),
  ];

  setUpAll(() {
    _registerPlatformViewHandler(messenger, channelSuffix);
    for (final channel in mapboxMethodChannels) {
      _registerMapboxMethodChannelHandler(messenger, channel);
    }
    _registerPermissionMethodChannelHandler(messenger);
    _registerBasicChannelHandlers(messenger, basicHandlers);
    for (final channel in annotationTapEventChannels) {
      messenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async => null,
      );
    }
    for (final channel in polygonTapEventChannels) {
      messenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async => null,
      );
    }
  });

  tearDownAll(() {
    for (final channel in mapboxMethodChannels) {
      _clearMethodChannelHandlers(messenger, channel);
    }
    _clearBasicChannelHandlers(messenger, basicHandlers);
    for (final channel in annotationTapEventChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    for (final channel in polygonTapEventChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
}

List<_BasicChannelStub> _buildBasicChannelStubs(
  int channelSuffix, {
  PointAnnotationRecorder? pointAnnotationRecorder,
  PolygonAnnotationRecorder? polygonAnnotationRecorder,
  MapCameraAnimationRecorder? mapCameraAnimationRecorder,
}) {
  final suffix = '.$channelSuffix';
  var pointAnnotationCreateCounter = 0;
  var polygonAnnotationCreateCounter = 0;

  return <_BasicChannelStub>[
    _BasicChannelStub(
      channelName:
          'dev.flutter.pigeon.mapbox_maps_flutter._LocationComponentSettingsInterface.updateSettings$suffix',
      codec: const Settings_PigeonCodec(),
      replyBuilder: (_) => <Object?>[null],
    ),
    _BasicChannelStub(
      channelName:
          'dev.flutter.pigeon.mapbox_maps_flutter._CameraManager.setCamera$suffix',
      codec: const MapInterfaces_PigeonCodec(),
      replyBuilder: (_) => <Object?>[null],
    ),
    _BasicChannelStub(
      channelName:
          'dev.flutter.pigeon.mapbox_maps_flutter._CameraManager.cameraForCoordinatesPadding$suffix',
      codec: const MapInterfaces_PigeonCodec(),
      replyBuilder: (_) => <Object?>[_mockCameraOptions],
    ),
    _BasicChannelStub(
      channelName:
          'dev.flutter.pigeon.mapbox_maps_flutter._PolylineAnnotationMessenger.deleteAll$suffix',
      codec: const PolylineAnnotationMessenger_PigeonCodec(),
      replyBuilder: (_) => <Object?>[null],
    ),
    _BasicChannelStub(
      channelName:
          'dev.flutter.pigeon.mapbox_maps_flutter._PolylineAnnotationMessenger.setLineCap$suffix',
      codec: const PolylineAnnotationMessenger_PigeonCodec(),
      replyBuilder: (_) => <Object?>[null],
    ),
    _BasicChannelStub(
      channelName:
          'dev.flutter.pigeon.mapbox_maps_flutter._PolylineAnnotationMessenger.setLineJoin$suffix',
      codec: const PolylineAnnotationMessenger_PigeonCodec(),
      replyBuilder: (_) => <Object?>[null],
    ),
    _BasicChannelStub(
      channelName:
          'dev.flutter.pigeon.mapbox_maps_flutter._PolylineAnnotationMessenger.create$suffix',
      codec: const PolylineAnnotationMessenger_PigeonCodec(),
      replyBuilder: (_) => <Object?>[_mockPolylineAnnotation],
    ),
    _BasicChannelStub(
      channelName:
          'dev.flutter.pigeon.mapbox_maps_flutter._PointAnnotationMessenger.deleteAll$suffix',
      codec: const PointAnnotationMessenger_PigeonCodec(),
      replyBuilder: (_) {
        pointAnnotationRecorder?.deleteAllCount += 1;
        return <Object?>[null];
      },
    ),
    _BasicChannelStub(
      channelName:
          'dev.flutter.pigeon.mapbox_maps_flutter._PointAnnotationMessenger.create$suffix',
      codec: const PointAnnotationMessenger_PigeonCodec(),
      replyBuilder: (message) {
        if (pointAnnotationRecorder?.throwRecoverableOnCreate ?? false) {
          throw PlatformException(
            code: 'channel-error',
            message:
                'Unable to establish connection on channel: '
                '"dev.flutter.pigeon.mapbox_maps_flutter._PointAnnotationMessenger.create$suffix".',
          );
        }
        pointAnnotationCreateCounter += 1;
        final id = 'mock-point-$pointAnnotationCreateCounter';
        final createdPoint = _extractPointAnnotation(message);
        pointAnnotationRecorder?.createCount += 1;
        pointAnnotationRecorder?.createdAnnotationIds.add(id);
        if (createdPoint != null) {
          pointAnnotationRecorder?.createdPoints.add(createdPoint);
        }
        return <Object?>[
          PointAnnotation(
            id: id,
            geometry: Point(
              coordinates: Position(
                createdPoint?.longitude ?? -74.0060,
                createdPoint?.latitude ?? 40.7128,
              ),
            ),
          ),
        ];
      },
    ),
    _BasicChannelStub(
      channelName:
          'dev.flutter.pigeon.mapbox_maps_flutter._PolygonAnnotationMessenger.create$suffix',
      codec: const PolygonAnnotationMessenger_PigeonCodec(),
      replyBuilder: (message) {
        polygonAnnotationCreateCounter += 1;
        final id = 'mock-polygon-$polygonAnnotationCreateCounter';
        final recorded = _extractPolygonAnnotation(message);
        polygonAnnotationRecorder?.createCount += 1;
        polygonAnnotationRecorder?.createdAnnotationIds.add(id);
        if (recorded != null) {
          polygonAnnotationRecorder?.createdPolygons.add(recorded);
        }
        return <Object?>[
          PolygonAnnotation(
            id: id,
            geometry: Polygon(
              coordinates:
                  recorded?.rings
                      .map(
                        (ring) => ring
                            .map((p) => Position(p.longitude, p.latitude))
                            .toList(),
                      )
                      .toList() ??
                  [
                    [Position(-74.0060, 40.7128)],
                  ],
            ),
          ),
        ];
      },
    ),
    _BasicChannelStub(
      channelName:
          'dev.flutter.pigeon.mapbox_maps_flutter._PolygonAnnotationMessenger.deleteAll$suffix',
      codec: const PolygonAnnotationMessenger_PigeonCodec(),
      replyBuilder: (_) {
        polygonAnnotationRecorder?.deleteAllCount += 1;
        if (polygonAnnotationRecorder?.throwRecoverableOnDeleteAll ?? false) {
          throw PlatformException(
            code: 'channel-error',
            message:
                'Unable to establish connection on channel: '
                '"dev.flutter.pigeon.mapbox_maps_flutter._PolygonAnnotationMessenger.deleteAll$suffix".',
          );
        }
        return <Object?>[null];
      },
    ),
    _BasicChannelStub(
      channelName:
          'dev.flutter.pigeon.mapbox_maps_flutter._PolygonAnnotationMessenger.update$suffix',
      codec: const PolygonAnnotationMessenger_PigeonCodec(),
      replyBuilder: (message) {
        final recorded = _extractPolygonAnnotation(message);
        polygonAnnotationRecorder?.updateCount += 1;
        if (recorded != null) {
          polygonAnnotationRecorder?.updatedPolygons.add(recorded);
        }
        return <Object?>[null];
      },
    ),
    _BasicChannelStub(
      channelName:
          'dev.flutter.pigeon.mapbox_maps_flutter._AnimationManager.flyTo$suffix',
      codec: const MapInterfaces_PigeonCodec(),
      replyBuilder: (message) {
        mapCameraAnimationRecorder?.flyToCount += 1;
        mapCameraAnimationRecorder?.lastFlyToCenter = _extractFlyToCenter(
          message,
        );
        return <Object?>[null];
      },
    ),
  ];
}

RecordedPolygonAnnotation? _extractPolygonAnnotation(Object? message) {
  if (message is! List<Object?> || message.length < 2) {
    return null;
  }

  final geometry = _extractPolygonGeometry(message[1]);
  if (geometry == null) {
    return null;
  }

  final rings = geometry.coordinates
      .map(
        (ring) => ring
            .map(
              (pos) => RecordedPointAnnotation(
                latitude: pos.lat.toDouble(),
                longitude: pos.lng.toDouble(),
              ),
            )
            .toList(),
      )
      .toList();
  return RecordedPolygonAnnotation(rings: rings);
}

Polygon? _extractPolygonGeometry(Object? annotationPayload) {
  if (annotationPayload is PolygonAnnotationOptions) {
    return annotationPayload.geometry;
  }
  if (annotationPayload is PolygonAnnotation) {
    return annotationPayload.geometry;
  }
  return null;
}

RecordedPointAnnotation? _extractPointAnnotation(Object? message) {
  if (message is! List<Object?> || message.length < 2) {
    return null;
  }

  final annotationOption = message[1];
  if (annotationOption is! PointAnnotationOptions) {
    return null;
  }

  final coordinates = annotationOption.geometry.coordinates;
  return RecordedPointAnnotation(
    latitude: coordinates.lat.toDouble(),
    longitude: coordinates.lng.toDouble(),
  );
}

RecordedPointAnnotation? _extractFlyToCenter(Object? message) {
  if (message is! List<Object?> || message.isEmpty) {
    return null;
  }

  CameraOptions? cameraOptions;
  for (final value in message) {
    if (value is CameraOptions) {
      cameraOptions = value;
      break;
    }
  }
  final center = cameraOptions?.center?.coordinates;
  if (center == null) {
    return null;
  }
  return RecordedPointAnnotation(
    latitude: center.lat.toDouble(),
    longitude: center.lng.toDouble(),
  );
}

void _registerPlatformViewHandler(
  TestDefaultBinaryMessenger messenger,
  int channelSuffix,
) {
  messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
    MethodCall call,
  ) async {
    switch (call.method) {
      case 'create':
        return channelSuffix;
      case 'dispose':
      case 'resize':
      case 'offset':
      case 'setDirection':
      case 'clearFocus':
      case 'touch':
      case 'synchronizeToNativeViewHierarchy':
        return null;
    }
    return null;
  });
}

void _registerMapboxMethodChannelHandler(
  TestDefaultBinaryMessenger messenger,
  MethodChannel mapboxMethodChannel,
) {
  messenger.setMockMethodCallHandler(mapboxMethodChannel, (
    MethodCall call,
  ) async {
    switch (call.method) {
      case 'annotation#create_manager':
        final args = call.arguments as Map<dynamic, dynamic>?;
        final type = args?['type'] as String?;
        if (type == 'polygon') return 'mock-polygon-manager';
        return 'mock-polyline-manager';
      case 'annotation#remove_manager':
      case 'gesture#add_listeners':
      case 'gesture#remove_listeners':
      case 'interactions#add_interaction':
      case 'interactions#remove_interaction':
      case 'mapView#submitViewSizeHint':
      case 'platform#releaseMethodChannels':
        return null;
      case 'map#snapshot':
        return <int>[];
    }
    return null;
  });
}

void _registerPermissionMethodChannelHandler(
  TestDefaultBinaryMessenger messenger,
) {
  messenger.setMockMethodCallHandler(_permissionMethodChannel, (
    MethodCall call,
  ) async {
    switch (call.method) {
      case 'checkPermissionStatus':
        return 1;
      case 'checkServiceStatus':
        return 1;
      case 'openAppSettings':
        return true;
      case 'shouldShowRequestPermissionRationale':
        return false;
      case 'requestPermissions':
        final requestedPermissions =
            (call.arguments as List<dynamic>? ?? const <dynamic>[])
                .whereType<int>();
        return {for (final permission in requestedPermissions) permission: 1};
    }
    return null;
  });
}

void _registerBasicChannelHandlers(
  TestDefaultBinaryMessenger messenger,
  List<_BasicChannelStub> basicHandlers,
) {
  for (final handler in basicHandlers) {
    messenger.setMockDecodedMessageHandler<Object?>(
      BasicMessageChannel<Object?>(handler.channelName, handler.codec),
      (Object? message) async => handler.replyBuilder(message),
    );
  }
}

void _clearMethodChannelHandlers(
  TestDefaultBinaryMessenger messenger,
  MethodChannel mapboxMethodChannel,
) {
  messenger
    ..setMockMethodCallHandler(SystemChannels.platform_views, null)
    ..setMockMethodCallHandler(mapboxMethodChannel, null)
    ..setMockMethodCallHandler(_permissionMethodChannel, null);
}

void _clearBasicChannelHandlers(
  TestDefaultBinaryMessenger messenger,
  List<_BasicChannelStub> basicHandlers,
) {
  for (final handler in basicHandlers) {
    messenger.setMockDecodedMessageHandler<Object?>(
      BasicMessageChannel<Object?>(handler.channelName, handler.codec),
      null,
    );
  }
}

final _mockCameraOptions = CameraOptions(
  center: Point(coordinates: Position(-74.0060, 40.7128)),
  zoom: 14,
);

final _mockPolylineAnnotation = PolylineAnnotation(
  id: 'mock-polyline',
  geometry: LineString(
    coordinates: [Position(-74.0060, 40.7128), Position(-73.9980, 40.7198)],
  ),
);

class _BasicChannelStub {
  const _BasicChannelStub({
    required this.channelName,
    required this.codec,
    required this.replyBuilder,
  });

  final String channelName;
  final MessageCodec<Object?> codec;
  final Object? Function(Object?) replyBuilder;
}

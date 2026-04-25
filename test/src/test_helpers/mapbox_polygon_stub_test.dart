import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'mapbox_platform_channel_stub.dart';

// ## Test Scenarios
// - [positive] Polygon create records vertices in PolygonAnnotationRecorder
// - [positive] Polygon deleteAll increments recorder count in same map lifecycle
void main() {
  const channelSuffix = 50;
  const suffix = '.$channelSuffix';
  final polygonRecorder = PolygonAnnotationRecorder();

  setUpMapboxPlatformChannelStub(
    channelSuffix: channelSuffix,
    polygonAnnotationRecorder: polygonRecorder,
  );

  setUp(polygonRecorder.reset);

  testWidgets(
    'polygon create records vertices and deleteAll in same lifecycle',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MapWidget(key: Key('test_map')),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      final ring = <Position>[
        Position(-74.0060, 40.7128),
        Position(-74.0050, 40.7138),
        Position(-74.0040, 40.7128),
        Position(-74.0060, 40.7128),
      ];
      const mapboxMethodChannel = MethodChannel('plugins.flutter.io$suffix');

      final managerId = await mapboxMethodChannel.invokeMethod<String>(
        'annotation#create_manager',
        <String, Object?>{
          'type': 'polygon',
        },
      );
      expect(managerId, 'mock-polygon-manager');

      const createChannel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.mapbox_maps_flutter._PolygonAnnotationMessenger.create$suffix',
        PolygonAnnotationMessenger_PigeonCodec(),
      );
      const deleteAllChannel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.mapbox_maps_flutter._PolygonAnnotationMessenger.deleteAll$suffix',
        PolygonAnnotationMessenger_PigeonCodec(),
      );

      await createChannel.send(<Object?>[
        managerId,
        PolygonAnnotationOptions(
          geometry: Polygon(coordinates: [ring]),
        ),
      ]);
      await tester.pump(const Duration(milliseconds: 50));

      expect(polygonRecorder.createCount, 1);
      expect(polygonRecorder.createdAnnotationIds, hasLength(1));
      expect(polygonRecorder.createdAnnotationIds.first, 'mock-polygon-1');
      expect(polygonRecorder.createdPolygons, hasLength(1));

      final recorded = polygonRecorder.createdPolygons.first;
      expect(recorded.rings, hasLength(1));
      expect(recorded.rings.first, hasLength(4));
      expect(recorded.rings.first[0].latitude, 40.7128);
      expect(recorded.rings.first[0].longitude, -74.0060);
      expect(recorded.rings.first[2].latitude, 40.7128);
      expect(recorded.rings.first[2].longitude, -74.0040);
      expect(recorded.vertexCount, 4);

      await deleteAllChannel.send(<Object?>[managerId]);
      await tester.pump(const Duration(milliseconds: 50));
      expect(polygonRecorder.deleteAllCount, 1);
    },
  );
}

// Scenario tags use bracket syntax enforced by the test standards script.
// ignore_for_file: comment_references

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:uff/src/common_widgets/static_route_preview.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';

/// ## Test Scenarios
/// - [edge] Null, empty, and malformed polylines render placeholder previews.
/// - [positive] Valid polylines render a deterministic [CustomPaint] route preview.
/// - [negative] Preview never renders a live [MapWidget] or network image widget.
/// - [positive] Feed/detail/compact presets expose stable keys and dimensions.
void main() {
  Widget buildPreview({
    String? polylineEncoded,
    List<RoutePoint>? routePoints,
    StaticRoutePreviewSizePreset preset = StaticRoutePreviewSizePreset.feed,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: StaticRoutePreview(
          polylineEncoded: polylineEncoded,
          routePoints: routePoints,
          preset: preset,
        ),
      ),
    );
  }

  testWidgets('null polyline renders grey placeholder', (tester) async {
    await tester.pumpWidget(buildPreview());

    expect(find.byKey(StaticRoutePreview.previewKey), findsOneWidget);
    expect(find.byKey(StaticRoutePreview.placeholderKey), findsOneWidget);
    expect(find.byKey(StaticRoutePreview.paintKey), findsNothing);
  });

  testWidgets('empty polyline renders grey placeholder', (tester) async {
    await tester.pumpWidget(buildPreview(polylineEncoded: ''));

    expect(find.byKey(StaticRoutePreview.placeholderKey), findsOneWidget);
    expect(find.byKey(StaticRoutePreview.paintKey), findsNothing);
  });

  testWidgets('malformed polyline renders grey placeholder', (tester) async {
    await tester.pumpWidget(
      buildPreview(polylineEncoded: '_p~iF~ps|U_ulLnnqC_mqNvxq'),
    );

    expect(find.byKey(StaticRoutePreview.placeholderKey), findsOneWidget);
    expect(find.byKey(StaticRoutePreview.paintKey), findsNothing);
  });

  testWidgets('too-short decoded route renders grey placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(buildPreview(polylineEncoded: '_p~iF~ps|U'));

    expect(find.byKey(StaticRoutePreview.placeholderKey), findsOneWidget);
    expect(find.byKey(StaticRoutePreview.paintKey), findsNothing);
  });

  testWidgets('valid polyline renders static custom-painted route', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildPreview(polylineEncoded: '_p~iF~ps|U_ulLnnqC_mqNvxq`@'),
    );

    expect(find.byKey(StaticRoutePreview.paintKey), findsOneWidget);
    expect(find.byKey(StaticRoutePreview.placeholderKey), findsNothing);
    expect(find.byType(MapWidget), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('route points render static custom-painted route', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildPreview(
        routePoints: const <RoutePoint>[
          RoutePoint(latitude: 40.7128, longitude: -74.0060),
          RoutePoint(latitude: 40.7228, longitude: -74.0160),
        ],
      ),
    );

    expect(find.byKey(StaticRoutePreview.paintKey), findsOneWidget);
    expect(find.byKey(StaticRoutePreview.placeholderKey), findsNothing);
  });

  testWidgets(
    'route points never fall back to polyline reconstruction when too short',
    (tester) async {
      await tester.pumpWidget(
        buildPreview(
          polylineEncoded: '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
          routePoints: const <RoutePoint>[
            RoutePoint(latitude: 40.7128, longitude: -74.0060),
          ],
        ),
      );

      expect(find.byKey(StaticRoutePreview.placeholderKey), findsOneWidget);
      expect(find.byKey(StaticRoutePreview.paintKey), findsNothing);
    },
  );

  testWidgets('feed preset uses fixed 150dp route preview height', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildPreview(
        polylineEncoded: '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
      ),
    );

    final sizedBox = tester.widget<SizedBox>(
      find.byKey(StaticRoutePreview.feedBoxKey),
    );
    expect(sizedBox.height, 150);
  });

  testWidgets('detail preset uses a 16:9 aspect ratio shell', (tester) async {
    await tester.pumpWidget(
      buildPreview(
        polylineEncoded: '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
        preset: StaticRoutePreviewSizePreset.detail,
      ),
    );

    final aspectRatio = tester.widget<AspectRatio>(
      find.byKey(StaticRoutePreview.detailAspectRatioKey),
    );
    expect(aspectRatio.aspectRatio, 16 / 9);
  });

  testWidgets('compact preset uses stable compact dimensions', (tester) async {
    await tester.pumpWidget(
      buildPreview(
        polylineEncoded: '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
        preset: StaticRoutePreviewSizePreset.compact,
      ),
    );

    final sizedBox = tester.widget<SizedBox>(
      find.byKey(StaticRoutePreview.compactBoxKey),
    );
    expect(sizedBox.width, 96);
    expect(sizedBox.height, 72);
  });
}

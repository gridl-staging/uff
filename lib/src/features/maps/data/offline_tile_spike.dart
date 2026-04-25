import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

typedef DownloadOfflineTileRegion =
    Future<void> Function({
      required String tileRegionId,
      required OfflineTileRegionBounds bounds,
      String styleUri,
      int minZoom,
      int maxZoom,
    });
typedef OfflineTileSpikeErrorHandler =
    void Function(Object error, StackTrace stackTrace);

/// NOTE(stuart): Document OfflineTileRegionBounds.
class OfflineTileRegionBounds {
  const OfflineTileRegionBounds({
    required this.minLatitude,
    required this.minLongitude,
    required this.maxLatitude,
    required this.maxLongitude,
  }) : assert(
         minLatitude < maxLatitude,
         'minLatitude must be less than maxLatitude.',
       ),
       assert(
         minLongitude < maxLongitude,
         'minLongitude must be less than maxLongitude.',
       );

  final double minLatitude;
  final double minLongitude;
  final double maxLatitude;
  final double maxLongitude;

  Map<String, Object?> toGeoJsonPolygon() {
    final ring = <Position>[
      Position(minLongitude, minLatitude),
      Position(maxLongitude, minLatitude),
      Position(maxLongitude, maxLatitude),
      Position(minLongitude, maxLatitude),
      Position(minLongitude, minLatitude),
    ];

    return Polygon(coordinates: [ring]).toJson();
  }
}

class OfflineTileSpikePlan {
  const OfflineTileSpikePlan({
    required this.tileRegionId,
    required this.bounds,
    this.styleUri = MapboxStyles.MAPBOX_STREETS,
    this.minZoom = 10,
    this.maxZoom = 16,
  });

  final String tileRegionId;
  final OfflineTileRegionBounds bounds;
  final String styleUri;
  final int minZoom;
  final int maxZoom;
}

const defaultStage2OfflineTileSpikePlan = OfflineTileSpikePlan(
  tileRegionId: 'stage-02-lower-manhattan',
  bounds: OfflineTileRegionBounds(
    minLatitude: 40.7005,
    minLongitude: -74.0196,
    maxLatitude: 40.7259,
    maxLongitude: -73.9712,
  ),
);

Future<void> runStage2OfflineTileSpike({
  required DownloadOfflineTileRegion downloadRegion,
  OfflineTileSpikePlan plan = defaultStage2OfflineTileSpikePlan,
}) {
  return downloadRegion(
    tileRegionId: plan.tileRegionId,
    bounds: plan.bounds,
    styleUri: plan.styleUri,
    minZoom: plan.minZoom,
    maxZoom: plan.maxZoom,
  );
}

Future<bool> runStage2OfflineTileSpikeSafely({
  required DownloadOfflineTileRegion downloadRegion,
  OfflineTileSpikePlan plan = defaultStage2OfflineTileSpikePlan,
  OfflineTileSpikeErrorHandler? onError,
}) async {
  try {
    await runStage2OfflineTileSpike(
      downloadRegion: downloadRegion,
      plan: plan,
    );
    return true;
  } on Object catch (error, stackTrace) {
    onError?.call(error, stackTrace);
    return false;
  }
}

/// NOTE(stuart): Document MapboxOfflineTileSpike.
class MapboxOfflineTileSpike {
  const MapboxOfflineTileSpike();

  Future<void> downloadRegion({
    required String tileRegionId,
    required OfflineTileRegionBounds bounds,
    String styleUri = MapboxStyles.MAPBOX_STREETS,
    int minZoom = 10,
    int maxZoom = 16,
  }) async {
    final offlineManager = await OfflineManager.create();
    final tileStore = await TileStore.createDefault();

    final stylePackLoadOptions = StylePackLoadOptions(
      acceptExpired: true,
      glyphsRasterizationMode:
          GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
      metadata: {'stage': 'stage-02-offline-spike'},
    );

    await offlineManager.loadStylePack(
      styleUri,
      stylePackLoadOptions,
      null,
    );

    final tileRegionOptions = TileRegionLoadOptions(
      acceptExpired: true,
      descriptorsOptions: [
        TilesetDescriptorOptions(
          maxZoom: maxZoom,
          minZoom: minZoom,
          styleURI: styleUri,
        ),
      ],
      geometry: bounds.toGeoJsonPolygon(),
      networkRestriction: NetworkRestriction.NONE,
    );

    await tileStore.loadTileRegion(
      tileRegionId,
      tileRegionOptions,
      null,
    );
  }
}

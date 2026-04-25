typedef ApplyMapboxAccessToken = void Function(String accessToken);

// TODO(uff): Document MapboxTokenInitializer.
/// TODO: Document MapboxTokenInitializer.
class MapboxTokenInitializer {
  const MapboxTokenInitializer();

  static const mapboxAccessTokenKey = 'MAPBOX_ACCESS_TOKEN';
  static const _mapboxSecretTokenPrefix = 'sk.';

  String? initialize({
    required Map<String, String> environment,
    required ApplyMapboxAccessToken applyAccessToken,
  }) {
    final token = environment[mapboxAccessTokenKey]?.trim() ?? '';
    if (token.isEmpty || token.startsWith(_mapboxSecretTokenPrefix)) {
      return null;
    }

    applyAccessToken(token);
    return token;
  }
}

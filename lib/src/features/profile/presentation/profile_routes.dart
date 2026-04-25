/// Shared privacy-zone route definitions.
///
/// Keeping these path constants in one place prevents route drift between
/// router wiring and in-app navigation entry points.
abstract final class ProfileRoutes {
  static const privacyZonesPath = '/privacy-zones';
  static const privacyZonesNewPath = '/privacy-zones/new';
  static const privacyZonesPathPattern = '/privacy-zones/:id';

  static String privacyZoneDetailPath(String id) {
    return '/privacy-zones/${Uri.encodeComponent(id)}';
  }
}

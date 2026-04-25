/// Shared club route definitions.
///
/// `clubListPath` is the single source of truth for the shell tab path — it is
/// consumed by `HomeShellScreen` destinations and must not be duplicated as a
/// standalone `GoRoute` in the router. Only `clubNewPath` and
/// `clubDetailPathPattern` are registered as non-shell routes.
abstract final class ClubRoutes {
  /// Shell tab path — owned by the `homeShellDestinations` branch loop.
  static const clubListPath = '/home/clubs';

  static const clubNewPath = '/clubs/new';
  static const clubDetailPathPattern = '/clubs/:id';
  static const clubEditPathPattern = '/clubs/:id/edit';
  static const clubRunNewPathPattern = '/clubs/:id/runs/new';

  static String clubDetailPath(String id) {
    return '/clubs/${Uri.encodeComponent(id)}';
  }

  static String clubEditPath(String id) {
    return '/clubs/${Uri.encodeComponent(id)}/edit';
  }

  static String clubRunNewPath(String clubId) {
    return '/clubs/${Uri.encodeComponent(clubId)}/runs/new';
  }
}

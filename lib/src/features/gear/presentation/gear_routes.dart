/// Shared gear route definitions.
///
/// Keeping these path constants in one place prevents route drift between
/// router wiring and in-app navigation entry points.
abstract final class GearRoutes {
  static const gearPath = '/gear';
  static const gearNewPath = '/gear/new';
  static const gearPathPattern = '/gear/:id';

  static String gearDetailPath(String id) {
    return '/gear/${Uri.encodeComponent(id)}';
  }
}

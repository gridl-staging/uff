/// Shared activity route definitions.
///
/// Keeping these path constants in one place prevents route drift between
/// router wiring and in-app navigation entry points.
abstract final class ActivityRoutes {
  static const activityPathPattern = '/activity/:id';

  static String activityDetailPath(int id) {
    return '/activity/$id';
  }
}

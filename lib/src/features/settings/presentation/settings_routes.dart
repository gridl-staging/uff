/// Shared settings route definitions.
///
/// Keeping path constants in one place prevents route drift between router
/// registration and caller navigation entry points.
abstract final class SettingsRoutes {
  static const settingsPath = '/settings';
  static const hrZonesPath = '/settings/hr-zones';
}

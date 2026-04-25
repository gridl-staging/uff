/// Sport discipline a club focuses on.
enum ClubSportType {
  running('running'),
  cycling('cycling'),
  hiking('hiking'),
  walking('walking'),
  trailRunning('trail_running'),
  ;

  const ClubSportType(this.databaseValue);

  final String databaseValue;

  static ClubSportType? fromDatabaseValue(String? value) {
    if (value == null) return null;
    for (final type in values) {
      if (type.databaseValue == value) return type;
    }
    return null;
  }
}

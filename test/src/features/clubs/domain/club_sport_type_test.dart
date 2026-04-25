import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/clubs/domain/club_sport_type.dart';

// ## Test Scenarios
// - [positive] Each enum value round-trips through databaseValue and fromDatabaseValue.
// - [positive] Null input returns null output from fromDatabaseValue.
// - [negative] Unknown string returns null instead of throwing.
// - [isolation] Each enum variant maps to a distinct snake_case DB string.
void main() {
  group('ClubSportType', () {
    test(
      'round-trips each enum value through databaseValue/fromDatabaseValue',
      () {
        expect(
          ClubSportType.fromDatabaseValue('running'),
          ClubSportType.running,
        );
        expect(ClubSportType.running.databaseValue, 'running');

        expect(
          ClubSportType.fromDatabaseValue('cycling'),
          ClubSportType.cycling,
        );
        expect(ClubSportType.cycling.databaseValue, 'cycling');

        expect(
          ClubSportType.fromDatabaseValue('hiking'),
          ClubSportType.hiking,
        );
        expect(ClubSportType.hiking.databaseValue, 'hiking');

        expect(
          ClubSportType.fromDatabaseValue('walking'),
          ClubSportType.walking,
        );
        expect(ClubSportType.walking.databaseValue, 'walking');

        expect(
          ClubSportType.fromDatabaseValue('trail_running'),
          ClubSportType.trailRunning,
        );
        expect(ClubSportType.trailRunning.databaseValue, 'trail_running');
      },
    );

    test('null input returns null', () {
      expect(ClubSportType.fromDatabaseValue(null), isNull);
    });

    test('unknown string returns null instead of throwing', () {
      expect(ClubSportType.fromDatabaseValue('skiing'), isNull);
      expect(ClubSportType.fromDatabaseValue(''), isNull);
      expect(ClubSportType.fromDatabaseValue('RUNNING'), isNull);
    });
  });
}

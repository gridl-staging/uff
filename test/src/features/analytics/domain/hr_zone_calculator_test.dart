import 'package:test/test.dart';
import 'package:uff/src/features/analytics/domain/hr_zone_calculator.dart';
import 'package:uff/src/features/analytics/domain/sport_type.dart';

void main() {
  group('HrZoneCalculator.forLthr()', () {
    group('running zones', () {
      test('LTHR=160 produces correct Friel 7-zone boundaries', () {
        final zones = HrZoneCalculator.forLthr(160, SportType.run);

        expect(zones.lthr, 160);
        expect(zones.zones, hasLength(7));

        // Z1: 0–135
        expect(zones.zones[0].number, 1);
        expect(zones.zones[0].label, 'Z1');
        expect(zones.zones[0].lowerBpm, 0);
        expect(zones.zones[0].upperBpm, 135);

        // Z2: 136–143
        expect(zones.zones[1].number, 2);
        expect(zones.zones[1].label, 'Z2');
        expect(zones.zones[1].lowerBpm, 136);
        expect(zones.zones[1].upperBpm, 143);

        // Z3: 144–151
        expect(zones.zones[2].number, 3);
        expect(zones.zones[2].label, 'Z3');
        expect(zones.zones[2].lowerBpm, 144);
        expect(zones.zones[2].upperBpm, 151);

        // Z4: 152–159
        expect(zones.zones[3].number, 4);
        expect(zones.zones[3].label, 'Z4');
        expect(zones.zones[3].lowerBpm, 152);
        expect(zones.zones[3].upperBpm, 159);

        // Z5a: 160–163
        expect(zones.zones[4].number, 5);
        expect(zones.zones[4].label, 'Z5a');
        expect(zones.zones[4].lowerBpm, 160);
        expect(zones.zones[4].upperBpm, 163);

        // Z5b: 164–169
        expect(zones.zones[5].number, 6);
        expect(zones.zones[5].label, 'Z5b');
        expect(zones.zones[5].lowerBpm, 164);
        expect(zones.zones[5].upperBpm, 169);

        // Z5c: 170+ (null upper)
        expect(zones.zones[6].number, 7);
        expect(zones.zones[6].label, 'Z5c');
        expect(zones.zones[6].lowerBpm, 170);
        expect(zones.zones[6].upperBpm, isNull);
      });
    });

    group('cycling zones', () {
      test('LTHR=160 cycling shifts Z1/Z3/Z4 boundaries', () {
        final zones = HrZoneCalculator.forLthr(160, SportType.ride);

        expect(zones.lthr, 160);
        expect(zones.zones, hasLength(7));

        // Z1: 0–128 (shifted from 135 in running)
        expect(zones.zones[0].lowerBpm, 0);
        expect(zones.zones[0].upperBpm, 128);

        // Z2: 129–143
        expect(zones.zones[1].lowerBpm, 129);
        expect(zones.zones[1].upperBpm, 143);

        // Z3: 144–149 (shifted from 151 in running)
        expect(zones.zones[2].lowerBpm, 144);
        expect(zones.zones[2].upperBpm, 149);

        // Z4: 150–159 (lower shifted from 152 in running)
        expect(zones.zones[3].lowerBpm, 150);
        expect(zones.zones[3].upperBpm, 159);

        // Z5a–Z5c identical to running
        expect(zones.zones[4].lowerBpm, 160);
        expect(zones.zones[4].upperBpm, 163);
        expect(zones.zones[5].lowerBpm, 164);
        expect(zones.zones[5].upperBpm, 169);
        expect(zones.zones[6].lowerBpm, 170);
        expect(zones.zones[6].upperBpm, isNull);
      });

      test(
        'exact-decimal ride breakpoints do not drift from double rounding',
        () {
          final zones = HrZoneCalculator.forLthr(2150, SportType.ride);

          // 94% of 2150 is exactly 2021.0, so Z3/Z4 must split at 2020/2021.
          expect(zones.zones[2].upperBpm, 2020);
          expect(zones.zones[3].lowerBpm, 2021);
        },
      );

      test('zones are contiguous with no gaps or overlaps', () {
        final zones = HrZoneCalculator.forLthr(160, SportType.ride);

        for (var i = 0; i < zones.zones.length - 1; i++) {
          final current = zones.zones[i];
          final next = zones.zones[i + 1];
          expect(
            current.upperBpm! + 1,
            next.lowerBpm,
            reason:
                '${current.label} upper + 1 should equal '
                '${next.label} lower',
          );
        }

        // Last zone (Z5c) has no upper bound
        expect(zones.zones.last.upperBpm, isNull);
      });
    });

    group('input validation', () {
      test('LTHR ≤ 0 throws ArgumentError', () {
        expect(
          () => HrZoneCalculator.forLthr(0, SportType.run),
          throwsArgumentError,
        );
        expect(
          () => HrZoneCalculator.forLthr(-10, SportType.ride),
          throwsArgumentError,
        );
      });

      test('small positive LTHR that cannot form 7 non-empty zones throws', () {
        expect(
          () => HrZoneCalculator.forLthr(1, SportType.run),
          throwsArgumentError,
        );
        expect(
          () => HrZoneCalculator.forLthr(33, SportType.ride),
          throwsArgumentError,
        );
      });

      test('minimum valid LTHR still produces 7 non-empty zones', () {
        for (final sport in [SportType.run, SportType.ride]) {
          final zones = HrZoneCalculator.forLthr(34, sport);

          expect(zones.zones, hasLength(7));
          for (final zone in zones.zones.take(6)) {
            expect(
              zone.lowerBpm <= zone.upperBpm!,
              isTrue,
              reason: '${zone.label} should not have an inverted range',
            );
          }
          expect(zones.zones.last.upperBpm, isNull);
        }
      });
    });
  });
}

/// ## Test Scenarios
/// - [positive] Static path constants match expected literal values
/// - [positive] privacyZoneDetailPath produces canonical path for simple id
/// - [edge] privacyZoneDetailPath URI-encodes reserved characters in id

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/profile/presentation/profile_routes.dart';

void main() {
  group('ProfileRoutes', () {
    test('privacyZonesPath is /privacy-zones', () {
      expect(ProfileRoutes.privacyZonesPath, '/privacy-zones');
    });

    test('privacyZonesNewPath is /privacy-zones/new', () {
      expect(ProfileRoutes.privacyZonesNewPath, '/privacy-zones/new');
    });

    test('privacyZonesPathPattern is /privacy-zones/:id', () {
      expect(ProfileRoutes.privacyZonesPathPattern, '/privacy-zones/:id');
    });

    test('privacyZoneDetailPath produces canonical path for simple id', () {
      expect(
        ProfileRoutes.privacyZoneDetailPath('zone-42'),
        '/privacy-zones/zone-42',
      );
    });

    test('privacyZoneDetailPath URI-encodes reserved characters', () {
      expect(
        ProfileRoutes.privacyZoneDetailPath('a/b'),
        '/privacy-zones/a%2Fb',
      );
      expect(
        ProfileRoutes.privacyZoneDetailPath('id with spaces'),
        '/privacy-zones/id%20with%20spaces',
      );
    });
  });
}

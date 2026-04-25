/// ## Test Scenarios
/// - [positive] Static path constants match expected literal values
/// - [positive] gearDetailPath produces canonical path for simple id
/// - [edge] gearDetailPath URI-encodes reserved characters in id

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/gear/presentation/gear_routes.dart';

void main() {
  group('GearRoutes', () {
    test('gearPath is /gear', () {
      expect(GearRoutes.gearPath, '/gear');
    });

    test('gearNewPath is /gear/new', () {
      expect(GearRoutes.gearNewPath, '/gear/new');
    });

    test('gearPathPattern is /gear/:id', () {
      expect(GearRoutes.gearPathPattern, '/gear/:id');
    });

    test('gearDetailPath produces canonical path for simple id', () {
      expect(GearRoutes.gearDetailPath('shoe-1'), '/gear/shoe-1');
    });

    test('gearDetailPath URI-encodes reserved characters', () {
      expect(GearRoutes.gearDetailPath('a/b'), '/gear/a%2Fb');
      expect(
        GearRoutes.gearDetailPath('id with spaces'),
        '/gear/id%20with%20spaces',
      );
    });
  });
}

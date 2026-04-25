/// ## Test Scenarios
/// - [positive] Static path pattern matches expected literal value
/// - [positive] activityDetailPath produces canonical integer path

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_routes.dart';

void main() {
  group('ActivityRoutes', () {
    test('activityPathPattern is /activity/:id', () {
      expect(ActivityRoutes.activityPathPattern, '/activity/:id');
    });

    test('activityDetailPath produces canonical integer path', () {
      expect(ActivityRoutes.activityDetailPath(42), '/activity/42');
      expect(ActivityRoutes.activityDetailPath(0), '/activity/0');
      expect(ActivityRoutes.activityDetailPath(999999), '/activity/999999');
    });
  });
}

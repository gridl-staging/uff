import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/clubs/presentation/club_routes.dart';

/// ## Test Scenarios
/// - [positive] Route constants point to the expected club paths.
/// - [positive] Club detail paths encode ids exactly once.
/// - [negative] Different ids produce different encoded detail paths.
/// - [isolation] Path constants do not depend on previous test state.

void main() {
  group('ClubRoutes path constants', () {
    test('clubListPath is the shell tab path', () {
      expect(ClubRoutes.clubListPath, '/home/clubs');
    });

    test('clubNewPath points to the create form', () {
      expect(ClubRoutes.clubNewPath, '/clubs/new');
    });

    test('clubDetailPathPattern uses :id parameter', () {
      expect(ClubRoutes.clubDetailPathPattern, '/clubs/:id');
    });

    test('clubDetailPath encodes the id segment', () {
      expect(ClubRoutes.clubDetailPath('abc'), '/clubs/abc');
      expect(
        ClubRoutes.clubDetailPath('has space'),
        '/clubs/has%20space',
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';

/// ## Test Scenarios
/// - [positive] viewedUserProfilePath URI-encodes user ids in route segments.
/// - [edge] remoteActivityDetailPath URI-encodes activity ids with reserved characters.
void main() {
  group('SocialRoutes URI encoding', () {
    test('viewedUserProfilePath URI-encodes the userId', () {
      final result = SocialRoutes.viewedUserProfilePath('user/with@special');
      expect(
        result,
        '/social/profile/${Uri.encodeComponent('user/with@special')}',
      );
    });

    test('remoteActivityDetailPath URI-encodes the activityId', () {
      final result = SocialRoutes.remoteActivityDetailPath('user/with@special');
      expect(
        result,
        '/social/activity/${Uri.encodeComponent('user/with@special')}',
      );
    });
  });
}

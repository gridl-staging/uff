import 'package:uff/src/features/social/domain/social_activity_detail.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';

/// Read-only remote activity access for social feeds and profile activity lists.
abstract interface class SocialActivityRepository {
  Future<List<SocialActivitySummary>> loadFeedActivities({
    required int offset,
    required int limit,
  });

  Future<List<SocialActivitySummary>> loadUserActivities(String userId);

  Future<SocialActivityDetail?> loadActivityDetail(String activityId);
}

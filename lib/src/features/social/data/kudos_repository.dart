import 'package:uff/src/features/social/domain/activity_kudos.dart';

/// Contract for activity kudos reads and mutations.
abstract interface class KudosRepository {
  Future<ActivityKudosSummary> loadActivityKudos(String activityId);

  Future<void> toggleKudos({
    required String activityId,
    required bool viewerHasKudo,
  });
}

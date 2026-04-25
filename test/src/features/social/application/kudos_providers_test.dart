import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/application/social_kudos_providers.dart';
import 'package:uff/src/features/social/data/kudos_repository.dart';
import 'package:uff/src/features/social/data/social_activity_repository.dart';
import 'package:uff/src/features/social/domain/activity_kudos.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/remote_activity_track_point.dart';
import 'package:uff/src/features/social/domain/social_activity_detail.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';

/// ## Test Scenarios
/// - [positive] Kudos toggle mutations refresh feed/detail/kudos read providers.
/// - [positive] In-flight optimistic state is cleared after async toggle completion.
/// - [negative] Failed kudos toggles preserve the existing activity read state.
/// - [edge] Toggle controller remains safe when disposed during in-flight mutation.
/// - [isolation] Toggle invalidation is scoped to the mutated activity id caches.
const _viewerId = '11111111-1111-1111-1111-111111111111';
const _ownerId = '22222222-2222-2222-2222-222222222222';
const _activityId = 'activity-1';

class _FakeSocialActivityRepository implements SocialActivityRepository {
  int loadFeedActivitiesCallCount = 0;
  int loadActivityDetailCallCount = 0;

  bool viewerHasKudo = false;
  int kudosCount = 0;

  @override
  Future<SocialActivityDetail?> loadActivityDetail(String activityId) async {
    loadActivityDetailCallCount++;
    return SocialActivityDetail(
      activityId: activityId,
      owner: _ownerSummary(),
      sportType: 'run',
      startedAt: DateTime.utc(2026, 3, 19, 10),
      finishedAt: DateTime.utc(2026, 3, 19, 10, 30),
      distanceMeters: 5000,
      durationSeconds: 1500,
      elevationGainMeters: 40,
      avgPaceSecondsPerKm: 300,
      title: 'Tempo',
      description: null,
      visibility: 'public',
      polylineEncoded: null,
      kudosCount: kudosCount,
      viewerHasKudo: viewerHasKudo,
      splits: const <SocialActivitySplit>[],
      trackPoints: const <RemoteActivityTrackPoint>[],
    );
  }

  @override
  Future<List<SocialActivitySummary>> loadFeedActivities({
    required int offset,
    required int limit,
  }) async {
    loadFeedActivitiesCallCount++;
    return [
      SocialActivitySummary(
        activityId: _activityId,
        owner: _ownerSummary(),
        sportType: 'run',
        startedAt: DateTime.utc(2026, 3, 19, 10),
        finishedAt: DateTime.utc(2026, 3, 19, 10, 30),
        distanceMeters: 5000,
        durationSeconds: 1500,
        elevationGainMeters: 40,
        avgPaceSecondsPerKm: 300,
        title: 'Tempo',
        description: null,
        visibility: 'public',
        polylineEncoded: null,
        commentCount: 0,
        kudosCount: kudosCount,
        viewerHasKudo: viewerHasKudo,
      ),
    ];
  }

  @override
  Future<List<SocialActivitySummary>> loadUserActivities(String userId) async {
    return const <SocialActivitySummary>[];
  }
}

class _FakeKudosRepository implements KudosRepository {
  int toggleCallCount = 0;
  int loadActivityKudosCallCount = 0;
  bool viewerHasKudo = false;
  int kudosCount = 0;

  @override
  Future<ActivityKudosSummary> loadActivityKudos(String activityId) async {
    loadActivityKudosCallCount++;
    return ActivityKudosSummary(
      kudosCount: kudosCount,
      viewerHasKudo: viewerHasKudo,
      users: const <ActivityKudoUser>[],
    );
  }

  @override
  Future<void> toggleKudos({
    required String activityId,
    required bool viewerHasKudo,
  }) async {
    toggleCallCount++;
    this.viewerHasKudo = !viewerHasKudo;
    kudosCount += viewerHasKudo ? -1 : 1;
  }
}

class _BlockingKudosRepository implements KudosRepository {
  final Completer<void> _toggleCompleter = Completer<void>();
  int toggleCallCount = 0;
  int loadActivityKudosCallCount = 0;
  bool viewerHasKudo = false;
  int kudosCount = 0;
  bool? _pendingViewerHasKudo;

  @override
  Future<ActivityKudosSummary> loadActivityKudos(String activityId) async {
    loadActivityKudosCallCount++;
    return ActivityKudosSummary(
      kudosCount: kudosCount,
      viewerHasKudo: viewerHasKudo,
      users: const <ActivityKudoUser>[],
    );
  }

  @override
  Future<void> toggleKudos({
    required String activityId,
    required bool viewerHasKudo,
  }) async {
    toggleCallCount++;
    _pendingViewerHasKudo = viewerHasKudo;
    await _toggleCompleter.future;
  }

  void completeToggle() {
    if (!_toggleCompleter.isCompleted) {
      final previousViewerHasKudo = _pendingViewerHasKudo ?? viewerHasKudo;
      viewerHasKudo = !previousViewerHasKudo;
      kudosCount += previousViewerHasKudo ? -1 : 1;
      _toggleCompleter.complete();
    }
  }
}

SocialUserSummary _ownerSummary() {
  return const SocialUserSummary(
    userId: _ownerId,
    displayName: 'Owner',
    avatarUrl: null,
    relationship: FollowRelationship(
      currentUserId: _viewerId,
      targetUserId: _ownerId,
      status: FollowRelationshipStatus.following,
    ),
  );
}

void main() {
  test(
    'kudos toggle invalidates feed, remote detail, and owner-detail activity kudos read',
    () async {
      final socialRepository = _FakeSocialActivityRepository();
      final kudosRepository = _FakeKudosRepository();
      final container = ProviderContainer(
        overrides: [
          socialActivityRepositoryProvider.overrideWithValue(socialRepository),
          kudosRepositoryProvider.overrideWithValue(kudosRepository),
          activityPhotoListProvider(
            _activityId,
          ).overrideWith((ref) async => <ActivityPhoto>[]),
        ],
      );
      addTearDown(container.dispose);

      await container.read(socialFeedProvider.future);
      await container.read(remoteActivityDetailProvider(_activityId).future);
      await container.read(activityKudosProvider(_activityId).future);
      expect(socialRepository.loadFeedActivitiesCallCount, 1);
      expect(socialRepository.loadActivityDetailCallCount, 1);
      expect(kudosRepository.loadActivityKudosCallCount, 1);

      await container
          .read(kudosToggleControllerProvider.notifier)
          .toggleKudos(
            activityId: _activityId,
            viewerHasKudo: false,
          );

      socialRepository
        ..viewerHasKudo = kudosRepository.viewerHasKudo
        ..kudosCount = kudosRepository.kudosCount;
      await container.read(socialFeedProvider.future);
      await container.read(remoteActivityDetailProvider(_activityId).future);
      await container.read(activityKudosProvider(_activityId).future);

      expect(kudosRepository.toggleCallCount, 1);
      expect(socialRepository.loadFeedActivitiesCallCount, 2);
      expect(socialRepository.loadActivityDetailCallCount, 2);
      expect(kudosRepository.loadActivityKudosCallCount, 2);
    },
  );

  test(
    'kudos toggle clears in-flight state and refreshes reads after an async toggle with only notifier reads',
    () async {
      final socialRepository = _FakeSocialActivityRepository();
      final blockingRepository = _BlockingKudosRepository();
      final container = ProviderContainer(
        overrides: [
          socialActivityRepositoryProvider.overrideWithValue(socialRepository),
          kudosRepositoryProvider.overrideWithValue(blockingRepository),
          activityPhotoListProvider(
            _activityId,
          ).overrideWith((ref) async => <ActivityPhoto>[]),
        ],
      );
      addTearDown(container.dispose);

      final feedSubscription = container.listen(socialFeedProvider, (_, __) {});
      final detailSubscription = container.listen(
        remoteActivityDetailProvider(_activityId),
        (_, __) {},
      );
      final activityKudosSubscription = container.listen(
        activityKudosProvider(_activityId),
        (_, __) {},
      );
      final inFlightSubscription = container.listen(
        kudosToggleInFlightByActivityProvider,
        (_, __) {},
      );
      addTearDown(feedSubscription.close);
      addTearDown(detailSubscription.close);
      addTearDown(activityKudosSubscription.close);
      addTearDown(inFlightSubscription.close);

      await container.read(socialFeedProvider.future);
      await container.read(remoteActivityDetailProvider(_activityId).future);
      await container.read(activityKudosProvider(_activityId).future);

      expect(socialRepository.loadFeedActivitiesCallCount, 1);
      expect(socialRepository.loadActivityDetailCallCount, 1);
      expect(blockingRepository.loadActivityKudosCallCount, 1);
      expect(container.read(kudosToggleInFlightByActivityProvider), isEmpty);

      final toggleFuture = container
          .read(kudosToggleControllerProvider.notifier)
          .toggleKudos(
            activityId: _activityId,
            viewerHasKudo: false,
          );

      await container.pump();
      expect(
        container.read(kudosToggleInFlightByActivityProvider),
        containsPair(_activityId, true),
      );

      socialRepository
        ..viewerHasKudo = true
        ..kudosCount = 1;
      blockingRepository.completeToggle();

      await toggleFuture;
      await container.pump();

      expect(blockingRepository.toggleCallCount, 1);
      expect(socialRepository.loadFeedActivitiesCallCount, 2);
      expect(socialRepository.loadActivityDetailCallCount, 2);
      expect(blockingRepository.loadActivityKudosCallCount, 2);
      expect(container.read(kudosToggleInFlightByActivityProvider), isEmpty);
    },
  );

  test(
    'kudos toggle does not throw when provider is disposed mid-flight',
    () async {
      final socialRepository = _FakeSocialActivityRepository();
      final blockingRepository = _BlockingKudosRepository();
      final container = ProviderContainer(
        overrides: [
          socialActivityRepositoryProvider.overrideWithValue(socialRepository),
          kudosRepositoryProvider.overrideWithValue(blockingRepository),
          activityPhotoListProvider(
            _activityId,
          ).overrideWith((ref) async => <ActivityPhoto>[]),
        ],
      );

      final toggleFuture = container
          .read(kudosToggleControllerProvider.notifier)
          .toggleKudos(
            activityId: _activityId,
            viewerHasKudo: false,
          );

      container.dispose();
      blockingRepository.completeToggle();

      await expectLater(toggleFuture, completes);
      expect(blockingRepository.toggleCallCount, 1);
    },
  );
}

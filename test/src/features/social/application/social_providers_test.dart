import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/data/follow_repository.dart';
import 'package:uff/src/features/social/data/social_activity_repository.dart';
import 'package:uff/src/features/social/data/user_search_repository.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/relationship_counts.dart';
import 'package:uff/src/features/social/domain/social_activity_detail.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/domain/viewed_user_profile_header.dart';

/// ## Test Scenarios
/// - `[positive]` Followers/following/pending/count/header providers read
///   through follow repository seams.
/// - `[positive]` Follow action controller routes send/accept/reject/unfollow
///   mutations correctly.
/// - `[edge]` User search trims whitespace and avoids repository reads for
///   empty queries.
/// - `[error]` Follow action controller remains stable when disposed during
///   async mutation.
/// - `[negative]` Stale viewed-user profile and activity data does not persist
///   after follow mutations.
/// - `[isolation]` Follow mutations invalidate relationship and search caches
///   without profile-provider coupling.
class FakeFollowRepository implements FollowRepository {
  int sendFollowRequestCallCount = 0;
  int acceptFollowRequestCallCount = 0;
  int rejectFollowRequestCallCount = 0;
  int unfollowCallCount = 0;
  int getFollowersCallCount = 0;
  int getFollowingCallCount = 0;
  int getPendingRequestsCallCount = 0;
  int getRelationshipCountsCallCount = 0;
  int getViewedUserProfileHeaderCallCount = 0;
  String? lastViewedUserId;
  ViewedUserProfileHeader? viewedUserProfileHeaderToReturn;

  @override
  Future<void> acceptFollowRequest(String followId) async {
    acceptFollowRequestCallCount++;
  }

  @override
  Future<List<SocialUserSummary>> getFollowers() async {
    getFollowersCallCount++;
    return const [];
  }

  @override
  Future<List<SocialUserSummary>> getFollowing() async {
    getFollowingCallCount++;
    return const [];
  }

  @override
  Future<List<SocialUserSummary>> getPendingRequests() async {
    getPendingRequestsCallCount++;
    return const [];
  }

  @override
  Future<RelationshipCounts> getRelationshipCounts() async {
    getRelationshipCountsCallCount++;
    return const RelationshipCounts(
      userId: '11111111-1111-1111-1111-111111111111',
      followers: 0,
      following: 0,
      pendingRequests: 0,
    );
  }

  @override
  Future<ViewedUserProfileHeader?> getViewedUserProfileHeader(
    String userId,
  ) async {
    getViewedUserProfileHeaderCallCount++;
    lastViewedUserId = userId;
    return viewedUserProfileHeaderToReturn;
  }

  @override
  Future<void> rejectFollowRequest(String followId) async {
    rejectFollowRequestCallCount++;
  }

  @override
  Future<void> sendFollowRequest(String targetUserId) async {
    sendFollowRequestCallCount++;
  }

  @override
  Future<void> unfollow(String targetUserId) async {
    unfollowCallCount++;
  }
}

class FakeUserSearchRepository implements UserSearchRepository {
  int callCount = 0;
  String? lastQuery;

  @override
  Future<List<SocialUserSummary>> searchUsers(String query) async {
    callCount++;
    lastQuery = query;
    return const <SocialUserSummary>[];
  }
}

class _FakeSocialActivityRepository implements SocialActivityRepository {
  int loadFeedActivitiesCallCount = 0;
  int loadUserActivitiesCallCount = 0;

  @override
  Future<SocialActivityDetail?> loadActivityDetail(String activityId) async {
    return null;
  }

  @override
  Future<List<SocialActivitySummary>> loadFeedActivities({
    required int offset,
    required int limit,
  }) async {
    loadFeedActivitiesCallCount++;
    return const <SocialActivitySummary>[];
  }

  @override
  Future<List<SocialActivitySummary>> loadUserActivities(String userId) async {
    loadUserActivitiesCallCount++;
    return const <SocialActivitySummary>[];
  }
}

class _BlockingFollowRepository extends FakeFollowRepository {
  final Completer<void> _acceptCompleter = Completer<void>();

  @override
  Future<void> acceptFollowRequest(String followId) async {
    acceptFollowRequestCallCount++;
    await _acceptCompleter.future;
  }

  void completeAccept() {
    if (!_acceptCompleter.isCompleted) {
      _acceptCompleter.complete();
    }
  }
}

void main() {
  group('social providers', () {
    test('followersProvider reads from followRepositoryProvider', () async {
      final followRepository = FakeFollowRepository();
      final userSearchRepository = FakeUserSearchRepository();
      final container = ProviderContainer(
        overrides: [
          followRepositoryProvider.overrideWithValue(followRepository),
          userSearchRepositoryProvider.overrideWithValue(userSearchRepository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(followersProvider.future);

      expect(followRepository.getFollowersCallCount, 1);
    });

    test('followingProvider reads from followRepositoryProvider', () async {
      final followRepository = FakeFollowRepository();
      final userSearchRepository = FakeUserSearchRepository();
      final container = ProviderContainer(
        overrides: [
          followRepositoryProvider.overrideWithValue(followRepository),
          userSearchRepositoryProvider.overrideWithValue(userSearchRepository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(followingProvider.future);

      expect(followRepository.getFollowingCallCount, 1);
    });

    test(
      'pendingRequestsProvider reads from followRepositoryProvider',
      () async {
        final followRepository = FakeFollowRepository();
        final userSearchRepository = FakeUserSearchRepository();
        final container = ProviderContainer(
          overrides: [
            followRepositoryProvider.overrideWithValue(followRepository),
            userSearchRepositoryProvider.overrideWithValue(
              userSearchRepository,
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(pendingRequestsProvider.future);

        expect(followRepository.getPendingRequestsCallCount, 1);
      },
    );

    test(
      'relationshipCountsProvider reads from followRepositoryProvider',
      () async {
        final followRepository = FakeFollowRepository();
        final userSearchRepository = FakeUserSearchRepository();
        final container = ProviderContainer(
          overrides: [
            followRepositoryProvider.overrideWithValue(followRepository),
            userSearchRepositoryProvider.overrideWithValue(
              userSearchRepository,
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(relationshipCountsProvider.future);

        expect(followRepository.getRelationshipCountsCallCount, 1);
      },
    );

    test(
      'userSearchProvider trims empty query and skips repository call',
      () async {
        final followRepository = FakeFollowRepository();
        final userSearchRepository = FakeUserSearchRepository();
        final container = ProviderContainer(
          overrides: [
            followRepositoryProvider.overrideWithValue(followRepository),
            userSearchRepositoryProvider.overrideWithValue(
              userSearchRepository,
            ),
          ],
        );
        addTearDown(container.dispose);

        final result = await container.read(userSearchProvider('   ').future);

        expect(result, isEmpty);
        expect(userSearchRepository.callCount, 0);
      },
    );

    test('userSearchProvider forwards non-empty query to repository', () async {
      final followRepository = FakeFollowRepository();
      final userSearchRepository = FakeUserSearchRepository();
      final container = ProviderContainer(
        overrides: [
          followRepositoryProvider.overrideWithValue(followRepository),
          userSearchRepositoryProvider.overrideWithValue(userSearchRepository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(userSearchProvider(' runner ').future);

      expect(userSearchRepository.callCount, 1);
      expect(userSearchRepository.lastQuery, 'runner');
    });

    test(
      'followActionController invalidates relationship queries after send',
      () async {
        final followRepository = FakeFollowRepository();
        final userSearchRepository = FakeUserSearchRepository();
        final container = ProviderContainer(
          overrides: [
            followRepositoryProvider.overrideWithValue(followRepository),
            userSearchRepositoryProvider.overrideWithValue(
              userSearchRepository,
            ),
          ],
        );
        addTearDown(container.dispose);

        final followersSubscription = container.listen(
          followersProvider,
          (_, __) {},
        );
        final followingSubscription = container.listen(
          followingProvider,
          (_, __) {},
        );
        final pendingSubscription = container.listen(
          pendingRequestsProvider,
          (_, __) {},
        );
        final countsSubscription = container.listen(
          relationshipCountsProvider,
          (_, __) {},
        );
        final searchSubscription = container.listen(
          userSearchProvider('runner'),
          (_, __) {},
        );
        addTearDown(followersSubscription.close);
        addTearDown(followingSubscription.close);
        addTearDown(pendingSubscription.close);
        addTearDown(countsSubscription.close);
        addTearDown(searchSubscription.close);

        await container.read(followersProvider.future);
        await container.read(followingProvider.future);
        await container.read(pendingRequestsProvider.future);
        await container.read(relationshipCountsProvider.future);
        await container.read(userSearchProvider('runner').future);

        expect(followRepository.getFollowersCallCount, 1);
        expect(followRepository.getFollowingCallCount, 1);
        expect(followRepository.getPendingRequestsCallCount, 1);
        expect(followRepository.getRelationshipCountsCallCount, 1);
        expect(userSearchRepository.callCount, 1);

        await container
            .read(followActionControllerProvider.notifier)
            .sendFollowRequest(
              '22222222-2222-2222-2222-222222222222',
              activeSearchQuery: 'runner',
            );

        expect(followRepository.sendFollowRequestCallCount, 1);

        await container.read(followersProvider.future);
        await container.read(followingProvider.future);
        await container.read(pendingRequestsProvider.future);
        await container.read(relationshipCountsProvider.future);
        await container.read(userSearchProvider('runner').future);

        expect(followRepository.getFollowersCallCount, 2);
        expect(followRepository.getFollowingCallCount, 2);
        expect(followRepository.getPendingRequestsCallCount, 2);
        expect(followRepository.getRelationshipCountsCallCount, 2);
        expect(userSearchRepository.callCount, 2);
      },
    );

    test(
      'viewedUserProfileHeaderProvider reads follow-repository seam and avoids profileRepositoryProvider',
      () async {
        final followRepository = FakeFollowRepository()
          ..viewedUserProfileHeaderToReturn = const ViewedUserProfileHeader(
            user: SocialUserSummary(
              userId: 'user-2',
              displayName: 'Viewed Runner',
              avatarUrl: null,
              relationship: FollowRelationship(
                currentUserId: 'user-1',
                targetUserId: 'user-2',
                status: FollowRelationshipStatus.following,
              ),
            ),
            followersCount: 3,
            followingCount: 9,
          );
        final userSearchRepository = FakeUserSearchRepository();
        final container = ProviderContainer(
          overrides: [
            followRepositoryProvider.overrideWithValue(followRepository),
            userSearchRepositoryProvider.overrideWithValue(
              userSearchRepository,
            ),
            profileRepositoryProvider.overrideWith((ref) {
              throw StateError(
                'profileRepositoryProvider must stay self-only and unused',
              );
            }),
          ],
        );
        addTearDown(container.dispose);

        final header = await container.read(
          viewedUserProfileHeaderProvider('user-2').future,
        );

        expect(header?.user.userId, 'user-2');
        expect(header?.user.displayName, 'Viewed Runner');
        expect(header?.followersCount, 3);
        expect(header?.followingCount, 9);
        expect(followRepository.getViewedUserProfileHeaderCallCount, 1);
        expect(followRepository.lastViewedUserId, 'user-2');
      },
    );

    test(
      'followActionController invalidates viewed profile header, viewed user activities, and social feed caches',
      () async {
        const viewedUserId = '22222222-2222-2222-2222-222222222222';
        final followRepository = FakeFollowRepository();
        final userSearchRepository = FakeUserSearchRepository();
        final socialActivityRepository = _FakeSocialActivityRepository();
        final container = ProviderContainer(
          overrides: [
            followRepositoryProvider.overrideWithValue(followRepository),
            userSearchRepositoryProvider.overrideWithValue(
              userSearchRepository,
            ),
            socialActivityRepositoryProvider.overrideWithValue(
              socialActivityRepository,
            ),
          ],
        );
        addTearDown(container.dispose);

        final headerSubscription = container.listen(
          viewedUserProfileHeaderProvider(viewedUserId),
          (_, __) {},
        );
        final viewedActivitiesSubscription = container.listen(
          viewedUserActivityListProvider(viewedUserId),
          (_, __) {},
        );
        final socialFeedSubscription = container.listen(
          socialFeedProvider,
          (_, __) {},
        );
        addTearDown(headerSubscription.close);
        addTearDown(viewedActivitiesSubscription.close);
        addTearDown(socialFeedSubscription.close);

        await container.read(
          viewedUserProfileHeaderProvider(viewedUserId).future,
        );
        await container.read(
          viewedUserActivityListProvider(viewedUserId).future,
        );
        await container.read(socialFeedProvider.future);

        expect(followRepository.getViewedUserProfileHeaderCallCount, 1);
        expect(socialActivityRepository.loadUserActivitiesCallCount, 1);
        expect(socialActivityRepository.loadFeedActivitiesCallCount, 1);

        await container
            .read(followActionControllerProvider.notifier)
            .sendFollowRequest(viewedUserId);

        await container.pump();
        await container.read(
          viewedUserProfileHeaderProvider(viewedUserId).future,
        );
        await container.read(
          viewedUserActivityListProvider(viewedUserId).future,
        );
        await container.read(socialFeedProvider.future);

        expect(followRepository.sendFollowRequestCallCount, 1);
        expect(followRepository.getViewedUserProfileHeaderCallCount, 2);
        expect(socialActivityRepository.loadUserActivitiesCallCount, 2);
        expect(socialActivityRepository.loadFeedActivitiesCallCount, 2);
      },
    );

    test(
      'followActionController accept/reject/unfollow call repository methods',
      () async {
        final followRepository = FakeFollowRepository();
        final userSearchRepository = FakeUserSearchRepository();
        final container = ProviderContainer(
          overrides: [
            followRepositoryProvider.overrideWithValue(followRepository),
            userSearchRepositoryProvider.overrideWithValue(
              userSearchRepository,
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(followActionControllerProvider.notifier)
            .acceptFollowRequest('follow-1');
        await container
            .read(followActionControllerProvider.notifier)
            .rejectFollowRequest('follow-2');
        await container
            .read(followActionControllerProvider.notifier)
            .unfollow('user-2');

        expect(followRepository.acceptFollowRequestCallCount, 1);
        expect(followRepository.rejectFollowRequestCallCount, 1);
        expect(followRepository.unfollowCallCount, 1);
      },
    );

    test(
      'followActionController refreshes relationship and search queries after an async mutation with only notifier reads',
      () async {
        final followRepository = _BlockingFollowRepository();
        final userSearchRepository = FakeUserSearchRepository();
        final container = ProviderContainer(
          overrides: [
            followRepositoryProvider.overrideWithValue(followRepository),
            userSearchRepositoryProvider.overrideWithValue(
              userSearchRepository,
            ),
          ],
        );
        addTearDown(container.dispose);

        final followersSubscription = container.listen(
          followersProvider,
          (_, __) {},
        );
        final followingSubscription = container.listen(
          followingProvider,
          (_, __) {},
        );
        final pendingSubscription = container.listen(
          pendingRequestsProvider,
          (_, __) {},
        );
        final countsSubscription = container.listen(
          relationshipCountsProvider,
          (_, __) {},
        );
        final searchSubscription = container.listen(
          userSearchProvider('runner'),
          (_, __) {},
        );
        addTearDown(followersSubscription.close);
        addTearDown(followingSubscription.close);
        addTearDown(pendingSubscription.close);
        addTearDown(countsSubscription.close);
        addTearDown(searchSubscription.close);

        await container.read(followersProvider.future);
        await container.read(followingProvider.future);
        await container.read(pendingRequestsProvider.future);
        await container.read(relationshipCountsProvider.future);
        await container.read(userSearchProvider('runner').future);

        expect(followRepository.getFollowersCallCount, 1);
        expect(followRepository.getFollowingCallCount, 1);
        expect(followRepository.getPendingRequestsCallCount, 1);
        expect(followRepository.getRelationshipCountsCallCount, 1);
        expect(userSearchRepository.callCount, 1);

        final mutationFuture = container
            .read(followActionControllerProvider.notifier)
            .acceptFollowRequest('follow-1', activeSearchQuery: 'runner');

        await container.pump();
        followRepository.completeAccept();
        await mutationFuture;
        await container.pump();

        expect(followRepository.acceptFollowRequestCallCount, 1);
        expect(followRepository.getFollowersCallCount, 2);
        expect(followRepository.getFollowingCallCount, 2);
        expect(followRepository.getPendingRequestsCallCount, 2);
        expect(followRepository.getRelationshipCountsCallCount, 2);
        expect(userSearchRepository.callCount, 2);
      },
    );

    test(
      'followActionController invalidates userSearchProvider even without active query',
      () async {
        final followRepository = FakeFollowRepository();
        final userSearchRepository = FakeUserSearchRepository();
        final container = ProviderContainer(
          overrides: [
            followRepositoryProvider.overrideWithValue(followRepository),
            userSearchRepositoryProvider.overrideWithValue(
              userSearchRepository,
            ),
          ],
        );
        addTearDown(container.dispose);

        final searchSubscription = container.listen(
          userSearchProvider('runner'),
          (_, __) {},
        );
        addTearDown(searchSubscription.close);

        await container.read(userSearchProvider('runner').future);
        expect(userSearchRepository.callCount, 1);

        await container
            .read(followActionControllerProvider.notifier)
            .acceptFollowRequest('follow-1');

        // Non-search surfaces (followers/following/requests) do not pass an
        // active query, but search caches still must refresh after mutations.
        await container.read(userSearchProvider('runner').future);
        expect(userSearchRepository.callCount, 2);
      },
    );

    test(
      'followActionController invalidates trimmed userSearchProvider when active query has extra whitespace',
      () async {
        final followRepository = FakeFollowRepository();
        final userSearchRepository = FakeUserSearchRepository();
        final container = ProviderContainer(
          overrides: [
            followRepositoryProvider.overrideWithValue(followRepository),
            userSearchRepositoryProvider.overrideWithValue(
              userSearchRepository,
            ),
          ],
        );
        addTearDown(container.dispose);

        final searchSubscription = container.listen(
          userSearchProvider('runner'),
          (_, __) {},
        );
        addTearDown(searchSubscription.close);

        await container.read(userSearchProvider('runner').future);
        expect(userSearchRepository.callCount, 1);

        await container
            .read(followActionControllerProvider.notifier)
            .sendFollowRequest(
              '22222222-2222-2222-2222-222222222222',
              activeSearchQuery: ' runner ',
            );

        await container.read(userSearchProvider('runner').future);
        expect(userSearchRepository.callCount, 2);
      },
    );

    test(
      'followActionController does not throw when disposed during async mutation',
      () async {
        final followRepository = _BlockingFollowRepository();
        final userSearchRepository = FakeUserSearchRepository();
        final container = ProviderContainer(
          overrides: [
            followRepositoryProvider.overrideWithValue(followRepository),
            userSearchRepositoryProvider.overrideWithValue(
              userSearchRepository,
            ),
          ],
        );

        final mutationFuture = container
            .read(followActionControllerProvider.notifier)
            .acceptFollowRequest('follow-1');

        container.dispose();
        followRepository.completeAccept();

        await expectLater(mutationFuture, completes);
        expect(followRepository.acceptFollowRequestCallCount, 1);
      },
    );
  });
}

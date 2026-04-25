import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart';
import 'package:uff/src/features/photos/data/photo_repository.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/data/social_activity_repository.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/remote_activity_track_point.dart';
import 'package:uff/src/features/social/domain/social_activity_detail.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';

/// ## Test Scenarios
/// - [positive] Feed and viewed-user list providers delegate to SocialActivityRepository.
/// - [positive] Remote detail provider composes social detail with activity photo data.
/// - [negative] Remote detail provider returns null and skips photo reads when detail is missing.
/// - [isolation] Social providers fail loudly if they accidentally depend on activity-tracking state.
/// - [isolation] Viewed-user list and detail providers preserve UUID-scoped routing inputs.
const _viewerId = '11111111-1111-1111-1111-111111111111';
const _ownerId = '22222222-2222-2222-2222-222222222222';

class _FakeSocialActivityRepository implements SocialActivityRepository {
  List<SocialActivitySummary> feedToReturn = const <SocialActivitySummary>[];
  List<SocialActivitySummary> userActivitiesToReturn =
      const <SocialActivitySummary>[];
  SocialActivityDetail? detailToReturn;

  int loadFeedActivitiesCallCount = 0;
  int loadUserActivitiesCallCount = 0;
  int loadActivityDetailCallCount = 0;

  String? lastViewedUserId;
  String? lastActivityId;

  @override
  Future<SocialActivityDetail?> loadActivityDetail(String activityId) async {
    loadActivityDetailCallCount++;
    lastActivityId = activityId;
    return detailToReturn;
  }

  @override
  Future<List<SocialActivitySummary>> loadFeedActivities({
    required int offset,
    required int limit,
  }) async {
    loadFeedActivitiesCallCount++;
    return feedToReturn;
  }

  @override
  Future<List<SocialActivitySummary>> loadUserActivities(String userId) async {
    loadUserActivitiesCallCount++;
    lastViewedUserId = userId;
    return userActivitiesToReturn;
  }
}

class _FakePhotoRepository implements PhotoRepository {
  int loadActivityPhotosCallCount = 0;
  String? lastActivityId;
  List<ActivityPhoto> photosToReturn = const <ActivityPhoto>[];

  @override
  Future<void> deletePhoto(ActivityPhoto photo) {
    throw UnimplementedError();
  }

  @override
  Future<List<ActivityPhoto>> loadActivityPhotos(String activityId) async {
    loadActivityPhotosCallCount++;
    lastActivityId = activityId;
    return photosToReturn;
  }

  @override
  Future<ActivityPhoto> uploadPhoto({
    required String activityId,
    required Uint8List bytes,
    required String fileName,
    required int sortOrder,
    double? latitude,
    double? longitude,
  }) {
    throw UnimplementedError();
  }
}

SocialUserSummary _ownerSummary() {
  return const SocialUserSummary(
    userId: _ownerId,
    displayName: 'Owner Runner',
    avatarUrl: 'https://cdn.example.com/owner.jpg',
    relationship: FollowRelationship(
      currentUserId: _viewerId,
      targetUserId: _ownerId,
      status: FollowRelationshipStatus.none,
    ),
  );
}

SocialActivitySummary _summary(String activityId) {
  return SocialActivitySummary(
    activityId: activityId,
    owner: _ownerSummary(),
    sportType: 'run',
    startedAt: DateTime.utc(2026, 3, 19, 10),
    finishedAt: DateTime.utc(2026, 3, 19, 11),
    distanceMeters: 3218,
    durationSeconds: 1320,
    elevationGainMeters: 25,
    avgPaceSecondsPerKm: 410,
    title: 'Morning Run',
    description: null,
    visibility: 'public',
    polylineEncoded: null,
    commentCount: 0,
    kudosCount: 0,
    viewerHasKudo: false,
  );
}

SocialActivityDetail _detail(String activityId) {
  return SocialActivityDetail(
    activityId: activityId,
    owner: _ownerSummary(),
    sportType: 'run',
    startedAt: DateTime.utc(2026, 3, 19, 10),
    finishedAt: DateTime.utc(2026, 3, 19, 11),
    distanceMeters: 3218,
    durationSeconds: 1320,
    elevationGainMeters: 25,
    avgPaceSecondsPerKm: 410,
    title: 'Morning Run',
    description: null,
    visibility: 'public',
    polylineEncoded: null,
    kudosCount: 0,
    viewerHasKudo: false,
    splits: const <SocialActivitySplit>[],
    trackPoints: <RemoteActivityTrackPoint>[
      RemoteActivityTrackPoint(
        id: 1,
        activityId: activityId,
        timestamp: DateTime.utc(2026, 3, 19, 10, 0, 1),
        latitude: null,
        longitude: null,
        elevation: 8,
        heartRate: 145,
        cadence: 86,
        speed: 3.5,
        distance: 10,
        temperature: 18,
      ),
    ],
  );
}

ActivityPhoto _photo(String activityId) {
  return ActivityPhoto(
    id: 'photo-1',
    activityId: activityId,
    userId: _ownerId,
    storagePath: '$_ownerId/$activityId/photo-1.jpg',
    thumbnailPath: '$_ownerId/$activityId/photo-1_thumb.jpg',
    sortOrder: 0,
    createdAt: DateTime.utc(2026, 3, 19, 11, 30),
  );
}

ProviderContainer _container({
  required _FakeSocialActivityRepository socialRepository,
  required _FakePhotoRepository photoRepository,
}) {
  return ProviderContainer(
    overrides: [
      socialActivityRepositoryProvider.overrideWithValue(socialRepository),
      photoRepositoryProvider.overrideWithValue(photoRepository),
      savedActivitiesProvider.overrideWith(
        (ref) => Future<List<TrackingSessionRecord>>.error(
          StateError(
            'savedActivitiesProvider should not be used by social reads',
          ),
        ),
      ),
    ],
  );
}

void main() {
  group('social activity providers', () {
    test('socialFeedProvider returns empty list from repository', () async {
      final socialRepository = _FakeSocialActivityRepository()
        ..feedToReturn = const <SocialActivitySummary>[];
      final photoRepository = _FakePhotoRepository();
      final container = _container(
        socialRepository: socialRepository,
        photoRepository: photoRepository,
      );
      addTearDown(container.dispose);

      final feedState = await container.read(socialFeedProvider.future);

      expect(feedState.activities, isEmpty);
      expect(socialRepository.loadFeedActivitiesCallCount, 1);
    });

    test(
      'viewedUserActivityListProvider returns empty list from repository',
      () async {
        final socialRepository = _FakeSocialActivityRepository()
          ..userActivitiesToReturn = const <SocialActivitySummary>[];
        final photoRepository = _FakePhotoRepository();
        final container = _container(
          socialRepository: socialRepository,
          photoRepository: photoRepository,
        );
        addTearDown(container.dispose);

        final list = await container.read(
          viewedUserActivityListProvider(_ownerId).future,
        );

        expect(list, isEmpty);
        expect(socialRepository.lastViewedUserId, _ownerId);
        expect(socialRepository.loadUserActivitiesCallCount, 1);
      },
    );

    test(
      'viewedUserActivityListProvider loads UUID-scoped remote list',
      () async {
        final socialRepository = _FakeSocialActivityRepository()
          ..userActivitiesToReturn = <SocialActivitySummary>[
            _summary('activity-a'),
          ];
        final photoRepository = _FakePhotoRepository();
        final container = _container(
          socialRepository: socialRepository,
          photoRepository: photoRepository,
        );
        addTearDown(container.dispose);

        final list = await container.read(
          viewedUserActivityListProvider(_ownerId).future,
        );

        expect(list, hasLength(1));
        expect(list.single.activityId, 'activity-a');
        expect(socialRepository.lastViewedUserId, _ownerId);
        expect(socialRepository.loadUserActivitiesCallCount, 1);
      },
    );

    test(
      'remoteActivityDetailProvider composes detail with activityPhotoListProvider',
      () async {
        const activityId = 'activity-123';
        final socialRepository = _FakeSocialActivityRepository()
          ..detailToReturn = _detail(activityId);
        final photoRepository = _FakePhotoRepository()
          ..photosToReturn = <ActivityPhoto>[_photo(activityId)];
        final container = _container(
          socialRepository: socialRepository,
          photoRepository: photoRepository,
        );
        addTearDown(container.dispose);

        final result = await container.read(
          remoteActivityDetailProvider(activityId).future,
        );

        expect(result?.detail.activityId, activityId);
        expect(result?.detail.owner.userId, _ownerId);
        expect(result?.photos, hasLength(1));
        expect(result?.photos.single.activityId, activityId);
        expect(photoRepository.loadActivityPhotosCallCount, 1);
        expect(photoRepository.lastActivityId, activityId);
        expect(socialRepository.loadActivityDetailCallCount, 1);
        expect(socialRepository.lastActivityId, activityId);
      },
    );

    test(
      'remoteActivityDetailProvider forwards UUID activity ids without rewriting',
      () async {
        const activityId = '6f1c6ecf-8922-4c20-b74f-8f53ab4ec8f8';
        final socialRepository = _FakeSocialActivityRepository()
          ..detailToReturn = _detail(activityId);
        final photoRepository = _FakePhotoRepository()
          ..photosToReturn = const <ActivityPhoto>[];
        final container = _container(
          socialRepository: socialRepository,
          photoRepository: photoRepository,
        );
        addTearDown(container.dispose);

        final result = await container.read(
          remoteActivityDetailProvider(activityId).future,
        );

        expect(result?.detail.activityId, activityId);
        expect(result?.photos, isEmpty);
        expect(socialRepository.lastActivityId, activityId);
        expect(photoRepository.lastActivityId, activityId);
      },
    );

    test(
      'remoteActivityDetailProvider skips photo load when detail is missing',
      () async {
        const activityId = 'missing-activity';
        final socialRepository = _FakeSocialActivityRepository()
          ..detailToReturn = null;
        final photoRepository = _FakePhotoRepository();
        final container = _container(
          socialRepository: socialRepository,
          photoRepository: photoRepository,
        );
        addTearDown(container.dispose);

        final result = await container.read(
          remoteActivityDetailProvider(activityId).future,
        );

        expect(result, isNull);
        expect(photoRepository.loadActivityPhotosCallCount, 0);
        expect(socialRepository.loadActivityDetailCallCount, 1);
      },
    );
  });
}

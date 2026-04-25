// Scenario tags use bracket syntax enforced by the test standards script.
// ignore_for_file: comment_references

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';
import 'package:uff/src/features/social/data/social_activity_repository.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/remote_activity_track_point.dart';
import 'package:uff/src/features/social/domain/social_activity_detail.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';

/// ## Test Scenarios
/// - [positive] SocialActivityRepository exposes feed, viewed-user list, and detail read operations.
/// - [positive] Repository contract forwards input identifiers to the implementation seam.
/// - [negative] Repository contract does not invent fallback ids or mutate caller-owned identifiers.
/// - [isolation] Feed, viewed-user list, and detail reads remain independently addressable contract seams.
/// - [edge] Summary preview contract can represent owner polylines or viewer-visible masked route points without exposing owner-only geometry.
/// - [edge] RemoteActivityTrackPoint allows masked latitude/longitude for privacy-zone reads.
const _viewerId = '11111111-1111-1111-1111-111111111111';
const _ownerId = '22222222-2222-2222-2222-222222222222';
const _rawTwoPointRoutePolyline = '_p~iF~ps|U_ulLnnqC';

class _FakeSocialActivityRepository implements SocialActivityRepository {
  int loadFeedActivitiesCallCount = 0;
  int loadUserActivitiesCallCount = 0;
  int loadActivityDetailCallCount = 0;
  String? lastUserId;
  String? lastActivityId;

  @override
  Future<SocialActivityDetail?> loadActivityDetail(String activityId) async {
    loadActivityDetailCallCount++;
    lastActivityId = activityId;
    return _testActivityDetail(activityId: activityId);
  }

  @override
  Future<List<SocialActivitySummary>> loadFeedActivities({
    required int offset,
    required int limit,
  }) async {
    loadFeedActivitiesCallCount++;
    return <SocialActivitySummary>[_testActivitySummary(activityId: 'feed-1')];
  }

  @override
  Future<List<SocialActivitySummary>> loadUserActivities(String userId) async {
    loadUserActivitiesCallCount++;
    lastUserId = userId;
    return <SocialActivitySummary>[
      _testActivitySummary(activityId: 'user-activity-1'),
    ];
  }
}

SocialUserSummary _testOwnerSummary() {
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

SocialActivitySummary _testActivitySummary({
  required String activityId,
  String? polylineEncoded,
  List<RoutePoint>? routePoints,
}) {
  return SocialActivitySummary(
    activityId: activityId,
    owner: _testOwnerSummary(),
    sportType: 'run',
    startedAt: DateTime.utc(2026, 3, 19, 12),
    finishedAt: DateTime.utc(2026, 3, 19, 13),
    distanceMeters: 5000,
    durationSeconds: 1500,
    elevationGainMeters: 42,
    avgPaceSecondsPerKm: 300,
    title: 'Lunch Run',
    description: 'Steady aerobic effort',
    visibility: 'followers',
    polylineEncoded: polylineEncoded,
    routePoints: routePoints,
    commentCount: 0,
    kudosCount: 3,
    viewerHasKudo: true,
  );
}

SocialActivityDetail _testActivityDetail({required String activityId}) {
  return SocialActivityDetail(
    activityId: activityId,
    owner: _testOwnerSummary(),
    sportType: 'run',
    startedAt: DateTime.utc(2026, 3, 19, 12),
    finishedAt: DateTime.utc(2026, 3, 19, 13),
    distanceMeters: 5000,
    durationSeconds: 1500,
    elevationGainMeters: 42,
    avgPaceSecondsPerKm: 300,
    title: 'Lunch Run',
    description: 'Steady aerobic effort',
    visibility: 'followers',
    polylineEncoded: null,
    kudosCount: 3,
    viewerHasKudo: true,
    splits: const <SocialActivitySplit>[
      SocialActivitySplit(
        splitNumber: 1,
        distanceMeters: 1000,
        durationSeconds: 300,
        avgPaceSecondsPerKm: 300,
        avgHeartRate: 152,
        elevationChangeMeters: 5,
      ),
    ],
    trackPoints: <RemoteActivityTrackPoint>[
      RemoteActivityTrackPoint(
        id: 1,
        activityId: activityId,
        timestamp: DateTime.utc(2026, 3, 19, 12),
        latitude: null,
        longitude: null,
        elevation: 12.5,
        heartRate: 150,
        cadence: 88,
        speed: 3.2,
        distance: 200,
        temperature: 19,
      ),
    ],
  );
}

void main() {
  group('SocialActivityRepository contract', () {
    test('exposes read-only feed, user-list, and detail operations', () async {
      final repository = _FakeSocialActivityRepository();

      final feed = await repository.loadFeedActivities(offset: 0, limit: 20);
      final userList = await repository.loadUserActivities(_ownerId);
      final detail = await repository.loadActivityDetail('activity-123');

      expect(feed, hasLength(1));
      expect(userList, hasLength(1));
      expect(detail?.activityId, 'activity-123');
      expect(detail?.owner.userId, _ownerId);
      expect(repository.loadFeedActivitiesCallCount, 1);
      expect(repository.loadUserActivitiesCallCount, 1);
      expect(repository.loadActivityDetailCallCount, 1);
      expect(repository.lastUserId, _ownerId);
      expect(repository.lastActivityId, 'activity-123');
    });
  });

  group('SocialActivitySummary preview contract', () {
    test(
      'supports owner-visible polylines and viewer-visible masked route points',
      () {
        final ownerVisibleSummary = _testActivitySummary(
          activityId: 'owner-visible',
          polylineEncoded: _rawTwoPointRoutePolyline,
        );
        final maskedSummary = _testActivitySummary(
          activityId: 'masked-visible',
          routePoints: const <RoutePoint>[
            RoutePoint(latitude: 40.7, longitude: -120.95),
            RoutePoint(latitude: 43.252, longitude: -126.453),
          ],
        );

        expect(ownerVisibleSummary.polylineEncoded, _rawTwoPointRoutePolyline);
        expect(ownerVisibleSummary.routePoints, isNull);
        expect(maskedSummary.polylineEncoded, isNull);
        expect(
          maskedSummary.routePoints,
          const <RoutePoint>[
            RoutePoint(latitude: 40.7, longitude: -120.95),
            RoutePoint(latitude: 43.252, longitude: -126.453),
          ],
        );
        expect(
          () => maskedSummary.routePoints!.add(
            const RoutePoint(latitude: 39, longitude: -121),
          ),
          throwsUnsupportedError,
        );
      },
    );

    test('copies masked route points at construction', () {
      final sourceRoutePoints = <RoutePoint>[
        const RoutePoint(latitude: 40.7, longitude: -120.95),
        const RoutePoint(latitude: 43.252, longitude: -126.453),
      ];

      final maskedSummary = _testActivitySummary(
        activityId: 'masked-copy',
        routePoints: sourceRoutePoints,
      );
      sourceRoutePoints.add(const RoutePoint(latitude: 39, longitude: -121));

      expect(
        maskedSummary.routePoints,
        const <RoutePoint>[
          RoutePoint(latitude: 40.7, longitude: -120.95),
          RoutePoint(latitude: 43.252, longitude: -126.453),
        ],
      );
    });
  });

  group('RemoteActivityTrackPoint', () {
    test('allows masked coordinates from read_activity_track_points', () {
      final maskedPoint = RemoteActivityTrackPoint(
        id: 7,
        activityId: 'activity-123',
        timestamp: DateTime.utc(2026, 3, 19, 12, 3),
        latitude: null,
        longitude: null,
        elevation: 15.2,
        heartRate: 149,
        cadence: 86,
        speed: 3.4,
        distance: 350,
        temperature: 20,
      );

      expect(maskedPoint.latitude, isNull);
      expect(maskedPoint.longitude, isNull);
    });
  });
}

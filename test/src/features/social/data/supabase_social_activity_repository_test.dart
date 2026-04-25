// Scenario tags use bracket syntax enforced by the test standards script.
// ignore_for_file: comment_references

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';
import 'package:uff/src/features/maps/data/polyline_codec.dart';
import 'package:uff/src/features/social/data/supabase_social_activity_repository.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';

import '../../../test_helpers/supabase_query_test_doubles.dart';

/// ## Test Scenarios
/// - [positive] Feed and viewed-user list reads map social summaries, relationship state, and kudos metadata.
/// - [negative] Non-owner list summaries must not leak raw route polylines and should derive preview truth from masked RPC track points.
/// - [positive] Detail read maps activity payload, ordered splits, and RPC track points.
/// - [negative] Detail read returns null when the activity row is not visible.
/// - [isolation] Feed, list, and detail reads require an authenticated viewer session.
/// - [edge] Feed read short-circuits to empty when the viewer follows no accepted owners.
class MockGoTrueClient extends Mock implements GoTrueClient {}

const _rawTwoPointRoutePolyline = '_p~iF~ps|U_ulLnnqC';
const _viewerUserId = '11111111-1111-1111-1111-111111111111';
const _ownerUserId = '22222222-2222-2222-2222-222222222222';
const _strangerUserId = '99999999-9999-9999-9999-999999999999';
const _ownerVisibleRouteCoordinates = <Map<String, double?>>[
  <String, double?>{'latitude': 38.5, 'longitude': -120.2},
  <String, double?>{'latitude': 40.7, 'longitude': -120.95},
];
const _maskedSummaryRouteCoordinates = <Map<String, double?>>[
  <String, double?>{'latitude': null, 'longitude': null},
  <String, double?>{'latitude': 40.7, 'longitude': -120.95},
  <String, double?>{'latitude': 43.252, 'longitude': -126.453},
];
const _maskedSummaryVisibleRoutePoints = <RoutePoint>[
  RoutePoint(latitude: 40.7, longitude: -120.95),
  RoutePoint(latitude: 43.252, longitude: -126.453),
];

User _testUser({
  String id = '11111111-1111-1111-1111-111111111111',
  String email = 'test@example.com',
}) {
  return User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00.000Z',
    email: email,
  );
}

Map<String, dynamic> _profileRow({
  required String id,
  required String displayName,
  String? avatarUrl,
}) => {
  'id': id,
  'display_name': displayName,
  'avatar_url': avatarUrl,
};

Map<String, dynamic> _activityRow({
  required String id,
  required String userId,
  required String startedAt,
  required Map<String, dynamic> profile,
  String visibility = 'public',
  String sportType = 'run',
  String? title,
  String? polylineEncoded,
}) => {
  'id': id,
  'user_id': userId,
  'sport_type': sportType,
  'started_at': startedAt,
  'finished_at': '2026-03-19T12:30:00.000Z',
  'distance_meters': 5200.0,
  'duration_seconds': 1850,
  'elevation_gain_meters': 32.0,
  'avg_pace_seconds_per_km': 355.0,
  'title': title,
  'description': 'Steady effort',
  'visibility': visibility,
  'polyline_encoded': polylineEncoded,
  'created_at': '2026-03-19T12:31:00.000Z',
  'updated_at': '2026-03-19T12:35:00.000Z',
  'profiles': profile,
};

Map<String, dynamic> _kudosRow({
  required String activityId,
  required String userId,
}) => {
  'activity_id': activityId,
  'user_id': userId,
};

Map<String, dynamic> _followRow({
  required String id,
  required String followerId,
  required String followingId,
  required String status,
}) => {
  'id': id,
  'follower_id': followerId,
  'following_id': followingId,
  'status': status,
  'created_at': '2026-03-19T12:00:00.000Z',
};

Map<String, dynamic> _splitRow({
  required int splitNumber,
  required double distanceMeters,
  required int durationSeconds,
}) => {
  'split_number': splitNumber,
  'distance_meters': distanceMeters,
  'duration_seconds': durationSeconds,
  'avg_pace_seconds_per_km': 360.0,
  'avg_heart_rate': 154,
  'elevation_change_meters': 4.0,
};

Map<String, dynamic> _trackPointRow({
  required int id,
  required String activityId,
  required String timestamp,
  required double? latitude,
  required double? longitude,
}) => {
  'id': id,
  'activity_id': activityId,
  'timestamp': timestamp,
  'latitude': latitude,
  'longitude': longitude,
  'elevation': 12.0,
  'heart_rate': 150,
  'cadence': 88,
  'power': null,
  'speed': 3.4,
  'distance': 250.0,
  'temperature': 19,
};

List<Map<String, dynamic>> _trackPointRowsFromCoordinates({
  required String activityId,
  required List<Map<String, double?>> coordinates,
}) {
  return List<Map<String, dynamic>>.generate(coordinates.length, (index) {
    final coordinate = coordinates[index];
    final pointIndex = index + 1;
    return _trackPointRow(
      id: pointIndex,
      activityId: activityId,
      timestamp: '2026-03-19T12:00:0$pointIndex.000Z',
      latitude: coordinate['latitude'],
      longitude: coordinate['longitude'],
    );
  });
}

void _stubTable(
  MockSupabaseClient mockClient,
  String tableName,
  RecordingSupabaseQueryBuilder Function() builder,
) {
  when(() => mockClient.from(tableName)).thenAnswer((_) => builder());
}

void _stubTrackPointRpc(
  MockSupabaseClient mockClient,
  String activityId,
  RecordingPostgrestListBuilder builder,
) {
  when(
    () => mockClient.rpc<List<Map<String, dynamic>>>(
      'read_activity_track_points',
      params: {'p_activity_id': activityId},
    ),
  ).thenAnswer((_) => builder);
}

void _verifyTrackPointRpc(MockSupabaseClient mockClient, String activityId) {
  verify(
    () => mockClient.rpc<List<Map<String, dynamic>>>(
      'read_activity_track_points',
      params: {'p_activity_id': activityId},
    ),
  ).called(1);
}

void _verifyNoTrackPointRpc(MockSupabaseClient mockClient, String activityId) {
  verifyNever(
    () => mockClient.rpc<List<Map<String, dynamic>>>(
      'read_activity_track_points',
      params: {'p_activity_id': activityId},
    ),
  );
}

class _MaskedSummaryPreviewScenario {
  const _MaskedSummaryPreviewScenario({
    required this.activityId,
    required this.viewerUserId,
    this.ownerPolylineEncoded = _rawTwoPointRoutePolyline,
    this.acceptedFollow = false,
    this.loadFeed = false,
  });

  final String activityId;
  final String viewerUserId;
  final String? ownerPolylineEncoded;
  final bool acceptedFollow;
  final bool loadFeed;
}

Future<void> _expectMaskedSummaryPreview(
  MockSupabaseClient mockClient,
  MockGoTrueClient mockAuth,
  _MaskedSummaryPreviewScenario scenario,
) async {
  when(
    () => mockAuth.currentUser,
  ).thenReturn(_testUser(id: scenario.viewerUserId));

  final activitiesBuilder = RecordingSupabaseQueryBuilder(
    selectRows: [
      _activityRow(
        id: scenario.activityId,
        userId: _ownerUserId,
        startedAt: '2026-03-19T12:00:00.000Z',
        profile: _profileRow(id: _ownerUserId, displayName: 'Owner Runner'),
        polylineEncoded: scenario.ownerPolylineEncoded,
      ),
    ],
  );
  final kudosBuilder = RecordingSupabaseQueryBuilder();
  final followedOwnersBuilder = RecordingSupabaseQueryBuilder(
    selectRows: [
      if (scenario.loadFeed) {'following_id': _ownerUserId},
    ],
  );
  final outgoingFollowsBuilder = RecordingSupabaseQueryBuilder(
    selectRows: [
      if (scenario.acceptedFollow)
        _followRow(
          id: 'accepted-follow',
          followerId: scenario.viewerUserId,
          followingId: _ownerUserId,
          status: 'accepted',
        ),
    ],
  );
  final incomingPendingBuilder = RecordingSupabaseQueryBuilder();
  final trackPointRpcBuilder = RecordingPostgrestListBuilder(
    _trackPointRowsFromCoordinates(
      activityId: scenario.activityId,
      coordinates: _maskedSummaryRouteCoordinates,
    ),
  );
  final followsBuilders = <RecordingSupabaseQueryBuilder>[
    if (scenario.loadFeed) followedOwnersBuilder,
    outgoingFollowsBuilder,
    incomingPendingBuilder,
  ];
  _stubTable(mockClient, 'activities', () => activitiesBuilder);
  _stubTable(mockClient, 'kudos', () => kudosBuilder);
  _stubTable(mockClient, 'follows', () => followsBuilders.removeAt(0));
  _stubTrackPointRpc(mockClient, scenario.activityId, trackPointRpcBuilder);

  final repository = SupabaseSocialActivityRepository(mockClient);
  final summaries = scenario.loadFeed
      ? await repository.loadFeedActivities(offset: 0, limit: 20)
      : await repository.loadUserActivities(_ownerUserId);

  expect(summaries, hasLength(1));
  expect(summaries.single.activityId, scenario.activityId);
  expect(summaries.single.polylineEncoded, isNull);
  expect(summaries.single.routePoints, _maskedSummaryVisibleRoutePoints);
  _verifyTrackPointRpc(mockClient, scenario.activityId);
  if (scenario.loadFeed) {
    verifyNever(() => mockClient.from('track_points'));
  }
}

void main() {
  late MockSupabaseClient mockClient;
  late MockGoTrueClient mockAuth;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockGoTrueClient();
    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(_testUser());
  });

  group('SupabaseSocialActivityRepository list reads', () {
    test(
      'loadFeedActivities returns followed-user summaries in newest-first order',
      () async {
        final followedOwnersBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            {'following_id': '22222222-2222-2222-2222-222222222222'},
            {'following_id': '33333333-3333-3333-3333-333333333333'},
          ],
        );
        final activitiesBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _activityRow(
              id: 'activity-new',
              userId: '22222222-2222-2222-2222-222222222222',
              startedAt: '2026-03-19T12:00:00.000Z',
              profile: _profileRow(
                id: '22222222-2222-2222-2222-222222222222',
                displayName: 'Latest Runner',
              ),
              title: 'Newest',
            ),
            _activityRow(
              id: 'activity-old',
              userId: '33333333-3333-3333-3333-333333333333',
              startedAt: '2026-03-18T12:00:00.000Z',
              profile: _profileRow(
                id: '33333333-3333-3333-3333-333333333333',
                displayName: 'Earlier Runner',
              ),
              title: 'Older',
            ),
          ],
        );
        final kudosBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _kudosRow(
              activityId: 'activity-new',
              userId: '11111111-1111-1111-1111-111111111111',
            ),
            _kudosRow(
              activityId: 'activity-new',
              userId: '44444444-4444-4444-4444-444444444444',
            ),
          ],
        );
        final outgoingFollowsBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _followRow(
              id: 'follow-accepted',
              followerId: '11111111-1111-1111-1111-111111111111',
              followingId: '22222222-2222-2222-2222-222222222222',
              status: 'accepted',
            ),
            _followRow(
              id: 'follow-accepted-2',
              followerId: '11111111-1111-1111-1111-111111111111',
              followingId: '33333333-3333-3333-3333-333333333333',
              status: 'accepted',
            ),
          ],
        );
        final incomingPendingBuilder = RecordingSupabaseQueryBuilder();
        final emptyTrackPointRpcBuilder = RecordingPostgrestListBuilder(
          const <Map<String, dynamic>>[],
        );
        final followsBuilders = <RecordingSupabaseQueryBuilder>[
          followedOwnersBuilder,
          outgoingFollowsBuilder,
          incomingPendingBuilder,
        ];
        _stubTable(mockClient, 'activities', () => activitiesBuilder);
        _stubTable(mockClient, 'kudos', () => kudosBuilder);
        _stubTable(mockClient, 'follows', () => followsBuilders.removeAt(0));
        _stubTrackPointRpc(
          mockClient,
          'activity-new',
          emptyTrackPointRpcBuilder,
        );
        _stubTrackPointRpc(
          mockClient,
          'activity-old',
          emptyTrackPointRpcBuilder,
        );

        final repository = SupabaseSocialActivityRepository(mockClient);
        final feed = await repository.loadFeedActivities(offset: 0, limit: 20);

        expect(feed, hasLength(2));
        expect(feed.first.activityId, 'activity-new');
        expect(feed.first.owner.displayName, 'Latest Runner');
        expect(
          feed.first.owner.relationship.status,
          FollowRelationshipStatus.following,
        );
        expect(feed.first.kudosCount, 2);
        expect(feed.first.viewerHasKudo, isTrue);
        expect(feed.last.activityId, 'activity-old');
        expect(feed.last.kudosCount, 0);
        expect(feed.last.viewerHasKudo, isFalse);
        expect(
          feed.last.owner.relationship.status,
          FollowRelationshipStatus.following,
        );
        expect(feed.first.owner.userId, '22222222-2222-2222-2222-222222222222');
        expect(feed.first.title, 'Newest');
        expect(activitiesBuilder.selectBuilder.lastOrderedColumn, 'started_at');
        expect(activitiesBuilder.selectBuilder.lastOrderAscending, isFalse);
        expect(
          activitiesBuilder.selectBuilder.lastInFilterColumn,
          'user_id',
        );
        expect(
          activitiesBuilder.selectBuilder.lastInFilterValues,
          <Object?>[
            '22222222-2222-2222-2222-222222222222',
            '33333333-3333-3333-3333-333333333333',
          ],
        );
        verifyNever(() => mockClient.from('profiles'));
      },
    );

    test(
      'loadFeedActivities returns empty without querying activities when viewer follows nobody',
      () async {
        final followedOwnersBuilder = RecordingSupabaseQueryBuilder();
        _stubTable(mockClient, 'follows', () => followedOwnersBuilder);

        final repository = SupabaseSocialActivityRepository(mockClient);
        final feed = await repository.loadFeedActivities(offset: 0, limit: 20);

        expect(feed, isEmpty);
        verifyNever(() => mockClient.from('activities'));
        verifyNever(() => mockClient.from('kudos'));
      },
    );

    test(
      'loadUserActivities filters by owner id and preserves social list shape',
      () async {
        final activitiesBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _activityRow(
              id: 'activity-1',
              userId: '22222222-2222-2222-2222-222222222222',
              startedAt: '2026-03-19T12:00:00.000Z',
              profile: _profileRow(
                id: '22222222-2222-2222-2222-222222222222',
                displayName: 'Owner Runner',
              ),
            ),
          ],
        );
        final kudosBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _kudosRow(
              activityId: 'activity-1',
              userId: '11111111-1111-1111-1111-111111111111',
            ),
          ],
        );
        final outgoingFollowsBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _followRow(
              id: 'follow-pending',
              followerId: '11111111-1111-1111-1111-111111111111',
              followingId: '22222222-2222-2222-2222-222222222222',
              status: 'pending',
            ),
          ],
        );
        final incomingPendingBuilder = RecordingSupabaseQueryBuilder();
        final emptyTrackPointRpcBuilder = RecordingPostgrestListBuilder(
          const <Map<String, dynamic>>[],
        );
        final followsBuilders = <RecordingSupabaseQueryBuilder>[
          outgoingFollowsBuilder,
          incomingPendingBuilder,
        ];
        _stubTable(mockClient, 'activities', () => activitiesBuilder);
        _stubTable(mockClient, 'kudos', () => kudosBuilder);
        _stubTable(mockClient, 'follows', () => followsBuilders.removeAt(0));
        _stubTrackPointRpc(mockClient, 'activity-1', emptyTrackPointRpcBuilder);

        final repository = SupabaseSocialActivityRepository(mockClient);
        final list = await repository.loadUserActivities(
          '22222222-2222-2222-2222-222222222222',
        );

        expect(list, hasLength(1));
        expect(list.single.activityId, 'activity-1');
        expect(list.single.kudosCount, 1);
        expect(list.single.viewerHasKudo, isTrue);
        expect(
          list.single.owner.relationship.status,
          FollowRelationshipStatus.outgoingPending,
        );
        expect(activitiesBuilder.selectBuilder.lastEqColumn, 'user_id');
        expect(
          activitiesBuilder.selectBuilder.lastEqValue,
          '22222222-2222-2222-2222-222222222222',
        );
        expect(activitiesBuilder.selectBuilder.lastOrderedColumn, 'started_at');
        expect(activitiesBuilder.selectBuilder.lastOrderAscending, isFalse);
        expect(
          outgoingFollowsBuilder.selectBuilder.lastEqColumn,
          'following_id',
        );
        expect(
          outgoingFollowsBuilder.selectBuilder.lastEqValue,
          '22222222-2222-2222-2222-222222222222',
        );
        expect(outgoingFollowsBuilder.selectBuilder.lastInFilterColumn, isNull);
        expect(
          incomingPendingBuilder.selectBuilder.lastEqColumn,
          'follower_id',
        );
        expect(
          incomingPendingBuilder.selectBuilder.lastEqValue,
          '22222222-2222-2222-2222-222222222222',
        );
        expect(incomingPendingBuilder.selectBuilder.lastInFilterColumn, isNull);
      },
    );

    test(
      'loadUserActivities keeps owner full route preview when viewer is owner',
      () async {
        const ownerUserId = '22222222-2222-2222-2222-222222222222';
        when(() => mockAuth.currentUser).thenReturn(_testUser(id: ownerUserId));

        final activitiesBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _activityRow(
              id: 'owner-activity',
              userId: ownerUserId,
              startedAt: '2026-03-19T12:00:00.000Z',
              profile: _profileRow(
                id: ownerUserId,
                displayName: 'Owner Runner',
              ),
              polylineEncoded: _rawTwoPointRoutePolyline,
            ),
          ],
        );
        final kudosBuilder = RecordingSupabaseQueryBuilder();
        final outgoingFollowsBuilder = RecordingSupabaseQueryBuilder();
        final incomingPendingBuilder = RecordingSupabaseQueryBuilder();
        final followsBuilders = <RecordingSupabaseQueryBuilder>[
          outgoingFollowsBuilder,
          incomingPendingBuilder,
        ];
        _stubTable(mockClient, 'activities', () => activitiesBuilder);
        _stubTable(mockClient, 'kudos', () => kudosBuilder);
        _stubTable(mockClient, 'follows', () => followsBuilders.removeAt(0));

        final repository = SupabaseSocialActivityRepository(mockClient);
        final summaries = await repository.loadUserActivities(ownerUserId);

        expect(summaries, hasLength(1));
        expect(summaries.single.polylineEncoded, _rawTwoPointRoutePolyline);
        final decodedOwnerPoints = decodePolyline(
          summaries.single.polylineEncoded,
        );
        expect(decodedOwnerPoints.length, _ownerVisibleRouteCoordinates.length);
        for (
          var index = 0;
          index < _ownerVisibleRouteCoordinates.length;
          index++
        ) {
          final expectedCoordinate = _ownerVisibleRouteCoordinates[index];
          expect(
            decodedOwnerPoints[index].latitude,
            closeTo(expectedCoordinate['latitude']!, 0.000001),
          );
          expect(
            decodedOwnerPoints[index].longitude,
            closeTo(expectedCoordinate['longitude']!, 0.000001),
          );
        }
        _verifyNoTrackPointRpc(mockClient, 'owner-activity');
      },
    );

    const maskedPreviewScenarios = <String, _MaskedSummaryPreviewScenario>{
      'loadUserActivities should use masked RPC preview for accepted follower and avoid raw summary polyline leakage':
          _MaskedSummaryPreviewScenario(
            activityId: 'public-activity',
            viewerUserId: _viewerUserId,
            acceptedFollow: true,
          ),
      'loadUserActivities should still use masked RPC preview for non-owner summaries when owner polyline is null':
          _MaskedSummaryPreviewScenario(
            activityId: 'public-activity-without-polyline',
            viewerUserId: _viewerUserId,
            ownerPolylineEncoded: null,
            acceptedFollow: true,
          ),
      'loadUserActivities should give stranger same masked public preview and no raw polyline':
          _MaskedSummaryPreviewScenario(
            activityId: 'public-activity',
            viewerUserId: _strangerUserId,
          ),
      'loadFeedActivities should use masked RPC preview for accepted followers and never leak raw polyline':
          _MaskedSummaryPreviewScenario(
            activityId: 'feed-activity',
            viewerUserId: _viewerUserId,
            acceptedFollow: true,
            loadFeed: true,
          ),
    };
    for (final scenarioEntry in maskedPreviewScenarios.entries) {
      test(scenarioEntry.key, () async {
        await _expectMaskedSummaryPreview(
          mockClient,
          mockAuth,
          scenarioEntry.value,
        );
      });
    }

    test(
      'list reads require an authenticated session',
      () async {
        when(() => mockAuth.currentUser).thenReturn(null);
        final repository = SupabaseSocialActivityRepository(mockClient);

        await expectLater(
          repository.loadFeedActivities(offset: 0, limit: 20),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Social activity reads require an authenticated user session.',
            ),
          ),
        );
        await expectLater(
          repository.loadUserActivities(
            '22222222-2222-2222-2222-222222222222',
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Social activity reads require an authenticated user session.',
            ),
          ),
        );
        verifyNever(() => mockClient.from('activities'));
        verifyNever(() => mockClient.from('follows'));
      },
    );
  });

  group('SupabaseSocialActivityRepository detail read', () {
    test(
      'loadActivityDetail maps activity, ordered splits, kudos, and rpc track points',
      () async {
        final activityBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _activityRow(
              id: 'activity-detail',
              userId: '22222222-2222-2222-2222-222222222222',
              startedAt: '2026-03-19T12:00:00.000Z',
              profile: _profileRow(
                id: '22222222-2222-2222-2222-222222222222',
                displayName: 'Owner Runner',
              ),
            ),
          ],
        );
        final splitsBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _splitRow(
              splitNumber: 1,
              distanceMeters: 1000,
              durationSeconds: 360,
            ),
            _splitRow(
              splitNumber: 2,
              distanceMeters: 1000,
              durationSeconds: 355,
            ),
          ],
        );
        final kudosBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _kudosRow(
              activityId: 'activity-detail',
              userId: '11111111-1111-1111-1111-111111111111',
            ),
            _kudosRow(
              activityId: 'activity-detail',
              userId: '55555555-5555-5555-5555-555555555555',
            ),
          ],
        );
        final outgoingFollowsBuilder = RecordingSupabaseQueryBuilder();
        final incomingPendingBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [
            _followRow(
              id: 'incoming-pending',
              followerId: '22222222-2222-2222-2222-222222222222',
              followingId: '11111111-1111-1111-1111-111111111111',
              status: 'pending',
            ),
          ],
        );
        final followsBuilders = <RecordingSupabaseQueryBuilder>[
          outgoingFollowsBuilder,
          incomingPendingBuilder,
        ];
        final trackPointRpcBuilder = RecordingPostgrestListBuilder([
          _trackPointRow(
            id: 1,
            activityId: 'activity-detail',
            timestamp: '2026-03-19T12:00:01.000Z',
            latitude: null,
            longitude: null,
          ),
          _trackPointRow(
            id: 2,
            activityId: 'activity-detail',
            timestamp: '2026-03-19T12:00:02.000Z',
            latitude: 40.7128,
            longitude: -74.006,
          ),
        ]);
        _stubTable(mockClient, 'activities', () => activityBuilder);
        _stubTable(mockClient, 'splits', () => splitsBuilder);
        _stubTable(mockClient, 'kudos', () => kudosBuilder);
        _stubTable(mockClient, 'follows', () => followsBuilders.removeAt(0));
        _stubTrackPointRpc(mockClient, 'activity-detail', trackPointRpcBuilder);

        final repository = SupabaseSocialActivityRepository(mockClient);
        final detail = await repository.loadActivityDetail('activity-detail');

        expect(detail?.activityId, 'activity-detail');
        expect(detail?.owner.displayName, 'Owner Runner');
        expect(
          detail?.owner.relationship.status,
          FollowRelationshipStatus.incomingPending,
        );
        expect(detail?.kudosCount, 2);
        expect(detail?.viewerHasKudo, isTrue);
        expect(detail?.splits, hasLength(2));
        expect(detail?.splits.first.splitNumber, 1);
        expect(detail?.trackPoints, hasLength(2));
        expect(detail?.trackPoints.first.latitude, isNull);
        expect(detail?.trackPoints.first.longitude, isNull);
        expect(detail?.trackPoints.last.latitude, closeTo(40.7128, 0.0001));
        expect(splitsBuilder.selectBuilder.lastOrderedColumn, 'split_number');
        expect(splitsBuilder.selectBuilder.lastOrderAscending, isTrue);
        verifyNever(() => mockClient.from('track_points'));
      },
    );

    test(
      'loadActivityDetail returns null when activity is not visible',
      () async {
        final activityBuilder = RecordingSupabaseQueryBuilder();
        _stubTable(mockClient, 'activities', () => activityBuilder);

        final repository = SupabaseSocialActivityRepository(mockClient);
        final detail = await repository.loadActivityDetail('missing-activity');

        expect(detail, isNull);
        verifyNever(() => mockClient.from('splits'));
        verifyNever(() => mockClient.from('kudos'));
        _verifyNoTrackPointRpc(mockClient, 'missing-activity');
      },
    );

    test('loadActivityDetail requires an authenticated session', () async {
      when(() => mockAuth.currentUser).thenReturn(null);
      final repository = SupabaseSocialActivityRepository(mockClient);

      expect(
        () => repository.loadActivityDetail('activity-detail'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Social activity reads require an authenticated user session.',
          ),
        ),
      );
      verifyNever(() => mockClient.from('activities'));
    });
  });
}

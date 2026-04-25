import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/common_widgets/static_route_preview.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/data/social_activity_repository.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/social_activity_detail.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/presentation/feed_screen.dart';

/// ## Test Scenarios
/// - `[positive]` Feed cards render static route preview from summary polyline data.
/// - `[positive]` Feed cards render static route preview from summary route-points data.
/// - `[negative]` Feed cards omit route preview when summary preview data is absent.
/// - `[isolation]` Mixed feed rows render preview only from the matching card summary data.
const _viewerId = '11111111-1111-1111-1111-111111111111';
const _ownerId = '22222222-2222-2222-2222-222222222222';
const _summaryRoutePolyline = '_p~iF~ps|U_ulLnnqC';
const _maskedSummaryRoutePoints = <RoutePoint>[
  RoutePoint(latitude: 40.7, longitude: -120.95),
  RoutePoint(latitude: 43.252, longitude: -126.453),
];

class _FakeSocialActivityRepository implements SocialActivityRepository {
  _FakeSocialActivityRepository({required this.loadFeedPage});

  final FutureOr<List<SocialActivitySummary>> Function(int offset, int limit)
  loadFeedPage;

  @override
  Future<SocialActivityDetail?> loadActivityDetail(String activityId) async {
    return null;
  }

  @override
  Future<List<SocialActivitySummary>> loadFeedActivities({
    required int offset,
    required int limit,
  }) async {
    return loadFeedPage(offset, limit);
  }

  @override
  Future<List<SocialActivitySummary>> loadUserActivities(String userId) async {
    return const <SocialActivitySummary>[];
  }
}

SocialUserSummary _ownerSummary() {
  return const SocialUserSummary(
    userId: _ownerId,
    displayName: 'Alice Runner',
    avatarUrl: null,
    relationship: FollowRelationship(
      currentUserId: _viewerId,
      targetUserId: _ownerId,
      status: FollowRelationshipStatus.following,
    ),
  );
}

SocialActivitySummary _summary({
  required String activityId,
  String? title,
  String? polylineEncoded,
  List<RoutePoint>? routePoints,
  int kudosCount = 0,
}) {
  return SocialActivitySummary(
    activityId: activityId,
    owner: _ownerSummary(),
    sportType: 'run',
    startedAt: DateTime.utc(2026, 3, 19, 10),
    finishedAt: DateTime.utc(2026, 3, 19, 10, 25),
    distanceMeters: 5000,
    durationSeconds: 1500,
    elevationGainMeters: 30,
    avgPaceSecondsPerKm: 300,
    title: title,
    description: null,
    visibility: 'public',
    commentCount: 0,
    kudosCount: kudosCount,
    viewerHasKudo: false,
    polylineEncoded: polylineEncoded,
    routePoints: routePoints,
  );
}

Widget _buildFeedScreen({
  required FutureOr<List<SocialActivitySummary>> Function() socialFeed,
}) {
  final repository = _FakeSocialActivityRepository(
    loadFeedPage: (offset, limit) {
      if (offset != 0) {
        return const <SocialActivitySummary>[];
      }
      return socialFeed();
    },
  );

  return ProviderScope(
    overrides: [
      socialActivityRepositoryProvider.overrideWithValue(repository),
      savedActivitiesProvider.overrideWith(
        (ref) => Future<List<TrackingSessionRecord>>.error(
          StateError('savedActivitiesProvider must not be read by feed'),
        ),
      ),
    ],
    child: const MaterialApp(home: FeedScreen()),
  );
}

void main() {
  group('FeedScreen route preview', () {
    testWidgets('renders chronological feed cards from SocialActivitySummary', (
      tester,
    ) async {
      final activities = [
        _summary(
          activityId: 'a1',
          title: 'Morning Run',
          polylineEncoded: _summaryRoutePolyline,
          kudosCount: 3,
        ),
        _summary(activityId: 'a2', title: 'Evening Jog'),
      ];

      await tester.pumpWidget(
        _buildFeedScreen(socialFeed: () async => activities),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(FeedScreen.feedCardKey('a1')), findsOneWidget);
      expect(find.byKey(FeedScreen.feedCardKey('a2')), findsOneWidget);

      final a1Center = tester.getCenter(
        find.byKey(FeedScreen.feedCardKey('a1')),
      );
      final a2Center = tester.getCenter(
        find.byKey(FeedScreen.feedCardKey('a2')),
      );
      expect(
        a1Center.dy,
        lessThan(a2Center.dy),
        reason: 'First card (a1) must render above second card (a2)',
      );

      expect(find.text('Alice Runner'), findsNWidgets(2));

      final routePreviewFinder = find.byType(StaticRoutePreview);
      expect(routePreviewFinder, findsOneWidget);
      final routePreview = tester.widget<StaticRoutePreview>(
        routePreviewFinder,
      );
      expect(routePreview.polylineEncoded, _summaryRoutePolyline);
      expect(routePreview.routePoints, isNull);
      expect(routePreview.preset, StaticRoutePreviewSizePreset.feed);
      final secondCardPreview = find.descendant(
        of: find.byKey(FeedScreen.feedCardKey('a2')),
        matching: find.byType(StaticRoutePreview),
      );
      expect(secondCardPreview, findsNothing);

      expect(find.text('Morning Run'), findsOneWidget);
      expect(find.text('Evening Jog'), findsOneWidget);
      expect(find.text('5.00 km'), findsNWidgets(2));
      expect(find.text('05:00 /km'), findsNWidgets(2));
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets(
      'renders feed route preview from summary routePoints when masked preview data is provided',
      (tester) async {
        await tester.pumpWidget(
          _buildFeedScreen(
            socialFeed: () async => <SocialActivitySummary>[
              _summary(
                activityId: 'masked-a1',
                title: 'Masked Run',
                routePoints: _maskedSummaryRoutePoints,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final routePreview = tester.widget<StaticRoutePreview>(
          find.byType(StaticRoutePreview),
        );
        expect(routePreview.polylineEncoded, isNull);
        expect(routePreview.routePoints, _maskedSummaryRoutePoints);
        expect(routePreview.preset, StaticRoutePreviewSizePreset.feed);
      },
    );

    testWidgets(
      'renders mixed summary preview sources per card without cross-card leakage',
      (tester) async {
        await tester.pumpWidget(
          _buildFeedScreen(
            socialFeed: () async => <SocialActivitySummary>[
              _summary(
                activityId: 'poly-a1',
                title: 'Owner Polyline',
                polylineEncoded: _summaryRoutePolyline,
              ),
              _summary(
                activityId: 'masked-a2',
                title: 'Masked Preview',
                routePoints: _maskedSummaryRoutePoints,
              ),
              _summary(
                activityId: 'none-a3',
                title: 'No Preview',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final polylineCard = find.byKey(FeedScreen.feedCardKey('poly-a1'));
        final maskedCard = find.byKey(FeedScreen.feedCardKey('masked-a2'));
        final noPreviewCard = find.byKey(FeedScreen.feedCardKey('none-a3'));
        final polylinePreviewFinder = find.descendant(
          of: polylineCard,
          matching: find.byType(StaticRoutePreview),
        );
        final maskedPreviewFinder = find.descendant(
          of: maskedCard,
          matching: find.byType(StaticRoutePreview),
        );
        final noPreviewFinder = find.descendant(
          of: noPreviewCard,
          matching: find.byType(StaticRoutePreview),
        );

        expect(find.byType(StaticRoutePreview), findsNWidgets(2));
        expect(polylinePreviewFinder, findsOneWidget);
        expect(maskedPreviewFinder, findsOneWidget);
        expect(noPreviewFinder, findsNothing);

        final polylinePreview = tester.widget<StaticRoutePreview>(
          polylinePreviewFinder,
        );
        expect(polylinePreview.polylineEncoded, _summaryRoutePolyline);
        expect(polylinePreview.routePoints, isNull);
        expect(polylinePreview.preset, StaticRoutePreviewSizePreset.feed);

        final maskedPreview = tester.widget<StaticRoutePreview>(
          maskedPreviewFinder,
        );
        expect(maskedPreview.polylineEncoded, isNull);
        expect(maskedPreview.routePoints, _maskedSummaryRoutePoints);
        expect(maskedPreview.preset, StaticRoutePreviewSizePreset.feed);
      },
    );
  });
}

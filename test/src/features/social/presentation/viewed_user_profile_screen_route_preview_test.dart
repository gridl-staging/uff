import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/common_widgets/static_route_preview.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/domain/viewed_user_profile_header.dart';
import 'package:uff/src/features/social/presentation/viewed_user_profile_screen.dart';

/// ## Test Scenarios
/// - `[negative]` Activity row omits route preview when summary preview data is absent.
/// - `[isolation]` Mixed activity rows render a route preview only for entries with summary preview data.
const _viewerId = '11111111-1111-1111-1111-111111111111';
const _viewedUserId = '22222222-2222-2222-2222-222222222222';
const _summaryRoutePolyline = '_p~iF~ps|U_ulLnnqC';
const _maskedSummaryRoutePoints = <RoutePoint>[
  RoutePoint(latitude: 40.7, longitude: -120.95),
  RoutePoint(latitude: 43.252, longitude: -126.453),
];

ViewedUserProfileHeader _header() {
  return const ViewedUserProfileHeader(
    user: SocialUserSummary(
      userId: _viewedUserId,
      displayName: 'Viewed Runner',
      avatarUrl: null,
      relationship: FollowRelationship(
        currentUserId: _viewerId,
        targetUserId: _viewedUserId,
        status: FollowRelationshipStatus.following,
      ),
    ),
    followersCount: 6,
    followingCount: 14,
  );
}

SocialActivitySummary _activityWithPreviewData({
  required String activityId,
  String? polylineEncoded,
  List<RoutePoint>? routePoints,
}) {
  return SocialActivitySummary(
    activityId: activityId,
    owner: _header().user,
    sportType: 'run',
    startedAt: DateTime.utc(2026, 3, 19, 10),
    finishedAt: DateTime.utc(2026, 3, 19, 10, 30),
    distanceMeters: 5200,
    durationSeconds: 1800,
    elevationGainMeters: 24,
    avgPaceSecondsPerKm: 345,
    title: 'Morning Session',
    description: null,
    visibility: 'public',
    polylineEncoded: polylineEncoded,
    routePoints: routePoints,
    commentCount: 0,
    kudosCount: 3,
    viewerHasKudo: false,
  );
}

Widget _buildProfileScreen({
  required FutureOr<ViewedUserProfileHeader?> Function(Ref) headerBuilder,
  required FutureOr<List<SocialActivitySummary>> Function(Ref)
  activitiesBuilder,
}) {
  return ProviderScope(
    overrides: [
      viewedUserProfileHeaderProvider(
        _viewedUserId,
      ).overrideWith((ref) => headerBuilder(ref)),
      viewedUserActivityListProvider(
        _viewedUserId,
      ).overrideWith((ref) => activitiesBuilder(ref)),
    ],
    child: const MaterialApp(
      home: ViewedUserProfileScreen(userId: _viewedUserId),
    ),
  );
}

void main() {
  group('ViewedUserProfileScreen route preview', () {
    testWidgets(
      'mixed activity rows render compact previews only for rows with summary preview data',
      (tester) async {
        await tester.pumpWidget(
          _buildProfileScreen(
            headerBuilder: (ref) async => _header(),
            activitiesBuilder: (ref) async => [
              _activityWithPreviewData(
                activityId: 'activity-with-poly',
                polylineEncoded: _summaryRoutePolyline,
              ),
              _activityWithPreviewData(
                activityId: 'activity-with-route-points',
                routePoints: _maskedSummaryRoutePoints,
              ),
              _activityWithPreviewData(activityId: 'activity-without-preview'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final withPolylineRow = find.byKey(
          ViewedUserProfileScreen.activityRowKey('activity-with-poly'),
        );
        final withRoutePointsRow = find.byKey(
          ViewedUserProfileScreen.activityRowKey('activity-with-route-points'),
        );
        final withoutPreviewRow = find.byKey(
          ViewedUserProfileScreen.activityRowKey('activity-without-preview'),
        );
        final polylinePreviewFinder = find.descendant(
          of: withPolylineRow,
          matching: find.byType(StaticRoutePreview),
        );
        final routePointsPreviewFinder = find.descendant(
          of: withRoutePointsRow,
          matching: find.byType(StaticRoutePreview),
        );
        final withoutPreviewFinder = find.descendant(
          of: withoutPreviewRow,
          matching: find.byType(StaticRoutePreview),
        );

        expect(find.byType(StaticRoutePreview), findsNWidgets(2));
        expect(polylinePreviewFinder, findsOneWidget);
        expect(routePointsPreviewFinder, findsOneWidget);
        expect(withoutPreviewFinder, findsNothing);

        final polylinePreview = tester.widget<StaticRoutePreview>(
          polylinePreviewFinder,
        );
        expect(polylinePreview.preset, StaticRoutePreviewSizePreset.compact);
        expect(polylinePreview.polylineEncoded, _summaryRoutePolyline);
        expect(polylinePreview.routePoints, isNull);

        final routePointsPreview = tester.widget<StaticRoutePreview>(
          routePointsPreviewFinder,
        );
        expect(routePointsPreview.preset, StaticRoutePreviewSizePreset.compact);
        expect(routePointsPreview.polylineEncoded, isNull);
        expect(routePointsPreview.routePoints, _maskedSummaryRoutePoints);
      },
    );
  });
}

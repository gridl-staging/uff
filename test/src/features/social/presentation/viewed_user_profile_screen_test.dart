// Scenario tags use bracket syntax enforced by the test standards script.
// ignore_for_file: comment_references

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/data/follow_repository.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/domain/viewed_user_profile_header.dart';
import 'package:uff/src/features/social/presentation/social_user_row.dart';
import 'package:uff/src/common_widgets/static_route_preview.dart';
import 'package:uff/src/features/social/presentation/viewed_user_profile_screen.dart';

import 'fake_follow_repository.dart';

/// ## Test Scenarios
/// - [positive] Viewed profile screen renders header metadata and remote activity rows.
/// - [positive] Activity-row taps navigate to remote activity detail routes.
/// - [positive] Header follow action renders the correct label and enabled state for each relationship status.
/// - [error] Loading/error/not-found states provide route recovery and retry behavior.
/// - [negative] Insecure avatar URLs are rejected from rendered remote profile content.
/// - [isolation] Recovery chrome behavior differs for direct-entry versus pushed in-app navigation.
/// - [statemachine] Header follow action dispatches send-follow vs unfollow mutations from relationship state.
/// - [positive] Activity row renders compact static route preview from summary-provided preview data.
/// - [negative] Activity row omits route preview when summary preview data is absent.
const _viewerId = '11111111-1111-1111-1111-111111111111';
const _viewedUserId = '22222222-2222-2222-2222-222222222222';
const _summaryRoutePolyline = '_p~iF~ps|U_ulLnnqC';
const _maskedSummaryRoutePoints = <RoutePoint>[
  RoutePoint(latitude: 40.7, longitude: -120.95),
  RoutePoint(latitude: 43.252, longitude: -126.453),
];
const _profileRoutePath = '/profile';
const _originRoutePath = '/origin';
const _homeRoutePath = '/home';
const _openProfileButtonKey = Key('open_profile_button');

ViewedUserProfileHeader _header({
  String? avatarUrl,
  String? displayName = 'Viewed Runner',
  FollowRelationshipStatus status = FollowRelationshipStatus.following,
  String? followId,
}) {
  return ViewedUserProfileHeader(
    user: SocialUserSummary(
      userId: _viewedUserId,
      displayName: displayName,
      avatarUrl: avatarUrl,
      relationship: FollowRelationship(
        currentUserId: _viewerId,
        targetUserId: _viewedUserId,
        status: status,
        followId: followId,
      ),
    ),
    followersCount: 6,
    followingCount: 14,
  );
}

SocialActivitySummary _activity(String activityId) {
  return _activityWithPreviewData(activityId: activityId);
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

SocialActivitySummary _activityWithPolyline(String activityId) {
  return _activityWithPreviewData(
    activityId: activityId,
    polylineEncoded: _summaryRoutePolyline,
  );
}

SocialActivitySummary _activityWithRoutePoints(String activityId) {
  return _activityWithPreviewData(
    activityId: activityId,
    routePoints: _maskedSummaryRoutePoints,
  );
}

Widget _buildProfileScreen({
  required FutureOr<ViewedUserProfileHeader?> Function(Ref) headerBuilder,
  required FutureOr<List<SocialActivitySummary>> Function(Ref)
  activitiesBuilder,
  FollowRepository? followRepository,
  Key? scopeKey,
}) {
  return ProviderScope(
    key: scopeKey,
    overrides: [
      viewedUserProfileHeaderProvider(
        _viewedUserId,
      ).overrideWith((ref) => headerBuilder(ref)),
      viewedUserActivityListProvider(
        _viewedUserId,
      ).overrideWith((ref) => activitiesBuilder(ref)),
      if (followRepository != null)
        followRepositoryProvider.overrideWithValue(followRepository),
    ],
    child: const MaterialApp(
      home: ViewedUserProfileScreen(userId: _viewedUserId),
    ),
  );
}

Widget _buildProfileRouterScreen({
  required FutureOr<ViewedUserProfileHeader?> Function(Ref) headerBuilder,
  required FutureOr<List<SocialActivitySummary>> Function(Ref)
  activitiesBuilder,
  String initialLocation = _profileRoutePath,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: _originRoutePath,
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: _openProfileButtonKey,
              onPressed: () => context.push(_profileRoutePath),
              child: const Text('Open profile'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: _homeRoutePath,
        builder: (context, state) => const Text('home'),
      ),
      GoRoute(
        path: _profileRoutePath,
        builder: (context, state) =>
            const ViewedUserProfileScreen(userId: _viewedUserId),
      ),
      GoRoute(
        path: '/social/activity/:activityId',
        builder: (context, state) =>
            Text('activity:${state.pathParameters['activityId']}'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      viewedUserProfileHeaderProvider(
        _viewedUserId,
      ).overrideWith((ref) => headerBuilder(ref)),
      viewedUserActivityListProvider(
        _viewedUserId,
      ).overrideWith((ref) => activitiesBuilder(ref)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _openProfileFromOrigin(WidgetTester tester) async {
  await tester.tap(find.byKey(_openProfileButtonKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('ViewedUserProfileScreen', () {
    testWidgets('shows loading state while header/provider reads are pending', (
      tester,
    ) async {
      final pendingHeader = Completer<ViewedUserProfileHeader?>();
      addTearDown(() {
        if (!pendingHeader.isCompleted) {
          pendingHeader.complete(_header());
        }
      });

      await tester.pumpWidget(
        _buildProfileScreen(
          headerBuilder: (ref) => pendingHeader.future,
          activitiesBuilder: (ref) async => const <SocialActivitySummary>[],
        ),
      );
      await tester.pump();

      expect(
        find.byKey(ViewedUserProfileScreen.loadingStateKey),
        findsOneWidget,
      );
    });

    testWidgets('shows error state when header load fails', (tester) async {
      await tester.pumpWidget(
        _buildProfileScreen(
          headerBuilder: (ref) => Future<ViewedUserProfileHeader?>.error(
            Exception('network error'),
          ),
          activitiesBuilder: (ref) async => const <SocialActivitySummary>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ViewedUserProfileScreen.errorStateKey), findsOneWidget);
    });

    testWidgets('loading state shows route recovery chrome for direct entry', (
      tester,
    ) async {
      final pendingHeader = Completer<ViewedUserProfileHeader?>();
      addTearDown(() {
        if (!pendingHeader.isCompleted) {
          pendingHeader.complete(_header());
        }
      });

      await tester.pumpWidget(
        _buildProfileRouterScreen(
          headerBuilder: (ref) => pendingHeader.future,
          activitiesBuilder: (ref) async => const <SocialActivitySummary>[],
        ),
      );
      await tester.pump();

      expect(
        find.byKey(ViewedUserProfileScreen.loadingStateKey),
        findsOneWidget,
      );
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Go to Home'), findsOneWidget);
      expect(find.text('Go Back'), findsNothing);

      await tester.tap(find.text('Go to Home'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
    });

    testWidgets(
      'loading state exposes go-back recovery when pushed from in-app route',
      (tester) async {
        final pendingHeader = Completer<ViewedUserProfileHeader?>();
        addTearDown(() {
          if (!pendingHeader.isCompleted) {
            pendingHeader.complete(_header());
          }
        });

        await tester.pumpWidget(
          _buildProfileRouterScreen(
            initialLocation: _originRoutePath,
            headerBuilder: (ref) => pendingHeader.future,
            activitiesBuilder: (ref) async => const <SocialActivitySummary>[],
          ),
        );
        await tester.pumpAndSettle();

        await _openProfileFromOrigin(tester);

        expect(
          find.byKey(ViewedUserProfileScreen.loadingStateKey),
          findsOneWidget,
        );
        expect(find.text('Go Back'), findsOneWidget);

        await tester.tap(find.text('Go Back'));
        await tester.pumpAndSettle();

        expect(find.byKey(_openProfileButtonKey), findsOneWidget);
      },
    );

    testWidgets(
      'error state supports retry via provider invalidation on direct entry',
      (tester) async {
        var allowSuccess = false;
        var headerLoadCount = 0;
        var activitiesLoadCount = 0;

        await tester.pumpWidget(
          _buildProfileRouterScreen(
            headerBuilder: (ref) {
              headerLoadCount++;
              if (!allowSuccess) {
                return Future<ViewedUserProfileHeader?>.error(
                  Exception('network error'),
                );
              }
              return Future<ViewedUserProfileHeader?>.value(_header());
            },
            activitiesBuilder: (ref) async {
              activitiesLoadCount++;
              return const <SocialActivitySummary>[];
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(ViewedUserProfileScreen.errorStateKey),
          findsOneWidget,
        );
        expect(find.text('Go to Home'), findsOneWidget);
        expect(find.text('Go Back'), findsNothing);
        expect(find.text('Retry'), findsOneWidget);

        allowSuccess = true;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(ViewedUserProfileScreen.headerCardKey),
          findsOneWidget,
        );
        expect(headerLoadCount, greaterThan(1));
        expect(activitiesLoadCount, greaterThan(1));
      },
    );

    testWidgets(
      'error state exposes go-back recovery when pushed from in-app route',
      (tester) async {
        await tester.pumpWidget(
          _buildProfileRouterScreen(
            initialLocation: _originRoutePath,
            headerBuilder: (ref) => Future<ViewedUserProfileHeader?>.error(
              Exception('network error'),
            ),
            activitiesBuilder: (ref) async => const <SocialActivitySummary>[],
          ),
        );
        await tester.pumpAndSettle();

        await _openProfileFromOrigin(tester);
        await tester.pumpAndSettle();

        expect(
          find.byKey(ViewedUserProfileScreen.errorStateKey),
          findsOneWidget,
        );
        expect(find.text('Go Back'), findsOneWidget);

        await tester.tap(find.text('Go Back'));
        await tester.pumpAndSettle();

        expect(find.byKey(_openProfileButtonKey), findsOneWidget);
      },
    );

    testWidgets('shows not-found state when viewed user header is missing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildProfileScreen(
          headerBuilder: (ref) async => null,
          activitiesBuilder: (ref) async => const <SocialActivitySummary>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ViewedUserProfileScreen.notFoundStateKey),
        findsOneWidget,
      );
    });

    testWidgets('rejects insecure avatar URLs from remote profile data', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildProfileScreen(
          headerBuilder: (ref) async =>
              _header(avatarUrl: 'http://example.com/avatar.png'),
          activitiesBuilder: (ref) async => const <SocialActivitySummary>[],
        ),
      );
      await tester.pumpAndSettle();

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isNull);
      expect(find.text('VR'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsNothing);
    });

    testWidgets('blank remote display name falls back to user id', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildProfileScreen(
          headerBuilder: (ref) async => _header(displayName: '   '),
          activitiesBuilder: (ref) async => const <SocialActivitySummary>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_viewedUserId), findsWidgets);
      expect(find.text('Viewed Runner'), findsNothing);
    });

    testWidgets(
      'header follow action button maps status to label and enabled state',
      (tester) async {
        final cases =
            <
              (
                FollowRelationshipStatus status,
                String label,
                bool isEnabled,
                String? followId,
              )
            >[
              (FollowRelationshipStatus.none, 'Follow', true, null),
              (
                FollowRelationshipStatus.outgoingPending,
                'Requested',
                false,
                null,
              ),
              (
                FollowRelationshipStatus.incomingPending,
                'Accept',
                true,
                'follow-1',
              ),
              (FollowRelationshipStatus.following, 'Following', true, null),
            ];

        for (final testCase in cases) {
          final header = _header(status: testCase.$1, followId: testCase.$4);
          await tester.pumpWidget(
            _buildProfileScreen(
              scopeKey: ValueKey('status-${testCase.$1.name}'),
              headerBuilder: (ref) async => header,
              activitiesBuilder: (ref) async => const <SocialActivitySummary>[],
            ),
          );
          await tester.pumpAndSettle();

          final actionButton = find.byKey(
            SocialUserRow.actionButtonKey(header.user.userId),
          );
          expect(actionButton, findsOneWidget);
          expect(
            find.descendant(of: actionButton, matching: find.text(testCase.$2)),
            findsOneWidget,
          );

          final widget = tester.widget<ButtonStyleButton>(actionButton);
          expect(widget.onPressed != null, testCase.$3);
        }
      },
    );

    testWidgets(
      'header follow action dispatches send-follow and unfollow mutations',
      (tester) async {
        final followRepository = RecordingFollowRepository();

        await tester.pumpWidget(
          _buildProfileScreen(
            scopeKey: const ValueKey('follow-none'),
            headerBuilder: (ref) async =>
                _header(status: FollowRelationshipStatus.none),
            activitiesBuilder: (ref) async => const <SocialActivitySummary>[],
            followRepository: followRepository,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(SocialUserRow.actionButtonKey(_viewedUserId)),
        );
        await tester.pumpAndSettle();

        expect(followRepository.lastSentTargetUserId, _viewedUserId);

        await tester.pumpWidget(
          _buildProfileScreen(
            scopeKey: const ValueKey('follow-following'),
            headerBuilder: (ref) async => _header(),
            activitiesBuilder: (ref) async => const <SocialActivitySummary>[],
            followRepository: followRepository,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(SocialUserRow.actionButtonKey(_viewedUserId)),
        );
        await tester.pumpAndSettle();

        expect(followRepository.lastUnfollowedTargetUserId, _viewedUserId);
      },
    );

    testWidgets(
      'not-found state shows route recovery chrome for direct entry',
      (tester) async {
        await tester.pumpWidget(
          _buildProfileRouterScreen(
            headerBuilder: (ref) async => null,
            activitiesBuilder: (ref) async => const <SocialActivitySummary>[],
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(ViewedUserProfileScreen.notFoundStateKey),
          findsOneWidget,
        );
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.text('Go to Home'), findsOneWidget);
        expect(find.text('Go Back'), findsNothing);
        expect(find.text('Retry'), findsOneWidget);

        await tester.tap(find.text('Go to Home'));
        await tester.pumpAndSettle();

        expect(find.text('home'), findsOneWidget);
      },
    );

    testWidgets(
      'not-found state supports retry via provider invalidation on direct entry',
      (tester) async {
        var allowSuccess = false;
        var headerLoadCount = 0;
        var activitiesLoadCount = 0;

        await tester.pumpWidget(
          _buildProfileRouterScreen(
            headerBuilder: (ref) async {
              headerLoadCount++;
              if (!allowSuccess) {
                return null;
              }
              return _header();
            },
            activitiesBuilder: (ref) async {
              activitiesLoadCount++;
              return const <SocialActivitySummary>[];
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(ViewedUserProfileScreen.notFoundStateKey),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);

        allowSuccess = true;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(ViewedUserProfileScreen.headerCardKey),
          findsOneWidget,
        );
        expect(headerLoadCount, greaterThan(1));
        expect(activitiesLoadCount, greaterThan(1));
      },
    );

    testWidgets(
      'not-found state exposes go-back recovery when pushed from in-app route',
      (tester) async {
        await tester.pumpWidget(
          _buildProfileRouterScreen(
            initialLocation: _originRoutePath,
            headerBuilder: (ref) async => null,
            activitiesBuilder: (ref) async => const <SocialActivitySummary>[],
          ),
        );
        await tester.pumpAndSettle();

        await _openProfileFromOrigin(tester);
        await tester.pumpAndSettle();

        expect(
          find.byKey(ViewedUserProfileScreen.notFoundStateKey),
          findsOneWidget,
        );
        expect(find.text('Go Back'), findsOneWidget);

        await tester.tap(find.text('Go Back'));
        await tester.pumpAndSettle();

        expect(find.byKey(_openProfileButtonKey), findsOneWidget);
      },
    );

    testWidgets(
      'shows empty activities state when viewed user has no activities',
      (tester) async {
        await tester.pumpWidget(
          _buildProfileScreen(
            headerBuilder: (ref) async => _header(),
            activitiesBuilder: (ref) async => const <SocialActivitySummary>[],
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(ViewedUserProfileScreen.headerCardKey),
          findsOneWidget,
        );
        expect(
          find.byKey(ViewedUserProfileScreen.emptyStateKey),
          findsOneWidget,
        );
        expect(find.text('Viewed Runner'), findsWidgets);
        expect(find.text('6 followers'), findsOneWidget);
        expect(find.text('14 following'), findsOneWidget);
      },
    );

    testWidgets('renders viewed-user header and activity list rows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildProfileScreen(
          headerBuilder: (ref) async => _header(),
          activitiesBuilder: (ref) async => [
            _activity('activity-1'),
            _activity('activity-2'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ViewedUserProfileScreen.headerCardKey), findsOneWidget);
      expect(
        find.byKey(ViewedUserProfileScreen.activityRowKey('activity-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(ViewedUserProfileScreen.activityRowKey('activity-2')),
        findsOneWidget,
      );
    });

    testWidgets(
      'tapping viewed-user activity row pushes remote activity detail route path',
      (tester) async {
        await tester.pumpWidget(
          _buildProfileRouterScreen(
            headerBuilder: (ref) async => _header(),
            activitiesBuilder: (ref) async => [_activity('activity-1')],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(ViewedUserProfileScreen.activityRowKey('activity-1')),
        );
        await tester.pumpAndSettle();

        expect(find.text('activity:activity-1'), findsOneWidget);
      },
    );

    testWidgets(
      'activity row renders compact static route preview when polylineEncoded is present',
      (tester) async {
        await tester.pumpWidget(
          _buildProfileScreen(
            headerBuilder: (ref) async => _header(),
            activitiesBuilder: (ref) async => [
              _activityWithPolyline('activity-poly'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(StaticRoutePreview.previewKey), findsOneWidget);
        expect(find.byKey(StaticRoutePreview.compactBoxKey), findsOneWidget);
        final preview = tester.widget<StaticRoutePreview>(
          find.byType(StaticRoutePreview),
        );
        expect(preview.preset, StaticRoutePreviewSizePreset.compact);
        expect(preview.polylineEncoded, _summaryRoutePolyline);
        expect(preview.routePoints, isNull);
      },
    );

    testWidgets(
      'activity row omits route preview when polylineEncoded is null',
      (tester) async {
        await tester.pumpWidget(
          _buildProfileScreen(
            headerBuilder: (ref) async => _header(),
            activitiesBuilder: (ref) async => [_activity('activity-no-poly')],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(StaticRoutePreview.previewKey), findsNothing);
      },
    );

    testWidgets(
      'activity row renders compact static route preview from summary routePoints',
      (tester) async {
        await tester.pumpWidget(
          _buildProfileScreen(
            headerBuilder: (ref) async => _header(),
            activitiesBuilder: (ref) async => [
              _activityWithRoutePoints('activity-route-points'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final preview = tester.widget<StaticRoutePreview>(
          find.byType(StaticRoutePreview),
        );
        expect(preview.preset, StaticRoutePreviewSizePreset.compact);
        expect(preview.polylineEncoded, isNull);
        expect(preview.routePoints, _maskedSummaryRoutePoints);
      },
    );
  });
}

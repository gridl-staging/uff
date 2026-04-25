// Scenario tags use bracket syntax enforced by the test standards script.
// ignore_for_file: comment_references

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/common_widgets/static_route_preview.dart';
import 'package:uff/src/common_widgets/trusted_avatar_widget.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/application/social_comments_providers.dart';
import 'package:uff/src/features/social/application/social_kudos_providers.dart';
import 'package:uff/src/features/social/data/kudos_repository.dart';
import 'package:uff/src/features/social/domain/activity_kudos.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/remote_activity_track_point.dart';
import 'package:uff/src/features/social/domain/social_activity_detail.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/presentation/activity_comments_section.dart';
import 'package:uff/src/features/social/presentation/remote_activity_detail_screen.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';

import '../../../../src/features/activity_tracking/presentation/activity_detail_screen_test_support.dart';

/// ## Test Scenarios
/// - [positive] Remote activity detail renders content, comments section, and kudos-refresh interactions.
/// - [positive] Detail route preview is built from viewer-visible track-point geometry, not raw encoded polylines.
/// - [error] Pending/error/not-found states render recovery chrome and retry actions.
/// - [negative] Not-found detail state avoids rendering activity content.
/// - [edge] Recovery scaffold behavior differs for direct-entry vs in-app pushed routes.
/// - [isolation] Detail reads and kudos toggles stay scoped to the requested activity id.
const _viewerId = '11111111-1111-1111-1111-111111111111';
const _ownerId = '22222222-2222-2222-2222-222222222222';
const _activityId = 'activity-1';
const _detailRoutePath = '/detail';
const _originRoutePath = '/origin';
const _homeRoutePath = '/home';
const _openDetailButtonKey = Key('open_remote_activity_detail');
const _profileStateTextKey = Key('profile_state_text');
const _encodedPolyline = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

SocialUserSummary _ownerSummary({String? avatarUrl}) {
  return SocialUserSummary(
    userId: _ownerId,
    displayName: 'Owner Runner',
    avatarUrl: avatarUrl,
    relationship: const FollowRelationship(
      currentUserId: _viewerId,
      targetUserId: _ownerId,
      status: FollowRelationshipStatus.following,
    ),
  );
}

RemoteActivityDetailData _detailData({
  String? polylineEncoded,
  List<ActivityPhoto> photos = const <ActivityPhoto>[],
  String? ownerAvatarUrl,
  List<RemoteActivityTrackPoint>? trackPoints,
}) {
  final detail = SocialActivityDetail(
    activityId: _activityId,
    owner: _ownerSummary(avatarUrl: ownerAvatarUrl),
    sportType: 'run',
    startedAt: DateTime.utc(2026, 3, 19, 10),
    finishedAt: DateTime.utc(2026, 3, 19, 10, 34),
    distanceMeters: 7200,
    durationSeconds: 2040,
    elevationGainMeters: 72,
    avgPaceSecondsPerKm: 283,
    title: 'City Tempo',
    description: 'Steady run.',
    visibility: 'public',
    polylineEncoded: polylineEncoded,
    kudosCount: 4,
    viewerHasKudo: true,
    splits: const <SocialActivitySplit>[],
    trackPoints:
        trackPoints ??
        <RemoteActivityTrackPoint>[
          RemoteActivityTrackPoint(
            id: 1,
            activityId: _activityId,
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

  return RemoteActivityDetailData(
    detail: detail,
    photos: photos,
  );
}

Widget _buildRemoteDetailScreen({
  required FutureOr<RemoteActivityDetailData?> Function(Ref) detailBuilder,
  KudosRepository? kudosRepository,
  List<Object> additionalOverrides = const <Object>[],
}) {
  return ProviderScope(
    overrides: <Object>[
      remoteActivityDetailProvider(
        _activityId,
      ).overrideWith((ref) => detailBuilder(ref)),
      if (kudosRepository != null)
        kudosRepositoryProvider.overrideWithValue(kudosRepository),
      ...additionalOverrides,
    ].cast(),
    child: const MaterialApp(
      home: RemoteActivityDetailScreen(activityId: _activityId),
    ),
  );
}

Widget _buildRemoteDetailRouterScreen({
  required FutureOr<RemoteActivityDetailData?> Function(Ref) detailBuilder,
  KudosRepository? kudosRepository,
  String initialLocation = _detailRoutePath,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: _originRoutePath,
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: _openDetailButtonKey,
              onPressed: () => context.push(_detailRoutePath),
              child: const Text('Open activity detail'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: _homeRoutePath,
        builder: (context, state) => const Text('home'),
      ),
      GoRoute(
        path: _detailRoutePath,
        builder: (context, state) =>
            const RemoteActivityDetailScreen(activityId: _activityId),
      ),
      GoRoute(
        path: SocialRoutes.viewedUserProfilePathPattern,
        builder: (context, state) => Text(
          'profile:${state.pathParameters['userId']}',
          key: _profileStateTextKey,
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      remoteActivityDetailProvider(
        _activityId,
      ).overrideWith((ref) => detailBuilder(ref)),
      if (kudosRepository != null)
        kudosRepositoryProvider.overrideWithValue(kudosRepository),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _openDetailFromOrigin(WidgetTester tester) async {
  await tester.tap(find.byKey(_openDetailButtonKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('RemoteActivityDetailScreen', () {
    testWidgets('shows loading state while provider is pending', (
      tester,
    ) async {
      final pendingDetail = Completer<RemoteActivityDetailData?>();
      addTearDown(() {
        if (!pendingDetail.isCompleted) {
          pendingDetail.complete(_detailData());
        }
      });

      await tester.pumpWidget(
        _buildRemoteDetailScreen(
          detailBuilder: (ref) => pendingDetail.future,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(RemoteActivityDetailScreen.loadingStateKey),
        findsOneWidget,
      );
    });

    testWidgets('shows error state when provider throws', (tester) async {
      await tester.pumpWidget(
        _buildRemoteDetailScreen(
          detailBuilder: (ref) => Future<RemoteActivityDetailData?>.error(
            Exception('network error'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(RemoteActivityDetailScreen.errorStateKey),
        findsOneWidget,
      );
    });

    testWidgets(
      'loading state shows route recovery chrome for direct entry',
      (tester) async {
        final pendingDetail = Completer<RemoteActivityDetailData?>();
        addTearDown(() {
          if (!pendingDetail.isCompleted) {
            pendingDetail.complete(_detailData());
          }
        });

        await tester.pumpWidget(
          _buildRemoteDetailRouterScreen(
            detailBuilder: (ref) => pendingDetail.future,
          ),
        );
        await tester.pump();

        expect(
          find.byKey(RemoteActivityDetailScreen.loadingStateKey),
          findsOneWidget,
        );
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.text('Go to Home'), findsOneWidget);
        expect(find.text('Go Back'), findsNothing);

        await tester.tap(find.text('Go to Home'));
        await tester.pumpAndSettle();

        expect(find.text('home'), findsOneWidget);
      },
    );

    testWidgets(
      'loading state exposes go-back recovery when pushed from in-app route',
      (tester) async {
        final pendingDetail = Completer<RemoteActivityDetailData?>();
        addTearDown(() {
          if (!pendingDetail.isCompleted) {
            pendingDetail.complete(_detailData());
          }
        });

        await tester.pumpWidget(
          _buildRemoteDetailRouterScreen(
            initialLocation: _originRoutePath,
            detailBuilder: (ref) => pendingDetail.future,
          ),
        );
        await tester.pumpAndSettle();

        await _openDetailFromOrigin(tester);

        expect(
          find.byKey(RemoteActivityDetailScreen.loadingStateKey),
          findsOneWidget,
        );
        expect(find.text('Go Back'), findsOneWidget);

        await tester.tap(find.text('Go Back'));
        await tester.pumpAndSettle();

        expect(find.byKey(_openDetailButtonKey), findsOneWidget);
      },
    );

    testWidgets(
      'error state supports retry via provider invalidation on direct entry',
      (tester) async {
        var allowSuccess = false;
        var detailLoadCount = 0;

        await tester.pumpWidget(
          _buildRemoteDetailRouterScreen(
            detailBuilder: (ref) {
              detailLoadCount++;
              if (!allowSuccess) {
                return Future<RemoteActivityDetailData?>.error(
                  Exception('network error'),
                );
              }
              return Future<RemoteActivityDetailData?>.value(_detailData());
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(RemoteActivityDetailScreen.errorStateKey),
          findsOneWidget,
        );
        expect(find.text('Go to Home'), findsOneWidget);
        expect(find.text('Go Back'), findsNothing);
        expect(find.text('Retry'), findsOneWidget);

        allowSuccess = true;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(RemoteActivityDetailScreen.contentStateKey),
          findsOneWidget,
        );
        expect(detailLoadCount, greaterThan(1));
      },
    );

    testWidgets(
      'error state exposes go-back recovery when pushed from in-app route',
      (tester) async {
        await tester.pumpWidget(
          _buildRemoteDetailRouterScreen(
            initialLocation: _originRoutePath,
            detailBuilder: (ref) => Future<RemoteActivityDetailData?>.error(
              Exception('network error'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _openDetailFromOrigin(tester);
        await tester.pumpAndSettle();

        expect(
          find.byKey(RemoteActivityDetailScreen.errorStateKey),
          findsOneWidget,
        );
        expect(find.text('Go Back'), findsOneWidget);

        await tester.tap(find.text('Go Back'));
        await tester.pumpAndSettle();

        expect(find.byKey(_openDetailButtonKey), findsOneWidget);
      },
    );

    testWidgets('shows not-found state when detail is null', (tester) async {
      await tester.pumpWidget(
        _buildRemoteDetailScreen(
          detailBuilder: (ref) async => null,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(RemoteActivityDetailScreen.notFoundStateKey),
        findsOneWidget,
      );
    });

    testWidgets(
      'not-found state shows route recovery chrome for direct entry',
      (tester) async {
        await tester.pumpWidget(
          _buildRemoteDetailRouterScreen(
            detailBuilder: (ref) async => null,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(RemoteActivityDetailScreen.notFoundStateKey),
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
        var detailLoadCount = 0;

        await tester.pumpWidget(
          _buildRemoteDetailRouterScreen(
            detailBuilder: (ref) async {
              detailLoadCount++;
              if (!allowSuccess) {
                return null;
              }
              return _detailData();
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(RemoteActivityDetailScreen.notFoundStateKey),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);

        allowSuccess = true;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(RemoteActivityDetailScreen.contentStateKey),
          findsOneWidget,
        );
        expect(detailLoadCount, greaterThan(1));
      },
    );

    testWidgets(
      'not-found state exposes go-back recovery when pushed from in-app route',
      (tester) async {
        await tester.pumpWidget(
          _buildRemoteDetailRouterScreen(
            initialLocation: _originRoutePath,
            detailBuilder: (ref) async => null,
          ),
        );
        await tester.pumpAndSettle();

        await _openDetailFromOrigin(tester);
        await tester.pumpAndSettle();

        expect(
          find.byKey(RemoteActivityDetailScreen.notFoundStateKey),
          findsOneWidget,
        );
        expect(find.text('Go Back'), findsOneWidget);

        await tester.tap(find.text('Go Back'));
        await tester.pumpAndSettle();

        expect(find.byKey(_openDetailButtonKey), findsOneWidget);
      },
    );

    testWidgets('renders remote detail content from provider data', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildRemoteDetailScreen(
          detailBuilder: (ref) async => _detailData(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(RemoteActivityDetailScreen.contentStateKey),
        findsOneWidget,
      );
      expect(find.text('Owner Runner'), findsOneWidget);
      expect(find.text('City Tempo'), findsOneWidget);
      expect(
        find.byKey(RemoteActivityDetailScreen.metricsRowKey),
        findsOneWidget,
      );
      expect(find.text('7.20 km'), findsOneWidget);
      expect(find.text('00:34:00'), findsOneWidget);
      expect(find.text('04:43 /km'), findsOneWidget);
      expect(
        find.byKey(RemoteActivityDetailScreen.kudosCountTextKey),
        findsOneWidget,
      );
    });

    testWidgets(
      'owner row renders trusted avatar and navigates to viewed profile route',
      (tester) async {
        await tester.pumpWidget(
          _buildRemoteDetailRouterScreen(
            detailBuilder: (ref) async => _detailData(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TrustedAvatarWidget), findsOneWidget);

        await tester.tap(
          find.byKey(RemoteActivityDetailScreen.ownerTapTargetKey),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(_profileStateTextKey), findsOneWidget);
        expect(find.text('profile:$_ownerId'), findsOneWidget);
      },
    );

    testWidgets(
      'metrics section renders icon row and avoids plain text labels',
      (tester) async {
        await tester.pumpWidget(
          _buildRemoteDetailScreen(
            detailBuilder: (ref) async => _detailData(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(RemoteActivityDetailScreen.metricsRowKey),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.straighten), findsOneWidget);
        expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
        expect(find.byIcon(Icons.speed_outlined), findsOneWidget);
        expect(find.textContaining('Distance:'), findsNothing);
        expect(find.textContaining('Duration:'), findsNothing);
        expect(find.textContaining('Avg pace:'), findsNothing);
      },
    );

    testWidgets(
      'route preview renders in detail preset when at least two visible track points exist',
      (tester) async {
        await tester.pumpWidget(
          _buildRemoteDetailScreen(
            detailBuilder: (ref) async => _detailData(
              polylineEncoded: _encodedPolyline,
              trackPoints: <RemoteActivityTrackPoint>[
                RemoteActivityTrackPoint(
                  id: 1,
                  activityId: _activityId,
                  timestamp: DateTime.utc(2026, 3, 19, 10, 0, 1),
                  latitude: 40.7128,
                  longitude: -74.0060,
                  elevation: 8,
                  heartRate: 145,
                  cadence: 86,
                  speed: 3.5,
                  distance: 10,
                  temperature: 18,
                ),
                RemoteActivityTrackPoint(
                  id: 2,
                  activityId: _activityId,
                  timestamp: DateTime.utc(2026, 3, 19, 10, 1, 1),
                  latitude: 40.7228,
                  longitude: -74.0160,
                  elevation: 12,
                  heartRate: 148,
                  cadence: 88,
                  speed: 3.6,
                  distance: 1000,
                  temperature: 18,
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(RemoteActivityDetailScreen.routePreviewKey),
          findsOneWidget,
        );
        expect(
          find.byKey(StaticRoutePreview.detailAspectRatioKey),
          findsOneWidget,
        );
        final preview = tester.widget<StaticRoutePreview>(
          find.byType(StaticRoutePreview),
        );
        expect(preview.preset, StaticRoutePreviewSizePreset.detail);
        expect(preview.polylineEncoded, isNull);
        expect(preview.routePoints?.length, 2);
        expect(preview.routePoints?[0].latitude, closeTo(40.7128, 0.000001));
        expect(preview.routePoints?[0].longitude, closeTo(-74.0060, 0.000001));
        expect(preview.routePoints?[1].latitude, closeTo(40.7228, 0.000001));
        expect(preview.routePoints?[1].longitude, closeTo(-74.0160, 0.000001));
      },
    );

    testWidgets(
      'route preview is absent when fewer than two visible track points exist even if polyline exists',
      (tester) async {
        await tester.pumpWidget(
          _buildRemoteDetailScreen(
            detailBuilder: (ref) async => _detailData(
              polylineEncoded: _encodedPolyline,
              trackPoints: <RemoteActivityTrackPoint>[
                RemoteActivityTrackPoint(
                  id: 1,
                  activityId: _activityId,
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
                RemoteActivityTrackPoint(
                  id: 2,
                  activityId: _activityId,
                  timestamp: DateTime.utc(2026, 3, 19, 10, 1, 1),
                  latitude: 40.7228,
                  longitude: -74.0160,
                  elevation: 12,
                  heartRate: 148,
                  cadence: 88,
                  speed: 3.6,
                  distance: 1000,
                  temperature: 18,
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(RemoteActivityDetailScreen.routePreviewKey),
          findsNothing,
        );
        expect(find.byType(StaticRoutePreview), findsNothing);
      },
    );

    testWidgets(
      'photo strip renders horizontal thumbnails when photos exist',
      (tester) async {
        final photos = <ActivityPhoto>[
          ActivityPhoto(
            id: 'photo-1',
            activityId: _activityId,
            userId: _ownerId,
            storagePath: 'activities/$_activityId/photo-1.jpg',
            sortOrder: 0,
            createdAt: DateTime.utc(2026, 3, 19, 10, 5),
            signedStorageUrl: 'https://example.com/photo-1.jpg',
            signedThumbnailUrl: 'https://example.com/thumb-1.jpg',
          ),
          ActivityPhoto(
            id: 'photo-2',
            activityId: _activityId,
            userId: _ownerId,
            storagePath: 'activities/$_activityId/photo-2.jpg',
            sortOrder: 1,
            createdAt: DateTime.utc(2026, 3, 19, 10, 6),
            signedStorageUrl: 'https://example.com/photo-2.jpg',
            signedThumbnailUrl: 'https://example.com/thumb-2.jpg',
          ),
        ];

        await tester.pumpWidget(
          _buildRemoteDetailScreen(
            detailBuilder: (ref) async => _detailData(photos: photos),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(RemoteActivityDetailScreen.photoStripKey),
          findsOneWidget,
        );
        final photoListFinder = find.descendant(
          of: find.byKey(RemoteActivityDetailScreen.photoStripKey),
          matching: find.byType(ListView),
        );
        expect(photoListFinder, findsOneWidget);
        final photoList = tester.widget<ListView>(photoListFinder);
        expect(photoList.scrollDirection, Axis.horizontal);
        expect(find.byType(Image), findsNWidgets(2));
      },
    );

    testWidgets(
      'photo strip is absent when photos list is empty',
      (tester) async {
        await tester.pumpWidget(
          _buildRemoteDetailScreen(
            detailBuilder: (ref) async => _detailData(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(RemoteActivityDetailScreen.photoStripKey),
          findsNothing,
        );
      },
    );

    testWidgets('kudos toggle button refreshes remote detail count', (
      tester,
    ) async {
      final kudosRepository = _RecordingKudosRepository();
      var viewerHasKudo = false;
      var kudosCount = 0;
      var detailLoadCount = 0;

      await tester.pumpWidget(
        _buildRemoteDetailScreen(
          detailBuilder: (ref) {
            detailLoadCount++;
            final data = _detailData();
            return RemoteActivityDetailData(
              detail: SocialActivityDetail(
                activityId: data.detail.activityId,
                owner: data.detail.owner,
                sportType: data.detail.sportType,
                startedAt: data.detail.startedAt,
                finishedAt: data.detail.finishedAt,
                distanceMeters: data.detail.distanceMeters,
                durationSeconds: data.detail.durationSeconds,
                elevationGainMeters: data.detail.elevationGainMeters,
                avgPaceSecondsPerKm: data.detail.avgPaceSecondsPerKm,
                title: data.detail.title,
                description: data.detail.description,
                visibility: data.detail.visibility,
                polylineEncoded: data.detail.polylineEncoded,
                kudosCount: kudosCount,
                viewerHasKudo: viewerHasKudo,
                splits: data.detail.splits,
                trackPoints: data.detail.trackPoints,
              ),
              photos: data.photos,
            );
          },
          kudosRepository: kudosRepository,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
      await tester.tap(find.byKey(RemoteActivityDetailScreen.kudosButtonKey));
      await tester.pumpAndSettle();

      viewerHasKudo = true;
      kudosCount = 1;
      await tester.pumpAndSettle();

      expect(kudosRepository.toggleCallCount, 1);
      expect(detailLoadCount, greaterThan(1));
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('mounts ActivityCommentsSection after kudos card', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildRemoteDetailScreen(
          detailBuilder: (ref) async => _detailData(),
          additionalOverrides: [
            activityCommentsProvider(
              _activityId,
            ).overrideWith((ref) async => []),
            ...defaultAuthOverrides(userId: _viewerId),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Scroll down to where the comments section should appear.
      await tester.scrollUntilVisible(
        find.byKey(
          ActivityCommentsSection.sectionShellKey,
          skipOffstage: false,
        ),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ActivityCommentsSection.sectionShellKey),
        findsOneWidget,
      );

      final kudosTop = tester
          .getTopLeft(
            find.byKey(RemoteActivityDetailScreen.kudosCountTextKey),
          )
          .dy;
      final commentsTop = tester
          .getTopLeft(
            find.byKey(ActivityCommentsSection.sectionShellKey),
          )
          .dy;
      expect(kudosTop, lessThan(commentsTop));
    });
  });
}

class _RecordingKudosRepository implements KudosRepository {
  int toggleCallCount = 0;

  @override
  Future<ActivityKudosSummary> loadActivityKudos(String activityId) async {
    return const ActivityKudosSummary(
      kudosCount: 0,
      viewerHasKudo: false,
      users: <ActivityKudoUser>[],
    );
  }

  @override
  Future<void> toggleKudos({
    required String activityId,
    required bool viewerHasKudo,
  }) async {
    toggleCallCount++;
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/common_widgets/feed_skeleton_card.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/maps/data/route_polyline.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/application/social_kudos_providers.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/data/kudos_repository.dart';
import 'package:uff/src/features/social/data/social_activity_repository.dart';
import 'package:uff/src/features/social/domain/activity_kudos.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/social_activity_detail.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/presentation/feed_screen.dart';
import 'package:uff/src/features/social/presentation/relationship_search_screen.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';

/// ## Test Scenarios
/// - `[positive]` Feed cards render stable key contracts and retry/refresh behavior.
/// - `[positive]` Social navigation routes to search, profile, and activity destinations.
/// - `[positive]` Feed loading uses skeleton cards instead of a spinner.
/// - `[positive]` Feed card metrics render exact distance, duration, and preferred-unit pace text.
/// - `[negative]` Feed screen must not read `savedActivitiesProvider`; history-only data is out of scope for this surface.
/// - `[isolation]` Widget tests validate local presentation contracts only. Owner/follower/stranger visibility gating is owned by integration and E2E suites.
/// - `[statemachine]` Infinite scroll appends one next page, stops at terminal, and preserves cards on load-more errors.
/// - `[statemachine]` Scroll near bottom does not auto-retry load-more while error footer is shown.
/// - `[statemachine]` Kudos toggles only disable the targeted activity while pending.
/// - `[error]` Error and empty feed states preserve deterministic recovery UI.
/// - `[edge]` Empty feed branches between follows-nobody and no-recent-activity variants.
const _viewerId = '11111111-1111-1111-1111-111111111111';
const _ownerId = '22222222-2222-2222-2222-222222222222';

class _FeedRequest {
  const _FeedRequest(this.offset, this.limit);
  final int offset;
  final int limit;
}

class _FakeSocialActivityRepository implements SocialActivityRepository {
  _FakeSocialActivityRepository({required this.loadFeedPage});

  final FutureOr<List<SocialActivitySummary>> Function(int offset, int limit)
  loadFeedPage;
  final List<_FeedRequest> feedRequests = <_FeedRequest>[];

  @override
  Future<SocialActivityDetail?> loadActivityDetail(String activityId) async {
    return null;
  }

  @override
  Future<List<SocialActivitySummary>> loadFeedActivities({
    required int offset,
    required int limit,
  }) async {
    feedRequests.add(_FeedRequest(offset, limit));
    return loadFeedPage(offset, limit);
  }

  @override
  Future<List<SocialActivitySummary>> loadUserActivities(String userId) async {
    return const <SocialActivitySummary>[];
  }
}

class _FakeProfileNotifier extends ProfileNotifier {
  _FakeProfileNotifier(this._profile);

  final Profile _profile;

  @override
  Profile build() {
    return _profile;
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
  double distanceMeters = 5000,
  int durationSeconds = 1500,
  int kudosCount = 0,
  bool viewerHasKudo = false,
  String? polylineEncoded,
  List<RoutePoint>? routePoints,
  int commentCount = 0,
}) {
  return SocialActivitySummary(
    activityId: activityId,
    owner: _ownerSummary(),
    sportType: 'run',
    startedAt: DateTime.utc(2026, 3, 19, 10),
    finishedAt: DateTime.utc(2026, 3, 19, 10, 25),
    distanceMeters: distanceMeters,
    durationSeconds: durationSeconds,
    elevationGainMeters: 30,
    avgPaceSecondsPerKm: 300,
    title: title,
    description: null,
    visibility: 'public',
    commentCount: commentCount,
    kudosCount: kudosCount,
    viewerHasKudo: viewerHasKudo,
    polylineEncoded: polylineEncoded,
    routePoints: routePoints,
  );
}

Profile _profileWithUnits(String preferredUnits) {
  return Profile(
    userId: _viewerId,
    preferredUnits: preferredUnits,
    defaultActivityVisibility: 'public',
    onboardingCompleted: true,
    displayName: 'Viewer',
  );
}

/// Builds a [FeedScreen] wrapped in [ProviderScope] with repository seams.
Widget _buildFeedScreen({
  required FutureOr<List<SocialActivitySummary>> Function() socialFeed,
  FutureOr<List<SocialActivitySummary>> Function(int offset, int limit)?
  loadFeedPage,
  FutureOr<List<SocialUserSummary>> Function(Ref)? followingOverride,
  KudosRepository? kudosRepository,
  String? preferredUnits,
  _FakeSocialActivityRepository? socialRepository,
}) {
  final repository =
      socialRepository ??
      _FakeSocialActivityRepository(
        loadFeedPage:
            loadFeedPage ??
            (offset, limit) {
              if (offset != 0) {
                return const <SocialActivitySummary>[];
              }
              return socialFeed();
            },
      );

  return ProviderScope(
    overrides: [
      socialActivityRepositoryProvider.overrideWithValue(repository),
      if (followingOverride != null)
        followingProvider.overrideWith(followingOverride),
      if (kudosRepository != null)
        kudosRepositoryProvider.overrideWithValue(kudosRepository),
      if (preferredUnits != null)
        profileProvider.overrideWith(
          () => _FakeProfileNotifier(_profileWithUnits(preferredUnits)),
        ),
      savedActivitiesProvider.overrideWith(
        (ref) => Future<List<TrackingSessionRecord>>.error(
          StateError('savedActivitiesProvider must not be read by feed'),
        ),
      ),
    ],
    child: const MaterialApp(home: FeedScreen()),
  );
}

Widget _buildFeedRouterScope({
  required FutureOr<List<SocialActivitySummary>> Function() socialFeed,
  FutureOr<List<SocialActivitySummary>> Function(int offset, int limit)?
  loadFeedPage,
  FutureOr<List<SocialUserSummary>> Function(Ref)? followingOverride,
  KudosRepository? kudosRepository,
  _FakeSocialActivityRepository? socialRepository,
}) {
  final repository =
      socialRepository ??
      _FakeSocialActivityRepository(
        loadFeedPage:
            loadFeedPage ??
            (offset, limit) {
              if (offset != 0) {
                return const <SocialActivitySummary>[];
              }
              return socialFeed();
            },
      );

  final router = GoRouter(
    initialLocation: '/feed',
    routes: [
      GoRoute(
        path: '/feed',
        builder: (context, state) => const FeedScreen(),
      ),
      GoRoute(
        path: SocialRoutes.searchPath,
        builder: (context, state) => const RelationshipSearchScreen(),
      ),
      GoRoute(
        path: '/social/profile/:userId',
        builder: (context, state) =>
            Text('profile:${state.pathParameters['userId']}'),
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
      socialActivityRepositoryProvider.overrideWithValue(repository),
      if (followingOverride != null)
        followingProvider.overrideWith(followingOverride),
      if (kudosRepository != null)
        kudosRepositoryProvider.overrideWithValue(kudosRepository),
      savedActivitiesProvider.overrideWith(
        (ref) => Future<List<TrackingSessionRecord>>.error(
          StateError('savedActivitiesProvider must not be read by feed'),
        ),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _dragToRefresh(WidgetTester tester, Finder dragTarget) async {
  await tester.drag(dragTarget, const Offset(0, 300));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('FeedScreen', () {
    testWidgets('shows kudos button and count keys on each feed card', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildFeedScreen(
          socialFeed: () async => <SocialActivitySummary>[
            _summary(activityId: 'a1', kudosCount: 3),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(FeedScreen.kudosButtonKey('a1')), findsOneWidget);
      expect(find.byKey(FeedScreen.kudosCountKey('a1')), findsOneWidget);
    });

    testWidgets('shows skeleton cards while feed is loading', (
      tester,
    ) async {
      final pendingFeed = Completer<List<SocialActivitySummary>>();
      addTearDown(() {
        if (!pendingFeed.isCompleted) {
          pendingFeed.complete(const <SocialActivitySummary>[]);
        }
      });

      await tester.pumpWidget(
        _buildFeedScreen(
          socialFeed: () => pendingFeed.future,
        ),
      );
      await tester.pump();

      expect(find.byType(FeedSkeletonCard), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows error state and retries feed load after failure', (
      tester,
    ) async {
      var allowReloadSuccess = false;
      var loadCount = 0;

      await tester.pumpWidget(
        _buildFeedScreen(
          socialFeed: () {
            loadCount++;
            if (!allowReloadSuccess) {
              return Future<List<SocialActivitySummary>>.error(
                StateError('load failed'),
              );
            }

            return Future<List<SocialActivitySummary>>.value(
              <SocialActivitySummary>[
                _summary(activityId: 'retry-a1', title: 'Retry Run'),
              ],
            );
          },
        ),
      );
      for (var attempt = 0; attempt < 10; attempt++) {
        if (find.byKey(FeedScreen.errorStateKey).evaluate().isNotEmpty) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byKey(FeedScreen.errorStateKey), findsOneWidget);
      expect(find.byKey(FeedScreen.retryButtonKey), findsOneWidget);

      allowReloadSuccess = true;
      await tester.tap(find.byKey(FeedScreen.retryButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(FeedScreen.feedCardKey('retry-a1')), findsOneWidget);
      expect(find.text('Retry Run'), findsOneWidget);
      expect(loadCount, greaterThan(1));
    });

    testWidgets(
      'pull-to-refresh replaces loaded feed cards with refreshed page',
      (tester) async {
        var loadCount = 0;

        await tester.pumpWidget(
          _buildFeedScreen(
            socialFeed: () async {
              loadCount++;
              return loadCount == 1
                  ? <SocialActivitySummary>[
                      _summary(
                        activityId: 'refresh-a1',
                        title: 'Refresh Run A',
                      ),
                    ]
                  : <SocialActivitySummary>[
                      _summary(
                        activityId: 'refresh-b1',
                        title: 'Refresh Run B',
                      ),
                    ];
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(loadCount, 1);
        expect(
          find.byKey(FeedScreen.feedCardKey('refresh-a1')),
          findsOneWidget,
        );
        expect(find.byKey(FeedScreen.feedCardKey('refresh-b1')), findsNothing);

        await _dragToRefresh(tester, find.byType(ListView));
        await tester.pumpAndSettle();

        expect(loadCount, 2);
        expect(find.byKey(FeedScreen.feedCardKey('refresh-a1')), findsNothing);
        expect(
          find.byKey(FeedScreen.feedCardKey('refresh-b1')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'scrolling near bottom appends one next page and terminal page prevents extra requests',
      (tester) async {
        final socialRepository = _FakeSocialActivityRepository(
          loadFeedPage: (offset, limit) {
            if (offset == 0) {
              return List<SocialActivitySummary>.generate(
                socialFeedPageSize,
                (index) => _summary(
                  activityId: 'paged-$index',
                  title: 'Paged $index',
                ),
                growable: false,
              );
            }
            if (offset == socialFeedPageSize) {
              return <SocialActivitySummary>[
                _summary(activityId: 'paged-terminal', title: 'Terminal Page'),
              ];
            }
            return const <SocialActivitySummary>[];
          },
        );

        await tester.pumpWidget(
          _buildFeedScreen(
            socialFeed: () async => const <SocialActivitySummary>[],
            socialRepository: socialRepository,
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(find.byType(ListView), const Offset(0, -4000));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.byKey(FeedScreen.terminalStateKey),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(FeedScreen.feedCardKey('paged-terminal')),
          findsOneWidget,
        );
        expect(find.byKey(FeedScreen.terminalStateKey), findsOneWidget);
        expect(
          socialRepository.feedRequests
              .where((request) => request.offset == socialFeedPageSize)
              .length,
          1,
        );

        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pumpAndSettle();

        expect(
          socialRepository.feedRequests
              .where((request) => request.offset == socialFeedPageSize)
              .length,
          1,
        );
      },
    );

    testWidgets(
      'load-more error keeps current cards visible and shows retry footer',
      (tester) async {
        final socialRepository = _FakeSocialActivityRepository(
          loadFeedPage: (offset, limit) {
            if (offset == 0) {
              return List<SocialActivitySummary>.generate(
                socialFeedPageSize,
                (index) => _summary(activityId: 'err-$index'),
                growable: false,
              );
            }
            throw StateError('next page failed');
          },
        );

        await tester.pumpWidget(
          _buildFeedScreen(
            socialFeed: () async => const <SocialActivitySummary>[],
            socialRepository: socialRepository,
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(find.byType(ListView), const Offset(0, -4000));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.byKey(FeedScreen.feedCardKey('err-19')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(find.byKey(FeedScreen.feedCardKey('err-19')), findsOneWidget);
        expect(find.byKey(FeedScreen.loadMoreErrorKey), findsOneWidget);
        expect(find.byKey(FeedScreen.loadMoreRetryButtonKey), findsOneWidget);

        final requestCountAfterError = socialRepository.feedRequests.length;
        await tester.drag(find.byType(ListView), const Offset(0, 400));
        await tester.pump();
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();

        expect(
          socialRepository.feedRequests.length,
          requestCountAfterError,
          reason: 'Scroll must not auto-retry load-more while error is shown',
        );
      },
    );

    testWidgets(
      'empty feed plus following nobody shows follows-nobody empty state',
      (tester) async {
        await tester.pumpWidget(
          _buildFeedScreen(
            socialFeed: () async => <SocialActivitySummary>[],
            followingOverride: (ref) async => const <SocialUserSummary>[],
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(FeedScreen.emptyFollowingNobodyKey),
          findsOneWidget,
        );
        expect(find.byKey(FeedScreen.searchCtaButtonKey), findsOneWidget);
        // Assert the exact copy text so wording changes are caught.
        expect(
          find.text('Follow other runners to see their activities here.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'empty feed plus following people shows no-recent-activity empty state',
      (tester) async {
        await tester.pumpWidget(
          _buildFeedScreen(
            socialFeed: () async => <SocialActivitySummary>[],
            followingOverride: (ref) async => <SocialUserSummary>[
              _ownerSummary(),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(FeedScreen.emptyNoRecentActivityKey),
          findsOneWidget,
        );
        expect(find.byKey(FeedScreen.searchCtaButtonKey), findsNothing);
        expect(
          find.text('No recent activities from people you follow'),
          findsOneWidget,
        );
      },
    );

    testWidgets('empty state CTA navigates to relationship search', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildFeedRouterScope(
          socialFeed: () async => <SocialActivitySummary>[],
          followingOverride: (ref) async => const <SocialUserSummary>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(FeedScreen.emptyFollowingNobodyKey),
        findsOneWidget,
      );
      expect(find.byKey(FeedScreen.searchCtaButtonKey), findsOneWidget);

      await tester.tap(find.byKey(FeedScreen.searchCtaButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(RelationshipSearchScreen), findsOneWidget);
    });

    testWidgets(
      'tapping feed owner pushes viewed-user profile route path',
      (tester) async {
        await tester.pumpWidget(
          _buildFeedRouterScope(
            socialFeed: () async => <SocialActivitySummary>[
              _summary(activityId: 'a1', title: 'Morning Run'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(FeedScreen.ownerTapTargetKey('a1')));
        await tester.pumpAndSettle();

        expect(find.text('profile:$_ownerId'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping feed activity card pushes remote-activity detail route path',
      (tester) async {
        await tester.pumpWidget(
          _buildFeedRouterScope(
            socialFeed: () async => <SocialActivitySummary>[
              _summary(activityId: 'a1', title: 'Morning Run'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(FeedScreen.activityTapTargetKey('a1')));
        await tester.pumpAndSettle();

        expect(find.text('activity:a1'), findsOneWidget);
      },
    );

    testWidgets('renders exact imperial pace text from avgPaceSecondsPerKm', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildFeedScreen(
          socialFeed: () async => <SocialActivitySummary>[
            _summary(activityId: 'pace-a1', title: 'Pace Run'),
          ],
          preferredUnits: 'imperial',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('08:02 /mi'), findsOneWidget);
    });

    testWidgets('tapping kudos button toggles and refreshes feed data', (
      tester,
    ) async {
      final kudosRepository = _RecordingKudosRepository();
      var viewerHasKudo = false;
      var kudosCount = 0;
      var socialFeedLoadCount = 0;

      await tester.pumpWidget(
        _buildFeedScreen(
          socialFeed: () {
            socialFeedLoadCount++;
            return <SocialActivitySummary>[
              _summary(
                activityId: 'a1',
                viewerHasKudo: viewerHasKudo,
                kudosCount: kudosCount,
              ),
            ];
          },
          kudosRepository: kudosRepository,
        ),
      );
      await tester.pumpAndSettle();

      final kudosCountWidget = tester.widget<Text>(
        find.byKey(FeedScreen.kudosCountKey('a1')),
      );
      expect(kudosCountWidget.data, '0');
      await tester.tap(find.byKey(FeedScreen.kudosButtonKey('a1')));
      await tester.pumpAndSettle();

      viewerHasKudo = true;
      kudosCount = 1;
      await tester.pumpAndSettle();

      expect(kudosRepository.toggleCallCount, 1);
      expect(socialFeedLoadCount, greaterThan(1));
      final updatedKudosCount = tester.widget<Text>(
        find.byKey(FeedScreen.kudosCountKey('a1')),
      );
      expect(updatedKudosCount.data, '1');
    });

    testWidgets(
      'a pending toggle only disables the tapped activity button',
      (tester) async {
        final kudosRepository = _BlockingKudosRepository();
        addTearDown(kudosRepository.completeAll);

        await tester.pumpWidget(
          _buildFeedScreen(
            socialFeed: () async => <SocialActivitySummary>[
              _summary(activityId: 'a1', kudosCount: 3),
              _summary(activityId: 'a2', kudosCount: 5),
            ],
            kudosRepository: kudosRepository,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(FeedScreen.kudosButtonKey('a1')));
        await tester.pump();

        final firstButton = tester.widget<IconButton>(
          find.byKey(FeedScreen.kudosButtonKey('a1')),
        );
        final secondButton = tester.widget<IconButton>(
          find.byKey(FeedScreen.kudosButtonKey('a2')),
        );
        expect(firstButton.onPressed, isNull);
        expect(secondButton.onPressed == null, isFalse);

        await tester.tap(find.byKey(FeedScreen.kudosButtonKey('a2')));
        await tester.pump();

        expect(kudosRepository.toggleCallCount, 2);
      },
    );
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

class _BlockingKudosRepository implements KudosRepository {
  int toggleCallCount = 0;
  final _pendingToggles = <Completer<void>>[];

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
  }) {
    toggleCallCount++;
    final completer = Completer<void>();
    _pendingToggles.add(completer);
    return completer.future;
  }

  void completeAll() {
    for (final completer in _pendingToggles) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_smoke_overrides.dart';
import 'package:uff/src/features/activity_tracking/data/replay_tracking_engine.dart';
import 'package:uff/src/features/activity_tracking/data/tracelet_tracking_engine.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_repository.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart';
import 'package:uff/src/features/photos/data/photo_picker_service.dart';
import 'package:uff/src/features/auth/presentation/login_screen.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/social/presentation/relationship_search_screen.dart';
import 'package:uff/src/routing/app_router.dart';

import '../../e2e_test/fixtures.dart';
import '../src/features/import/data/fit_test_helpers.dart';

// ## Test Scenarios
// - [positive] createTestContainer produces a working Riverpod container
// - [positive] seedSyncedActivityInContainer returns local and remote IDs
// - [positive] Photo picker service override returns expected stub behavior
// - [positive] Social route helper pushes through the provider-owned app router
// - [positive] Signed-out auth helper waits for the login field before returning
// - [negative] Provider overrides prevent real Supabase/database access
// - [isolation] Each test container is independent with its own overrides

const _photoAFixturePath = 'e2e_test/test_data/photo_a.jpg';
const _photoBFixturePath = 'e2e_test/test_data/photo_b.png';
const _homeNavActivityKey = Key('home_nav_activity');
const _standardPhotoFixturePaths = <String>[
  _photoAFixturePath,
  _photoBFixturePath,
];

ProviderContainer createTestContainer(List<Object> overrides) {
  final container = ProviderContainer(overrides: overrides.cast());
  addTearDown(container.dispose);
  return container;
}

/// ## Test Scenarios
/// - `[positive]` Override composition installs deterministic tracking and picker fixtures.
/// - `[positive]` Replay-backed E2E overrides also enable the smoke-only GPS start bypass.
/// - `[positive]` Photo and point fixtures load with stable names and byte content.
/// - `[positive]` Remote photo seeding uploads the expected storage object and metadata payload.
/// - `[edge]` Fixture path guards reject reads outside the fixture tree.
/// - `[statemachine]` Synced activity seeding updates local and remote contracts in order.
/// - `[error]` Remote photo cleanup preserves DB rows when storage deletion fails.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildTestApp override composition', () {
    test(
      'tracking overrides on by default and custom picker override is merged',
      () async {
        final pickerService = FixturePhotoPickerService(
          pickedPhotos: <PickedPhoto>[
            PickedPhoto(
              fileName: 'custom.jpg',
              bytes: Uint8List.fromList([1, 2, 3]),
            ),
          ],
        );
        final overrides = await composeTestAppOverrides(
          fixtureOverrides: [
            photoPickerServiceProvider.overrideWithValue(pickerService),
          ],
        );
        final container = createTestContainer(overrides.cast());

        // Stage 3: these engine/permission types have no stable public fields
        // beyond their type; isA proves the override installed the correct impl.
        final trackingEngine = container.read(trackingEngineProvider);
        final permissionService = container.read(
          trackingPermissionServiceProvider,
        );
        expect(trackingEngine.runtimeType, ReplayTrackingEngine);
        expect(permissionService.runtimeType, FakePermissionService);
        expect(
          container.read(allowRecordingStartWithoutGpsFixProvider),
          isTrue,
        );
        expect(container.read(photoPickerServiceProvider), same(pickerService));
      },
    );

    test(
      'tracking overrides can be disabled while preserving fixture overrides',
      () async {
        final pickerService = FixturePhotoPickerService(
          pickedPhotos: <PickedPhoto>[
            PickedPhoto(
              fileName: 'disabled.jpg',
              bytes: Uint8List.fromList([4, 5, 6]),
            ),
          ],
        );
        final overrides = await composeTestAppOverrides(
          trackingOverrides: false,
          fixtureOverrides: [
            photoPickerServiceProvider.overrideWithValue(pickerService),
          ],
        );
        final container = createTestContainer(overrides.cast());

        // Stage 3: type identity is the contract for disabled-override checks;
        // no stable fields to match beyond the runtime type.
        final trackingEngine = container.read(trackingEngineProvider);
        expect(trackingEngine.runtimeType, TraceletTrackingEngine);
        expect(
          container.read(trackingPermissionServiceProvider),
          isNot(isA<FakePermissionService>()),
        );
        expect(
          container.read(allowRecordingStartWithoutGpsFixProvider),
          isFalse,
        );
        expect(container.read(photoPickerServiceProvider), same(pickerService));
      },
    );

    test(
      'tracking engine override is accepted when tracking defaults disabled',
      () async {
        final forcedEngine = ReplayTrackingEngine(
          points: const <TrackingPoint>[],
        );
        final overrides = await composeTestAppOverrides(
          trackingOverrides: false,
          fixtureOverrides: [
            trackingEngineProvider.overrideWithValue(forcedEngine),
          ],
        );
        final container = createTestContainer(overrides.cast());

        expect(container.read(trackingEngineProvider), same(forcedEngine));
      },
    );

    test(
      'buildTestApp accepts fixture overrides and custom init callback',
      () async {
        var initCallCount = 0;
        final pickerService = FixturePhotoPickerService(
          pickedPhotos: <PickedPhoto>[
            PickedPhoto(
              fileName: 'from-app.jpg',
              bytes: Uint8List.fromList([8, 9]),
            ),
          ],
        );
        final app = await buildTestApp(
          trackingOverrides: false,
          fixtureOverrides: [
            photoPickerServiceProvider.overrideWithValue(pickerService),
          ],
          initializeServices: () async {
            initCallCount += 1;
          },
        );

        expect(initCallCount, 1);
        final providerScope = app as ProviderScope;
        final container = createTestContainer(providerScope.overrides.cast());
        expect(container.read(photoPickerServiceProvider), same(pickerService));
      },
    );
  });

  group('social route helper', () {
    testWidgets(
      'pushRouteThroughAppRouterForTesting drives navigation via appRouterProvider',
      (tester) async {
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => const SizedBox.shrink(),
            ),
            GoRoute(
              path: '/social/search',
              builder: (_, __) => const RelationshipSearchScreen(),
            ),
          ],
        );
        addTearDown(router.dispose);

        final container = createTestContainer([
          appRouterProvider.overrideWithValue(router),
        ]);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(routerConfig: router),
          ),
        );

        pushRouteThroughAppRouterForTesting(container, '/social/search');
        await tester.pumpAndSettle();

        expect(
          find.byKey(RelationshipSearchScreen.searchFieldKey),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'goRouteThroughAppRouterForTesting replaces the current route via appRouterProvider',
      (tester) async {
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => const Text('root'),
            ),
            GoRoute(
              path: '/social/search',
              builder: (_, __) => const RelationshipSearchScreen(),
            ),
          ],
        );
        addTearDown(router.dispose);

        final container = createTestContainer([
          appRouterProvider.overrideWithValue(router),
        ]);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(routerConfig: router),
          ),
        );

        goRouteThroughAppRouterForTesting(container, '/social/search');
        await tester.pumpAndSettle();

        expect(
          find.byKey(RelationshipSearchScreen.searchFieldKey),
          findsOneWidget,
        );
        expect(find.text('root'), findsNothing);
      },
    );

    testWidgets(
      'unmountWidgetTreeForTesting disposes shell routes before same-test relaunch',
      (tester) async {
        Future<void> pumpRelaunchableShellApp() async {
          final router = GoRouter(
            initialLocation: '/home',
            routes: [
              StatefulShellRoute.indexedStack(
                builder: (_, __, navigationShell) =>
                    HomeShellScreen(navigationShell: navigationShell),
                branches: [
                  for (final destination in homeShellDestinations)
                    StatefulShellBranch(
                      routes: [
                        GoRoute(
                          path: destination.path,
                          builder: (_, __) =>
                              buildHomeShellBranchContent(destination.id),
                        ),
                      ],
                    ),
                ],
              ),
              GoRoute(
                path: '/social/search',
                builder: (_, __) => const RelationshipSearchScreen(),
              ),
            ],
          );
          final container = ProviderContainer(
            overrides: [
              appRouterProvider.overrideWithValue(router),
            ],
          );

          addTearDown(router.dispose);
          addTearDown(container.dispose);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp.router(routerConfig: router),
            ),
          );
          expect(
            find.byKey(HomeShellScreen.openSettingsButtonKey),
            findsOneWidget,
          );

          goRouteThroughAppRouterForTesting(container, '/social/search');
          await tester.pumpAndSettle();
          expect(
            find.byKey(RelationshipSearchScreen.searchFieldKey),
            findsOneWidget,
          );

          await unmountWidgetTreeForTesting(tester);
        }

        await pumpRelaunchableShellApp();
        await pumpRelaunchableShellApp();
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('signed-out auth readiness helper', () {
    testWidgets(
      'waitForFinderToBecomeHitTestableForTesting waits through delayed auth mount',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: _DelayedVisibilityHarness(
              delay: Duration(milliseconds: 150),
              child: TextField(key: LoginScreen.emailFieldKey),
            ),
          ),
        );

        await waitForFinderToBecomeHitTestableForTesting(
          tester,
          find.byKey(LoginScreen.emailFieldKey),
          timeout: const Duration(seconds: 1),
          pumpStep: const Duration(milliseconds: 25),
        );

        expect(find.byKey(LoginScreen.emailFieldKey), findsOneWidget);
      },
    );
  });

  group('deterministic photo picker fixtures', () {
    test('loads stable fixture names and bytes in request order', () async {
      final first = await loadPhotoFixture(_photoAFixturePath);
      final second = await loadPhotoFixture(_photoBFixturePath);

      expect(first.fileName, 'photo_a.jpg');
      expect(second.fileName, 'photo_b.png');
      expect(first.bytes, hasLength(398));
      expect(second.bytes, hasLength(68));

      final reloaded = await loadPhotoFixtures(_standardPhotoFixturePaths);
      expect(reloaded[0].fileName, first.fileName);
      expect(reloaded[1].fileName, second.fileName);
      expect(reloaded[0].bytes, orderedEquals(first.bytes));
      expect(reloaded[1].bytes, orderedEquals(second.bytes));
    });

    test(
      'fixture picker returns all selected photos in deterministic order',
      () async {
        final pickedPhotos = await loadPhotoFixtures(
          _standardPhotoFixturePaths,
        );
        final pickerService = FixturePhotoPickerService(
          pickedPhotos: pickedPhotos,
        );

        final selected = await pickerService.pickPhotos(
          source: PhotoPickSource.gallery,
        );

        expect(selected.map((photo) => photo.fileName).toList(), [
          'photo_a.jpg',
          'photo_b.png',
        ]);
        expect(selected[0].bytes, orderedEquals(pickedPhotos[0].bytes));
        expect(selected[1].bytes, orderedEquals(pickedPhotos[1].bytes));
      },
    );

    test(
      'fixture picker returns empty selection when configured empty',
      () async {
        final pickerService = FixturePhotoPickerService();

        final selected = await pickerService.pickPhotos(
          source: PhotoPickSource.gallery,
        );

        expect(selected, isEmpty);
      },
    );

    test(
      'buildPhotoPickerFixtureOverrides creates app-scoped provider override',
      () async {
        final overrides = await buildPhotoPickerFixtureOverrides(
          _standardPhotoFixturePaths,
        );
        final container = createTestContainer(overrides.cast());

        final selected = await container
            .read(photoPickerServiceProvider)
            .pickPhotos(source: PhotoPickSource.gallery);
        expect(selected.map((photo) => photo.fileName).toList(), [
          'photo_a.jpg',
          'photo_b.png',
        ]);
      },
    );

    test(
      'fixture picker returns deterministic camera fixtures via same API',
      () async {
        final galleryPhotos = await loadPhotoFixtures([_photoAFixturePath]);
        final cameraPhotos = await loadPhotoFixtures([_photoBFixturePath]);
        final pickerService = FixturePhotoPickerService(
          pickedPhotosBySource: {
            PhotoPickSource.gallery: galleryPhotos,
            PhotoPickSource.camera: cameraPhotos,
          },
        );

        final selected = await pickerService.pickPhotos(
          source: PhotoPickSource.camera,
        );

        expect(selected, hasLength(1));
        expect(selected[0].fileName, 'photo_b.png');
        expect(selected[0].bytes, orderedEquals(cameraPhotos[0].bytes));
      },
    );

    test('rejects photo fixture paths outside the fixture directory', () {
      expect(() => loadPhotoFixture('pubspec.yaml'), throwsArgumentError);
    });
  });

  group('deterministic import title fixtures', () {
    test(
      'expectedImportedRunTitleForTesting derives the exact generated title from the shared FIT timestamp',
      () {
        final expectedTitle = generateDefaultActivityTitle(
          startedAt: DateTime.fromMillisecondsSinceEpoch(
            fitBaseTimestamp,
            isUtc: true,
          ),
        );

        expect(expectedImportedRunTitleForTesting(), expectedTitle);
      },
    );
  });

  group('fixture point loader', () {
    test('rejects point fixture paths outside the fixture directory', () {
      expect(
        loadFixturePoints('pubspec.yaml', sessionId: 0),
        throwsArgumentError,
      );
    });
  });

  group('synced activity seeding', () {
    test(
      'seedSyncedActivityInContainer returns ids, updates remote id, and invalidates savedActivitiesProvider',
      () async {
        final operationLog = <String>[];
        final repository = _RecordingSeedTrackingRepository(
          operationLog: operationLog,
        );
        final insertedPayloads = <Map<String, dynamic>>[];
        var savedActivitiesLoadCount = 0;
        final container = createTestContainer([
          trackingRepositoryProvider.overrideWithValue(repository),
          savedActivitiesProvider.overrideWith((ref) async {
            savedActivitiesLoadCount += 1;
            return const <TrackingSessionRecord>[];
          }),
          // activityDetailProvider (listened by seedSyncedActivityInContainer
          // to prevent autoDispose) depends on profileProvider, which
          // cascades into Supabase unless overridden.
          profileProvider.overrideWith(_StubProfileNotifier.new),
        ]);

        await container.read(savedActivitiesProvider.future);
        expect(savedActivitiesLoadCount, 1);

        final result = await seedSyncedActivityInContainer(
          container,
          dependencies: SyncedActivitySeedDependencies(
            currentUserId: 'user-123',
            remoteIdGenerator: () => 'remote-abc',
            insertRemoteActivity: (payload) async {
              operationLog.add('insertRemoteActivity');
              insertedPayloads.add(payload);
            },
          ),
          distanceMeters: 4800,
          movingTimeSeconds: 1320,
          startedAt: DateTime.utc(2026, 3, 16, 11, 30),
        );

        expect(result.localSessionId, 1);
        expect(result.remoteActivityId, 'remote-abc');
        expect(repository.lastUpdatedSessionId, 1);
        expect(repository.lastUpdatedRemoteId, 'remote-abc');
        expect(
          operationLog,
          containsAllInOrder([
            'saveImportedSession',
            'loadSession',
            'insertRemoteActivity',
            'updateSessionRemoteId',
          ]),
        );

        await container.read(savedActivitiesProvider.future);
        expect(savedActivitiesLoadCount, 2);

        expect(insertedPayloads, hasLength(1));
        expect(insertedPayloads.single['id'], 'remote-abc');
        expect(insertedPayloads.single['user_id'], 'user-123');
        expect(insertedPayloads.single['distance_meters'], 4800.0);
      },
    );

    test(
      'seedSyncedActivityInContainer keeps the local session unsynced when remote insert fails',
      () async {
        final repository = _RecordingSeedTrackingRepository();
        final container = createTestContainer([
          trackingRepositoryProvider.overrideWithValue(repository),
        ]);

        await expectLater(
          seedSyncedActivityInContainer(
            container,
            dependencies: SyncedActivitySeedDependencies(
              currentUserId: 'user-123',
              remoteIdGenerator: () => 'remote-abc',
              insertRemoteActivity: (_) async {
                throw StateError('insert failed');
              },
            ),
            distanceMeters: 4800,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'insert failed',
            ),
          ),
        );

        expect(repository.lastUpdatedSessionId, isNull);
        expect(repository.lastUpdatedRemoteId, isNull);
        expect(repository.sessionsById[1]?.remoteId, isNull);
      },
    );
  });

  group('waitForHomeActivityHistoryLoaded metadata contract', () {
    // These tests validate the shared destination metadata that
    // waitForHomeActivityHistoryLoaded() relies on after the Stage 4
    // feed-first refactor. The function itself uses PatrolIntegrationTester
    // and can only run in a full integration environment, but its correctness
    // depends on this metadata being stable.

    test('feed is the first destination (index 0), not activity', () {
      expect(homeShellDestinations.first.id, HomeShellDestinationId.feed);
      expect(
        homeShellDestinations.first.id,
        isNot(HomeShellDestinationId.activity),
      );
    });

    test('activity destination exists and has a non-null navigation key', () {
      final activityDest = homeShellDestinations.where(
        (d) => d.id == HomeShellDestinationId.activity,
      );
      expect(
        activityDest,
        hasLength(1),
        reason: 'Exactly one activity destination must exist',
      );
      expect(activityDest.first.navigationKey, _homeNavActivityKey);
    });

    test('activity destination is not at index 0', () {
      final activityIndex = homeShellDestinations.indexWhere(
        (d) => d.id == HomeShellDestinationId.activity,
      );
      expect(activityIndex, 1);
    });

    test(
      'activity navigation key matches the key used by the shell bottom nav',
      () {
        final activityDest = homeShellDestinations.firstWhere(
          (d) => d.id == HomeShellDestinationId.activity,
        );
        // The key is constructed from a known convention. Verify it matches
        // so the Patrol tap target in waitForHomeActivityHistoryLoaded stays
        // in sync with the shell widget tree.
        expect(activityDest.navigationKey, _homeNavActivityKey);
      },
    );
  });

  group('remote photo cleanup fixtures', () {
    test(
      'seedRemoteActivityPhoto uploads storage before inserting metadata',
      () async {
        final operationLog = <String>[];
        String? uploadedPath;
        Uint8List? uploadedBytes;
        Map<String, dynamic>? insertedPayload;

        final seededPhoto = await seedRemoteActivityPhoto(
          activityId: 'remote-1',
          photoBytes: Uint8List.fromList([1, 2, 3, 4]),
          sortOrder: 7,
          dependencies: SeededRemoteActivityPhotoDependencies(
            currentUserId: 'user-123',
            uploadStorageObject:
                ({required String path, required Uint8List bytes}) async {
                  operationLog.add('upload');
                  uploadedPath = path;
                  uploadedBytes = bytes;
                },
            insertPhotoMetadata: (payload) async {
              operationLog.add('insert');
              insertedPayload = Map<String, dynamic>.from(payload);
              return 'photo-row-1';
            },
            photoIdGenerator: () => 'photo-uuid-1',
          ),
        );

        expect(
          uploadedPath,
          'user-123/remote-1/photo-uuid-1_photo_a.jpg',
        );
        expect(uploadedBytes, Uint8List.fromList([1, 2, 3, 4]));
        expect(
          insertedPayload,
          <String, dynamic>{
            'activity_id': 'remote-1',
            'user_id': 'user-123',
            'storage_path': 'user-123/remote-1/photo-uuid-1_photo_a.jpg',
            'thumbnail_path': null,
            'sort_order': 7,
          },
        );
        expect(
          seededPhoto.storagePath,
          'user-123/remote-1/photo-uuid-1_photo_a.jpg',
        );
        expect(seededPhoto.photoId, 'photo-row-1');
        expect(seededPhoto.sortOrder, 7);
        expect(operationLog, ['upload', 'insert']);
      },
    );

    test('seedRemoteActivityPhoto requires an authenticated user id', () async {
      await expectLater(
        seedRemoteActivityPhoto(
          activityId: 'remote-1',
          photoBytes: Uint8List.fromList([9]),
          dependencies: SeededRemoteActivityPhotoDependencies(
            currentUserId: null,
            uploadStorageObject:
                ({required String path, required Uint8List bytes}) async {},
            insertPhotoMetadata: (payload) async => 'photo-row-1',
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Cannot seed remote activity photo without an authenticated Supabase user.',
          ),
        ),
      );
    });

    test(
      'cleanupSeededPhotoArtifacts deletes rows after storage objects',
      () async {
        final operationLog = <String>[];
        final deletedRowActivityIds = <String>[];
        final removedStoragePaths = <List<String>>[];

        final dependencies = SeededPhotoCleanupDependencies(
          currentUserId: 'user-123',
          loadPhotoRowsForActivity:
              ({required String activityId, required String userId}) async {
                expect(userId, 'user-123');
                operationLog.add('load:$activityId');
                switch (activityId) {
                  case 'remote-1':
                    return <Map<String, dynamic>>[
                      {
                        'storage_path': 'user-123/remote-1/photo-a.jpg',
                        'thumbnail_path': 'user-123/remote-1/photo-a_thumb.jpg',
                      },
                    ];
                  case 'remote-2':
                    return <Map<String, dynamic>>[
                      {
                        'storage_path': 'user-123/remote-2/photo-b.jpg',
                        'thumbnail_path': null,
                      },
                    ];
                  default:
                    return const <Map<String, dynamic>>[];
                }
              },
          deletePhotoRowsForActivity:
              ({required String activityId, required String userId}) async {
                expect(userId, 'user-123');
                operationLog.add('deleteRows:$activityId');
                deletedRowActivityIds.add(activityId);
              },
          deleteStorageObjects: (paths) async {
            operationLog.add('deleteStorage');
            removedStoragePaths.add(paths);
          },
        );

        await cleanupSeededPhotoArtifacts(
          remoteActivityIds: const ['remote-1', 'remote-2'],
          dependencies: dependencies,
        );

        expect(deletedRowActivityIds, ['remote-1', 'remote-2']);
        expect(removedStoragePaths, hasLength(1));
        expect(
          removedStoragePaths.single,
          unorderedEquals([
            'user-123/remote-1/photo-a.jpg',
            'user-123/remote-1/photo-a_thumb.jpg',
            'user-123/remote-2/photo-b.jpg',
          ]),
        );
        expect(operationLog, [
          'load:remote-1',
          'load:remote-2',
          'deleteStorage',
          'deleteRows:remote-1',
          'deleteRows:remote-2',
        ]);
      },
    );

    test(
      'cleanupSeededPhotoArtifacts preserves rows when storage removal fails',
      () async {
        final deletedRowActivityIds = <String>[];

        Future<void> failingDeleteStorageObjects(List<String> paths) async {
          throw StateError('storage delete failed');
        }

        final dependencies = SeededPhotoCleanupDependencies(
          currentUserId: 'user-123',
          loadPhotoRowsForActivity:
              ({required String activityId, required String userId}) async {
                return <Map<String, dynamic>>[
                  {
                    'storage_path': 'user-123/$activityId/photo-a.jpg',
                    'thumbnail_path': null,
                  },
                ];
              },
          deletePhotoRowsForActivity:
              ({required String activityId, required String userId}) async {
                deletedRowActivityIds.add(activityId);
              },
          deleteStorageObjects: failingDeleteStorageObjects,
        );

        await expectLater(
          cleanupSeededPhotoArtifacts(
            remoteActivityIds: const ['remote-1'],
            dependencies: dependencies,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'storage delete failed',
            ),
          ),
        );

        expect(deletedRowActivityIds, isEmpty);
      },
    );
  });

  group('social scenario photo fixture seam', () {
    test(
      'seedSocialScenarioFeedPhoto seeds one previewable photo for the feed activity id',
      () async {
        final operationLog = <String>[];

        final seededPhoto = await seedSocialScenarioFeedPhoto(
          feedActivityId: 'activity-42',
          shouldSeedPhoto: true,
          seedRemotePhoto: ({required String activityId}) async {
            operationLog.add('seed:$activityId');
            return SeededRemoteActivityPhoto(
              photoId: 'photo-row-42',
              storagePath: 'user-123/activity-42/photo.jpg',
              sortOrder: 0,
            );
          },
        );

        expect(seededPhoto?.photoId, 'photo-row-42');
        expect(seededPhoto?.storagePath, 'user-123/activity-42/photo.jpg');
        expect(seededPhoto?.sortOrder, 0);
        expect(operationLog, ['seed:activity-42']);
      },
    );

    test(
      'cleanupSocialScenario deletes seeded photo artifacts before account rows',
      () async {
        final operationLog = <String>[];
        final scenario = SeededSocialScenario(
          viewer: const SocialTestAccount(
            email: 'viewer@example.com',
            password: 'Viewer!123',
            displayName: 'Viewer',
          ),
          feedOwner: const SocialTestAccount(
            email: 'owner@example.com',
            password: 'Owner!123',
            displayName: 'Owner',
          ),
          searchTarget: const SocialTestAccount(
            email: 'target@example.com',
            password: 'Target!123',
            displayName: 'Target',
          ),
          incomingRequester: const SocialTestAccount(
            email: 'requester@example.com',
            password: 'Requester!123',
            displayName: 'Requester',
          ),
          viewerUserId: 'viewer-id',
          feedOwnerUserId: 'owner-id',
          searchTargetUserId: 'target-id',
          incomingRequesterUserId: 'requester-id',
          feedActivityId: 'activity-42',
          feedActivityTitle: 'Feed title',
          feedActivityPhoto: const SeededRemoteActivityPhoto(
            photoId: 'photo-row-42',
            storagePath: 'user-123/activity-42/photo.jpg',
            sortOrder: 0,
          ),
          searchTargetSearchToken: 'target-token',
        );

        await cleanupSocialScenario(
          scenario,
          cleanupPhotoArtifacts:
              ({required Iterable<String> remoteActivityIds}) async {
                operationLog.add('cleanupPhotos');
                expect(remoteActivityIds.toList(), ['activity-42']);
              },
          cleanupAccounts: (accounts) async {
            operationLog.add('cleanupAccounts');
            expect(accounts.length, 4);
          },
        );

        expect(operationLog, ['cleanupPhotos', 'cleanupAccounts']);
      },
    );
  });
}

class _DelayedVisibilityHarness extends StatefulWidget {
  const _DelayedVisibilityHarness({
    required this.delay,
    required this.child,
  });

  final Duration delay;
  final Widget child;

  @override
  State<_DelayedVisibilityHarness> createState() =>
      _DelayedVisibilityHarnessState();
}

class _DelayedVisibilityHarnessState extends State<_DelayedVisibilityHarness> {
  bool _showChild = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (!mounted) {
        return;
      }

      setState(() {
        _showChild = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _showChild ? widget.child : const SizedBox.shrink(),
      ),
    );
  }
}

class _RecordingSeedTrackingRepository implements TrackingRepository {
  _RecordingSeedTrackingRepository({List<String>? operationLog})
    : _operationLog = operationLog;

  final List<String>? _operationLog;
  final Map<int, TrackingSessionRecord> sessionsById =
      <int, TrackingSessionRecord>{};
  int _nextId = 1;
  int? lastUpdatedSessionId;
  String? lastUpdatedRemoteId;

  @override
  Future<int> saveImportedSession(
    TrackingSessionRecord session,
    List<TrackingPoint> points,
  ) async {
    _operationLog?.add('saveImportedSession');
    final assignedId = _nextId;
    _nextId += 1;
    sessionsById[assignedId] = TrackingSessionRecord(
      id: assignedId,
      status: session.status,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      startedAt: session.startedAt,
      stoppedAt: session.stoppedAt,
      title: session.title,
      description: session.description,
      distanceMeters: session.distanceMeters,
      movingTimeSeconds: session.movingTimeSeconds,
      elevationGainMeters: session.elevationGainMeters,
      remoteId: session.remoteId,
      sportType: session.sportType,
      visibility: session.visibility,
    );
    return assignedId;
  }

  @override
  Future<void> updateSessionRemoteId(int sessionId, String remoteId) async {
    _operationLog?.add('updateSessionRemoteId');
    lastUpdatedSessionId = sessionId;
    lastUpdatedRemoteId = remoteId;
    final existing = sessionsById[sessionId];
    if (existing == null) {
      return;
    }
    sessionsById[sessionId] = existing.copyWith(remoteId: remoteId);
  }

  @override
  FutureOr<TrackingSessionRecord?> loadSession(int sessionId) {
    _operationLog?.add('loadSession');
    return sessionsById[sessionId];
  }

  @override
  FutureOr<TrackingSessionRecord?> loadActiveSession() {
    throw UnimplementedError();
  }

  @override
  FutureOr<TrackingSessionRecord> createSession() {
    throw UnimplementedError();
  }

  @override
  Future<void> appendPointBatch(List<TrackingPoint> points) {
    throw UnimplementedError();
  }

  @override
  Future<List<TrackingSessionRecord>> loadSavedSessions() {
    return Future.value(
      sessionsById.values
          .where((session) => session.status == TrackingSessionStatus.saved)
          .toList(growable: false),
    );
  }

  @override
  Future<List<TrackingPoint>> loadPointsForSession(int sessionId) {
    return Future.value(const <TrackingPoint>[]);
  }

  @override
  Future<void> saveSession(TrackingSessionRecord session) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateSessionStatus(
    int sessionId,
    TrackingSessionStatus status,
    DateTime at,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> finalizeSession(int sessionId) {
    throw UnimplementedError();
  }

  @override
  Future<void> discardSession(int sessionId) {
    throw UnimplementedError();
  }

  @override
  Future<void> upsertSyncQueueEntry({
    required int sessionId,
    required SyncQueueEntryStatus status,
    required DateTime queuedAt,
    int retryCount = 0,
    String? lastError,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<SyncQueueEntry>> loadPendingSyncQueueEntries() {
    throw UnimplementedError();
  }

  @override
  Future<SyncQueueEntry?> loadSyncQueueEntry(int sessionId) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteActivity(int sessionId) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateSyncQueueEntryStatus({
    required int sessionId,
    required SyncQueueEntryStatus status,
    int? retryCount,
    String? lastError,
  }) {
    throw UnimplementedError();
  }
}

class _StubProfileNotifier extends ProfileNotifier {
  @override
  FutureOr<Profile?> build() => const Profile(
    userId: 'stub-user',
    preferredUnits: 'imperial',
    defaultActivityVisibility: 'public',
    onboardingCompleted: true,
  );
}

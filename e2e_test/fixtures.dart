// This file is test infrastructure in e2e_test/ (not test/) so the analyzer
// does not recognize it as a test file for @visibleForTesting purposes.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:math' as math;
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fit_tool/fit_tool.dart' hide FileType;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:patrol/patrol.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/app.dart';
import 'package:uff/src/core/presentation/copyable_error_text.dart';
import 'package:uff/src/features/auth/presentation/login_screen.dart';
import 'package:uff/src/features/auth/presentation/signup_screen.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_smoke_overrides.dart';
import 'package:uff/src/features/activity_tracking/data/permission_service.dart';
import 'package:uff/src/features/activity_tracking/data/replay_tracking_engine.dart';
import 'package:uff/src/utils/uuid.dart'
    show generateUuidV4; // 2026-03-18 merge: moved out of sync_service.dart
import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_analytics_section.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';
import 'package:uff/src/features/activity_tracking/presentation/recording_screen.dart';
import 'package:uff/src/features/analytics/presentation/training_load_card.dart';
import 'package:uff/src/features/import/presentation/import_screen.dart';
import 'package:uff/src/features/maps/data/mapbox_token_initializer.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart';
import 'package:uff/src/features/photos/data/photo_picker_service.dart';
import 'package:uff/src/features/profile/presentation/profile_screen.dart';
import 'package:uff/src/features/settings/presentation/settings_screen.dart';
import 'package:uff/src/features/social/presentation/relationship_search_screen.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';
import 'package:uff/src/routing/app_router.dart';
import 'package:uff/src/utils/app_environment.dart';
import 'package:uff/src/utils/local_test_service_defaults.dart';

import 'auth_setup.dart';
import '../test/src/features/import/data/fit_test_helpers.dart';
import '../test/src/test_helpers/fixture_point_parser.dart';
part 'fixtures_activity_readers.dart';
part 'fixtures_import_support.dart';
part 'fixtures_photo_support.dart';
part 'fixtures_social_support.dart';

// ---------------------------------------------------------------------------
// Fixture data loader
// ---------------------------------------------------------------------------

Future<AssetManifest>? _assetManifestFuture;

/// Loads GPS fixture points from a bundled asset (with file fallback).
///
/// This is the single loader for all fixture data — both the replay engine
/// and data seeding use it. The [sessionId] overrides the placeholder value
/// in the JSON so points are associated with the correct test session.
Future<List<TrackingPoint>> loadFixturePoints(
  String path, {
  required int sessionId,
}) async {
  // 2026-03-18 merge: async loading from onboarding + path sandboxing from camera.
  final resolvedPath = _resolveFixtureFilePath(path);
  final raw = await _loadFixtureJson(
    assetPath: path,
    fileFallbackPath: resolvedPath,
  );
  return parseFixturePointsFromJson(raw, sessionId: sessionId);
}

Future<String> _loadFixtureJson({
  required String assetPath,
  required String fileFallbackPath,
}) async {
  if (await _fixtureAssetExists(assetPath)) {
    return rootBundle.loadString(assetPath);
  }

  return File(fileFallbackPath).readAsString();
}

Future<bool> _fixtureAssetExists(String path) async {
  final assetManifest = await (_assetManifestFuture ??=
      AssetManifest.loadFromAssetBundle(rootBundle));
  return assetManifest.listAssets().contains(path);
}

/// Loads fixture bytes from the asset bundle when available, falling back to
/// a direct file read for host-only test runs.
Future<Uint8List> _loadFixtureBytes({
  required String assetPath,
  required String fileFallbackPath,
}) async {
  if (await _fixtureAssetExists(assetPath)) {
    final byteData = await rootBundle.load(assetPath);
    return byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
  }

  return File(fileFallbackPath).readAsBytes();
}

// ---------------------------------------------------------------------------
// FakePermissionService — always grants permissions
// ---------------------------------------------------------------------------

/// A [TrackingPermissionService] that always returns granted immediately,
/// bypassing OS permission dialogs in E2E tests.
class FakePermissionService extends TrackingPermissionService {
  @override
  Future<TrackingPermissionDecision> ensureForegroundPermission() async {
    return TrackingPermissionDecision.granted;
  }

  @override
  Future<TrackingPermissionDecision> ensureBackgroundPermission() async {
    return TrackingPermissionDecision.granted;
  }
}

// ---------------------------------------------------------------------------
// App bootstrap
// ---------------------------------------------------------------------------

bool _supabaseInitialized = false;
const _supabaseUrlDefine = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKeyDefine = String.fromEnvironment('SUPABASE_ANON_KEY');
const _supabaseLocalUrlDefine = String.fromEnvironment('SUPABASE_LOCAL_URL');
const _supabaseLocalAnonKeyDefine = String.fromEnvironment(
  'SUPABASE_LOCAL_ANON_KEY',
);
const _mapboxAccessTokenDefine = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
const _fixtureTestDataDirectory = 'e2e_test/test_data';
final _pathSeparatorPattern = RegExp(r'[\\/]');

Future<void> initializeTestServices() async {
  if (_supabaseInitialized) {
    return;
  }

  await dotenv.load(fileName: resolveRuntimeEnvironmentAsset());
  final resolvedSupabaseUrl =
      _firstNonBlank(
        _supabaseUrlDefine,
        dotenv.env['SUPABASE_URL'],
        _supabaseLocalUrlDefine,
        dotenv.env['SUPABASE_LOCAL_URL'],
      ) ??
      _localSupabaseUrlFallback();
  final resolvedSupabaseAnonKey =
      _firstNonBlank(
        _supabaseAnonKeyDefine,
        dotenv.env['SUPABASE_ANON_KEY'],
        _supabaseLocalAnonKeyDefine,
        dotenv.env['SUPABASE_LOCAL_ANON_KEY'],
      ) ??
      LocalTestServiceDefaults.supabaseAnonKey;
  final resolvedMapboxAccessToken =
      _firstNonBlank(
        _mapboxAccessTokenDefine,
        dotenv.env[MapboxTokenInitializer.mapboxAccessTokenKey],
      ) ??
      LocalTestServiceDefaults.mapboxAccessToken;

  await Supabase.initialize(
    url: resolvedSupabaseUrl,
    anonKey: resolvedSupabaseAnonKey,
  );
  const MapboxTokenInitializer().initialize(
    environment: {
      ...dotenv.env,
      'SUPABASE_URL': resolvedSupabaseUrl,
      'SUPABASE_ANON_KEY': resolvedSupabaseAnonKey,
      MapboxTokenInitializer.mapboxAccessTokenKey: resolvedMapboxAccessToken,
    },
    applyAccessToken: MapboxOptions.setAccessToken,
  );
  _supabaseInitialized = true;
}

String _localSupabaseUrlFallback() {
  const defaultUrl = LocalTestServiceDefaults.supabaseUrl;
  if (!Platform.isAndroid) {
    return defaultUrl;
  }

  final uri = Uri.parse(defaultUrl);
  if (uri.host != '127.0.0.1' && uri.host != 'localhost') {
    return defaultUrl;
  }

  // Android emulators reach host services via 10.0.2.2 rather than loopback.
  return uri.replace(host: '10.0.2.2').toString();
}

String? _firstNonBlank(
  String? first,
  String? second, [
  String? third,
  String? fourth,
]) {
  for (final candidate in [first, second, third, fourth]) {
    final normalized = candidate?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }
  }
  return null;
}

String _resolveFixtureFilePath(String path) {
  final allowedDirectoryPath = _canonicalizeExistingEntityPath(
    Directory(
      _fixtureTestDataDirectory,
    ),
  );
  final resolvedPath = _canonicalizeCandidateFilePath(File(path));
  final normalizedAllowedDirectoryPath =
      allowedDirectoryPath.endsWith(Platform.pathSeparator)
      ? allowedDirectoryPath
      : '$allowedDirectoryPath${Platform.pathSeparator}';

  if (resolvedPath != allowedDirectoryPath &&
      !resolvedPath.startsWith(normalizedAllowedDirectoryPath)) {
    throw ArgumentError.value(
      path,
      'path',
      'must stay within $_fixtureTestDataDirectory',
    );
  }

  return resolvedPath;
}

String _canonicalizeCandidateFilePath(File file) {
  try {
    return _normalizePath(file.resolveSymbolicLinksSync());
  } on FileSystemException {
    final canonicalParentPath = _canonicalizeExistingEntityPath(file.parent);
    return _joinPath(canonicalParentPath, _fileNameFromPath(file.path));
  }
}

String _canonicalizeExistingEntityPath(FileSystemEntity entity) {
  try {
    return _normalizePath(entity.resolveSymbolicLinksSync());
  } on FileSystemException {
    return _normalizePath(entity.absolute.path);
  }
}

String _normalizePath(String path) {
  return Uri.file(
    path,
    windows: Platform.isWindows,
  ).normalizePath().toFilePath(windows: Platform.isWindows);
}

String _joinPath(String directoryPath, String fileName) {
  if (directoryPath.endsWith(Platform.pathSeparator)) {
    return '$directoryPath$fileName';
  }

  return '$directoryPath${Platform.pathSeparator}$fileName';
}

/// Initializes Supabase and Mapbox, then returns a [ProviderScope] wrapping
/// [UffApp] with optional tracking overrides for the replay engine and
/// fake permissions.
///
/// Set [trackingOverrides] to `false` for tests where tracking injection
/// is not needed (e.g., auth flow tests).
Future<Widget> buildTestApp({
  bool trackingOverrides = true,
  String fixturePath = 'e2e_test/test_data/5k_run.json',
  List<Object> fixtureOverrides = const <Object>[],
  Future<void> Function() initializeServices = initializeTestServices,
  Duration replayEmissionInterval = const Duration(milliseconds: 200),
}) async {
  await initializeServices();

  final overrides = await composeTestAppOverrides(
    trackingOverrides: trackingOverrides,
    fixturePath: fixturePath,
    fixtureOverrides: fixtureOverrides,
    replayEmissionInterval: replayEmissionInterval,
  );
  if (overrides.isEmpty) {
    return const ProviderScope(child: UffApp());
  }

  return ProviderScope(
    overrides: overrides.cast(),
    child: const UffApp(),
  );
}

@visibleForTesting
Future<List<Object>> composeTestAppOverrides({
  bool trackingOverrides = true,
  String fixturePath = 'e2e_test/test_data/5k_run.json',
  List<Object> fixtureOverrides = const <Object>[],
  Duration replayEmissionInterval = const Duration(milliseconds: 200),
}) async {
  // 2026-03-18 merge: made async because loadFixturePoints is async.
  final composedOverrides = <Object>[];
  if (trackingOverrides) {
    final points = await loadFixturePoints(
      fixturePath,
      sessionId: 0,
    );
    composedOverrides
      ..add(
        trackingEngineProvider.overrideWithValue(
          ReplayTrackingEngine(
            points: points,
            emissionInterval: replayEmissionInterval,
          ),
        ),
      )
      ..add(
        trackingPermissionServiceProvider.overrideWithValue(
          FakePermissionService(),
        ),
      )
      // Replay-backed E2E tests use deterministic fixture points instead of a
      // live simulator fix, so they must also bypass the initial red-GPS Start
      // gate. Without this override the tests tap a disabled Start button and
      // then hang waiting for distance that can never begin accumulating.
      ..add(
        allowRecordingStartWithoutGpsFixProvider.overrideWithValue(true),
      );
  }
  composedOverrides.addAll(fixtureOverrides);
  return composedOverrides;
}

// ---------------------------------------------------------------------------
// Data seeding — uses local Drift database, NOT Supabase
// ---------------------------------------------------------------------------

/// Gets the [ProviderContainer] from the live widget tree.
///
/// Uses `find.byType(UffApp)` which is a banned pattern in test files
/// but allowed in fixtures.dart.
ProviderContainer _containerOf(PatrolIntegrationTester $) {
  return ProviderScope.containerOf(
    $.tester.element(find.byType(UffApp)),
    listen: false,
  );
}

/// Pushes [path] through the provider-owned app router instead of reading a
/// router from an arbitrary widget context.
///
/// Patrol helpers often only have easy access to the root `UffApp` element,
/// but that root context is not guaranteed to sit below `InheritedGoRouter`.
/// Reading the router from Riverpod keeps navigation tied to the app's single
/// source of truth and avoids brittle context lookups in full-suite runs.
@visibleForTesting
void pushRouteThroughAppRouterForTesting(
  ProviderContainer container,
  String path,
) {
  // `push()` completes when the route is popped, not when it is shown. Fire
  // and forget here, then let the caller settle the widget tree explicitly.
  unawaited(container.read(appRouterProvider).push(path));
}

/// Replaces the current route through the provider-owned app router.
///
/// Use this for deep-link style helpers that should swap locations instead of
/// stacking another shell instance above the current one.
@visibleForTesting
void goRouteThroughAppRouterForTesting(
  ProviderContainer container,
  String path,
) {
  container.read(appRouterProvider).go(path);
}

ProviderContainer? _maybeContainerOf(PatrolIntegrationTester $) {
  final appFinder = find.byType(UffApp);
  if (appFinder.evaluate().isEmpty) {
    return null;
  }

  return ProviderScope.containerOf(
    $.tester.element(appFinder),
    listen: false,
  );
}

/// Seeds a single activity with track points into the local Drift database.
///
/// Returns the auto-generated session ID. The [distanceMeters] and
/// [movingTimeSeconds] are written to the session record for display in
/// the history screen.
Future<int> seedActivity(
  PatrolIntegrationTester $, {
  required double distanceMeters,
  int movingTimeSeconds = 1800,
  DateTime? startedAt,
  String? visibility,
  List<TrackingPoint> points = const [],
}) async {
  return seedActivityInContainer(
    _containerOf($),
    distanceMeters: distanceMeters,
    movingTimeSeconds: movingTimeSeconds,
    startedAt: startedAt,
    visibility: visibility,
    points: points,
  );
}

@visibleForTesting
Future<int> seedActivityInContainer(
  ProviderContainer container, {
  required double distanceMeters,
  int movingTimeSeconds = 1800,
  DateTime? startedAt,
  String? visibility,
  List<TrackingPoint> points = const [],
}) async {
  final repository = container.read(trackingRepositoryProvider);

  final now = DateTime.now().toUtc();
  final session = TrackingSessionRecord(
    id: 0, // ignored — auto-generated by saveImportedSession
    status: TrackingSessionStatus.saved,
    createdAt: now,
    updatedAt: now,
    startedAt: startedAt ?? now,
    stoppedAt: (startedAt ?? now).add(Duration(seconds: movingTimeSeconds)),
    distanceMeters: distanceMeters,
    movingTimeSeconds: movingTimeSeconds,
    visibility: visibility,
  );

  final sessionId = await repository.saveImportedSession(session, points);
  container.invalidate(savedActivitiesProvider);
  return sessionId;
}

/// Seeds a saved activity whose points follow a deterministic straight line.
Future<int> seedStraightLineActivity(
  PatrolIntegrationTester $, {
  required double distanceMeters,
  required DateTime startedAt,
  required Duration duration,
  int segmentCount = 1,
  double elevationStepMeters = 0,
  String? visibility,
}) {
  return seedActivity(
    $,
    distanceMeters: distanceMeters,
    movingTimeSeconds: duration.inSeconds,
    startedAt: startedAt,
    visibility: visibility,
    points: buildStraightLineRoute(
      distanceMeters: distanceMeters,
      startedAt: startedAt,
      duration: duration,
      segmentCount: segmentCount,
      elevationStepMeters: elevationStepMeters,
    ),
  );
}

/// Seeds [count] activities with incrementally different distances.
///
/// Returns the list of auto-generated session IDs in creation order.
Future<List<int>> seedActivities(
  PatrolIntegrationTester $, {
  required int count,
  double baseDistanceMeters = 3000,
  double distanceStepMeters = 1000,
}) async {
  final ids = <int>[];
  for (var i = 0; i < count; i++) {
    final id = await seedActivity(
      $,
      distanceMeters: baseDistanceMeters + i * distanceStepMeters,
      startedAt: DateTime.now().toUtc().subtract(Duration(hours: count - i)),
    );
    ids.add(id);
  }
  return ids;
}

/// Builds deterministic straight-line route points for seeded activities.
///
/// The generated points span [distanceMeters] over [duration] using
/// [segmentCount] equal-length segments on the equator so distance math stays
/// stable across tests.
List<TrackingPoint> buildStraightLineRoute({
  required double distanceMeters,
  required DateTime startedAt,
  required Duration duration,
  int segmentCount = 1,
  double elevationStepMeters = 0,
}) {
  if (segmentCount < 1) {
    throw ArgumentError.value(
      segmentCount,
      'segmentCount',
      'must be at least 1',
    );
  }
  if (duration <= Duration.zero) {
    throw ArgumentError.value(duration, 'duration', 'must be positive');
  }

  final speedMetersPerSecond = distanceMeters / duration.inSeconds;
  final segmentDistanceMeters = distanceMeters / segmentCount;
  const metersToLongitudeDegrees = 180 / (earthRadiusMeters * math.pi);

  return List<TrackingPoint>.generate(segmentCount + 1, (index) {
    final elapsedMilliseconds = (duration.inMilliseconds * index / segmentCount)
        .round();
    final longitude = segmentDistanceMeters * index * metersToLongitudeDegrees;

    return TrackingPoint(
      sessionId: 0,
      timestamp: startedAt.add(Duration(milliseconds: elapsedMilliseconds)),
      coordinate: GeoCoordinate(latitude: 0, longitude: longitude),
      elevation: elevationStepMeters == 0 ? null : elevationStepMeters * index,
      speed: speedMetersPerSecond,
    );
  });
}

// ---------------------------------------------------------------------------
// Teardown
// ---------------------------------------------------------------------------

/// Clears all sessions and points from the local Drift database.
///
/// Call in test tearDown blocks to prevent cross-test contamination.
Future<void> cleanupTestData(PatrolIntegrationTester $) async {
  final container = _maybeContainerOf($);
  if (container == null) {
    return;
  }

  final db = container.read(trackingDatabaseProvider);
  await db.customStatement('DELETE FROM tracking_points');
  await db.customStatement('DELETE FROM tracking_sessions');
  container.invalidate(savedActivitiesProvider);
}

/// Clears all privacy zones owned by the currently authenticated user.
Future<void> cleanupPrivacyZones() {
  return _cleanupCurrentUserRows('privacy_zones');
}

/// Clears all gear rows owned by the currently authenticated user.
Future<void> cleanupGearItems() {
  return _cleanupCurrentUserRows('gear');
}

Future<void> _cleanupCurrentUserRows(String tableName) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) {
    return;
  }

  await client.from(tableName).delete().eq('user_id', userId);
}

/// Launches the app without a persisted auth session and clears local test data.
Future<void> launchUnauthenticatedApp(PatrolIntegrationTester $) async {
  await initializeTestServices();
  await clearAuthSession();
  await $.pumpWidget(
    await buildTestApp(trackingOverrides: false),
  );
  await cleanupTestData($);
  // Hosted Patrol runs can take a few extra beats to finish redirecting from
  // splash to the signed-out auth route after signOut clears persistence.
  // Returning before the login field is actually mounted created a flaky seam
  // where the next test step sometimes raced the router.
  await waitForSignedOutAuthScreen($);
}

/// Unmounts the app so auth teardown does not fight router disposal.
Future<void> unmountTestApp(PatrolIntegrationTester $) async {
  await unmountWidgetTreeForTesting($.tester);
}

/// Unmounts the root widget tree and gives routed shell state time to dispose.
///
/// Keeping the exact teardown sequence in one helper lets the hosted Patrol
/// flows and local widget tests prove the same relaunch contract.
@visibleForTesting
Future<void> unmountWidgetTreeForTesting(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  // StatefulShellRoute disposal can lag one frame behind the root unmount
  // during same-test relaunches. Give the shell an extra frame to tear down so
  // the next app pump does not trip duplicate GlobalKey assertions.
  await tester.pump(const Duration(milliseconds: 100));
}

/// Advances the test widget-tree clock by [duration] without settling.
///
/// Test files must not call `$.tester.pump()` directly (banned by
/// `scripts/check_e2e_standards.sh`); use this fixture helper instead.
Future<void> advanceTestClock(
  PatrolIntegrationTester $,
  Duration duration,
) async {
  await $.tester.pump(duration);
}

/// Registers standard local-data and auth cleanup for auth/onboarding smokes.
void registerAuthCleanup(PatrolIntegrationTester $) {
  addTearDown(() async {
    // cleanupTestData reads the mounted ProviderScope, so keep the app tree
    // alive until local database cleanup completes.
    await cleanupTestData($);
    await unmountTestApp($);
    await clearAuthSession();
  });
}

/// Launches the app and pre-authenticates before returning to the test body.
Future<void> launchAuthenticatedApp(
  PatrolIntegrationTester $, {
  bool trackingOverrides = false,
  bool cleanupLocalData = true,
  String? email,
  String? password,
}) async {
  await initializeTestServices();
  await clearAuthSession();
  // Pre-authenticate BEFORE pumping the widget tree. When auth happens after
  // pump, the router processes rapid state transitions (splash → auth →
  // home → signout → home) that can create duplicate GlobalKey errors in
  // go_router's StatefulShellRoute. Authenticating first means the app
  // reads an existing session on startup and routes directly to /home.
  await preAuthenticate(email: email, password: password);
  await $.pumpWidget(
    await buildTestApp(trackingOverrides: trackingOverrides),
  );
  if (cleanupLocalData) {
    await cleanupTestData($);
  }
}

/// Taps a Home shell destination using the shared destination metadata keys.
Future<void> navigateToHomeShellDestination(
  PatrolIntegrationTester $,
  HomeShellDestinationId destinationId,
) async {
  final destination = homeShellDestinations.firstWhere(
    (d) => d.id == destinationId,
  );
  await $(find.byKey(destination.navigationKey)).waitUntilVisible();
  await $(find.byKey(destination.navigationKey)).tap();
}

/// Waits for the authenticated Home shell to render, navigates to the
/// Activity tab, and waits for the Activity history content to appear.
///
/// The feed is now the default `/home` body (Stage 4 refactor). This helper
/// uses the shared destination metadata from [homeShellDestinations] to tap
/// the Activity tab rather than assuming it is visible on launch.
Future<void> waitForHomeActivityHistoryLoaded(
  PatrolIntegrationTester $,
) async {
  await waitForAuthenticatedHomeShell($);
  await navigateToHomeShellDestination($, HomeShellDestinationId.activity);
  await $(find.text('Activities')).waitUntilVisible();
}

/// Waits for the authenticated home shell chrome to finish mounting.
///
/// Direct route pushes can race the auth redirect if callers navigate before
/// the home shell is visible. Using the shared settings button as the readiness
/// probe keeps route helpers on one stable contract.
Future<void> waitForAuthenticatedHomeShell(
  PatrolIntegrationTester $, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  // Measured <1s on local sim, but a 30s ceiling keeps hosted cold starts and
  // slower CI/device runs from tripping false negatives during auth bootstrap.
  await $(
    find.byKey(HomeShellScreen.openSettingsButtonKey),
  ).waitUntilVisible(timeout: timeout);
}

/// Waits until [finder] is both present and hit-testable.
///
/// This stays in `fixtures.dart` so Patrol helpers and widget tests can share
/// the same readiness contract instead of duplicating bespoke polling loops.
@visibleForTesting
Future<void> waitForFinderToBecomeHitTestableForTesting(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  Duration pumpStep = const Duration(milliseconds: 100),
}) async {
  bool isFinderHitTestable() => finder.hitTestable().evaluate().isNotEmpty;

  if (isFinderHitTestable()) {
    return;
  }

  final deadline = tester.binding.clock.fromNowBy(timeout);
  while (tester.binding.clock.now().isBefore(deadline)) {
    await tester.pump(pumpStep);
    if (isFinderHitTestable()) {
      return;
    }
  }

  throw FlutterError(
    'Timed out waiting for $finder to become hit-testable within $timeout.',
  );
}

/// Waits for the signed-out auth screen to finish mounting.
Future<void> waitForSignedOutAuthScreen(
  PatrolIntegrationTester $, {
  Duration timeout = const Duration(seconds: 20),
}) {
  return waitForFinderToBecomeHitTestableForTesting(
    $.tester,
    find.byKey(LoginScreen.emailFieldKey),
    timeout: timeout,
  );
}

/// Navigates back from activity detail to the home history list and lets the
/// shell settle before the next interaction.
Future<void> returnToHomeActivityHistory(
  PatrolIntegrationTester $, {
  Finder? activityCardFinder,
}) async {
  final backButtonFinder = find.byTooltip('Back');
  await $(backButtonFinder).waitUntilVisible();
  await $(backButtonFinder).tap();
  await $.tester.pump(const Duration(milliseconds: 300));
  await waitForHomeActivityHistoryLoaded($);
  if (activityCardFinder != null) {
    await $(activityCardFinder).waitUntilVisible();
  }
}

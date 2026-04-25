import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/utils/local_test_service_defaults.dart';

const _supabaseUrlDefine = String.fromEnvironment('SUPABASE_URL');
const _supabaseLocalUrlDefine = String.fromEnvironment('SUPABASE_LOCAL_URL');
const _supabaseAnonKeyDefine = String.fromEnvironment('SUPABASE_ANON_KEY');
const _supabaseLocalAnonKeyDefine = String.fromEnvironment(
  'SUPABASE_LOCAL_ANON_KEY',
);
const _runSupabaseSmokeTestsEnv = 'RUN_SUPABASE_SMOKE_TESTS';
const _runSupabaseSmokeTestsDefine = String.fromEnvironment(
  _runSupabaseSmokeTestsEnv,
);

/// In-memory [GotrueAsyncStorage] for test clients that use PKCE flow.
class _InMemoryAsyncStorage extends GotrueAsyncStorage {
  final _store = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _store[key];

  @override
  Future<void> setItem({required String key, required String value}) async =>
      _store[key] = value;

  @override
  Future<void> removeItem({required String key}) async => _store.remove(key);
}

/// Reads the Supabase URL from the environment or the local test stack.
String get supabaseUrl => resolveSupabaseRuntimeSetting(
  dartDefinePrimary: _supabaseUrlDefine,
  dartDefineSecondary: _supabaseLocalUrlDefine,
  environmentPrimary: Platform.environment['SUPABASE_URL'],
  environmentSecondary: Platform.environment['SUPABASE_LOCAL_URL'],
  fallback: LocalTestServiceDefaults.supabaseUrl,
);

/// Reads the Supabase anon key from the environment or the local test stack.
String get supabaseAnonKey => resolveSupabaseRuntimeSetting(
  dartDefinePrimary: _supabaseAnonKeyDefine,
  dartDefineSecondary: _supabaseLocalAnonKeyDefine,
  environmentPrimary: Platform.environment['SUPABASE_ANON_KEY'],
  environmentSecondary: Platform.environment['SUPABASE_LOCAL_ANON_KEY'],
  fallback: LocalTestServiceDefaults.supabaseAnonKey,
);

/// Whether the helper resolved non-empty Supabase credentials.
bool get hasSupabaseCredentials =>
    supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

/// Integration smoke tests are opt-in for local/dev runs.
///
/// This keeps `flutter test test/ --coverage` fast and deterministic on
/// machines that do not have a running local Supabase stack. Device/emulator
/// runs must pass the opt-in via `--dart-define`, because `Platform.environment`
/// is not populated inside the launched app process.
String? get skipReason => resolveSupabaseSmokeSkipReason(
  runSupabaseSmokeTests: resolveSupabaseRuntimeFlag(
    dartDefineValue: _runSupabaseSmokeTestsDefine,
    environmentValue: Platform.environment[_runSupabaseSmokeTestsEnv],
  ),
);

@visibleForTesting
String? resolveSupabaseSmokeSkipReason({
  required String? runSupabaseSmokeTests,
}) {
  final normalized = runSupabaseSmokeTests?.trim().toLowerCase();
  if (normalized == 'true') {
    return null;
  }
  return 'Set RUN_SUPABASE_SMOKE_TESTS=true or pass '
      '--dart-define=RUN_SUPABASE_SMOKE_TESTS=true to run Supabase smoke '
      'tests.';
}

@visibleForTesting
String resolveSupabaseRuntimeSetting({
  required String? dartDefinePrimary,
  required String? dartDefineSecondary,
  required String? environmentPrimary,
  required String? environmentSecondary,
  required String fallback,
}) {
  return resolveSupabaseSetting(
    primary: _firstNonBlank(dartDefinePrimary, dartDefineSecondary),
    secondary: _firstNonBlank(environmentPrimary, environmentSecondary),
    fallback: fallback,
  );
}

@visibleForTesting
String? resolveSupabaseRuntimeFlag({
  required String? dartDefineValue,
  required String? environmentValue,
}) {
  return _firstNonBlank(dartDefineValue, environmentValue);
}

/// Creates a test-scoped [SupabaseClient] — not the global singleton.
///
/// Each test can create its own client for isolation. Callers must call
/// `client.dispose()` in tearDown.
SupabaseClient createTestClient() {
  return SupabaseClient(
    supabaseUrl,
    supabaseAnonKey,
    authOptions: AuthClientOptions(
      pkceAsyncStorage: _InMemoryAsyncStorage(),
    ),
  );
}

int _lastGeneratedEmailTimestamp = 0;
final _generatedSmokeTestPasswordsByEmail = <String, String>{};
const _smokeTestPasswordAlphabet =
    'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';

/// Generates a unique email for each test run to avoid collisions.
String generateTestEmail({DateTime Function()? now}) {
  final timestamp = _nextUniqueEmailTimestamp(
    (now ?? DateTime.now)().microsecondsSinceEpoch,
  );
  return 'smoke_$timestamp@test.local';
}

@visibleForTesting
void resetGeneratedTestEmailSequence() {
  _lastGeneratedEmailTimestamp = 0;
  _generatedSmokeTestPasswordsByEmail.clear();
}

/// Legacy fixed password retained for older smoke tests that still sign up
/// users directly instead of going through createSignedInTestUser().
const testPassword = 'Sm0keTe5t!Pass#2024';

/// Generates a password with policy-shaping prefixes plus random entropy.
String generateTestPassword({Random? random}) {
  final source = random ?? Random.secure();
  final buffer = StringBuffer('Smk!9a');
  for (var i = 0; i < 17; i++) {
    buffer.write(
      _smokeTestPasswordAlphabet[source.nextInt(
        _smokeTestPasswordAlphabet.length,
      )],
    );
  }
  return buffer.toString();
}

@visibleForTesting
void rememberGeneratedSmokeTestPassword({
  required String email,
  required String password,
}) {
  _generatedSmokeTestPasswordsByEmail[email] = password;
}

@visibleForTesting
String resolveSmokeTestPassword({
  required String email,
  String? passwordOverride,
}) {
  final explicitPassword = passwordOverride?.trim();
  if (explicitPassword != null && explicitPassword.isNotEmpty) {
    return explicitPassword;
  }
  final generatedPassword = _generatedSmokeTestPasswordsByEmail[email];
  if (generatedPassword != null && generatedPassword.isNotEmpty) {
    return generatedPassword;
  }
  throw StateError(
    'Expected an in-memory password for smoke-test user $email.',
  );
}

/// Authenticated test client identity used by social smoke tests.
class SmokeTestUser {
  const SmokeTestUser({
    required this.client,
    required this.userId,
    required this.email,
    required this.password,
  });

  final SupabaseClient client;
  final String userId;
  final String email;
  final String password;
}

class SmokeAuthOutcome {
  const SmokeAuthOutcome({
    required this.userId,
    required this.hasAuthenticatedSession,
  });

  final String? userId;
  final bool hasAuthenticatedSession;
}

/// Creates a unique signed-in test user and returns the attached client.
Future<SmokeTestUser> createSignedInTestUser({
  String displayName = 'Smoke User',
}) async {
  final client = createTestClient();
  final email = generateTestEmail();
  final password = generateTestPassword();
  rememberGeneratedSmokeTestPassword(email: email, password: password);
  final userId = await ensureSmokeTestUserIsSignedIn(
    signUp: () async {
      final authResponse = await client.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
      );
      return SmokeAuthOutcome(
        userId: authResponse.user?.id ?? client.auth.currentUser?.id,
        hasAuthenticatedSession: client.auth.currentSession != null,
      );
    },
    signIn: () async {
      final authResponse = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return SmokeAuthOutcome(
        userId: authResponse.user?.id ?? client.auth.currentUser?.id,
        hasAuthenticatedSession: client.auth.currentSession != null,
      );
    },
  );
  return SmokeTestUser(
    client: client,
    userId: userId,
    email: email,
    password: password,
  );
}

/// Signs in an existing smoke-test user on the given [client].
Future<String> signInSmokeTestUser({
  required SupabaseClient client,
  required String email,
  String? password,
}) async {
  final resolvedPassword = resolveSmokeTestPassword(
    email: email,
    passwordOverride: password,
  );
  final authResponse = await client.auth.signInWithPassword(
    email: email,
    password: resolvedPassword,
  );
  final signedInUserId = authResponse.user?.id ?? client.auth.currentUser?.id;
  if (client.auth.currentSession == null || signedInUserId == null) {
    throw StateError(
      'Expected password sign-in to authenticate smoke-test user $email.',
    );
  }
  return signedInUserId;
}

@visibleForTesting
Future<String> ensureSmokeTestUserIsSignedIn({
  required Future<SmokeAuthOutcome> Function() signUp,
  required Future<SmokeAuthOutcome> Function() signIn,
}) async {
  final signUpOutcome = await signUp();
  final signedInUserId = signUpOutcome.userId;
  if (signUpOutcome.hasAuthenticatedSession && signedInUserId != null) {
    return signedInUserId;
  }

  final createdUserId = signUpOutcome.userId;
  if (createdUserId == null) {
    throw StateError('Expected signUp to create a smoke-test user.');
  }

  final signInOutcome = await signIn();
  final authenticatedUserId = signInOutcome.userId;
  if (!signInOutcome.hasAuthenticatedSession || authenticatedUserId == null) {
    throw StateError(
      'Smoke tests require an authenticated session after sign-up. '
      'Verify password sign-in is allowed for generated test users.',
    );
  }
  if (authenticatedUserId != createdUserId) {
    throw StateError(
      'Smoke tests expected sign-in to authenticate the created user. '
      'Expected $createdUserId but got $authenticatedUserId.',
    );
  }
  return authenticatedUserId;
}

/// Seeds an activity row for the authenticated user and returns its UUID.
Future<String> seedActivityForCurrentUser(
  SupabaseClient client, {
  required String visibility,
  DateTime? startedAt,
  DateTime? finishedAt,
  double distanceMeters = 5000,
  int durationSeconds = 1800,
  String sportType = 'run',
  String? title,
}) async {
  final userId = _requireAuthenticatedUserId(
    client,
    'Expected an authenticated user when seeding activity.',
  );
  final started = startedAt ?? DateTime.now().toUtc();
  final finished =
      finishedAt ?? started.add(Duration(seconds: durationSeconds));
  final inserted = await client
      .from('activities')
      .insert({
        'user_id': userId,
        'sport_type': sportType,
        'started_at': started.toIso8601String(),
        'finished_at': finished.toIso8601String(),
        'distance_meters': distanceMeters,
        'duration_seconds': durationSeconds,
        'visibility': visibility,
        'title': title,
      })
      .select('id')
      .single();
  return inserted['id'] as String;
}

/// Seeds basic track points for an activity owned by the authenticated user.
Future<void> seedTrackPointsForActivity(
  SupabaseClient client, {
  required String activityId,
  DateTime? startedAt,
}) async {
  final started = startedAt ?? DateTime.now().toUtc();
  await client.from('track_points').insert([
    {
      'activity_id': activityId,
      'timestamp': started.toIso8601String(),
      'latitude': 40.7128,
      'longitude': -74.0060,
      'distance': 0,
      'speed': 2.6,
    },
    {
      'activity_id': activityId,
      'timestamp': started.add(const Duration(minutes: 5)).toIso8601String(),
      'latitude': 40.7228,
      'longitude': -74.0160,
      'distance': 1000,
      'speed': 3.1,
    },
  ]);
}

/// Creates a pending follow edge requester -> target and returns follow UUID.
Future<String> sendFollowRequest(
  SupabaseClient requesterClient, {
  required String targetUserId,
}) async {
  final requesterId = _requireAuthenticatedUserId(
    requesterClient,
    'Expected authenticated requester when seeding follow request.',
  );
  final inserted = await requesterClient
      .from('follows')
      .insert({
        'follower_id': requesterId,
        'following_id': targetUserId,
        'status': 'pending',
      })
      .select('id')
      .single();
  return inserted['id'] as String;
}

/// Accepts a pending follow edge by follow id as the followed user.
Future<void> acceptFollowRequest(
  SupabaseClient targetClient, {
  required String followId,
}) async {
  await targetClient
      .from('follows')
      .update({'status': 'accepted'})
      .eq(
        'id',
        followId,
      );
}

/// Rejects a pending follow edge by follow id as the followed user.
Future<void> rejectFollowRequest(
  SupabaseClient targetClient, {
  required String followId,
}) async {
  await targetClient.from('follows').delete().eq('id', followId);
}

/// Creates an accepted follow edge requester -> target and returns follow UUID.
Future<String> seedAcceptedFollow({
  required SupabaseClient requesterClient,
  required SupabaseClient targetClient,
}) async {
  final targetUserId = _requireAuthenticatedUserId(
    targetClient,
    'Expected authenticated target when seeding follow.',
  );
  final followId = await sendFollowRequest(
    requesterClient,
    targetUserId: targetUserId,
  );
  await acceptFollowRequest(targetClient, followId: followId);
  return followId;
}

/// Seeds a consent row for the authenticated user.
Future<void> seedConsentForCurrentUser(
  SupabaseClient client, {
  required String termsVersion,
  DateTime? termsAcceptedAt,
}) async {
  final userId = _requireAuthenticatedUserId(
    client,
    'Expected an authenticated user when seeding consent.',
  );
  final acceptedAt = termsAcceptedAt ?? DateTime.now().toUtc();
  await client.from('profile_consent').upsert({
    'user_id': userId,
    'terms_accepted_at': acceptedAt.toIso8601String(),
    'terms_version': termsVersion,
  });
}

/// Seeds a gear row for the authenticated user and returns its UUID.
Future<String> seedGearForCurrentUser(
  SupabaseClient client, {
  required String name,
  String gearType = 'shoe',
  String? brand,
  String? model,
}) async {
  final userId = _requireAuthenticatedUserId(
    client,
    'Expected an authenticated user when seeding gear.',
  );
  final inserted = await client
      .from('gear')
      .insert({
        'user_id': userId,
        'name': name,
        'gear_type': gearType,
        'brand': brand,
        'model': model,
      })
      .select('id')
      .single();
  return inserted['id'] as String;
}

/// Seeds splits for an activity owned by the authenticated user.
Future<void> seedSplitsForActivity(
  SupabaseClient client, {
  required String activityId,
  int splitCount = 2,
  double splitDistanceMeters = 1000,
  int splitDurationSeconds = 300,
}) async {
  final rows = <Map<String, dynamic>>[];
  for (var i = 1; i <= splitCount; i++) {
    rows.add({
      'activity_id': activityId,
      'split_number': i,
      'distance_meters': splitDistanceMeters,
      'duration_seconds': splitDurationSeconds,
      'avg_pace_seconds_per_km':
          (splitDurationSeconds / splitDistanceMeters * 1000).round(),
    });
  }
  await client.from('splits').insert(rows);
}

/// Seeds a privacy zone for the authenticated user and returns its UUID.
Future<String> seedPrivacyZoneForCurrentUser(
  SupabaseClient client, {
  required String label,
  double latitude = 40.7128,
  double longitude = -74.0060,
  int radiusMeters = 200,
}) async {
  final userId = _requireAuthenticatedUserId(
    client,
    'Expected an authenticated user when seeding privacy zone.',
  );
  final inserted = await client
      .from('privacy_zones')
      .insert({
        'user_id': userId,
        'label': label,
        'latitude': latitude,
        'longitude': longitude,
        'radius_meters': radiusMeters,
      })
      .select('id')
      .single();
  return inserted['id'] as String;
}

/// Seeds a storage object in the given bucket for the authenticated user.
///
/// Uploads a tiny placeholder file so `storage.objects` has a row that
/// `export_my_data()` can return.
Future<void> seedStorageObjectForCurrentUser(
  SupabaseClient client, {
  required String bucket,
  required String fileName,
}) async {
  final userId = _requireAuthenticatedUserId(
    client,
    'Expected an authenticated user when seeding storage object.',
  );
  final path = '$userId/$fileName';
  await client.storage
      .from(bucket)
      .uploadBinary(
        path,
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]), // PNG magic bytes
        fileOptions: const FileOptions(upsert: true),
      );
}

/// Builds the storage object path format required by activity photo policies.
String buildActivityPhotoStorageObjectPath({
  required String userId,
  required String activityId,
  required String fileName,
}) {
  return '$userId/$activityId/$fileName';
}

@visibleForTesting
List<String> buildUserScopedStorageObjectPaths({
  required String userId,
  required Iterable<FileObject> listedObjects,
}) {
  return listedObjects
      .map((file) => '$userId/${file.name}')
      .toList(growable: false);
}

@visibleForTesting
List<String> buildActivityPhotoStorageCleanupPaths({
  required String userId,
  required String activityId,
  required Iterable<FileObject> listedObjects,
}) {
  return listedObjects
      .map(
        (file) => buildActivityPhotoStorageObjectPath(
          userId: userId,
          activityId: activityId,
          fileName: file.name,
        ),
      )
      .toList(growable: false);
}

/// Best-effort cleanup for social rows owned by the current authenticated user.
Future<void> cleanupSocialRowsForCurrentUser(SupabaseClient client) async {
  final userId = client.auth.currentUser?.id;
  if (userId == null) {
    return;
  }
  final ownedActivityIds = await _loadOwnedActivityIdsForCleanup(
    client,
    userId: userId,
  );

  await _runBestEffort(() async {
    await client.from('kudos').delete().eq('user_id', userId);
  });
  await _runBestEffort(() async {
    await client
        .from('follows')
        .delete()
        .or('follower_id.eq.$userId,following_id.eq.$userId');
  });
  await _runBestEffort(() async {
    await client.from('activities').delete().eq('user_id', userId);
  });
  await _runBestEffort(() async {
    await client.from('gear').delete().eq('user_id', userId);
  });
  await _runBestEffort(() async {
    await client.from('privacy_zones').delete().eq('user_id', userId);
  });
  await _runBestEffort(() async {
    await client.from('profile_consent').delete().eq('user_id', userId);
  });
  await _runBestEffort(() async {
    await _cleanupOwnedStorageObjects(
      client,
      userId: userId,
      ownedActivityIds: ownedActivityIds,
    );
  });
}

Future<List<String>> _loadOwnedActivityIdsForCleanup(
  SupabaseClient client, {
  required String userId,
}) async {
  try {
    final rows =
        await client.from('activities').select('id').eq('user_id', userId)
            as List<dynamic>;
    return rows
        .map((row) => (row as Map<String, dynamic>)['id'] as String)
        .toList(growable: false);
  } on Object {
    return const [];
  }
}

Future<void> _cleanupOwnedStorageObjects(
  SupabaseClient client, {
  required String userId,
  required List<String> ownedActivityIds,
}) async {
  final avatars = await client.storage.from('avatars').list(path: userId);
  final avatarPaths = buildUserScopedStorageObjectPaths(
    userId: userId,
    listedObjects: avatars,
  );
  if (avatarPaths.isNotEmpty) {
    await client.storage.from('avatars').remove(avatarPaths);
  }

  final activityPhotoEntries = await client.storage
      .from('activity-photos')
      .list(path: userId);
  final ownedActivityIdSet = ownedActivityIds.toSet();
  final legacyActivityPhotoPaths = buildUserScopedStorageObjectPaths(
    userId: userId,
    listedObjects: activityPhotoEntries.where(
      (entry) => !ownedActivityIdSet.contains(entry.name),
    ),
  );
  if (legacyActivityPhotoPaths.isNotEmpty) {
    await client.storage
        .from('activity-photos')
        .remove(legacyActivityPhotoPaths);
  }

  for (final activityId in ownedActivityIds) {
    final files = await client.storage
        .from('activity-photos')
        .list(path: '$userId/$activityId');
    final activityPhotoPaths = buildActivityPhotoStorageCleanupPaths(
      userId: userId,
      activityId: activityId,
      listedObjects: files,
    );
    if (activityPhotoPaths.isNotEmpty) {
      await client.storage.from('activity-photos').remove(activityPhotoPaths);
    }
  }
}

/// Best-effort sign-out and dispose of a test [SupabaseClient].
Future<void> cleanupSupabaseClient(SupabaseClient client) async {
  await _runBestEffort(() async {
    await client.auth.signOut();
  });
  await _runBestEffort(() async {
    await client.dispose();
  });
}

/// Best-effort cleanup + sign-out/dispose for all given test users.
Future<void> cleanupSmokeTestUsers(Iterable<SmokeTestUser> users) async {
  for (final user in users) {
    _generatedSmokeTestPasswordsByEmail.remove(user.email);
    await cleanupSocialRowsForCurrentUser(user.client);
    await cleanupSupabaseClient(user.client);
  }
}

String resolveSupabaseSetting({
  required String? primary,
  required String? secondary,
  required String fallback,
}) {
  return _firstNonBlank(primary, secondary) ?? fallback;
}

String? _firstNonBlank(String? first, String? second) {
  for (final candidate in [first, second]) {
    final normalized = candidate?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }
  }
  return null;
}

String _requireAuthenticatedUserId(
  SupabaseClient client,
  String errorMessage,
) {
  final userId = client.auth.currentUser?.id;
  if (userId != null) {
    return userId;
  }
  throw StateError(errorMessage);
}

Future<void> _runBestEffort(Future<void> Function() action) async {
  try {
    await action();
  } on Object catch (_) {
    // Best-effort cleanup.
  }
}

int _nextUniqueEmailTimestamp(int timestamp) {
  if (timestamp > _lastGeneratedEmailTimestamp) {
    _lastGeneratedEmailTimestamp = timestamp;
  } else {
    _lastGeneratedEmailTimestamp += 1;
  }
  return _lastGeneratedEmailTimestamp;
}

part of 'fixtures.dart';

// ---------------------------------------------------------------------------
// Social test infrastructure
// ---------------------------------------------------------------------------

/// Test account credentials used for seeded social scenarios.
class SocialTestAccount {
  const SocialTestAccount({
    required this.email,
    required this.password,
    required this.displayName,
  });

  final String email;
  final String password;
  final String displayName;
}

typedef SeedSocialScenarioRemotePhoto =
    Future<SeededRemoteActivityPhoto> Function({required String activityId});
typedef CleanupSocialScenarioPhotoArtifacts =
    Future<void> Function({required Iterable<String> remoteActivityIds});
typedef CleanupSocialScenarioAccounts =
    Future<void> Function(List<SocialTestAccount> accounts);

/// Multi-user social seed data used by Stage 7 Patrol tests.
class SeededSocialScenario {
  const SeededSocialScenario({
    required this.viewer,
    required this.feedOwner,
    required this.searchTarget,
    required this.incomingRequester,
    required this.viewerUserId,
    required this.feedOwnerUserId,
    required this.searchTargetUserId,
    required this.incomingRequesterUserId,
    required this.feedActivityId,
    required this.feedActivityTitle,
    required this.feedActivityPhoto,
    required this.searchTargetSearchToken,
  });

  final SocialTestAccount viewer;
  final SocialTestAccount feedOwner;
  final SocialTestAccount searchTarget;
  final SocialTestAccount incomingRequester;
  final String viewerUserId;
  final String feedOwnerUserId;
  final String searchTargetUserId;
  final String incomingRequesterUserId;
  final String feedActivityId;
  final String feedActivityTitle;
  final SeededRemoteActivityPhoto? feedActivityPhoto;
  final String searchTargetSearchToken;
}

/// Seeds a reusable social graph and leaves the app authenticated as viewer.
Future<SeededSocialScenario> seedSocialScenario({
  bool maskFeedActivityForViewer = false,
  bool seedFeedActivityPhoto = true,
  SeedSocialScenarioRemotePhoto seedRemotePhoto = _seedRemotePhotoForScenario,
}) async {
  final runTimestamp = DateTime.now().microsecondsSinceEpoch.toString();
  final runEntropySuffix = _randomSuffix(8);
  final salt = '$runTimestamp-$runEntropySuffix';
  final searchTargetSearchToken =
      '${runTimestamp.substring(runTimestamp.length - 6)}-$runEntropySuffix';
  final viewer = SocialTestAccount(
    email: 'social-viewer-$salt@example.com',
    password: 'Viewer!$salt',
    displayName: 'Feed Viewer',
  );
  final feedOwner = SocialTestAccount(
    email: 'social-owner-$salt@example.com',
    password: 'Owner!$salt',
    displayName: 'Feed Owner',
  );
  final searchTarget = SocialTestAccount(
    email: 'social-target-$salt@example.com',
    password: 'Target!$salt',
    displayName: 'Search Target $searchTargetSearchToken',
  );
  final incomingRequester = SocialTestAccount(
    email: 'social-requester-$salt@example.com',
    password: 'Requester!$salt',
    displayName: 'Pending Requester',
  );

  await ensureTestUser(email: feedOwner.email, password: feedOwner.password);
  final feedOwnerUserId = Supabase.instance.client.auth.currentUser!.id;
  await _upsertCurrentUserProfileDisplayName(feedOwner.displayName);
  await _cleanupCurrentUserSocialRows();
  final feedActivityTitle = 'Feed Seed ${generateUuidV4().substring(0, 8)}';
  final feedActivityId = await _seedSocialActivity(
    ownerUserId: feedOwnerUserId,
    title: feedActivityTitle,
    visibility: 'public',
  );
  final feedActivityPhoto = await seedSocialScenarioFeedPhoto(
    feedActivityId: feedActivityId,
    shouldSeedPhoto: seedFeedActivityPhoto,
    seedRemotePhoto: seedRemotePhoto,
  );
  if (maskFeedActivityForViewer) {
    await Supabase.instance.client.from('privacy_zones').insert({
      'user_id': feedOwnerUserId,
      'label': 'Feed Detail Mask Zone',
      'latitude': _seedTrackPointStartLatitude,
      'longitude': _seedTrackPointStartLongitude,
      'radius_meters': _seedMaskRadiusMeters,
    });
  }

  await ensureTestUser(
    email: searchTarget.email,
    password: searchTarget.password,
  );
  final searchTargetUserId = Supabase.instance.client.auth.currentUser!.id;
  await _upsertCurrentUserProfileDisplayName(searchTarget.displayName);
  await _cleanupCurrentUserSocialRows();

  await ensureTestUser(
    email: incomingRequester.email,
    password: incomingRequester.password,
  );
  final incomingRequesterUserId = Supabase.instance.client.auth.currentUser!.id;
  await _upsertCurrentUserProfileDisplayName(incomingRequester.displayName);
  await _cleanupCurrentUserSocialRows();

  await ensureTestUser(email: viewer.email, password: viewer.password);
  final viewerUserId = Supabase.instance.client.auth.currentUser!.id;
  await _upsertCurrentUserProfileDisplayName(viewer.displayName);
  await _cleanupCurrentUserSocialRows();

  // Viewer follows feed owner so owner activity appears in feed.
  final viewerFollowId = await _insertPendingFollow(
    followerId: viewerUserId,
    followingId: feedOwnerUserId,
  );
  await preAuthenticate(email: feedOwner.email, password: feedOwner.password);
  await Supabase.instance.client
      .from('follows')
      .update({'status': 'accepted'})
      .eq('id', viewerFollowId);

  // Incoming requester sends a pending request to viewer.
  await preAuthenticate(
    email: incomingRequester.email,
    password: incomingRequester.password,
  );
  await _insertPendingFollow(
    followerId: Supabase.instance.client.auth.currentUser!.id,
    followingId: viewerUserId,
  );

  await preAuthenticate(email: viewer.email, password: viewer.password);

  return SeededSocialScenario(
    viewer: viewer,
    feedOwner: feedOwner,
    searchTarget: searchTarget,
    incomingRequester: incomingRequester,
    viewerUserId: viewerUserId,
    feedOwnerUserId: feedOwnerUserId,
    searchTargetUserId: searchTargetUserId,
    incomingRequesterUserId: incomingRequesterUserId,
    feedActivityId: feedActivityId,
    feedActivityTitle: feedActivityTitle,
    feedActivityPhoto: feedActivityPhoto,
    searchTargetSearchToken: searchTargetSearchToken,
  );
}

/// Seeds one remote-detail photo for a social feed activity when enabled.
Future<SeededRemoteActivityPhoto?> seedSocialScenarioFeedPhoto({
  required String feedActivityId,
  required bool shouldSeedPhoto,
  SeedSocialScenarioRemotePhoto seedRemotePhoto = _seedRemotePhotoForScenario,
}) async {
  if (!shouldSeedPhoto) {
    return null;
  }
  return seedRemotePhoto(activityId: feedActivityId);
}

/// Cleans social rows for all accounts created by [seedSocialScenario].
Future<void> cleanupSocialScenario(
  SeededSocialScenario scenario, {
  CleanupSocialScenarioPhotoArtifacts cleanupPhotoArtifacts =
      cleanupSeededPhotoArtifacts,
  CleanupSocialScenarioAccounts cleanupAccounts = _cleanupAccountRows,
}) async {
  if (scenario.feedActivityPhoto != null) {
    await cleanupPhotoArtifacts(remoteActivityIds: [scenario.feedActivityId]);
  }
  await cleanupAccounts([
    scenario.viewer,
    scenario.feedOwner,
    scenario.searchTarget,
    scenario.incomingRequester,
  ]);
}

Future<SeededRemoteActivityPhoto> _seedRemotePhotoForScenario({
  required String activityId,
}) {
  return seedRemoteActivityPhoto(activityId: activityId);
}

/// Signs up a new user through the email/password auth UI.
Future<void> submitEmailSignUpForm(
  PatrolIntegrationTester $, {
  required String email,
  required String displayName,
  required String password,
}) async {
  await $(find.byKey(LoginScreen.emailFieldKey)).waitUntilVisible();
  await $(find.text('Create account')).tap();

  await $(find.byKey(SignUpScreen.displayNameFieldKey)).waitUntilVisible();
  await $(find.byKey(SignUpScreen.displayNameFieldKey)).enterText(displayName);
  await $(find.byKey(SignUpScreen.emailFieldKey)).enterText(email);
  await $(find.byKey(SignUpScreen.passwordFieldKey)).enterText(password);
  await $(find.byKey(SignUpScreen.confirmPasswordFieldKey)).enterText(password);
  await $(find.byKey(SignUpScreen.signUpButtonKey)).tap();
}

/// Enters and submits a relationship search query through the keyboard action.
Future<void> submitRelationshipSearchQuery(
  PatrolIntegrationTester $,
  String query,
) async {
  final searchFieldFinder = find.byKey(RelationshipSearchScreen.searchFieldKey);
  await $(searchFieldFinder).waitUntilVisible();
  await $(searchFieldFinder).enterText(query);
  await $.tester.testTextInput.receiveAction(TextInputAction.search);
  await $.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Social — internal helpers
// ---------------------------------------------------------------------------

Future<void> _cleanupAccountRows(List<SocialTestAccount> accounts) async {
  for (final account in accounts) {
    await preAuthenticate(email: account.email, password: account.password);
    await _cleanupCurrentUserSocialRows();
  }
}

Future<String> _prepareSocialAccount(SocialTestAccount account) async {
  await ensureTestUser(email: account.email, password: account.password);
  final userId = Supabase.instance.client.auth.currentUser!.id;
  await _upsertCurrentUserProfileDisplayName(account.displayName);
  await _cleanupCurrentUserSocialRows();
  return userId;
}

({
  SocialTestAccount owner,
  SocialTestAccount follower,
  SocialTestAccount stranger,
  SocialTestAccount transitioner,
})
_buildVisibilityMatrixAccounts({
  required String salt,
  required String ownerSearchToken,
}) {
  final owner = SocialTestAccount(
    email: 'matrix-owner-$salt@example.com',
    password: 'Owner!$salt',
    displayName: 'Matrix Owner $ownerSearchToken',
  );
  final follower = SocialTestAccount(
    email: 'matrix-follower-$salt@example.com',
    password: 'Follower!$salt',
    displayName: 'Matrix Follower',
  );
  final stranger = SocialTestAccount(
    email: 'matrix-stranger-$salt@example.com',
    password: 'Stranger!$salt',
    displayName: 'Matrix Stranger',
  );
  final transitioner = SocialTestAccount(
    email: 'matrix-transitioner-$salt@example.com',
    password: 'Transitioner!$salt',
    displayName: 'Matrix Transitioner',
  );
  return (
    owner: owner,
    follower: follower,
    stranger: stranger,
    transitioner: transitioner,
  );
}

String _randomSuffix(int length) {
  const alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final random = math.Random.secure();
  return String.fromCharCodes(
    Iterable<int>.generate(
      length,
      (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ),
  );
}

Future<String> _seedSocialActivity({
  required String ownerUserId,
  required String title,
  required String visibility,
}) async {
  final startedAt = DateTime.now().toUtc().subtract(
    const Duration(minutes: 15),
  );
  final inserted = await Supabase.instance.client
      .from('activities')
      .insert({
        'user_id': ownerUserId,
        'sport_type': 'run',
        'started_at': startedAt.toIso8601String(),
        'finished_at': startedAt
            .add(const Duration(minutes: 30))
            .toIso8601String(),
        'distance_meters': 5000,
        'duration_seconds': 1800,
        'visibility': visibility,
        'title': title,
      })
      .select('id')
      .single();
  final activityId = inserted['id'] as String;
  await Supabase.instance.client.from('track_points').insert([
    {
      'activity_id': activityId,
      'timestamp': startedAt.toIso8601String(),
      'latitude': _seedTrackPointStartLatitude,
      'longitude': _seedTrackPointStartLongitude,
      'distance': 0,
      'speed': 2.9,
    },
    {
      'activity_id': activityId,
      'timestamp': startedAt.add(const Duration(minutes: 5)).toIso8601String(),
      'latitude': _seedTrackPointSecondLatitude,
      'longitude': _seedTrackPointSecondLongitude,
      'distance': 1000,
      'speed': 3.1,
    },
  ]);
  return activityId;
}

const _seedTrackPointStartLatitude = 40.7128;
const _seedTrackPointStartLongitude = -74.0060;
const _seedTrackPointSecondLatitude = 40.7228;
const _seedTrackPointSecondLongitude = -74.0160;
const _seedMaskRadiusMeters = 200;

Future<String> _insertPendingFollow({
  required String followerId,
  required String followingId,
}) async {
  final inserted = await Supabase.instance.client
      .from('follows')
      .insert({
        'follower_id': followerId,
        'following_id': followingId,
        'status': 'pending',
      })
      .select('id')
      .single();
  return inserted['id'] as String;
}

Future<void> _cleanupCurrentUserSocialRows() async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) {
    return;
  }
  try {
    await client.from('kudos').delete().eq('user_id', userId);
  } on Object catch (_) {}
  try {
    await client
        .from('follows')
        .delete()
        .or('follower_id.eq.$userId,following_id.eq.$userId');
  } on Object catch (_) {}
  try {
    await client.from('activities').delete().eq('user_id', userId);
  } on Object catch (_) {}
  try {
    await client.from('privacy_zones').delete().eq('user_id', userId);
  } on Object catch (_) {}
}

Future<void> _upsertCurrentUserProfileDisplayName(String displayName) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) {
    return;
  }

  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final profileRows = await client
        .from('profiles')
        .select('id,display_name')
        .eq('id', userId);
    if (profileRows.isNotEmpty) {
      final profileRow = Map<String, dynamic>.from(profileRows.first);
      if (profileRow['display_name'] == displayName) {
        return;
      }

      // Hosted test users rely on the auth trigger to create their profile row.
      // Once that row exists, update the owned record in-place instead of trying
      // to upsert a brand-new row that hosted RLS correctly rejects.
      await client
          .from('profiles')
          .update({'display_name': displayName})
          .eq('id', userId);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      continue;
    }

    // Hosted auth/profile bootstrap can lag slightly behind account creation.
    // Poll the canonical profile row instead of letting search-based tests race
    // the trigger that materializes the owned profile record.
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  throw StateError(
    'Timed out waiting for profile $userId to expose display_name '
    '"$displayName" after hosted profile bootstrap.',
  );
}

// ---------------------------------------------------------------------------
// Visibility matrix test infrastructure
// ---------------------------------------------------------------------------

/// Multi-user visibility matrix seed data used by cross-user Patrol tests.
class VisibilityMatrixScenario {
  const VisibilityMatrixScenario({
    required this.owner,
    required this.ownerUserId,
    required this.follower,
    required this.stranger,
    required this.transitioner,
    required this.transitionerUserId,
    required this.publicActivityId,
    required this.followersActivityId,
    required this.privateActivityId,
    required this.publicTitle,
    required this.followersTitle,
    required this.privateTitle,
  });

  final SocialTestAccount owner;
  final String ownerUserId;
  final SocialTestAccount follower;
  final SocialTestAccount stranger;
  final SocialTestAccount transitioner;
  final String transitionerUserId;
  final String publicActivityId;
  final String followersActivityId;
  final String privateActivityId;
  final String publicTitle;
  final String followersTitle;
  final String privateTitle;
}

Future<VisibilityMatrixScenario> seedVisibilityMatrixScenario() async {
  final runTimestamp = DateTime.now().microsecondsSinceEpoch.toString();
  final runEntropySuffix = _randomSuffix(8);
  final salt = '$runTimestamp-$runEntropySuffix';
  final ownerSearchToken =
      '${runTimestamp.substring(runTimestamp.length - 6)}-$runEntropySuffix';
  final accounts = _buildVisibilityMatrixAccounts(
    salt: salt,
    ownerSearchToken: ownerSearchToken,
  );
  final owner = accounts.owner;
  final follower = accounts.follower;
  final stranger = accounts.stranger;
  final transitioner = accounts.transitioner;
  final ownerUserId = await _prepareSocialAccount(owner);
  final publicTitle = 'Matrix Public Run $ownerSearchToken';
  final followersTitle = 'Matrix Followers Run $ownerSearchToken';
  final privateTitle = 'Matrix Private Run $ownerSearchToken';
  final publicActivityId = await _seedSocialActivity(
    ownerUserId: ownerUserId,
    title: publicTitle,
    visibility: 'public',
  );
  final followersActivityId = await _seedSocialActivity(
    ownerUserId: ownerUserId,
    title: followersTitle,
    visibility: 'followers',
  );
  final privateActivityId = await _seedSocialActivity(
    ownerUserId: ownerUserId,
    title: privateTitle,
    visibility: 'private',
  );
  final followerId = await _prepareSocialAccount(follower);
  final followId = await _insertPendingFollow(
    followerId: followerId,
    followingId: ownerUserId,
  );
  await preAuthenticate(email: owner.email, password: owner.password);
  await Supabase.instance.client
      .from('follows')
      .update({'status': 'accepted'})
      .eq('id', followId);
  await _prepareSocialAccount(stranger);
  final transitionerUserId = await _prepareSocialAccount(transitioner);
  return VisibilityMatrixScenario(
    owner: owner,
    ownerUserId: ownerUserId,
    follower: follower,
    stranger: stranger,
    transitioner: transitioner,
    transitionerUserId: transitionerUserId,
    publicActivityId: publicActivityId,
    followersActivityId: followersActivityId,
    privateActivityId: privateActivityId,
    publicTitle: publicTitle,
    followersTitle: followersTitle,
    privateTitle: privateTitle,
  );
}

Future<void> cleanupVisibilityMatrixScenario(
  VisibilityMatrixScenario scenario,
) async {
  await _cleanupAccountRows([
    scenario.owner,
    scenario.follower,
    scenario.stranger,
    scenario.transitioner,
  ]);
}

/// Accepts exactly one pending follow request for [followerId] -> [ownerUserId].
Future<void> acceptFollowRequestAsOwner({
  required SocialTestAccount owner,
  required String followerId,
  required String ownerUserId,
}) async {
  await preAuthenticate(email: owner.email, password: owner.password);
  final pendingRows = await Supabase.instance.client
      .from('follows')
      .select('id,status')
      .eq('follower_id', followerId)
      .eq('following_id', ownerUserId)
      .eq('status', 'pending');
  if (pendingRows.length != 1) {
    throw StateError(
      'Expected exactly one pending follow row for '
      '$followerId -> $ownerUserId, found ${pendingRows.length}.',
    );
  }

  final pendingId = pendingRows.first['id'] as String;
  await Supabase.instance.client
      .from('follows')
      .update({'status': 'accepted'})
      .eq('id', pendingId);
}

Future<void> navigateToSearchScreen(PatrolIntegrationTester $) async {
  await waitForAuthenticatedHomeShell($);
  // This helper behaves like a deep link into a top-level social route, so
  // replace the current location instead of stacking another shell above it.
  // That avoids the duplicate StatefulNavigationShell key seen on relaunch.
  goRouteThroughAppRouterForTesting(_containerOf($), SocialRoutes.searchPath);
  await $.pumpAndSettle();
}

Future<void> navigateToOwnSocialProfile(
  PatrolIntegrationTester $, {
  required String ownerUserId,
}) async {
  await waitForAuthenticatedHomeShell($);
  // This helper is also a deep-link style jump, not an in-app drill-down from
  // visible UI state, so replace the location instead of stacking routes.
  goRouteThroughAppRouterForTesting(
    _containerOf($),
    SocialRoutes.viewedUserProfilePath(ownerUserId),
  );
  await $.pumpAndSettle();
}

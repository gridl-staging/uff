import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart'
    as tracking_database;
import 'package:uff/src/features/activity_tracking/data/tracking_repository.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/auth/data/supabase_auth_repository.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/data/supabase_social_activity_repository.dart';

import 'supabase_smoke_helpers.dart';

// ## Test Scenarios
// - [positive] Sign-up establishes an authenticated session and sign-out
//   returns the client to unauthenticated state.
// - [negative] After same-client account switch, viewer reads do not return
//   owner private saved/social activity data.
// - [isolation] Auth transition cleanup invalidates user-scoped providers so
//   cached owner data is not retained for the next authenticated user.
Future<int> _seedLocalSavedOwnerActivity({
  required DriftTrackingRepository repository,
  required String remoteActivityId,
  required DateTime startedAt,
}) async {
  final localSessionId = await repository.saveImportedSession(
    TrackingSessionRecord(
      id: 0,
      status: TrackingSessionStatus.saved,
      createdAt: startedAt,
      updatedAt: startedAt,
      startedAt: startedAt,
      stoppedAt: startedAt.add(const Duration(minutes: 30)),
      title: 'Owner Local Cached Session',
      distanceMeters: 5100,
      movingTimeSeconds: 1800,
      sportType: 'run',
      visibility: 'private',
    ),
    const <TrackingPoint>[],
  );
  await repository.updateSessionRemoteId(localSessionId, remoteActivityId);
  return localSessionId;
}

Future<void> _expectAuthState({
  required ProviderContainer container,
  required AuthState expectedState,
}) async {
  for (var attempt = 0; attempt < 25; attempt++) {
    final currentState = container.read(authProvider).value;
    if (currentState == expectedState) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  expect(container.read(authProvider).value, expectedState);
}

/// Keeps activity-detail reads self-contained in this smoke harness by
/// bypassing the real Supabase-backed profile lookup.
class _StubProfileNotifier extends ProfileNotifier {
  @override
  FutureOr<Profile?> build() => null;
}

void main() {
  group('Auth lifecycle smoke test', skip: skipReason, () {
    late SupabaseClient client;

    setUp(() {
      client = createTestClient();
    });

    tearDown(() => cleanupSupabaseClient(client));

    test(
      'sign up → verify authenticated session → sign out → verify unauthenticated',
      () async {
        final email = generateTestEmail();

        // Sign up (assumes local Supabase with auto-confirm enabled).
        final response = await client.auth.signUp(
          email: email,
          password: testPassword,
          data: {'display_name': 'Smoke Test'},
        );

        expect(
          response.user?.email,
          email,
          reason: 'signUp should return user',
        );

        // Verify authenticated session exists.
        final session = client.auth.currentSession;
        expect(session == null, isFalse, reason: 'session should exist');
        expect(session?.user.email, email);

        // Sign out.
        await client.auth.signOut();

        // Verify unauthenticated.
        final afterSignOut = client.auth.currentSession;
        expect(
          afterSignOut,
          isNull,
          reason: 'session should be null after signOut',
        );
      },
    );

    test(
      'same-client account switch clears saved and social provider reads',
      () async {
        final owner = await createSignedInTestUser(displayName: 'Auth Owner');
        final viewer = await createSignedInTestUser(displayName: 'Auth Viewer');
        addTearDown(() async {
          await cleanupSmokeTestUsers([owner, viewer]);
        });

        final ownerRemoteActivityId = await seedActivityForCurrentUser(
          owner.client,
          visibility: 'private',
          startedAt: DateTime.utc(2026, 3, 26, 10),
          title: 'Owner Private Baseline',
        );
        await seedTrackPointsForActivity(
          owner.client,
          activityId: ownerRemoteActivityId,
          startedAt: DateTime.utc(2026, 3, 26, 10),
        );

        final signedInOwnerId = await signInSmokeTestUser(
          client: client,
          email: owner.email,
        );
        expect(signedInOwnerId, owner.userId);

        final tempDir = Directory.systemTemp.createTempSync(
          'auth_lifecycle_smoke_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final database = tracking_database.TrackingDatabase.forTesting(
          NativeDatabase(File('${tempDir.path}/auth_lifecycle_smoke.sqlite')),
        );
        addTearDown(() async {
          await database.close();
        });
        final repository = DriftTrackingRepository(database);
        final ownerLocalSessionId = await _seedLocalSavedOwnerActivity(
          repository: repository,
          remoteActivityId: ownerRemoteActivityId,
          startedAt: DateTime.utc(2026, 3, 26, 10),
        );

        final container = ProviderContainer(
          overrides: [
            trackingDatabaseProvider.overrideWithValue(database),
            socialActivityRepositoryProvider.overrideWithValue(
              SupabaseSocialActivityRepository(client),
            ),
            authStateChangesProvider.overrideWith((ref) {
              return client.auth.onAuthStateChange.map(
                (event) => mapSessionToAuthState(event.session),
              );
            }),
            profileProvider.overrideWith(_StubProfileNotifier.new),
          ],
        );
        addTearDown(container.dispose);

        final authSubscription = container.listen(authProvider, (_, __) {});
        addTearDown(authSubscription.close);
        await _expectAuthState(
          container: container,
          expectedState: AuthState.authenticated(
            userId: owner.userId,
            email: owner.email,
          ),
        );

        // Verify owner sees their own data while signed in.
        {
          final savedSub = container.listen(
            savedActivitiesProvider,
            (_, __) {},
          );
          final viewedSub = container.listen(
            viewedUserActivityListProvider(owner.userId),
            (_, __) {},
          );

          final ownerSavedActivities = await container.read(
            savedActivitiesProvider.future,
          );
          expect(ownerSavedActivities.map((session) => session.id).toList(), [
            ownerLocalSessionId,
          ]);
          expect(
            ownerSavedActivities.map((session) => session.remoteId).toList(),
            [ownerRemoteActivityId],
          );

          final ownerActivityDetail = await container.read(
            activityDetailProvider(ownerLocalSessionId).future,
          );
          expect(ownerActivityDetail?.session.id, ownerLocalSessionId);
          expect(ownerActivityDetail?.session.remoteId, ownerRemoteActivityId);
          expect(
            ownerActivityDetail?.session.title,
            'Owner Local Cached Session',
          );
          expect(ownerActivityDetail?.session.visibility, 'private');
          expect(ownerActivityDetail?.cleanedPoints.length, 0);

          final ownerViewedActivities = await container.read(
            viewedUserActivityListProvider(owner.userId).future,
          );
          expect(ownerViewedActivities.map((a) => a.activityId).toList(), [
            ownerRemoteActivityId,
          ]);
          expect(ownerViewedActivities.map((a) => a.visibility).toList(), [
            'private',
          ]);

          // Close social subscriptions BEFORE sign-out to prevent the social
          // repository from re-evaluating with a cleared auth session.
          savedSub.close();
          viewedSub.close();
        }

        await client.auth.signOut();
        expect(client.auth.currentSession, isNull);
        await _expectAuthState(
          container: container,
          expectedState: const AuthState.unauthenticated(),
        );

        final signedInViewerId = await signInSmokeTestUser(
          client: client,
          email: viewer.email,
        );
        expect(signedInViewerId, viewer.userId);
        await _expectAuthState(
          container: container,
          expectedState: AuthState.authenticated(
            userId: viewer.userId,
            email: viewer.email,
          ),
        );

        // Re-subscribe after signing in as viewer.
        final savedSubAfter = container.listen(
          savedActivitiesProvider,
          (_, __) {},
        );
        addTearDown(savedSubAfter.close);
        final viewedSubAfter = container.listen(
          viewedUserActivityListProvider(owner.userId),
          (_, __) {},
        );
        addTearDown(viewedSubAfter.close);

        final savedActivitiesAfterSwitch = await container.read(
          savedActivitiesProvider.future,
        );
        expect(
          savedActivitiesAfterSwitch.map((session) => session.id).toList(),
          const <int>[],
        );

        final activityDetailAfterSwitch = await container.read(
          activityDetailProvider(ownerLocalSessionId).future,
        );
        expect(activityDetailAfterSwitch, isNull);

        final ownerActivitiesViewedAsViewer = await container.read(
          viewedUserActivityListProvider(owner.userId).future,
        );
        expect(
          ownerActivitiesViewedAsViewer.map((a) => a.activityId).toList(),
          const <String>[],
        );
      },
    );
  });
}

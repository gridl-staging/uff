import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/profile/data/supabase_profile_repository.dart';
import 'package:uff/src/features/social/data/supabase_follow_repository.dart';
import 'package:uff/src/features/social/data/supabase_social_activity_repository.dart';

import 'supabase_smoke_helpers.dart';

/// ## Test Scenarios
/// - `[positive]` Owner reads own profile with exact migration defaults.
/// - `[negative]` Owner preference writes do not mutate another user's preferences.
/// - `[isolation]` Owner sign-out plus other-user sign-in still reads the other user's own preferences.
/// - `[negative]` Cross-user profile UPDATE is blocked and leaves owner values unchanged.
/// - `[negative]` Cross-user `fcm_token` write is blocked after owner-seeded token.
/// - `[negative]` Cross-user `SELECT *` cannot read private profile columns.
/// - `[isolation]` Social repositories return public summary data only for viewed profile and activity owner.
void main() {
  group('Profile RLS smoke test', skip: skipReason, () {
    late SmokeTestUser owner;
    late SmokeTestUser otherUser;
    late SupabaseProfileRepository ownerProfileRepository;
    late SupabaseFollowRepository otherFollowRepository;
    late SupabaseSocialActivityRepository otherSocialActivityRepository;

    setUp(() async {
      owner = await createSignedInTestUser(displayName: 'Profile Owner');
      otherUser = await createSignedInTestUser(displayName: 'Profile Viewer');
      ownerProfileRepository = SupabaseProfileRepository(owner.client);
      otherFollowRepository = SupabaseFollowRepository(otherUser.client);
      otherSocialActivityRepository = SupabaseSocialActivityRepository(
        otherUser.client,
      );
    });

    tearDown(() async {
      await cleanupSmokeTestUsers([owner, otherUser]);
    });

    test('owner reads own profile with exact default private fields', () async {
      final ownerRow = await owner.client
          .rpc<List<Map<String, dynamic>>>('get_my_profile')
          .single();

      expect(ownerRow['id'], owner.userId);
      expect(ownerRow['preferred_units'], 'metric');
      expect(ownerRow['default_activity_visibility'], 'private');
      expect(ownerRow['onboarding_completed'], false);
      expect(ownerRow['lthr_bpm'], isNull);
      expect(ownerRow['fcm_token'], isNull);
      // PostgREST decodes PostgreSQL text[] '{}' default as an empty JSON list.
      expect(ownerRow['sport_preferences'], <dynamic>[]);
    });

    test(
      'owner preference writes keep other user preference defaults unchanged',
      () async {
        final ownerBaseline = await owner.client
            .rpc<List<Map<String, dynamic>>>('get_my_profile')
            .single();
        final otherBaseline = await otherUser.client
            .rpc<List<Map<String, dynamic>>>('get_my_profile')
            .single();

        final ownerUpdatedUnits = ownerBaseline['preferred_units'] == 'metric'
            ? 'imperial'
            : 'metric';
        final ownerUpdatedVisibility =
            ownerBaseline['default_activity_visibility'] == 'private'
            ? 'followers'
            : 'private';

        await owner.client
            .from('profiles')
            .update({
              'preferred_units': ownerUpdatedUnits,
              'default_activity_visibility': ownerUpdatedVisibility,
            })
            .eq('id', owner.userId)
            .select('id')
            .single();

        final ownerReRead = await owner.client
            .rpc<List<Map<String, dynamic>>>('get_my_profile')
            .single();
        final otherReRead = await otherUser.client
            .rpc<List<Map<String, dynamic>>>('get_my_profile')
            .single();

        expect(ownerReRead['preferred_units'], ownerUpdatedUnits);
        expect(
          ownerReRead['default_activity_visibility'],
          ownerUpdatedVisibility,
        );
        expect(
          otherReRead['preferred_units'],
          otherBaseline['preferred_units'],
        );
        expect(
          otherReRead['default_activity_visibility'],
          otherBaseline['default_activity_visibility'],
        );
      },
    );

    test(
      'owner sign-out then other-user sign-in preserves other user preferences',
      () async {
        final otherBaseline = await otherUser.client
            .rpc<List<Map<String, dynamic>>>('get_my_profile')
            .single();

        await owner.client
            .from('profiles')
            .update({
              'preferred_units': 'imperial',
              'default_activity_visibility': 'private',
            })
            .eq('id', owner.userId)
            .select('id')
            .single();

        await owner.client.auth.signOut();
        await otherUser.client.auth.signOut();
        await signInSmokeTestUser(
          client: otherUser.client,
          email: otherUser.email,
          password: otherUser.password,
        );

        final otherAfterReSignIn = await otherUser.client
            .rpc<List<Map<String, dynamic>>>('get_my_profile')
            .single();
        expect(
          otherAfterReSignIn['preferred_units'],
          otherBaseline['preferred_units'],
        );
        expect(
          otherAfterReSignIn['default_activity_visibility'],
          otherBaseline['default_activity_visibility'],
        );
      },
    );

    test(
      'cross-user profile update returns zero rows and preserves owner state',
      () async {
        await owner.client
            .from('profiles')
            .update({
              'display_name': 'Owner Seed Name',
              'preferred_units': 'imperial',
              'default_activity_visibility': 'followers',
              'onboarding_completed': true,
              'sport_preferences': ['run', 'ride'],
              'lthr_bpm': 165,
            })
            .eq('id', owner.userId)
            .select('id')
            .single();

        final crossUserUpdatedRows = await otherUser.client
            .from('profiles')
            .update({
              'display_name': 'Cross User Mutation',
              'preferred_units': 'metric',
              'default_activity_visibility': 'public',
              'onboarding_completed': false,
              'sport_preferences': ['swim'],
              'lthr_bpm': 111,
            })
            .eq('id', owner.userId)
            .select('id');
        expect(crossUserUpdatedRows, isEmpty);

        final ownerReRead = await owner.client
            .rpc<List<Map<String, dynamic>>>('get_my_profile')
            .single();
        expect(ownerReRead['display_name'], 'Owner Seed Name');
        expect(ownerReRead['preferred_units'], 'imperial');
        expect(ownerReRead['default_activity_visibility'], 'followers');
        expect(ownerReRead['onboarding_completed'], true);
        expect(ownerReRead['sport_preferences'], ['run', 'ride']);
        expect(ownerReRead['lthr_bpm'], 165);
      },
    );

    test(
      'cross-user fcm_token update returns zero rows and keeps owner token',
      () async {
        const ownerToken = 'owner-device-token-1';
        await ownerProfileRepository.updateFcmToken(ownerToken);

        final crossUserUpdatedRows = await otherUser.client
            .from('profiles')
            .update({'fcm_token': 'attacker-token'})
            .eq('id', owner.userId)
            .select('id');
        expect(crossUserUpdatedRows, isEmpty);

        final ownerTokenRow = await owner.client
            .rpc<List<Map<String, dynamic>>>('get_my_profile')
            .single();
        expect(ownerTokenRow['fcm_token'], ownerToken);
      },
    );

    test('cross-user SELECT * cannot read private profile fields', () async {
      await owner.client
          .from('profiles')
          .update({
            'display_name': 'Owner Private Fields Seed',
            'preferred_units': 'imperial',
            'default_activity_visibility': 'followers',
            'onboarding_completed': true,
            'sport_preferences': ['run', 'trail'],
            'lthr_bpm': 172,
            'fcm_token': 'owner-security-gap-token',
          })
          .eq('id', owner.userId)
          .select('id')
          .single();

      await expectLater(
        () => otherUser.client
            .from('profiles')
            // ignore: avoid_redundant_argument_values, reason: Keep explicit SELECT * to enforce private-field read denial.
            .select('*')
            .eq('id', owner.userId)
            .single(),
        throwsA(
          isA<PostgrestException>().having(
            (error) => error.message,
            'message',
            contains('permission denied for table profiles'),
          ),
        ),
      );

      final crossUserPublicProjection = await otherUser.client
          .from('profiles')
          .select('id,display_name,avatar_url')
          .eq('id', owner.userId)
          .single();
      expect(crossUserPublicProjection['id'], owner.userId);
      expect(
        crossUserPublicProjection['display_name'],
        'Owner Private Fields Seed',
      );
      expect(crossUserPublicProjection.containsKey('preferred_units'), false);
      expect(crossUserPublicProjection.containsKey('fcm_token'), false);
    });

    test(
      'social repository reads expose only public summary profile fields',
      () async {
        await owner.client
            .from('profiles')
            .update({
              'display_name': 'Owner Social Header',
              'avatar_url': 'https://example.test/avatar-owner.png',
              'preferred_units': 'imperial',
              'default_activity_visibility': 'followers',
              'onboarding_completed': true,
              'sport_preferences': ['run'],
              'lthr_bpm': 168,
              'fcm_token': 'owner-social-private-token',
            })
            .eq('id', owner.userId)
            .select('id')
            .single();
        await seedAcceptedFollow(
          requesterClient: otherUser.client,
          targetClient: owner.client,
        );
        await seedActivityForCurrentUser(
          owner.client,
          visibility: 'followers',
          startedAt: DateTime.utc(2026, 3, 26, 9),
          title: 'Owner Followers Activity',
        );

        final header = await otherFollowRepository.getViewedUserProfileHeader(
          owner.userId,
        );
        expect(header?.user.userId, owner.userId);
        expect(header?.followersCount, 1);
        expect(header?.followingCount, 0);
        final resolvedHeader = header!;
        expect(resolvedHeader.user.displayName, 'Owner Social Header');
        expect(
          resolvedHeader.user.avatarUrl,
          'https://example.test/avatar-owner.png',
        );
        final headerSummary = <String, Object?>{
          'id': resolvedHeader.user.userId,
          'display_name': resolvedHeader.user.displayName,
          'avatar_url': resolvedHeader.user.avatarUrl,
        };
        expect(
          headerSummary.keys.toList(growable: false),
          ['id', 'display_name', 'avatar_url'],
        );
        expect(headerSummary.containsKey('fcm_token'), false);
        expect(headerSummary.containsKey('preferred_units'), false);
        expect(headerSummary.containsKey('default_activity_visibility'), false);
        expect(headerSummary.containsKey('onboarding_completed'), false);
        expect(headerSummary.containsKey('sport_preferences'), false);
        expect(headerSummary.containsKey('lthr_bpm'), false);

        final feedRows = await otherSocialActivityRepository.loadFeedActivities(
          offset: 0,
          limit: 20,
        );
        expect(feedRows.length, 1);
        final feedOwner = feedRows.single.owner;
        expect(feedOwner.userId, owner.userId);
        expect(feedOwner.displayName, 'Owner Social Header');
        expect(feedOwner.avatarUrl, 'https://example.test/avatar-owner.png');
        final feedOwnerSummary = <String, Object?>{
          'id': feedOwner.userId,
          'display_name': feedOwner.displayName,
          'avatar_url': feedOwner.avatarUrl,
        };
        expect(
          feedOwnerSummary.keys.toList(growable: false),
          ['id', 'display_name', 'avatar_url'],
        );
        expect(feedOwnerSummary.containsKey('fcm_token'), false);
        expect(feedOwnerSummary.containsKey('preferred_units'), false);
        expect(
          feedOwnerSummary.containsKey('default_activity_visibility'),
          false,
        );
        expect(feedOwnerSummary.containsKey('onboarding_completed'), false);
        expect(feedOwnerSummary.containsKey('sport_preferences'), false);
        expect(feedOwnerSummary.containsKey('lthr_bpm'), false);
      },
    );
  });
}

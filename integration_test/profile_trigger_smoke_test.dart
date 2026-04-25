import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/profile/data/profile.dart';

import 'supabase_smoke_helpers.dart';

/// ## Test Scenarios
/// - `[positive]` Signing up creates a profile row through the auth trigger
/// - `[positive]` Trigger defaults map to Profile.fromJson stable defaults
void main() {
  group('Profile trigger smoke test', skip: skipReason, () {
    late SupabaseClient client;

    setUp(() {
      client = createTestClient();
    });

    tearDown(() => cleanupSupabaseClient(client));

    test(
      'sign up → profile row created by database trigger with defaults',
      () async {
        final email = generateTestEmail();
        await client.auth.signUp(
          email: email,
          password: testPassword,
          data: {'display_name': 'Profile Trigger Test'},
        );

        final userId = client.auth.currentUser!.id;

        // Read through the auth-scoped RPC so the test stays aligned with the
        // hardened private-field contract for authenticated clients.
        final row = await client
            .rpc<List<Map<String, dynamic>>>('get_my_profile')
            .single();

        final profile = Profile.fromJson(row);

        expect(profile.userId, userId);
        expect(profile.preferredUnits, 'metric');
        expect(profile.defaultActivityVisibility, 'private');
        expect(profile.onboardingCompleted, isFalse);
      },
    );
  });
}

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/utils/local_test_service_defaults.dart';

import '../../integration_test/supabase_smoke_helpers.dart';

/// ## Test Scenarios
/// - `[positive]` Supabase runtime setting helpers prefer the intended value source and fallback order.
/// - `[positive]` Generated smoke-test emails stay unique and monotonic across repeated timestamps.
/// - `[positive]` Disposable smoke clients and sign-in helpers preserve their cleanup and per-user credential contracts.
/// - `[positive]` Storage cleanup path helpers rebuild exact user-scoped and activity-photo object paths from listed files.
/// - `[error]` Fallback sign-in must authenticate the same user id that sign-up created.
/// - `[error]` Password sign-in rejects missing cached credentials for generated smoke users.
void main() {
  setUp(resetGeneratedTestEmailSequence);

  test('resolveSupabaseSetting prefers the primary configured value', () {
    final resolved = resolveSupabaseSetting(
      primary: ' https://primary.example ',
      secondary: 'https://secondary.example',
      fallback: LocalTestServiceDefaults.supabaseUrl,
    );

    expect(resolved, 'https://primary.example');
  });

  test('resolveSupabaseSetting falls back to the secondary value', () {
    final resolved = resolveSupabaseSetting(
      primary: '   ',
      secondary: ' https://secondary.example ',
      fallback: LocalTestServiceDefaults.supabaseUrl,
    );

    expect(resolved, 'https://secondary.example');
  });

  test('resolveSupabaseSetting falls back to the committed local default', () {
    final resolved = resolveSupabaseSetting(
      primary: null,
      secondary: '   ',
      fallback: LocalTestServiceDefaults.supabaseAnonKey,
    );

    expect(resolved, LocalTestServiceDefaults.supabaseAnonKey);
  });

  test('helper resolves non-empty credentials', () {
    const supabaseUrlDefine = String.fromEnvironment('SUPABASE_URL');
    const supabaseLocalUrlDefine = String.fromEnvironment('SUPABASE_LOCAL_URL');
    const supabaseAnonKeyDefine = String.fromEnvironment('SUPABASE_ANON_KEY');
    const supabaseLocalAnonKeyDefine = String.fromEnvironment(
      'SUPABASE_LOCAL_ANON_KEY',
    );
    final expectedUrl = resolveSupabaseRuntimeSetting(
      dartDefinePrimary: supabaseUrlDefine,
      dartDefineSecondary: supabaseLocalUrlDefine,
      environmentPrimary: Platform.environment['SUPABASE_URL'],
      environmentSecondary: Platform.environment['SUPABASE_LOCAL_URL'],
      fallback: LocalTestServiceDefaults.supabaseUrl,
    );
    final expectedAnonKey = resolveSupabaseRuntimeSetting(
      dartDefinePrimary: supabaseAnonKeyDefine,
      dartDefineSecondary: supabaseLocalAnonKeyDefine,
      environmentPrimary: Platform.environment['SUPABASE_ANON_KEY'],
      environmentSecondary: Platform.environment['SUPABASE_LOCAL_ANON_KEY'],
      fallback: LocalTestServiceDefaults.supabaseAnonKey,
    );

    expect(supabaseUrl, expectedUrl);
    expect(supabaseAnonKey, expectedAnonKey);
    expect(hasSupabaseCredentials, isTrue);
  });

  test('runtime Supabase settings prefer dart defines over env vars', () {
    final resolved = resolveSupabaseRuntimeSetting(
      dartDefinePrimary: ' https://define-primary.example ',
      dartDefineSecondary: 'https://define-secondary.example',
      environmentPrimary: 'https://env-primary.example',
      environmentSecondary: 'https://env-secondary.example',
      fallback: LocalTestServiceDefaults.supabaseUrl,
    );

    expect(resolved, 'https://define-primary.example');
  });

  test('runtime Supabase settings fall back from env vars to defaults', () {
    final resolved = resolveSupabaseRuntimeSetting(
      dartDefinePrimary: ' ',
      dartDefineSecondary: null,
      environmentPrimary: null,
      environmentSecondary: '   ',
      fallback: LocalTestServiceDefaults.supabaseUrl,
    );

    expect(resolved, LocalTestServiceDefaults.supabaseUrl);
  });

  test('runtime smoke flag prefers dart define over environment', () {
    expect(
      resolveSupabaseRuntimeFlag(
        dartDefineValue: ' true ',
        environmentValue: 'false',
      ),
      'true',
    );
  });

  test('runtime smoke flag falls back to environment when needed', () {
    expect(
      resolveSupabaseRuntimeFlag(
        dartDefineValue: '   ',
        environmentValue: ' TRUE ',
      ),
      'TRUE',
    );
  });

  test(
    'activity photo storage path builder returns the three-segment path',
    () {
      expect(
        buildActivityPhotoStorageObjectPath(
          userId: 'user-1',
          activityId: 'activity-1',
          fileName: 'photo.jpg',
        ),
        'user-1/activity-1/photo.jpg',
      );
    },
  );

  test('user-scoped cleanup paths preserve the listed basenames', () {
    expect(
      buildUserScopedStorageObjectPaths(
        userId: 'user-1',
        listedObjects: [
          _fileObject('avatar.png'),
          _fileObject('export.jpg'),
        ],
      ),
      [
        'user-1/avatar.png',
        'user-1/export.jpg',
      ],
    );
  });

  test('activity photo cleanup paths rebuild nested activity file paths', () {
    expect(
      buildActivityPhotoStorageCleanupPaths(
        userId: 'user-1',
        activityId: 'activity-1',
        listedObjects: [
          _fileObject('photo.jpg'),
          _fileObject('photo_thumb.jpg'),
        ],
      ),
      [
        'user-1/activity-1/photo.jpg',
        'user-1/activity-1/photo_thumb.jpg',
      ],
    );
  });

  test('smoke tests are skipped unless explicitly enabled', () {
    const expectedSkipReason =
        'Set RUN_SUPABASE_SMOKE_TESTS=true or pass '
        '--dart-define=RUN_SUPABASE_SMOKE_TESTS=true to run Supabase smoke '
        'tests.';
    expect(
      resolveSupabaseSmokeSkipReason(runSupabaseSmokeTests: null),
      expectedSkipReason,
    );
    expect(
      resolveSupabaseSmokeSkipReason(runSupabaseSmokeTests: 'false'),
      expectedSkipReason,
    );
  });

  test('smoke tests run when explicit opt-in flag is true', () {
    expect(
      resolveSupabaseSmokeSkipReason(runSupabaseSmokeTests: 'true'),
      isNull,
    );
    expect(
      resolveSupabaseSmokeSkipReason(runSupabaseSmokeTests: ' TRUE '),
      isNull,
    );
  });

  test('generateTestEmail stays unique when the clock does not advance', () {
    final fixedTime = DateTime(2026);
    final format = RegExp(r'^smoke_(\d+)@test\.local$');
    final first = generateTestEmail(now: () => fixedTime);
    final second = generateTestEmail(now: () => fixedTime);
    final firstMatch = format.firstMatch(first);
    final secondMatch = format.firstMatch(second);

    expect(second, isNot(first));
    expect(
      int.parse(secondMatch!.group(1)!),
      int.parse(firstMatch!.group(1)!) + 1,
    );
  });

  test('generateTestEmail stays monotonic if the clock moves backwards', () {
    final newerTime = DateTime(2026, 1, 1, 0, 0, 0, 10);
    final olderTime = DateTime(2026, 1, 1, 0, 0, 0, 9);
    final format = RegExp(r'^smoke_(\d+)@test\.local$');

    final first = generateTestEmail(now: () => newerTime);
    final second = generateTestEmail(now: () => olderTime);
    final third = generateTestEmail(now: () => olderTime);

    final firstMatch = format.firstMatch(first);
    final secondMatch = format.firstMatch(second);
    final thirdMatch = format.firstMatch(third);

    expect(
      int.parse(secondMatch!.group(1)!),
      int.parse(firstMatch!.group(1)!) + 1,
    );
    expect(
      int.parse(thirdMatch!.group(1)!),
      int.parse(secondMatch.group(1)!) + 1,
    );
  });

  test('generateTestEmail resumes real timestamp when clock moves ahead', () {
    final newerTime = DateTime(2026, 1, 1, 0, 0, 0, 10);
    final olderTime = DateTime(2026, 1, 1, 0, 0, 0, 9);
    final muchNewerTime = DateTime(2026, 1, 1, 0, 0, 0, 20);
    final format = RegExp(r'^smoke_(\d+)@test\.local$');

    final first = generateTestEmail(now: () => newerTime);
    final second = generateTestEmail(now: () => olderTime);
    final third = generateTestEmail(now: () => muchNewerTime);

    final firstMatch = format.firstMatch(first);
    final secondMatch = format.firstMatch(second);
    final thirdMatch = format.firstMatch(third);

    expect(
      int.parse(secondMatch!.group(1)!),
      int.parse(firstMatch!.group(1)!) + 1,
    );
    expect(
      int.parse(thirdMatch!.group(1)!),
      muchNewerTime.microsecondsSinceEpoch,
    );
  });

  test('generateTestPassword returns policy-shaped unique passwords', () {
    final first = generateTestPassword(random: Random(1));
    final second = generateTestPassword(random: Random(2));
    final passwordPattern = RegExp(
      r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[^A-Za-z0-9]).{23}$',
    );

    expect(first, matches(passwordPattern));
    expect(second, matches(passwordPattern));
    expect(second, isNot(first));
  });

  test('createTestClient returns disposable test-scoped clients', () async {
    final first = createTestClient();
    final second = createTestClient();

    expect(first, isNot(same(second)));
    expect(first.auth.currentSession, isNull);
    expect(second.auth.currentSession, isNull);

    await cleanupSupabaseClient(first);
    await cleanupSupabaseClient(second);
  });

  test(
    'cleanupSupabaseClient remains best-effort on disposed clients',
    () async {
      final client = createTestClient();
      await client.dispose();

      await cleanupSupabaseClient(client);
    },
  );

  test('cleanupSupabaseClient is idempotent across repeated calls', () async {
    final client = createTestClient();

    await cleanupSupabaseClient(client);
    await cleanupSupabaseClient(client);
  });

  test('smoke helper accepts sign-up results with an active session', () async {
    final userId = await ensureSmokeTestUserIsSignedIn(
      signUp: () async => const SmokeAuthOutcome(
        userId: 'user-from-sign-up',
        hasAuthenticatedSession: true,
      ),
      signIn: () async => throw UnimplementedError('signIn should not run'),
    );

    expect(userId, 'user-from-sign-up');
  });

  test(
    'resolveSmokeTestPassword uses the cached generated password',
    () {
      rememberGeneratedSmokeTestPassword(
        email: 'smoke@test.local',
        password: 'Stored!Pass#1234567890',
      );

      expect(
        resolveSmokeTestPassword(email: 'smoke@test.local'),
        'Stored!Pass#1234567890',
      );
    },
  );

  test(
    'resolveSmokeTestPassword prefers an explicit override password',
    () {
      rememberGeneratedSmokeTestPassword(
        email: 'smoke@test.local',
        password: 'Stored!Pass#1234567890',
      );

      expect(
        resolveSmokeTestPassword(
          email: 'smoke@test.local',
          passwordOverride: 'Override!Pass#1234567',
        ),
        'Override!Pass#1234567',
      );
    },
  );

  test(
    'resolveSmokeTestPassword fails clearly when no password is available',
    () {
      expect(
        () => resolveSmokeTestPassword(email: 'missing@test.local'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(
              'Expected an in-memory password for smoke-test user missing@test.local.',
            ),
          ),
        ),
      );
    },
  );

  test(
    'smoke helper falls back to password sign-in when sign-up is unsigned',
    () async {
      var signInCallCount = 0;

      final userId = await ensureSmokeTestUserIsSignedIn(
        signUp: () async => const SmokeAuthOutcome(
          userId: 'created-user',
          hasAuthenticatedSession: false,
        ),
        signIn: () async {
          signInCallCount++;
          return const SmokeAuthOutcome(
            userId: 'created-user',
            hasAuthenticatedSession: true,
          );
        },
      );

      expect(userId, 'created-user');
      expect(signInCallCount, 1);
    },
  );

  test(
    'smoke helper fails clearly when sign-in still lacks a session',
    () async {
      await expectLater(
        ensureSmokeTestUserIsSignedIn(
          signUp: () async => const SmokeAuthOutcome(
            userId: 'created-user',
            hasAuthenticatedSession: false,
          ),
          signIn: () async => const SmokeAuthOutcome(
            userId: 'created-user',
            hasAuthenticatedSession: false,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(
              'Smoke tests require an authenticated session after sign-up.',
            ),
          ),
        ),
      );
    },
  );

  test(
    'smoke helper fails when fallback sign-in authenticates a different user',
    () async {
      await expectLater(
        ensureSmokeTestUserIsSignedIn(
          signUp: () async => const SmokeAuthOutcome(
            userId: 'created-user',
            hasAuthenticatedSession: false,
          ),
          signIn: () async => const SmokeAuthOutcome(
            userId: 'wrong-user',
            hasAuthenticatedSession: true,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Expected created-user but got wrong-user.'),
          ),
        ),
      );
    },
  );
}

FileObject _fileObject(String name) {
  return FileObject(
    name: name,
    bucketId: null,
    owner: null,
    id: null,
    updatedAt: null,
    createdAt: null,
    lastAccessedAt: null,
    metadata: null,
    buckets: null,
  );
}

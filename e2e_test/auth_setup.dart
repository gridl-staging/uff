import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/auth/data/auth_exception_classifiers.dart';
import 'package:uff/src/utils/app_environment.dart';

const _testEmailEnvKey = 'E2E_TEST_EMAIL';
const _testPasswordEnvKey = 'E2E_TEST_PASSWORD';
const _serviceRoleEnvKey = 'SUPABASE_SERVICE_ROLE_KEY';
const _testEmailDefine = String.fromEnvironment(_testEmailEnvKey);
const _testPasswordDefine = String.fromEnvironment(_testPasswordEnvKey);
const _serviceRoleDefine = String.fromEnvironment(_serviceRoleEnvKey);
const _passwordAlphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

String? _generatedTestEmail;
String? _generatedTestPassword;

typedef OnboardingCompletionCallback = Future<void> Function(String userId);

/// Unique account credentials for a credentialed E2E user.
class E2eTestUserCredentials {
  const E2eTestUserCredentials({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;
}

/// Owner/viewer account pair for multi-account E2E isolation audits.
class E2eOwnerViewerAccounts {
  const E2eOwnerViewerAccounts({
    required this.owner,
    required this.viewer,
  });

  final E2eTestUserCredentials owner;
  final E2eTestUserCredentials viewer;
}

/// Clears any persisted Supabase auth session.
///
/// Use this in setup/teardown to keep smoke files isolated when they run as a
/// directory and share app auth persistence.
Future<void> clearAuthSession() async {
  await clearAuthSessionWithClient(Supabase.instance.client.auth);
}

@visibleForTesting
Future<void> clearAuthSessionWithClient(GoTrueClient authClient) async {
  try {
    await authClient.signOut();
  } on AuthException catch (error) {
    if (!_isMissingSessionAuthException(error)) {
      rethrow;
    }
  }
}

/// Signs in a test user via Supabase Auth API.
///
/// For tests where auth is a precondition (not under test). When
/// `E2E_TEST_EMAIL` and `E2E_TEST_PASSWORD` are present in `.env.dev`, those
/// credentials are used directly. Otherwise a per-run test user is created and
/// reused for the remainder of the run.
Future<void> preAuthenticate({
  String? email,
  String? password,
}) async {
  final authClient = Supabase.instance.client.auth;
  final existingUserCredentials = _providedOrConfiguredTestCredentials(
    email: email,
    password: password,
  );
  if (existingUserCredentials != null) {
    await _preAuthenticateWithCredentials(authClient, existingUserCredentials);
    return;
  }

  final generatedCredentials = _generatedTestCredentials();
  await ensureTestUserWithClient(
    authClient,
    email: generatedCredentials.email,
    password: generatedCredentials.password,
    markOnboardingCompleted: _markOnboardingCompletedForUser,
  );
}

@visibleForTesting
Future<void> preAuthenticateWithClient(
  GoTrueClient authClient, {
  required String email,
  required String password,
  OnboardingCompletionCallback? markOnboardingCompleted,
}) async {
  final initialSignInResponse = await authClient.signInWithPassword(
    email: email,
    password: password,
  );

  final userId = initialSignInResponse.user?.id;
  if (userId == null) {
    throw StateError(
      'Expected Supabase sign-in to return a user id during E2E '
      'pre-authentication.',
    );
  }

  final markOnboarding =
      markOnboardingCompleted ?? _markOnboardingCompletedForUser;
  await markOnboarding(userId);

  // The first sign-in can hydrate profile state before onboarding_completed is
  // persisted. Re-authenticate so auth/profile listeners reload with the
  // updated onboarding flag and routes land on /home in pre-auth tests.
  await authClient.signOut();
  await authClient.signInWithPassword(
    email: email,
    password: password,
  );
}

/// Creates a test user if one does not already exist, then signs in.
///
/// Safe to call multiple times. Duplicate-user sign-up failures are caught and
/// falls through to sign-in.
Future<void> ensureTestUser({
  String? email,
  String? password,
}) async {
  final authClient = Supabase.instance.client.auth;
  final credentials =
      _providedOrConfiguredTestCredentials(email: email, password: password) ??
      _generatedTestCredentials();
  await ensureTestUserWithClient(
    authClient,
    email: credentials.email,
    password: credentials.password,
  );
}

/// Creates unique owner/viewer users and returns the credentials for both.
Future<E2eOwnerViewerAccounts> ensureOwnerViewerAccounts({
  required String namespace,
}) async {
  final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
  final owner = E2eTestUserCredentials(
    email: '$namespace-owner-$uniqueSuffix@example.com',
    password: 'OwnerPass!$uniqueSuffix',
  );
  final viewer = E2eTestUserCredentials(
    email: '$namespace-viewer-$uniqueSuffix@example.com',
    password: 'ViewerPass!$uniqueSuffix',
  );

  await ensureTestUser(email: owner.email, password: owner.password);
  await ensureTestUser(email: viewer.email, password: viewer.password);

  return E2eOwnerViewerAccounts(owner: owner, viewer: viewer);
}

/// Creates a test user and signs in WITHOUT marking onboarding completed.
///
/// Use this for tests that exercise the onboarding flow. In hosted
/// environments (staging/prod), the user is created via the admin API to
/// bypass email confirmation. The Supabase database trigger creates the
/// profile row with `onboarding_completed = false`, so the router will
/// redirect to `/onboarding` when the app launches.
///
/// Callers must call [initializeTestServices] before this — the Supabase
/// singleton must be available.
Future<E2eTestUserCredentials> ensureTestUserForOnboarding({
  String? email,
  String? password,
}) async {
  final authClient = Supabase.instance.client.auth;
  final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
  final resolvedEmail = email ?? 'onboarding-$uniqueSuffix@example.com';
  final resolvedPassword = password ?? 'OnboardTest!$uniqueSuffix';

  if (_shouldUseHostedAdminBootstrap()) {
    // Hosted environments require admin API to bypass email confirmation.
    await _ensureHostedTestUserWithAdminApi(
      email: resolvedEmail,
      password: resolvedPassword,
    );
  } else {
    // Local Supabase auto-confirms on signup.
    try {
      await authClient.signUp(
        email: resolvedEmail,
        password: resolvedPassword,
      );
    } on AuthException catch (error) {
      if (!isDuplicateUserAuthException(error)) {
        rethrow;
      }
    }
  }

  // Sign in to establish a session, but do NOT mark onboarding completed.
  // The database trigger sets onboarding_completed = false on profile
  // creation, so the router will redirect to /onboarding.
  await authClient.signInWithPassword(
    email: resolvedEmail,
    password: resolvedPassword,
  );

  return E2eTestUserCredentials(
    email: resolvedEmail,
    password: resolvedPassword,
  );
}

@visibleForTesting
Future<void> ensureTestUserWithClient(
  GoTrueClient authClient, {
  required String email,
  required String password,
  OnboardingCompletionCallback? markOnboardingCompleted,
}) async {
  if (_shouldUseHostedAdminBootstrap()) {
    await _ensureHostedTestUserWithAdminApi(
      email: email,
      password: password,
    );
  } else {
    try {
      await authClient.signUp(
        email: email,
        password: password,
      );
    } on AuthException catch (error) {
      if (!isDuplicateUserAuthException(error)) {
        rethrow;
      }
    }
  }
  await preAuthenticateWithClient(
    authClient,
    email: email,
    password: password,
    markOnboardingCompleted: markOnboardingCompleted,
  );
}

Future<void> _markOnboardingCompletedForUser(String userId) async {
  await Supabase.instance.client
      .from('profiles')
      .update({'onboarding_completed': true})
      .eq('id', userId);
}

bool _shouldUseHostedAdminBootstrap() {
  final environmentName = readConfiguredAppEnvironment();
  if (environmentName == defaultAppEnvironmentName) {
    return false;
  }

  return _resolvedServiceRoleKey().isNotEmpty;
}

Future<void> _ensureHostedTestUserWithAdminApi({
  required String email,
  required String password,
}) async {
  final supabaseUrl = dotenv.isInitialized
      ? (dotenv.maybeGet('SUPABASE_URL')?.trim() ?? '')
      : '';
  final serviceRoleKey = _resolvedServiceRoleKey();
  if (supabaseUrl.isEmpty || serviceRoleKey.isEmpty) {
    throw StateError(
      'Hosted admin test-user bootstrap requires SUPABASE_URL and '
      'SUPABASE_SERVICE_ROLE_KEY.',
    );
  }

  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('$supabaseUrl/auth/v1/admin/users'),
    );
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $serviceRoleKey')
      ..set('apikey', serviceRoleKey)
      ..contentType = ContentType.json;
    request.write(
      jsonEncode({
        'email': email,
        'password': password,
        'email_confirm': true,
      }),
    );

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    final duplicateUser = _isHostedDuplicateUserResponse(responseBody);
    if (duplicateUser) {
      return;
    }

    throw AuthException(
      'Hosted admin test-user bootstrap failed: $responseBody',
      statusCode: '${response.statusCode}',
      code: 'admin_user_create_failed',
    );
  } finally {
    client.close(force: true);
  }
}

bool _isHostedDuplicateUserResponse(String responseBody) {
  final normalizedBody = responseBody.toLowerCase();
  if (normalizedBody.contains('already been registered') ||
      normalizedBody.contains('already registered') ||
      normalizedBody.contains('already exists')) {
    return true;
  }

  // The plain-text check above already catches "already registered" etc.
  // in both JSON and non-JSON bodies. Only the structured code field adds
  // a case the text scan cannot reach.
  try {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map<String, dynamic>) {
      final code = decoded['code']?.toString().toLowerCase() ?? '';
      return code == 'email_exists';
    }
  } on FormatException {
    // Some GoTrue failures return plain text rather than JSON.
  }

  return false;
}

bool _isMissingSessionAuthException(AuthException error) {
  switch (error.code) {
    case 'session_not_found':
    case 'session_missing':
      return true;
  }

  return error.message == 'Auth session missing!';
}

E2eTestUserCredentials? _providedOrConfiguredTestCredentials({
  String? email,
  String? password,
}) {
  return _explicitTestCredentials(email: email, password: password) ??
      _definedTestCredentials() ??
      _configuredTestCredentials();
}

Future<void> _preAuthenticateWithCredentials(
  GoTrueClient authClient,
  E2eTestUserCredentials credentials,
) {
  return preAuthenticateWithClient(
    authClient,
    email: credentials.email,
    password: credentials.password,
    markOnboardingCompleted: _markOnboardingCompletedForUser,
  );
}

E2eTestUserCredentials? _explicitTestCredentials({
  String? email,
  String? password,
}) {
  if ((email == null) != (password == null)) {
    throw ArgumentError(
      'Provide both email and password together, or neither.',
    );
  }

  if (email == null || password == null) {
    return null;
  }

  return E2eTestUserCredentials(email: email, password: password);
}

E2eTestUserCredentials? _configuredTestCredentials() {
  if (!dotenv.isInitialized) {
    return null;
  }

  final email = dotenv.maybeGet(_testEmailEnvKey)?.trim();
  final password = dotenv.maybeGet(_testPasswordEnvKey)?.trim();
  final missingEmail = email == null || email.isEmpty;
  final missingPassword = password == null || password.isEmpty;

  if (missingEmail && missingPassword) {
    return null;
  }
  if (missingEmail || missingPassword) {
    throw StateError(
      'Set both $_testEmailEnvKey and $_testPasswordEnvKey in '
      '${resolveRuntimeEnvironmentAsset()}.',
    );
  }

  return E2eTestUserCredentials(email: email, password: password);
}

E2eTestUserCredentials? _definedTestCredentials() {
  final missingEmail = _testEmailDefine.trim().isEmpty;
  final missingPassword = _testPasswordDefine.trim().isEmpty;

  if (missingEmail && missingPassword) {
    return null;
  }
  if (missingEmail || missingPassword) {
    throw StateError(
      'Set both $_testEmailEnvKey and $_testPasswordEnvKey dart defines together.',
    );
  }

  return const E2eTestUserCredentials(
    email: _testEmailDefine,
    password: _testPasswordDefine,
  );
}

String _resolvedServiceRoleKey() {
  if (dotenv.isInitialized) {
    final configuredValue = dotenv.maybeGet(_serviceRoleEnvKey)?.trim();
    if (configuredValue != null && configuredValue.isNotEmpty) {
      return configuredValue;
    }
  }

  final definedValue = _serviceRoleDefine.trim();
  if (definedValue.isNotEmpty) {
    return definedValue;
  }

  return '';
}

E2eTestUserCredentials _generatedTestCredentials() {
  _generatedTestEmail ??=
      'e2e-${DateTime.now().microsecondsSinceEpoch}-${_randomSuffix(8)}@example.com';
  _generatedTestPassword ??= 'Test!${_randomSuffix(20)}';
  return E2eTestUserCredentials(
    email: _generatedTestEmail!,
    password: _generatedTestPassword!,
  );
}

String _randomSuffix(int length) {
  final random = Random.secure();
  return String.fromCharCodes(
    Iterable<int>.generate(
      length,
      (_) => _passwordAlphabet.codeUnitAt(
        random.nextInt(_passwordAlphabet.length),
      ),
    ),
  );
}

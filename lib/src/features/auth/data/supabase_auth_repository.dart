import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:uff/src/features/auth/data/auth_repository.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/profile/data/profile_repository.dart';

/// TODO: Document SupabaseAuthRepository.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(
    this._auth, {
    AppleNativeSignInClient? appleSignInClient,
    GoogleNativeSignInClient? googleSignInClient,
    ProfileRepository? profileRepository,
    String Function()? nonceGenerator,
  }) : _appleSignInClient =
           appleSignInClient ?? SignInWithAppleNativeSignInClient(),
       _googleSignInClient =
           googleSignInClient ?? GoogleSignInNativeSignInClient(),
       _profileRepository = profileRepository,
       _nonceGenerator = nonceGenerator ?? _generateNonce;

  final supabase.GoTrueClient _auth;
  final AppleNativeSignInClient _appleSignInClient;
  final GoogleNativeSignInClient _googleSignInClient;
  final ProfileRepository? _profileRepository;
  final String Function() _nonceGenerator;

  @override
  Future<AuthState> getCurrentSession() async {
    final session = _auth.currentSession;
    return mapSessionToAuthState(session);
  }

  @override
  AuthState getCurrentSessionSync() {
    return mapSessionToAuthState(_auth.currentSession);
  }

  @override
  Future<AuthState> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _auth.signInWithPassword(
      email: email,
      password: password,
    );
    return mapSessionToAuthState(response.session);
  }

  @override
  Future<AuthState> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _auth.signUp(
      email: email,
      password: password,
      data: {'display_name': displayName},
    );
    return mapSessionToAuthState(response.session);
  }

  @override
  Future<AuthState> signInWithApple() async {
    final rawNonce = _nonceGenerator();
    final hashedNonce = _hashSha256(rawNonce);
    final nativeSignInResult = await _appleSignInClient.signIn(
      rawNonce: rawNonce,
      hashedNonce: hashedNonce,
    );
    final idToken = _requireToken(
      providerName: 'Apple',
      tokenName: 'id token',
      idToken: nativeSignInResult.idToken,
    );
    final response = await _auth.signInWithIdToken(
      provider: supabase.OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
    await _syncAppleDisplayNameIfNeeded(
      session: response.session,
      nativeSignInResult: nativeSignInResult,
    );
    return mapSessionToAuthState(response.session);
  }

  @override
  Future<AuthState> signInWithGoogle() async {
    final nativeSignInResult = await _googleSignInClient.signIn();
    if (nativeSignInResult == null) {
      throw const NativeAuthTokenException('Google sign-in was cancelled.');
    }
    final idToken = _requireToken(
      providerName: 'Google',
      tokenName: 'id token',
      idToken: nativeSignInResult.idToken,
    );
    final accessToken = _requireToken(
      providerName: 'Google',
      tokenName: 'access token',
      idToken: nativeSignInResult.accessToken,
    );
    final response = await _auth.signInWithIdToken(
      provider: supabase.OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
    return mapSessionToAuthState(response.session);
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    await _auth.updateUser(supabase.UserAttributes(password: newPassword));
  }

  @override
  Future<List<String>> connectedProviders() async {
    final identities = _auth.currentUser?.identities;
    if (identities == null) {
      return const <String>[];
    }
    return identities.map((identity) => identity.provider).toList();
  }

  @override
  DateTime? memberSince() {
    final createdAt = _auth.currentUser?.createdAt;
    if (createdAt == null) {
      return null;
    }
    return DateTime.tryParse(createdAt);
  }

  Future<void> _syncAppleDisplayNameIfNeeded({
    required supabase.Session? session,
    required AppleNativeSignInResult nativeSignInResult,
  }) async {
    final profileRepository = _profileRepository;
    final userId = session?.user.id;
    final appleDisplayName = _joinAppleDisplayName(
      nativeSignInResult.givenName,
      nativeSignInResult.familyName,
    );
    if (profileRepository == null ||
        userId == null ||
        appleDisplayName == null) {
      return;
    }
    final currentProfile = await profileRepository.getProfile(userId);
    if ((currentProfile.displayName ?? '').trim().isNotEmpty) {
      return;
    }
    await profileRepository.updateProfile(
      currentProfile.copyWith(displayName: appleDisplayName),
    );
  }
}

String _hashSha256(String value) {
  return sha256.convert(utf8.encode(value)).toString();
}

String _requireToken({
  required String providerName,
  required String tokenName,
  required String? idToken,
}) {
  if (idToken == null || idToken.isEmpty) {
    throw NativeAuthTokenException(
      '$providerName sign-in did not return a $tokenName.',
    );
  }
  return idToken;
}

String? _joinAppleDisplayName(String? givenName, String? familyName) {
  final parts = [
    if (givenName != null && givenName.trim().isNotEmpty) givenName.trim(),
    if (familyName != null && familyName.trim().isNotEmpty) familyName.trim(),
  ];
  if (parts.isEmpty) {
    return null;
  }
  return parts.join(' ');
}

String _generateNonce({int length = 32}) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List<String>.generate(
    length,
    (_) => charset[random.nextInt(charset.length)],
  ).join();
}

class NativeAuthTokenException implements Exception {
  const NativeAuthTokenException(this.message);

  final String message;

  @override
  String toString() {
    return 'NativeAuthTokenException($message)';
  }
}

class AppleNativeSignInResult {
  const AppleNativeSignInResult({
    this.idToken,
    this.givenName,
    this.familyName,
  });

  final String? idToken;
  final String? givenName;
  final String? familyName;
}

class AppleNativeSignInClient {
  Future<AppleNativeSignInResult> signIn({
    required String rawNonce,
    required String hashedNonce,
  }) {
    throw UnimplementedError();
  }
}

/// NOTE(stuart): Document SignInWithAppleNativeSignInClient.
class SignInWithAppleNativeSignInClient implements AppleNativeSignInClient {
  @override
  Future<AppleNativeSignInResult> signIn({
    required String rawNonce,
    required String hashedNonce,
  }) async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );
    return AppleNativeSignInResult(
      idToken: credential.identityToken,
      givenName: credential.givenName,
      familyName: credential.familyName,
    );
  }
}

class GoogleNativeSignInResult {
  const GoogleNativeSignInResult({this.idToken, this.accessToken});

  final String? idToken;
  final String? accessToken;
}

class GoogleNativeSignInClient {
  Future<GoogleNativeSignInResult?> signIn() {
    throw UnimplementedError();
  }
}

/// NOTE(stuart): Document GoogleSignInNativeSignInClient.
class GoogleSignInNativeSignInClient implements GoogleNativeSignInClient {
  GoogleSignInNativeSignInClient({GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? GoogleSignIn();

  GoogleSignInNativeSignInClient.withClientIds({
    required String googleWebClientId,
    required String googleIosClientId,
  }) : _googleSignIn = GoogleSignIn(
         serverClientId: googleWebClientId,
         clientId: googleIosClientId,
       );

  final GoogleSignIn _googleSignIn;

  @override
  Future<GoogleNativeSignInResult?> signIn() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      return null;
    }
    final googleAuth = await googleUser.authentication;
    return GoogleNativeSignInResult(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );
  }
}

/// Maps a Supabase session to the app's [AuthState].
///
/// Shared by [SupabaseAuthRepository] and the auth-state stream provider.
AuthState mapSessionToAuthState(supabase.Session? session) {
  if (session == null) {
    return const AuthState.unauthenticated();
  }
  return AuthState.authenticated(
    userId: session.user.id,
    email: session.user.email ?? '',
  );
}

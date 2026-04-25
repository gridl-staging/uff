import 'dart:async';

import 'package:uff/src/features/auth/data/auth_state.dart';

/// TODO: Document AuthRepository.
abstract interface class AuthRepository {
  Future<AuthState> getCurrentSession();

  /// Returns the current session state synchronously.
  ///
  /// Used by [Auth.build()] to avoid an async gap during initialization.
  /// The Supabase broadcast stream may have already emitted its initial
  /// event before the auth provider is created, so reading the session
  /// synchronously prevents the provider from hanging in AsyncLoading.
  AuthState getCurrentSessionSync();

  Future<AuthState> signIn({required String email, required String password});

  Future<AuthState> signUp({
    required String email,
    required String password,
    required String displayName,
  });

  Future<AuthState> signInWithApple();

  Future<AuthState> signInWithGoogle();

  Future<void> signOut();

  Future<void> updatePassword(String newPassword);

  Future<List<String>> connectedProviders();

  DateTime? memberSince();
}

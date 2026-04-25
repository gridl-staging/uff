import 'dart:async';

import 'package:uff/src/features/notifications/data/notification_token_service.dart';
import 'package:uff/src/features/profile/data/profile_repository.dart';

typedef NotificationRefreshSyncErrorHandler =
    void Function(Object error, StackTrace stackTrace);

/// Coordinates notification permission/token sync with profile persistence.
class NotificationService {
  NotificationService({
    required NotificationTokenService notificationTokenService,
    required ProfileRepository profileRepository,
    NotificationRefreshSyncErrorHandler? onRefreshSyncError,
  }) : _notificationTokenService = notificationTokenService,
       _profileRepository = profileRepository,
       _onRefreshSyncError =
           onRefreshSyncError ?? Zone.current.handleUncaughtError;

  final NotificationTokenService _notificationTokenService;
  final ProfileRepository _profileRepository;
  final NotificationRefreshSyncErrorHandler _onRefreshSyncError;

  StreamSubscription<void>? _tokenRefreshSubscription;
  bool _isDisposed = false;
  int _syncGeneration = 0;

  /// Runs one authenticated sync and starts listening for token refreshes.
  Future<void> syncAuthenticatedSession() async {
    _throwIfDisposed();
    final syncGeneration = _beginNewSyncGeneration();
    await _cancelRefreshSubscription();

    await _notificationTokenService.requestPermission();
    if (!_isActiveSyncGeneration(syncGeneration)) {
      return;
    }

    final token = await _notificationTokenService.getToken();
    if (!_isActiveSyncGeneration(syncGeneration)) {
      return;
    }

    await _profileRepository.updateFcmToken(token);
    if (!_isActiveSyncGeneration(syncGeneration)) {
      return;
    }

    // Route async persistence failures through the subscription error path so
    // callers can observe refresh-sync issues deterministically.
    _tokenRefreshSubscription = _notificationTokenService
        .onTokenRefresh()
        .asyncMap(_profileRepository.updateFcmToken)
        .listen(
          null,
          onError: _onRefreshSyncError,
        );
  }

  /// Stops authenticated sync without writing after auth is gone.
  /// Backend `clearFcmToken` is auth-provider-owned (auth_provider.dart:300).
  Future<void> stopForUnauthenticatedSession() async {
    if (_isDisposed) {
      return;
    }
    _syncGeneration++;
    await _cancelRefreshSubscription();
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _syncGeneration++;
    await _cancelRefreshSubscription();
  }

  Future<void> _cancelRefreshSubscription() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }

  void _throwIfDisposed() {
    if (_isDisposed) {
      throw StateError(
        'NotificationService has been disposed and cannot sync tokens.',
      );
    }
  }

  int _beginNewSyncGeneration() {
    _syncGeneration++;
    return _syncGeneration;
  }

  bool _isActiveSyncGeneration(int syncGeneration) {
    return !_isDisposed && _syncGeneration == syncGeneration;
  }
}

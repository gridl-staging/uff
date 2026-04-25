import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_repository.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart';
import 'package:uff/src/features/photos/data/photo_picker_service.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';
import 'package:uff/src/features/profile/data/profile_repository.dart';
import 'package:uff/src/features/profile/presentation/profile_screen.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/domain/relationship_counts.dart';
import 'package:uff/src/features/profile/presentation/profile_routes.dart';
import 'package:uff/src/features/gear/presentation/gear_routes.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';

import 'package:riverpod/misc.dart' show Override;

import '../../auth/presentation/auth_test_support.dart';

/// TODO: Document FakeProfileRepository.
class FakeProfileRepository implements ProfileRepository {
  Profile? profileToReturn;
  Completer<Profile>? getProfileCompleter;
  int updateProfileCallCount = 0;
  int uploadAvatarCallCount = 0;
  Profile? lastUpdatedProfile;
  Exception? updateProfileException;
  Completer<Profile>? updateProfileCompleter;
  String? lastUploadAvatarUserId;
  Uint8List? lastUploadAvatarBytes;
  String? lastUploadAvatarFileName;
  String uploadAvatarUrlToReturn =
      'https://example.com/user-1/default-avatar.jpg';
  Exception? uploadAvatarException;
  Exception? exportMyDataException;
  Completer<Map<String, dynamic>>? exportMyDataCompleter;

  @override
  Future<Profile> getProfile(String userId) async {
    final pending = getProfileCompleter;
    if (pending != null) {
      return pending.future;
    }
    if (profileToReturn == null) {
      throw StateError('No profile configured');
    }
    return profileToReturn!;
  }

  @override
  Future<Profile> updateProfile(Profile profile) async {
    updateProfileCallCount++;
    lastUpdatedProfile = profile;
    final pendingUpdate = updateProfileCompleter;
    if (pendingUpdate != null) {
      return pendingUpdate.future;
    }
    if (updateProfileException != null) {
      throw updateProfileException!;
    }
    return profile;
  }

  @override
  Future<void> updateFcmToken(String? token) async {}

  @override
  Future<void> clearFcmToken() async {}

  @override
  Future<String> uploadAvatar(
    String userId,
    Uint8List bytes,
    String fileName,
  ) async {
    uploadAvatarCallCount++;
    lastUploadAvatarUserId = userId;
    lastUploadAvatarBytes = bytes;
    lastUploadAvatarFileName = fileName;
    final uploadFailure = uploadAvatarException;
    if (uploadFailure != null) {
      throw uploadFailure;
    }
    return uploadAvatarUrlToReturn;
  }

  int exportMyDataCallCount = 0;
  Map<String, dynamic> exportDataToReturn = const <String, dynamic>{
    'profile': <String, dynamic>{
      'id': 'user-1',
      'display_name': 'Alice',
      'avatar_url': null,
      'preferred_units': 'metric',
      'default_activity_visibility': 'private',
      'terms_accepted_at': '2026-03-15T09:55:00.000Z',
      'terms_version': '1.0',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    },
    'gear': <dynamic>[
      <String, dynamic>{
        'id': 'gear-1',
        'user_id': 'user-1',
        'name': 'Daily Trainer',
        'gear_type': 'shoe',
        'brand': 'Acme',
        'model': 'Velocity',
      },
    ],
    'activities': <dynamic>[
      <String, dynamic>{
        'id': 'activity-1',
        'sport_type': 'run',
        'started_at': '2026-03-15T10:00:00.000Z',
        'finished_at': '2026-03-15T10:30:00.000Z',
        'distance_meters': 5000.0,
        'duration_seconds': 1800,
        'elevation_gain_meters': null,
        'avg_pace_seconds_per_km': null,
        'title': 'Export Test Run',
        'description': null,
        'visibility': 'public',
        'gear_id': 'gear-1',
        'polyline_encoded': null,
        'created_at': '2026-03-15T10:00:00.000Z',
        'updated_at': '2026-03-15T10:30:00.000Z',
        'track_points': <dynamic>[
          <String, dynamic>{
            'activity_id': 'activity-1',
            'timestamp': '2026-03-15T10:00:00.000Z',
            'latitude': 40.7128,
            'longitude': -74.006,
            'distance': 0,
            'speed': 2.6,
          },
          <String, dynamic>{
            'activity_id': 'activity-1',
            'timestamp': '2026-03-15T10:05:00.000Z',
            'latitude': 40.7228,
            'longitude': -74.016,
            'distance': 1000,
            'speed': 3.1,
          },
        ],
        'splits': <dynamic>[
          <String, dynamic>{
            'activity_id': 'activity-1',
            'split_number': 1,
            'distance_meters': 1000.0,
            'duration_seconds': 300,
            'avg_pace_seconds_per_km': 300,
          },
          <String, dynamic>{
            'activity_id': 'activity-1',
            'split_number': 2,
            'distance_meters': 1000.0,
            'duration_seconds': 300,
            'avg_pace_seconds_per_km': 300,
          },
        ],
      },
    ],
    'privacy_zones': <dynamic>[
      <String, dynamic>{
        'id': 'privacy-zone-1',
        'user_id': 'user-1',
        'label': 'Export Test Home',
        'latitude': 40.7128,
        'longitude': -74.006,
        'radius_meters': 200,
      },
    ],
    'storage_objects': <dynamic>[
      <String, dynamic>{
        'bucket': 'avatars',
        'path': 'user-1/export_test_avatar.png',
      },
      <String, dynamic>{
        'bucket': 'activity-photos',
        'path': 'user-1/export_test_photo.jpg',
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> exportMyData() async {
    exportMyDataCallCount++;
    final pendingExport = exportMyDataCompleter;
    if (pendingExport != null) {
      return pendingExport.future;
    }
    if (exportMyDataException != null) {
      throw exportMyDataException!;
    }
    return exportDataToReturn;
  }

  int deleteMyAccountCallCount = 0;
  Exception? deleteMyAccountException;
  Completer<void>? deleteMyAccountCompleter;

  @override
  Future<void> deleteMyAccount() async {
    deleteMyAccountCallCount++;
    final pendingDelete = deleteMyAccountCompleter;
    if (pendingDelete != null) {
      await pendingDelete.future;
      return;
    }
    if (deleteMyAccountException != null) {
      throw deleteMyAccountException!;
    }
  }
}

const testProfile = Profile(
  userId: 'user-1',
  preferredUnits: 'metric',
  defaultActivityVisibility: 'private',
  onboardingCompleted: true,
  displayName: 'Alice',
);

const testProfileImperial = Profile(
  userId: 'user-1',
  preferredUnits: 'imperial',
  defaultActivityVisibility: 'private',
  onboardingCompleted: true,
  displayName: 'Alice',
);

const testProfileWithAvatar = Profile(
  userId: 'user-1',
  preferredUnits: 'metric',
  defaultActivityVisibility: 'private',
  onboardingCompleted: true,
  displayName: 'Alice Runner',
  avatarUrl: 'https://cdn.example.com/avatars/alice.jpg',
);

const defaultRelationshipCounts = RelationshipCounts(
  userId: 'user-1',
  followers: 12,
  following: 8,
  pendingRequests: 3,
);
const profilePopExitRouteText = 'Profile Exit Route';

const _authenticatedAuthState = AuthState.authenticated(
  userId: 'user-1',
  email: 'a@b.com',
);

/// TODO: Document FakePhotoPickerService.
class FakePhotoPickerService extends PhotoPickerService {
  List<PickedPhoto> photosToReturn = const <PickedPhoto>[];
  Object? pickPhotosException;
  int pickPhotosCallCount = 0;
  PhotoPickSource? lastSource;
  int? lastMaxSelection;
  bool? lastOfferCrop;

  @override
  Future<List<PickedPhoto>> pickPhotos({
    required PhotoPickSource source,
    int maxSelection = 20,
    bool offerCrop = false,
  }) async {
    pickPhotosCallCount++;
    lastSource = source;
    lastMaxSelection = maxSelection;
    lastOfferCrop = offerCrop;
    final error = pickPhotosException;
    if (error != null) {
      if (error is Exception) {
        throw error;
      }
      if (error is Error) {
        throw error;
      }
      throw StateError(error.toString());
    }
    return photosToReturn.take(maxSelection).toList(growable: false);
  }
}

FutureOr<RelationshipCounts> _defaultRelationshipCounts(Ref ref) async =>
    defaultRelationshipCounts;

AuthRepository _buildAuthRepository(AuthRepository? authRepo) {
  return authRepo ??
      RecordingAuthRepository(initialState: _authenticatedAuthState);
}

List<TrackingSessionRecord> buildTestSessions({
  int count = 3,
  double distanceMetersEach = 5000.0,
  int? movingTimeSecondsEach,
}) {
  final now = DateTime.now();
  return List.generate(count, (i) {
    final started = now.subtract(Duration(days: i, hours: 1));
    final stopped = now.subtract(Duration(days: i));
    return TrackingSessionRecord(
      id: i + 1,
      status: TrackingSessionStatus.saved,
      createdAt: started,
      updatedAt: stopped,
      startedAt: started,
      stoppedAt: stopped,
      distanceMeters: distanceMetersEach,
      movingTimeSeconds: movingTimeSecondsEach ?? 1800,
      title: 'Run ${i + 1}',
    );
  });
}

List<Override> _buildOverrides({
  required FakeProfileRepository profileRepo,
  AuthRepository? authRepo,
  PhotoPickerService? photoPickerService,
  FutureOr<RelationshipCounts> Function(Ref)? relationshipCounts,
  List<TrackingSessionRecord>? savedSessions,
}) {
  final authRepository = _buildAuthRepository(authRepo);
  return [
    authRepositoryProvider.overrideWithValue(authRepository),
    authStateChangesProvider.overrideWith(
      (ref) => Stream.value(_authenticatedAuthState),
    ),
    profileRepositoryProvider.overrideWithValue(profileRepo),
    if (photoPickerService != null)
      photoPickerServiceProvider.overrideWithValue(photoPickerService),
    relationshipCountsProvider.overrideWith(
      relationshipCounts ?? _defaultRelationshipCounts,
    ),
    savedActivitiesProvider.overrideWith(
      (ref) async => savedSessions ?? const <TrackingSessionRecord>[],
    ),
  ];
}

List<GoRoute> _buildProfileDestinationRoutes() {
  return [
    GoRoute(
      path: GearRoutes.gearPath,
      builder: (_, __) => const Scaffold(body: Text('Gear Target')),
    ),
    GoRoute(
      path: ProfileRoutes.privacyZonesPath,
      builder: (_, __) => const Scaffold(body: Text('Privacy Zones Target')),
    ),
    GoRoute(
      path: SocialRoutes.followersPath,
      builder: (_, __) => const Scaffold(body: Text('Followers Target')),
    ),
    GoRoute(
      path: SocialRoutes.followingPath,
      builder: (_, __) => const Scaffold(body: Text('Following Target')),
    ),
    GoRoute(
      path: SocialRoutes.requestsPath,
      builder: (_, __) => const Scaffold(body: Text('Requests Target')),
    ),
  ];
}

Widget buildProfileTestScope({
  required FakeProfileRepository profileRepo,
  AuthRepository? authRepo,
  PhotoPickerService? photoPickerService,
  FutureOr<RelationshipCounts> Function(Ref)? relationshipCounts,
  List<TrackingSessionRecord>? savedSessions,
}) {
  return ProviderScope(
    overrides: _buildOverrides(
      profileRepo: profileRepo,
      authRepo: authRepo,
      photoPickerService: photoPickerService,
      relationshipCounts: relationshipCounts,
      savedSessions: savedSessions,
    ),
    child: const MaterialApp(home: Scaffold(body: ProfileScreen())),
  );
}

Widget buildProfileRouterTestScope({
  required FakeProfileRepository profileRepo,
  AuthRepository? authRepo,
  PhotoPickerService? photoPickerService,
  FutureOr<RelationshipCounts> Function(Ref)? relationshipCounts,
  List<TrackingSessionRecord>? savedSessions,
}) {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: ProfileScreen()),
      ),
      ..._buildProfileDestinationRoutes(),
    ],
  );
  addTearDown(router.dispose);

  return ProviderScope(
    overrides: _buildOverrides(
      profileRepo: profileRepo,
      authRepo: authRepo,
      photoPickerService: photoPickerService,
      relationshipCounts: relationshipCounts,
      savedSessions: savedSessions,
    ),
    child: MaterialApp.router(routerConfig: router),
  );
}

Widget buildPoppableProfileRouterTestScope({
  required FakeProfileRepository profileRepo,
  AuthRepository? authRepo,
  PhotoPickerService? photoPickerService,
  FutureOr<RelationshipCounts> Function(Ref)? relationshipCounts,
  List<TrackingSessionRecord>? savedSessions,
}) {
  final router = GoRouter(
    initialLocation: '/stack/home/profile',
    routes: [
      GoRoute(
        path: '/stack',
        builder: (_, __) => const Scaffold(body: Text(profilePopExitRouteText)),
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, __, navigationShell) => navigationShell,
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'home/profile',
                    builder: (_, __) => const Scaffold(body: ProfileScreen()),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      ..._buildProfileDestinationRoutes(),
    ],
  );
  addTearDown(router.dispose);

  return ProviderScope(
    overrides: _buildOverrides(
      profileRepo: profileRepo,
      authRepo: authRepo,
      photoPickerService: photoPickerService,
      relationshipCounts: relationshipCounts,
      savedSessions: savedSessions,
    ),
    child: MaterialApp.router(routerConfig: router),
  );
}

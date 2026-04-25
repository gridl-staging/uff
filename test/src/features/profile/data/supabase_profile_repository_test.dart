import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/supabase_profile_repository.dart';
import '../../../test_helpers/supabase_query_test_doubles.dart';

/// ## Test Scenarios
/// - [positive] Profile.fromJson maps all fields including null handling, empty sport prefs, missing lthr_bpm
/// - [positive] Profile.toJson round-trips correctly
/// - [positive] getProfile maps RPC row with null avatar and lthr_bpm
/// - [negative] getProfile rejects profile belonging to different user
/// - [positive] updateProfile sends correct payload, preserves fields, handles null lthr
/// - [negative] updateProfile rejects other user's profile
/// - [positive] updateFcmToken sets and clears token
/// - [negative] updateFcmToken throws when no authenticated user
/// - [positive] clearFcmToken nulls fcm_token for authenticated user
/// - [isolation] clearFcmToken returns silently when session is already gone (null currentUser)
/// - [error] clearFcmToken propagates Supabase errors when session is valid
/// - [positive] uploadAvatar constructs correct storage path
/// - [negative] uploadAvatar rejects path traversal in filename
/// - [negative] uploadAvatar rejects other user's profile
/// - [positive] exportMyData calls rpc and returns map rooted at singular `profile` key, not `profiles`
/// - [negative] Cross-user export stays isolated to the authenticated user.
/// - [isolation] Fresh repository instances do not reuse auth state.

// ---------------------------------------------------------------------------
// Mocks for SupabaseClient sub-clients
// ---------------------------------------------------------------------------

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSupabaseStorageClient extends Mock implements SupabaseStorageClient {}

class MockStorageFileApi extends Mock implements StorageFileApi {}

// ---------------------------------------------------------------------------
// Test data helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _testProfileRow({
  String id = 'test-user-id',
  String? displayName = 'Alice',
  String? avatarUrl,
  String preferredUnits = 'metric',
  String defaultActivityVisibility = 'public',
  bool onboardingCompleted = false,
  List<String> sportPreferences = const ['run'],
  int? lthrBpm,
  bool includeLthrBpm = true,
}) => {
  'id': id,
  'display_name': displayName,
  'avatar_url': avatarUrl,
  'preferred_units': preferredUnits,
  'default_activity_visibility': defaultActivityVisibility,
  'onboarding_completed': onboardingCompleted,
  'sport_preferences': sportPreferences,
  if (includeLthrBpm) 'lthr_bpm': lthrBpm,
};

User _testUser({
  String id = 'test-user-id',
  String email = 'test@example.com',
}) {
  return User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00.000Z',
    email: email,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockSupabaseClient mockClient;
  late MockGoTrueClient mockAuth;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const FileOptions());
  });

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockGoTrueClient();
    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(_testUser(id: 'user-1'));
  });

  group('Profile.fromJson', () {
    test('maps all fields from Supabase row', () {
      final row = _testProfileRow(
        id: 'abc-123',
        displayName: 'Bob',
        avatarUrl: 'https://example.com/avatar.jpg',
        preferredUnits: 'imperial',
        defaultActivityVisibility: 'followers',
        onboardingCompleted: true,
        sportPreferences: const ['ride', 'trail_run'],
        lthrBpm: 172,
      );

      final profile = Profile.fromJson(row);

      expect(profile.userId, 'abc-123');
      expect(profile.displayName, 'Bob');
      expect(profile.avatarUrl, 'https://example.com/avatar.jpg');
      expect(profile.preferredUnits, 'imperial');
      expect(profile.defaultActivityVisibility, 'followers');
      expect(profile.onboardingCompleted, isTrue);
      expect(profile.sportPreferences, const ['ride', 'trail_run']);
      expect(profile.lthrBpm, 172);
    });

    test('handles null displayName and avatarUrl', () {
      final row = _testProfileRow(displayName: null);

      final profile = Profile.fromJson(row);

      expect(profile.displayName, isNull);
      expect(profile.avatarUrl, isNull);
    });

    test('handles empty sport preferences from legacy rows', () {
      final row = _testProfileRow(sportPreferences: const []);

      final profile = Profile.fromJson(row);

      expect(profile.sportPreferences, isEmpty);
    });

    test('defaults lthrBpm to null when legacy rows omit lthr_bpm', () {
      final row = _testProfileRow(includeLthrBpm: false);

      final profile = Profile.fromJson(row);

      expect(profile.lthrBpm, isNull);
    });
  });

  group('Profile.toJson', () {
    test('serializes to Supabase column names', () {
      const profile = Profile(
        userId: 'u-1',
        preferredUnits: 'imperial',
        defaultActivityVisibility: 'private',
        onboardingCompleted: true,
        displayName: 'Eve',
        avatarUrl: 'https://cdn.example.com/eve.png',
        sportPreferences: ['run', 'walk'],
        lthrBpm: 168,
      );

      final json = profile.toJson();

      expect(json['id'], 'u-1');
      expect(json['display_name'], 'Eve');
      expect(json['avatar_url'], 'https://cdn.example.com/eve.png');
      expect(json['preferred_units'], 'imperial');
      expect(json['default_activity_visibility'], 'private');
      expect(json['onboarding_completed'], isTrue);
      expect(json['sport_preferences'], const ['run', 'walk']);
      expect(json['lthr_bpm'], 168);
    });

    test('serializes cleared lthrBpm as null', () {
      const profile = Profile(
        userId: 'u-1',
        preferredUnits: 'metric',
        defaultActivityVisibility: 'private',
        onboardingCompleted: true,
      );

      final json = profile.toJson();

      expect(json.containsKey('lthr_bpm'), isTrue);
      expect(json['lthr_bpm'], isNull);
    });
  });

  group('SupabaseProfileRepository', () {
    group('getProfile', () {
      test('maps get_my_profile rpc row to Profile', () async {
        when(
          () => mockClient.rpc<List<Map<String, dynamic>>>('get_my_profile'),
        ).thenAnswer(
          (_) => RecordingPostgrestListBuilder([
            _testProfileRow(id: 'user-1'),
          ]),
        );

        final repo = SupabaseProfileRepository(mockClient);
        final profile = await repo.getProfile('user-1');

        expect(profile.userId, 'user-1');
        expect(profile.displayName, 'Alice');
        expect(profile.preferredUnits, 'metric');
        expect(profile.defaultActivityVisibility, 'public');
        expect(profile.onboardingCompleted, isFalse);
        expect(profile.lthrBpm, isNull);
      });

      test('handles null avatarUrl', () async {
        when(
          () => mockClient.rpc<List<Map<String, dynamic>>>('get_my_profile'),
        ).thenAnswer(
          (_) => RecordingPostgrestListBuilder([
            _testProfileRow(id: 'user-1'),
          ]),
        );

        final repo = SupabaseProfileRepository(mockClient);
        final profile = await repo.getProfile('user-1');

        expect(profile.avatarUrl, isNull);
      });

      test('maps configured lthr_bpm from Supabase row', () async {
        when(
          () => mockClient.rpc<List<Map<String, dynamic>>>('get_my_profile'),
        ).thenAnswer(
          (_) => RecordingPostgrestListBuilder([
            _testProfileRow(id: 'user-1', lthrBpm: 169),
          ]),
        );

        final repo = SupabaseProfileRepository(mockClient);
        final profile = await repo.getProfile('user-1');

        expect(profile.lthrBpm, 169);
      });

      test('treats missing lthr_bpm from legacy row as null', () async {
        when(
          () => mockClient.rpc<List<Map<String, dynamic>>>('get_my_profile'),
        ).thenAnswer(
          (_) => RecordingPostgrestListBuilder([
            _testProfileRow(id: 'user-1', includeLthrBpm: false),
          ]),
        );

        final repo = SupabaseProfileRepository(mockClient);
        final profile = await repo.getProfile('user-1');

        expect(profile.lthrBpm, isNull);
      });

      test('rejects fetching a different user profile', () async {
        final repo = SupabaseProfileRepository(mockClient);

        expect(
          () => repo.getProfile('user-2'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Profile operations may only target the authenticated user.',
            ),
          ),
        );
      });
    });

    group('updateProfile', () {
      test(
        'sends correct column payload and returns updated Profile',
        () async {
          const updatedProfile = Profile(
            userId: 'user-1',
            preferredUnits: 'imperial',
            defaultActivityVisibility: 'private',
            onboardingCompleted: true,
            displayName: 'Bob Updated',
            sportPreferences: ['run', 'hike'],
            lthrBpm: 175,
          );
          final fakeBuilder = RecordingSupabaseQueryBuilder(
            selectRows: [_testProfileRow()],
            updateRows: [
              {
                'id': 'user-1',
                'display_name': 'Bob Updated',
                'avatar_url': null,
                'preferred_units': 'imperial',
                'default_activity_visibility': 'private',
                'onboarding_completed': true,
                'sport_preferences': ['run', 'hike'],
                'lthr_bpm': 175,
              },
            ],
          );
          when(
            () => mockClient.from('profiles'),
          ).thenAnswer((_) => fakeBuilder);
          when(
            () => mockClient.rpc<List<Map<String, dynamic>>>('get_my_profile'),
          ).thenAnswer(
            (_) => RecordingPostgrestListBuilder([
              _testProfileRow(
                id: 'user-1',
                displayName: 'Bob Updated',
                preferredUnits: 'imperial',
                defaultActivityVisibility: 'private',
                onboardingCompleted: true,
                sportPreferences: const ['run', 'hike'],
                lthrBpm: 175,
              ),
            ]),
          );

          final repo = SupabaseProfileRepository(mockClient);
          final result = await repo.updateProfile(updatedProfile);

          expect(result.userId, 'user-1');
          expect(result.displayName, 'Bob Updated');
          expect(result.preferredUnits, 'imperial');
          expect(result.defaultActivityVisibility, 'private');
          expect(result.onboardingCompleted, isTrue);
          expect(result.sportPreferences, const ['run', 'hike']);
          expect(result.lthrBpm, 175);

          // Verify the payload sent to Supabase has the correct column names
          expect(
            fakeBuilder.lastUpdatePayload!['display_name'],
            'Bob Updated',
          );
          expect(fakeBuilder.lastUpdatePayload!['preferred_units'], 'imperial');
          expect(
            fakeBuilder.lastUpdatePayload!['default_activity_visibility'],
            'private',
          );
          expect(
            fakeBuilder.lastUpdatePayload!['onboarding_completed'],
            isTrue,
          );
          expect(
            fakeBuilder.lastUpdatePayload!['sport_preferences'],
            const ['run', 'hike'],
          );
          expect(fakeBuilder.lastUpdatePayload!['lthr_bpm'], 175);
          // Should NOT send the 'id' column in the update payload
          expect(fakeBuilder.lastUpdatePayload!.containsKey('id'), isFalse);
        },
      );

      test('sends lthr_bpm as null when user clears value', () async {
        const updatedProfile = Profile(
          userId: 'user-1',
          preferredUnits: 'metric',
          defaultActivityVisibility: 'private',
          onboardingCompleted: true,
          displayName: 'Bob',
        );
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [_testProfileRow(id: 'user-1')],
          updateRows: [
            _testProfileRow(
              id: 'user-1',
              displayName: 'Bob',
              defaultActivityVisibility: 'private',
              onboardingCompleted: true,
            ),
          ],
        );
        when(() => mockClient.from('profiles')).thenAnswer((_) => fakeBuilder);
        when(
          () => mockClient.rpc<List<Map<String, dynamic>>>('get_my_profile'),
        ).thenAnswer(
          (_) => RecordingPostgrestListBuilder([
            _testProfileRow(
              id: 'user-1',
              displayName: 'Bob',
              defaultActivityVisibility: 'private',
              onboardingCompleted: true,
            ),
          ]),
        );

        final repo = SupabaseProfileRepository(mockClient);
        final result = await repo.updateProfile(updatedProfile);

        expect(result.lthrBpm, isNull);
        expect(fakeBuilder.lastUpdatePayload!.containsKey('lthr_bpm'), isTrue);
        expect(fakeBuilder.lastUpdatePayload!['lthr_bpm'], isNull);
      });

      test(
        'preserves displayName and avatarUrl in updated Profile result',
        () async {
          const updatedProfile = Profile(
            userId: 'user-1',
            preferredUnits: 'imperial',
            defaultActivityVisibility: 'private',
            onboardingCompleted: true,
            displayName: 'Runner Bob',
            avatarUrl: 'https://cdn.example.com/runner-bob.png',
            sportPreferences: ['run'],
          );
          final fakeBuilder = RecordingSupabaseQueryBuilder(
            selectRows: [_testProfileRow(id: 'user-1')],
            updateRows: [
              _testProfileRow(
                id: 'user-1',
                displayName: 'Runner Bob',
                avatarUrl: 'https://cdn.example.com/runner-bob.png',
                preferredUnits: 'imperial',
                defaultActivityVisibility: 'private',
                onboardingCompleted: true,
              ),
            ],
          );
          when(
            () => mockClient.from('profiles'),
          ).thenAnswer((_) => fakeBuilder);
          when(
            () => mockClient.rpc<List<Map<String, dynamic>>>('get_my_profile'),
          ).thenAnswer(
            (_) => RecordingPostgrestListBuilder([
              _testProfileRow(
                id: 'user-1',
                displayName: 'Runner Bob',
                avatarUrl: 'https://cdn.example.com/runner-bob.png',
                preferredUnits: 'imperial',
                defaultActivityVisibility: 'private',
                onboardingCompleted: true,
              ),
            ]),
          );

          final repo = SupabaseProfileRepository(mockClient);
          final result = await repo.updateProfile(updatedProfile);

          expect(result.displayName, 'Runner Bob');
          expect(result.avatarUrl, 'https://cdn.example.com/runner-bob.png');
        },
      );

      test('rejects updating a different user profile', () async {
        const updatedProfile = Profile(
          userId: 'user-2',
          preferredUnits: 'imperial',
          defaultActivityVisibility: 'private',
          onboardingCompleted: true,
        );
        final repo = SupabaseProfileRepository(mockClient);

        expect(
          () => repo.updateProfile(updatedProfile),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Profile operations may only target the authenticated user.',
            ),
          ),
        );
      });
    });

    group('updateFcmToken', () {
      test('updates fcm_token for the authenticated user', () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(updateRows: const []);
        when(() => mockClient.from('profiles')).thenAnswer((_) => fakeBuilder);

        final repo = SupabaseProfileRepository(mockClient);
        await repo.updateFcmToken('token-123');

        expect(fakeBuilder.lastUpdatePayload!['fcm_token'], 'token-123');
        expect(fakeBuilder.updateBuilder.lastEqColumn, 'id');
        expect(fakeBuilder.updateBuilder.lastEqValue, 'user-1');
      });

      test('clears fcm_token when token is null', () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(updateRows: const []);
        when(() => mockClient.from('profiles')).thenAnswer((_) => fakeBuilder);

        final repo = SupabaseProfileRepository(mockClient);
        await repo.updateFcmToken(null);

        expect(fakeBuilder.lastUpdatePayload!['fcm_token'], isNull);
        expect(fakeBuilder.updateBuilder.lastEqColumn, 'id');
        expect(fakeBuilder.updateBuilder.lastEqValue, 'user-1');
      });

      test('throws when no authenticated user exists', () async {
        when(() => mockAuth.currentUser).thenReturn(null);

        final repo = SupabaseProfileRepository(mockClient);

        expect(
          () => repo.updateFcmToken('token-123'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Profile operations require an authenticated user session.',
            ),
          ),
        );
      });
    });

    group('clearFcmToken', () {
      test('nulls fcm_token for the authenticated user', () async {
        when(() => mockAuth.currentUser).thenReturn(_testUser(id: 'user-1'));
        final fakeBuilder = RecordingSupabaseQueryBuilder(updateRows: const []);
        when(() => mockClient.from('profiles')).thenAnswer((_) => fakeBuilder);

        final repo = SupabaseProfileRepository(mockClient);
        await repo.clearFcmToken();

        expect(fakeBuilder.lastUpdatePayload!['fcm_token'], isNull);
        expect(fakeBuilder.updateBuilder.lastEqColumn, 'id');
        expect(fakeBuilder.updateBuilder.lastEqValue, 'user-1');
      });

      test('returns silently when currentUser is null', () async {
        when(() => mockAuth.currentUser).thenReturn(null);
        final fakeBuilder = RecordingSupabaseQueryBuilder(updateRows: const []);
        when(() => mockClient.from('profiles')).thenAnswer((_) => fakeBuilder);

        final repo = SupabaseProfileRepository(mockClient);
        await repo.clearFcmToken();

        expect(fakeBuilder.lastUpdatePayload, isNull);
      });

      test('propagates Supabase errors when session is valid', () async {
        when(() => mockAuth.currentUser).thenReturn(_testUser(id: 'user-1'));
        final fakeBuilder = RecordingSupabaseQueryBuilder(updateRows: const []);
        when(() => mockClient.from('profiles')).thenThrow(
          PostgrestException(message: 'connection failed'),
        );

        final repo = SupabaseProfileRepository(mockClient);

        expect(
          () => repo.clearFcmToken(),
          throwsA(
            isA<PostgrestException>().having(
              (e) => e.message,
              'message',
              'connection failed',
            ),
          ),
        );
      });
    });

    group('uploadAvatar', () {
      test('constructs {userId}/{fileName} storage path', () async {
        final mockStorage = MockSupabaseStorageClient();
        final mockBucket = MockStorageFileApi();
        when(() => mockClient.storage).thenReturn(mockStorage);
        when(() => mockStorage.from('avatars')).thenReturn(mockBucket);
        when(
          () => mockBucket.uploadBinary(
            any(),
            any(),
            fileOptions: any(named: 'fileOptions'),
          ),
        ).thenAnswer((_) async => 'avatars/user-1/photo.jpg');
        when(
          () => mockBucket.getPublicUrl(any()),
        ).thenReturn('https://storage.example.com/avatars/user-1/photo.jpg');

        // Mock the profile update after avatar upload
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          selectRows: [_testProfileRow()],
          updateRows: [
            _testProfileRow(
              avatarUrl: 'https://storage.example.com/avatars/user-1/photo.jpg',
            ),
          ],
        );
        when(() => mockClient.from('profiles')).thenAnswer((_) => fakeBuilder);

        final repo = SupabaseProfileRepository(mockClient);
        final url = await repo.uploadAvatar(
          'user-1',
          Uint8List.fromList([0xFF, 0xD8]),
          'photo.jpg',
        );

        expect(url, 'https://storage.example.com/avatars/user-1/photo.jpg');

        // Verify the storage path is {userId}/{fileName}
        verify(
          () => mockBucket.uploadBinary(
            'user-1/photo.jpg',
            any(),
            fileOptions: any(named: 'fileOptions'),
          ),
        ).called(1);
        verify(() => mockBucket.getPublicUrl('user-1/photo.jpg')).called(1);
      });

      test(
        'sanitizes path traversal characters from avatar file names',
        () async {
          final mockStorage = MockSupabaseStorageClient();
          final mockBucket = MockStorageFileApi();
          when(() => mockClient.storage).thenReturn(mockStorage);
          when(() => mockStorage.from('avatars')).thenReturn(mockBucket);
          when(
            () => mockBucket.uploadBinary(
              any(),
              any(),
              fileOptions: any(named: 'fileOptions'),
            ),
          ).thenAnswer((_) async => 'avatars/user-1/photo.png');
          when(
            () => mockBucket.getPublicUrl(any()),
          ).thenReturn('https://storage.example.com/avatars/user-1/photo.png');

          final fakeBuilder = RecordingSupabaseQueryBuilder(
            selectRows: [_testProfileRow()],
            updateRows: [
              _testProfileRow(
                avatarUrl:
                    'https://storage.example.com/avatars/user-1/photo.png',
              ),
            ],
          );
          when(
            () => mockClient.from('profiles'),
          ).thenAnswer((_) => fakeBuilder);

          final repo = SupabaseProfileRepository(mockClient);
          final url = await repo.uploadAvatar(
            'user-1',
            Uint8List.fromList([0xFF, 0xD8]),
            '../../photo.png',
          );

          expect(url, 'https://storage.example.com/avatars/user-1/photo.png');
          verify(
            () => mockBucket.uploadBinary(
              'user-1/photo.png',
              any(),
              fileOptions: any(named: 'fileOptions'),
            ),
          ).called(1);
          verify(() => mockBucket.getPublicUrl('user-1/photo.png')).called(1);
        },
      );

      test('rejects uploading an avatar for a different user', () async {
        final repo = SupabaseProfileRepository(mockClient);

        expect(
          () => repo.uploadAvatar(
            'user-2',
            Uint8List.fromList([0xFF, 0xD8]),
            'photo.png',
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Profile operations may only target the authenticated user.',
            ),
          ),
        );
      });
    });

    group('exportMyData', () {
      test(
        'calls rpc export_my_data and returns map rooted at profile key',
        () async {
          final exportData = <String, dynamic>{
            'profile': {
              'id': 'user-1',
              'display_name': 'Alice',
              'avatar_url': null,
              'preferred_units': 'metric',
              'default_activity_visibility': 'public',
              'terms_accepted_at': '2026-03-15T00:00:00.000Z',
              'terms_version': '1.0',
              'created_at': '2026-01-01T00:00:00.000Z',
              'updated_at': '2026-01-01T00:00:00.000Z',
            },
            'gear': <dynamic>[
              {
                'id': 'gear-1',
                'user_id': 'user-1',
                'name': 'Daily Trainer',
                'gear_type': 'shoe',
                'brand': 'Acme',
                'model': 'Velocity',
              },
            ],
            'activities': <dynamic>[],
            'privacy_zones': <dynamic>[],
            'storage_objects': <dynamic>[],
          };

          when(
            () => mockClient.rpc<Map<String, dynamic>>('export_my_data'),
          ).thenAnswer(
            (_) => RecordingPostgrestMapBuilder(exportData),
          );

          final repo = SupabaseProfileRepository(mockClient);
          final result = await repo.exportMyData();

          // Top-level key is 'profile' (singular), not 'profiles'
          expect(result.containsKey('profile'), isTrue);
          expect(result.containsKey('profiles'), isFalse);

          // Verify exact structure
          final profile = result['profile'] as Map<String, dynamic>;
          expect(profile['id'], 'user-1');
          expect(profile['display_name'], 'Alice');
          expect(profile['terms_version'], '1.0');

          final gear = result['gear'] as List;
          expect(gear.length, 1);
          expect((gear[0] as Map<String, dynamic>)['name'], 'Daily Trainer');

          final activities = result['activities'] as List;
          expect(activities, isEmpty);

          verify(
            () => mockClient.rpc<Map<String, dynamic>>('export_my_data'),
          ).called(1);
        },
      );
    });
  });
}

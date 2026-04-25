import 'package:flutter_test/flutter_test.dart';

import 'supabase_smoke_helpers.dart';

/// ## Test Scenarios
/// - [positive] Populated user export returns exact seeded profile, gear, activities with nested track_points/splits, privacy_zones, and storage_objects
/// - [negative] Cross-user isolation: second user export contains none of first user's data
/// - [isolation] Empty user with no seeded data returns profile object and empty arrays
void main() {
  group('export_my_data smoke test', skip: skipReason, () {
    late SmokeTestUser owner;
    late SmokeTestUser otherUser;

    setUp(() async {
      owner = await createSignedInTestUser(displayName: 'Export Owner');
      otherUser = await createSignedInTestUser(displayName: 'Export Other');
    });

    tearDown(() async {
      await cleanupSmokeTestUsers([owner, otherUser]);
    });

    test(
      'populated user export returns exact seeded data across all sections',
      () async {
        // Seed consent
        final seededTermsAcceptedAt = DateTime.utc(2026, 3, 15, 9, 55, 0);
        await seedConsentForCurrentUser(
          owner.client,
          termsVersion: '1.0',
          termsAcceptedAt: seededTermsAcceptedAt,
        );

        // Seed gear
        final gearId = await seedGearForCurrentUser(
          owner.client,
          name: 'Export Test Shoe',
          gearType: 'shoe',
          brand: 'TestBrand',
          model: 'TestModel',
        );

        // Seed activity with track points and splits
        final activityStarted = DateTime.utc(2026, 3, 15, 10, 0, 0);
        final activityId = await seedActivityForCurrentUser(
          owner.client,
          visibility: 'public',
          startedAt: activityStarted,
          finishedAt: activityStarted.add(const Duration(minutes: 30)),
          distanceMeters: 5000,
          durationSeconds: 1800,
          title: 'Export Test Run',
        );

        await seedTrackPointsForActivity(
          owner.client,
          activityId: activityId,
          startedAt: activityStarted,
        );

        await seedSplitsForActivity(
          owner.client,
          activityId: activityId,
          splitCount: 2,
          splitDistanceMeters: 1000,
          splitDurationSeconds: 300,
        );

        // Seed privacy zone
        await seedPrivacyZoneForCurrentUser(
          owner.client,
          label: 'Export Test Home',
          latitude: 40.7128,
          longitude: -74.0060,
          radiusMeters: 200,
        );

        // Seed storage objects
        await seedStorageObjectForCurrentUser(
          owner.client,
          bucket: 'avatars',
          fileName: 'export_test_avatar.png',
        );
        await seedStorageObjectForCurrentUser(
          owner.client,
          bucket: 'activity-photos',
          fileName: 'export_test_photo.jpg',
        );

        // Call export_my_data RPC
        final export = await owner.client.rpc<Map<String, dynamic>>(
          'export_my_data',
        );

        // Verify top-level keys
        expect(export.containsKey('profile'), isTrue);
        expect(export.containsKey('gear'), isTrue);
        expect(export.containsKey('activities'), isTrue);
        expect(export.containsKey('privacy_zones'), isTrue);
        expect(export.containsKey('storage_objects'), isTrue);

        // Verify profile section (singular object, not array)
        final profile = export['profile'] as Map<String, dynamic>;
        expect(profile['id'], owner.userId);
        expect(profile['display_name'], 'Export Owner');
        expect(profile['terms_version'], '1.0');
        expect(
          DateTime.parse(profile['terms_accepted_at'] as String).toUtc(),
          seededTermsAcceptedAt,
        );

        // Verify gear section
        final gear = export['gear'] as List;
        expect(gear.length, 1);
        final gearItem = gear[0] as Map<String, dynamic>;
        expect(gearItem['id'], gearId);
        expect(gearItem['user_id'], owner.userId);
        expect(gearItem['name'], 'Export Test Shoe');
        expect(gearItem['gear_type'], 'shoe');
        expect(gearItem['brand'], 'TestBrand');
        expect(gearItem['model'], 'TestModel');

        // Verify activities section
        final activities = export['activities'] as List;
        expect(activities.length, 1);
        final activity = activities[0] as Map<String, dynamic>;
        expect(activity['id'], activityId);
        expect(activity['sport_type'], 'run');
        expect(activity['title'], 'Export Test Run');
        expect(activity['visibility'], 'public');
        expect(
          (activity['distance_meters'] as num).toDouble(),
          closeTo(5000, 0.1),
        );
        expect(activity['duration_seconds'], 1800);

        // Verify nested track_points in activities
        final trackPoints = activity['track_points'] as List;
        expect(trackPoints.length, 2);
        final firstPoint = trackPoints[0] as Map<String, dynamic>;
        expect(
          (firstPoint['latitude'] as num).toDouble(),
          closeTo(40.7128, 0.001),
        );
        expect(
          (firstPoint['longitude'] as num).toDouble(),
          closeTo(-74.006, 0.001),
        );

        // Verify nested splits in activities
        final splits = activity['splits'] as List;
        expect(splits.length, 2);
        final firstSplit = splits[0] as Map<String, dynamic>;
        expect(firstSplit['split_number'], 1);
        expect(
          (firstSplit['distance_meters'] as num).toDouble(),
          closeTo(1000, 0.1),
        );
        expect(firstSplit['duration_seconds'], 300);

        // Verify privacy zones
        final privacyZones = export['privacy_zones'] as List;
        expect(privacyZones.length, 1);
        final zone = privacyZones[0] as Map<String, dynamic>;
        expect(zone['user_id'], owner.userId);
        expect(zone['label'], 'Export Test Home');
        expect(zone['radius_meters'], 200);

        // Verify storage objects
        final storageObjects = export['storage_objects'] as List;
        expect(storageObjects.length, 2);
        final exportedStorageObjects = storageObjects
            .cast<Map<String, dynamic>>()
            .map(
              (storageObject) =>
                  '${storageObject['bucket']}:${storageObject['path']}',
            )
            .toList();
        expect(
          exportedStorageObjects,
          unorderedEquals([
            'avatars:${owner.userId}/export_test_avatar.png',
            'activity-photos:${owner.userId}/export_test_photo.jpg',
          ]),
        );
      },
    );

    test(
      'cross-user isolation: second user sees none of first user data',
      () async {
        // Seed data only for owner
        await seedConsentForCurrentUser(
          owner.client,
          termsVersion: '1.0',
        );
        await seedGearForCurrentUser(
          owner.client,
          name: 'Owner Only Shoe',
        );
        final activityId = await seedActivityForCurrentUser(
          owner.client,
          visibility: 'public',
          title: 'Owner Only Run',
        );
        await seedTrackPointsForActivity(
          owner.client,
          activityId: activityId,
        );
        await seedSplitsForActivity(
          owner.client,
          activityId: activityId,
        );
        await seedPrivacyZoneForCurrentUser(
          owner.client,
          label: 'Owner Only Zone',
        );
        await seedStorageObjectForCurrentUser(
          owner.client,
          bucket: 'avatars',
          fileName: 'owner_avatar.png',
        );

        // Export as the other user (who has no seeded data)
        final otherExport = await otherUser.client.rpc<Map<String, dynamic>>(
          'export_my_data',
        );

        // Other user should have their own profile but no owner data
        final otherProfile = otherExport['profile'] as Map<String, dynamic>;
        expect(otherProfile['id'], otherUser.userId);
        expect(otherProfile['display_name'], 'Export Other');

        final otherGear = otherExport['gear'] as List;
        expect(otherGear, isEmpty);

        final otherActivities = otherExport['activities'] as List;
        expect(otherActivities, isEmpty);

        final otherZones = otherExport['privacy_zones'] as List;
        expect(otherZones, isEmpty);

        final otherStorage = otherExport['storage_objects'] as List;
        expect(otherStorage, isEmpty);
      },
    );

    test(
      'empty user with no seeded data returns profile and empty arrays',
      () async {
        // Create a fresh user with no additional data seeded
        final emptyUser = await createSignedInTestUser(
          displayName: 'Empty Export User',
        );

        try {
          final export = await emptyUser.client.rpc<Map<String, dynamic>>(
            'export_my_data',
          );

          // Profile should exist (created by auth trigger)
          final profile = export['profile'] as Map<String, dynamic>;
          expect(profile['id'], emptyUser.userId);
          expect(profile['display_name'], 'Empty Export User');

          // All collection sections should be empty arrays
          final gear = export['gear'] as List;
          expect(gear, isEmpty);

          final activities = export['activities'] as List;
          expect(activities, isEmpty);

          final privacyZones = export['privacy_zones'] as List;
          expect(privacyZones, isEmpty);

          final storageObjects = export['storage_objects'] as List;
          expect(storageObjects, isEmpty);

          // Consent fields should be null (no consent row)
          expect(profile['terms_accepted_at'], isNull);
          expect(profile['terms_version'], isNull);
        } finally {
          await cleanupSmokeTestUsers([emptyUser]);
        }
      },
    );
  });
}

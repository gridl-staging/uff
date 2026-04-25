import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/clubs/data/supabase_club_repository.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/domain/club_member.dart';
import 'package:uff/src/features/clubs/domain/club_sport_type.dart';

// ## Test Scenarios
// - [positive] Mapper helpers translate Supabase rows into immutable Club, ClubMember, and ClubRun values.
// - [negative] Missing or null joined profile payload maps to null identity fields.
// - [isolation] Joined profile mapping reads only the current row payload for each member.
// - [edge] Mapper helpers handle optional joined-profile payload shapes without throwing.
Map<String, dynamic> _clubRow({
  String id = 'club-1',
  String name = 'Downtown Run Club',
  String? description = 'Tuesday tempo group',
  String? avatarUrl = 'https://cdn.example.com/clubs/1.png',
  String? city = 'Boston',
  String? stateRegion = 'MA',
  String? country = 'US',
  double? locationLat = 42.3601,
  double? locationLng = -71.0589,
  String source = 'user_created',
  String? sourceUrl,
  String? sourceId,
  String? creatorId = 'user-1',
  String? claimedBy,
  String visibility = 'public',
  int memberCount = 12,
  String createdAt = '2026-03-01T10:00:00.000Z',
  String updatedAt = '2026-03-02T10:00:00.000Z',
  String? sportType,
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'description': description,
  'avatar_url': avatarUrl,
  'city': city,
  'state_region': stateRegion,
  'country': country,
  'location_lat': locationLat,
  'location_lng': locationLng,
  'source': source,
  'source_url': sourceUrl,
  'source_id': sourceId,
  'creator_id': creatorId,
  'claimed_by': claimedBy,
  'visibility': visibility,
  'member_count': memberCount,
  'created_at': createdAt,
  'updated_at': updatedAt,
  'sport_type': sportType,
};

Map<String, dynamic> _clubMemberRow({
  String id = 'member-1',
  String clubId = 'club-1',
  String userId = 'user-1',
  String role = 'member',
  String status = 'active',
  String joinedAt = '2026-03-03T09:00:00.000Z',
  String? displayName = 'Runner One',
  String? avatarUrl = 'https://cdn.example.com/profiles/runner-one.png',
}) => <String, dynamic>{
  'id': id,
  'club_id': clubId,
  'user_id': userId,
  'role': role,
  'status': status,
  'joined_at': joinedAt,
  'profiles': <String, dynamic>{
    'display_name': displayName,
    'avatar_url': avatarUrl,
  },
};

Map<String, dynamic> _clubRunRow({
  String id = 'run-1',
  String clubId = 'club-1',
  String title = 'Thursday Hills',
  String? description = 'Warmup then hill repeats',
  String scheduledAt = '2026-04-02T10:30:00.000Z',
  double? meetingPointLat = 40.7128,
  double? meetingPointLng = -74.006,
  String? meetingPointName = 'Prospect Park Main Gate',
  double? distanceMeters = 10000,
  String? paceDescription = 'Easy to moderate',
  String createdBy = 'user-1',
  String createdAt = '2026-03-20T10:30:00.000Z',
  String updatedAt = '2026-03-20T11:30:00.000Z',
}) => <String, dynamic>{
  'id': id,
  'club_id': clubId,
  'title': title,
  'description': description,
  'scheduled_at': scheduledAt,
  'meeting_point_lat': meetingPointLat,
  'meeting_point_lng': meetingPointLng,
  'meeting_point_name': meetingPointName,
  'distance_meters': distanceMeters,
  'pace_description': paceDescription,
  'created_by': createdBy,
  'created_at': createdAt,
  'updated_at': updatedAt,
};

void main() {
  group('row mappers', () {
    test('clubFromJson maps schema columns to Club fields', () {
      final club = clubFromJson(
        _clubRow(
          source: 'auto_discovered',
          visibility: 'private',
          sourceUrl: 'https://example.com/scraped',
          sourceId: 'source-1',
          claimedBy: 'claim-1',
        ),
      );

      expect(club.id, 'club-1');
      expect(club.source, ClubSource.autoDiscovered);
      expect(club.visibility, ClubVisibility.private);
      expect(club.sourceUrl, 'https://example.com/scraped');
      expect(club.sourceId, 'source-1');
      expect(club.claimedBy, 'claim-1');
    });

    test('clubFromJson parses known sport_type into ClubSportType enum', () {
      final club = clubFromJson(_clubRow(sportType: 'running'));
      expect(club.sportType, ClubSportType.running);
    });

    test(
      'clubFromJson returns null sportType for unknown sport_type value',
      () {
        final club = clubFromJson(_clubRow(sportType: 'skiing'));
        expect(club.sportType, isNull);
      },
    );

    test('clubFromJson returns null sportType when sport_type is null', () {
      final club = clubFromJson(_clubRow());
      expect(club.sportType, isNull);
    });

    test(
      'clubMemberFromJson maps role/status timestamps and joined profile fields',
      () {
        final member = clubMemberFromJson(
          _clubMemberRow(role: 'organizer', status: 'pending'),
        );

        expect(member.id, 'member-1');
        expect(member.role, ClubMemberRole.organizer);
        expect(member.status, ClubMemberStatus.pending);
        expect(member.joinedAt, DateTime.parse('2026-03-03T09:00:00.000Z'));
        expect(member.displayName, 'Runner One');
        expect(
          member.avatarUrl,
          'https://cdn.example.com/profiles/runner-one.png',
        );
      },
    );

    test(
      'clubMemberFromJson maps missing and null joined profile payloads to null profile fields',
      () {
        final missingProfiles = _clubMemberRow()..remove('profiles');
        final nullProfiles = _clubMemberRow()..['profiles'] = null;

        final memberWithMissingProfiles = clubMemberFromJson(missingProfiles);
        final memberWithNullProfiles = clubMemberFromJson(nullProfiles);

        expect(memberWithMissingProfiles.displayName, isNull);
        expect(memberWithMissingProfiles.avatarUrl, isNull);
        expect(memberWithNullProfiles.displayName, isNull);
        expect(memberWithNullProfiles.avatarUrl, isNull);
      },
    );

    test('clubMemberFromJson accepts list-shaped joined profile payloads', () {
      final listShapedProfile = _clubMemberRow()
        ..['profiles'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'display_name': 'List Joined Runner',
            'avatar_url': 'https://cdn.example.com/profiles/list-runner.png',
          },
        ];

      final member = clubMemberFromJson(listShapedProfile);

      expect(member.displayName, 'List Joined Runner');
      expect(
        member.avatarUrl,
        'https://cdn.example.com/profiles/list-runner.png',
      );
    });

    test('clubRunFromJson maps nullable and required event fields', () {
      final run = clubRunFromJson(_clubRunRow());

      expect(run.id, 'run-1');
      expect(run.title, 'Thursday Hills');
      expect(run.scheduledAt, DateTime.parse('2026-04-02T10:30:00.000Z'));
      expect(run.meetingPointName, 'Prospect Park Main Gate');
      expect(run.distanceMeters, 10000);
    });
  });
}

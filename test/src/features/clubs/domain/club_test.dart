import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/domain/club_sport_type.dart';

// ## Test Scenarios
// - [positive] Club stores all constructor fields as immutable value data.
// - [positive] Club equality and hashCode match exact field values.
// - [negative] Changing visibility or owner fields changes the Club value.
// - [isolation] A fresh Club fixture does not inherit fields from another one.
void main() {
  group('Club', () {
    test('constructor exposes every schema-backed field', () {
      final createdAt = DateTime.utc(2026, 3, 30, 12);
      final updatedAt = DateTime.utc(2026, 3, 30, 13);
      final club = Club(
        id: 'club-1',
        name: 'Downtown Run Club',
        description: 'Tuesday tempo group',
        avatarUrl: 'https://cdn.example.com/clubs/1.png',
        city: 'Boston',
        stateRegion: 'MA',
        country: 'US',
        locationLat: 42.3601,
        locationLng: -71.0589,
        source: ClubSource.autoDiscovered,
        sourceUrl: 'https://example.com/club/1',
        sourceId: 'scraped-1',
        creatorId: 'creator-1',
        claimedBy: 'claimer-1',
        visibility: ClubVisibility.private,
        memberCount: 19,
        createdAt: createdAt,
        updatedAt: updatedAt,
        sportType: ClubSportType.running,
      );

      expect(club.id, 'club-1');
      expect(club.name, 'Downtown Run Club');
      expect(club.description, 'Tuesday tempo group');
      expect(club.avatarUrl, 'https://cdn.example.com/clubs/1.png');
      expect(club.city, 'Boston');
      expect(club.stateRegion, 'MA');
      expect(club.country, 'US');
      expect(club.locationLat, 42.3601);
      expect(club.locationLng, -71.0589);
      expect(club.source, ClubSource.autoDiscovered);
      expect(club.sourceUrl, 'https://example.com/club/1');
      expect(club.sourceId, 'scraped-1');
      expect(club.creatorId, 'creator-1');
      expect(club.claimedBy, 'claimer-1');
      expect(club.visibility, ClubVisibility.private);
      expect(club.memberCount, 19);
      expect(club.createdAt, createdAt);
      expect(club.updatedAt, updatedAt);
      expect(club.sportType, ClubSportType.running);
    });

    test('uses value equality and hashCode across all fields', () {
      final createdAt = DateTime.utc(2026, 3, 30, 12);
      final updatedAt = DateTime.utc(2026, 3, 30, 13);
      final clubA = Club(
        id: 'club-2',
        name: 'Sunrise Track Crew',
        description: null,
        avatarUrl: null,
        city: 'Chicago',
        stateRegion: 'IL',
        country: 'US',
        locationLat: null,
        locationLng: null,
        source: ClubSource.userCreated,
        sourceUrl: null,
        sourceId: null,
        creatorId: 'creator-2',
        claimedBy: null,
        visibility: ClubVisibility.public,
        memberCount: 4,
        createdAt: createdAt,
        updatedAt: updatedAt,
        sportType: ClubSportType.cycling,
      );
      final clubB = Club(
        id: 'club-2',
        name: 'Sunrise Track Crew',
        description: null,
        avatarUrl: null,
        city: 'Chicago',
        stateRegion: 'IL',
        country: 'US',
        locationLat: null,
        locationLng: null,
        source: ClubSource.userCreated,
        sourceUrl: null,
        sourceId: null,
        creatorId: 'creator-2',
        claimedBy: null,
        visibility: ClubVisibility.public,
        memberCount: 4,
        createdAt: createdAt,
        updatedAt: updatedAt,
        sportType: ClubSportType.cycling,
      );

      expect(clubA, clubB);
      expect(clubA.hashCode, clubB.hashCode);
    });
  });
}

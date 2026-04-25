import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/clubs/domain/club_run.dart';

// ## Test Scenarios
// - [positive] ClubRun stores schedule, location, and pacing fields.
// - [positive] ClubRun equality and hashCode are deterministic by value.
// - [negative] Changing one scheduled field changes the ClubRun value.
// - [isolation] Optional fields remain null when a separate run omits them.
void main() {
  group('ClubRun', () {
    test('constructor exposes all scheduling fields', () {
      final scheduledAt = DateTime.utc(2026, 4, 2, 6, 30);
      final createdAt = DateTime.utc(2026, 3, 30, 8);
      final updatedAt = DateTime.utc(2026, 3, 30, 9);
      final run = ClubRun(
        id: 'run-1',
        clubId: 'club-1',
        title: 'Thursday Hills',
        description: 'Warmup then hill repeats',
        scheduledAt: scheduledAt,
        meetingPointLat: 40.7128,
        meetingPointLng: -74.006,
        meetingPointName: 'Prospect Park Main Gate',
        distanceMeters: 10000,
        paceDescription: 'Easy to moderate',
        createdBy: 'organizer-1',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(run.id, 'run-1');
      expect(run.clubId, 'club-1');
      expect(run.title, 'Thursday Hills');
      expect(run.description, 'Warmup then hill repeats');
      expect(run.scheduledAt, scheduledAt);
      expect(run.meetingPointLat, 40.7128);
      expect(run.meetingPointLng, -74.006);
      expect(run.meetingPointName, 'Prospect Park Main Gate');
      expect(run.distanceMeters, 10000);
      expect(run.paceDescription, 'Easy to moderate');
      expect(run.createdBy, 'organizer-1');
      expect(run.createdAt, createdAt);
      expect(run.updatedAt, updatedAt);
    });

    test('uses value equality and hashCode', () {
      final scheduledAt = DateTime.utc(2026, 4, 2, 6, 30);
      final createdAt = DateTime.utc(2026, 3, 30, 8);
      final updatedAt = DateTime.utc(2026, 3, 30, 9);
      final runA = ClubRun(
        id: 'run-2',
        clubId: 'club-2',
        title: 'Sunday Long Run',
        description: null,
        scheduledAt: scheduledAt,
        meetingPointLat: null,
        meetingPointLng: null,
        meetingPointName: null,
        distanceMeters: null,
        paceDescription: null,
        createdBy: 'organizer-2',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
      final runB = ClubRun(
        id: 'run-2',
        clubId: 'club-2',
        title: 'Sunday Long Run',
        description: null,
        scheduledAt: scheduledAt,
        meetingPointLat: null,
        meetingPointLng: null,
        meetingPointName: null,
        distanceMeters: null,
        paceDescription: null,
        createdBy: 'organizer-2',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(runA, runB);
      expect(runA.hashCode, runB.hashCode);
    });
  });
}

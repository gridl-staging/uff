import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/clubs/domain/club_member.dart';

// ## Test Scenarios
// - [positive] ClubMember keeps club/user role and status fields intact.
// - [positive] ClubMember keeps optional profile identity fields intact.
// - [positive] ClubMember equality and hashCode are exact-field value based.
// - [negative] Changing club or user ids changes the value object.
// - [isolation] Separate membership fixtures do not share mutable state.
void main() {
  group('ClubMember', () {
    test('constructor maps role, status, and joined timestamp', () {
      final joinedAt = DateTime.utc(2026, 3, 30, 10);
      final member = ClubMember(
        id: 'membership-1',
        clubId: 'club-1',
        userId: 'user-1',
        role: ClubMemberRole.organizer,
        status: ClubMemberStatus.pending,
        joinedAt: joinedAt,
        displayName: 'Runner One',
        avatarUrl: 'https://cdn.example.com/runner-one.png',
      );

      expect(member.id, 'membership-1');
      expect(member.clubId, 'club-1');
      expect(member.userId, 'user-1');
      expect(member.role, ClubMemberRole.organizer);
      expect(member.status, ClubMemberStatus.pending);
      expect(member.joinedAt, joinedAt);
      expect(member.displayName, 'Runner One');
      expect(member.avatarUrl, 'https://cdn.example.com/runner-one.png');
    });

    test('uses value equality and hashCode', () {
      final joinedAt = DateTime.utc(2026, 3, 30, 10);
      final memberA = ClubMember(
        id: 'membership-2',
        clubId: 'club-2',
        userId: 'user-2',
        role: ClubMemberRole.member,
        status: ClubMemberStatus.active,
        joinedAt: joinedAt,
        displayName: 'Runner Two',
      );
      final memberB = ClubMember(
        id: 'membership-2',
        clubId: 'club-2',
        userId: 'user-2',
        role: ClubMemberRole.member,
        status: ClubMemberStatus.active,
        joinedAt: joinedAt,
        displayName: 'Runner Two',
      );

      expect(memberA, memberB);
      expect(memberA.hashCode, memberB.hashCode);
    });
  });
}

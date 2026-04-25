import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/clubs/domain/club_member.dart';
import 'package:uff/src/features/clubs/presentation/club_detail_screen.dart';

import '../data/fake_club_repository.dart';
import 'club_detail_test_helpers.dart';

// ## Test Scenarios
// - [negative] User switch removes admin-only controls from the previous viewer.
// - [isolation] Auth changes update membership and admin controls without stale state.

void main() {
  testWidgets('[isolation] auth changes update membership and admin controls', (
    tester,
  ) async {
    final repository = RecordingClubRepository();
    final authNotifier = MutableAuthNotifier(authenticatedState(testUserId));

    await tester.pumpWidget(
      buildClubDetailTestAppWithAuthNotifier(
        repository: repository,
        club: makeClub(creatorId: testUserId),
        authNotifier: authNotifier,
        members: [
          makeClubMember(
            id: 'm1',
            userId: testUserId,
            role: ClubMemberRole.admin,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(ClubDetailScreen.overflowMenuButtonKey), findsOneWidget);
    expect(find.byKey(ClubDetailScreen.adminSectionKey), findsOneWidget);

    authNotifier.setAuthState(authenticatedState(testUserB));
    await tester.pumpAndSettle();

    expect(find.byKey(ClubDetailScreen.joinButtonKey), findsOneWidget);
    expect(find.byKey(ClubDetailScreen.overflowMenuButtonKey), findsNothing);
    expect(find.byKey(ClubDetailScreen.adminSectionKey), findsNothing);
  });
}

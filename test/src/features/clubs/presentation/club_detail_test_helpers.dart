import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/clubs/application/club_providers.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/domain/club_member.dart';
import 'package:uff/src/features/clubs/domain/club_run.dart';
import 'package:uff/src/features/clubs/domain/club_sport_type.dart';
import 'package:uff/src/features/clubs/presentation/club_detail_screen.dart';

import '../../activity_tracking/presentation/activity_detail_screen_test_support.dart';
import '../data/fake_club_repository.dart';

const testUserId = 'user-a-id';
const testUserB = 'user-b-id';
const testClubId = 'club-1';
final testNow = DateTime(2026, 3, 30);

Override authenticatedUserOverride({String userId = testUserId}) {
  return authProvider.overrideWith(
    () => FakeAuthNotifier(
      AuthState.authenticated(userId: userId, email: '$userId@test.com'),
    ),
  );
}

Override authNotifierOverride(Auth notifier) {
  return authProvider.overrideWith(() => notifier);
}

AuthState authenticatedState(String userId) {
  return AuthState.authenticated(userId: userId, email: '$userId@test.com');
}

class MutableAuthNotifier extends Auth {
  MutableAuthNotifier(this._initialState);

  final AuthState _initialState;

  @override
  FutureOr<AuthState> build() => _initialState;

  void setAuthState(AuthState nextState) {
    state = AsyncData(nextState);
  }
}

Club makeClub({
  String id = testClubId,
  String name = 'Portland Runners',
  String? description = 'A friendly running club',
  String? city = 'Portland',
  int memberCount = 42,
  ClubSource source = ClubSource.userCreated,
  String? creatorId = 'creator-id',
  String? claimedBy,
  ClubVisibility visibility = ClubVisibility.public,
  ClubSportType? sportType,
}) {
  return Club(
    id: id,
    name: name,
    description: description,
    avatarUrl: null,
    city: city,
    stateRegion: 'OR',
    country: 'US',
    locationLat: null,
    locationLng: null,
    source: source,
    sourceUrl: null,
    sourceId: null,
    creatorId: creatorId,
    claimedBy: claimedBy,
    visibility: visibility,
    memberCount: memberCount,
    createdAt: testNow,
    updatedAt: testNow,
    sportType: sportType,
  );
}

ClubMember makeClubMember({
  required String id,
  required String userId,
  String clubId = testClubId,
  ClubMemberRole role = ClubMemberRole.member,
  ClubMemberStatus status = ClubMemberStatus.active,
  String? displayName,
  String? avatarUrl,
}) {
  return ClubMember(
    id: id,
    clubId: clubId,
    userId: userId,
    role: role,
    status: status,
    joinedAt: testNow,
    displayName: displayName,
    avatarUrl: avatarUrl,
  );
}

ClubRun makeClubRun({
  required String id,
  required String title,
  String clubId = testClubId,
}) {
  return ClubRun(
    id: id,
    clubId: clubId,
    title: title,
    description: null,
    scheduledAt: testNow.add(const Duration(days: 1)),
    meetingPointLat: null,
    meetingPointLng: null,
    meetingPointName: null,
    distanceMeters: 5000,
    paceDescription: null,
    createdBy: 'creator-id',
    createdAt: testNow,
    updatedAt: testNow,
  );
}

/// Builds a test widget with ClubDetailScreen and provider overrides.
Widget buildClubDetailTestApp({
  required RecordingClubRepository repository,
  required Club club,
  List<ClubMember> members = const [],
  List<ClubRun> runs = const [],
  String currentUserId = testUserId,
}) {
  return ProviderScope(
    overrides: [
      clubRepositoryProvider.overrideWithValue(repository),
      clubDetailProvider(club.id).overrideWith((ref) => Future.value(club)),
      clubMembersProvider(club.id).overrideWith((ref) => Future.value(members)),
      upcomingClubRunsProvider(
        club.id,
      ).overrideWith((ref) => Future.value(runs)),
      authenticatedUserOverride(userId: currentUserId),
    ],
    child: MaterialApp(home: ClubDetailScreen(clubId: club.id)),
  );
}

Widget buildClubDetailTestAppWithAuthNotifier({
  required RecordingClubRepository repository,
  required Club club,
  required MutableAuthNotifier authNotifier,
  List<ClubMember> members = const [],
  List<ClubRun> runs = const [],
}) {
  return ProviderScope(
    overrides: [
      clubRepositoryProvider.overrideWithValue(repository),
      clubDetailProvider(club.id).overrideWith((ref) => Future.value(club)),
      clubMembersProvider(club.id).overrideWith((ref) => Future.value(members)),
      upcomingClubRunsProvider(
        club.id,
      ).overrideWith((ref) => Future.value(runs)),
      authNotifierOverride(authNotifier),
    ],
    child: MaterialApp(home: ClubDetailScreen(clubId: club.id)),
  );
}

/// Builds a routed test app with ClubDetailScreen and provider overrides.
Widget buildClubDetailRoutedTestApp({
  required RecordingClubRepository repository,
  required Club club,
  required GoRouter router,
  List<ClubMember> members = const [],
  List<ClubRun> runs = const [],
  String currentUserId = testUserId,
}) {
  return ProviderScope(
    overrides: [
      clubRepositoryProvider.overrideWithValue(repository),
      clubDetailProvider(club.id).overrideWith((ref) => Future.value(club)),
      clubMembersProvider(club.id).overrideWith((ref) => Future.value(members)),
      upcomingClubRunsProvider(
        club.id,
      ).overrideWith((ref) => Future.value(runs)),
      authenticatedUserOverride(userId: currentUserId),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Builds a switcher app that hosts two clubs for isolation tests.
Widget buildClubDetailSwitcherTestApp({
  required RecordingClubRepository repository,
  required Club initialClub,
  required Club alternateClub,
  String currentUserId = testUserId,
}) {
  return ProviderScope(
    overrides: [
      clubRepositoryProvider.overrideWithValue(repository),
      clubDetailProvider(
        initialClub.id,
      ).overrideWith((ref) => Future.value(initialClub)),
      clubMembersProvider(
        initialClub.id,
      ).overrideWith((ref) => Future.value(<ClubMember>[])),
      upcomingClubRunsProvider(
        initialClub.id,
      ).overrideWith((ref) => Future.value(<ClubRun>[])),
      clubDetailProvider(
        alternateClub.id,
      ).overrideWith((ref) => Future.value(alternateClub)),
      clubMembersProvider(
        alternateClub.id,
      ).overrideWith((ref) => Future.value(<ClubMember>[])),
      upcomingClubRunsProvider(
        alternateClub.id,
      ).overrideWith((ref) => Future.value(<ClubRun>[])),
      authenticatedUserOverride(userId: currentUserId),
    ],
    child: MaterialApp(
      home: ClubDetailSwitcher(
        initialClubId: initialClub.id,
        alternateClubId: alternateClub.id,
      ),
    ),
  );
}

/// Allows switching between two club IDs to test state isolation.
class ClubDetailSwitcher extends StatefulWidget {
  const ClubDetailSwitcher({
    required this.initialClubId,
    required this.alternateClubId,
    super.key,
  });
  final String initialClubId;
  final String alternateClubId;

  @override
  State<ClubDetailSwitcher> createState() => _ClubDetailSwitcherState();
}

/// TODO: Document _ClubDetailSwitcherState.
class _ClubDetailSwitcherState extends State<ClubDetailSwitcher> {
  late String _clubId;

  @override
  void initState() {
    super.initState();
    _clubId = widget.initialClubId;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          key: const Key('switch_club_button'),
          onPressed: () {
            setState(() {
              _clubId = _clubId == widget.initialClubId
                  ? widget.alternateClubId
                  : widget.initialClubId;
            });
          },
          child: const Text('Switch'),
        ),
        Expanded(child: ClubDetailScreen(clubId: _clubId)),
      ],
    );
  }
}

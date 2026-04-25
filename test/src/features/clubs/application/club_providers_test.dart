import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/clubs/application/club_location_service.dart';
import 'package:uff/src/features/clubs/application/club_providers.dart';
import 'package:uff/src/features/clubs/data/club_repository.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/domain/club_member.dart';
import 'package:uff/src/features/clubs/domain/club_run.dart';

import '../data/fake_club_repository.dart';

// ## Test Scenarios
// - [positive] Read providers route directly through the club repository seam with exact values.
// - [positive] `myClubs` returns `getMyClubs()` verbatim so Stage 2 membership filtering stays in the repository.
// - [positive] `nearbyClubs` sorts by ascending distance when location is available and keeps repository order when unavailable.
// - [edge] `clubSearch` trims whitespace and short-circuits empty queries without hitting the repository.
// - [negative] Read providers surface repository errors instead of masking failures.
// - [isolation] Nearby and run providers invalidate independently by provider key.
final _clubA = Club(
  id: 'club-a',
  name: 'Downtown Run Club',
  description: 'Tuesday tempo',
  avatarUrl: null,
  city: 'Boston',
  stateRegion: 'MA',
  country: 'US',
  locationLat: 42.36,
  locationLng: -71.05,
  source: ClubSource.userCreated,
  sourceUrl: null,
  sourceId: null,
  creatorId: 'user-a',
  claimedBy: null,
  visibility: ClubVisibility.public,
  memberCount: 12,
  createdAt: DateTime.utc(2026, 3, 30, 10),
  updatedAt: DateTime.utc(2026, 3, 30, 11),
  sportType: null,
);

final _clubB = Club(
  id: 'club-b',
  name: 'Bridge Runners',
  description: null,
  avatarUrl: 'https://cdn.example.com/club-b.png',
  city: 'New York',
  stateRegion: 'NY',
  country: 'US',
  locationLat: 40.71,
  locationLng: -74,
  source: ClubSource.autoDiscovered,
  sourceUrl: 'https://example.com/club-b',
  sourceId: 'source-b',
  creatorId: null,
  claimedBy: null,
  visibility: ClubVisibility.public,
  memberCount: 41,
  createdAt: DateTime.utc(2026, 3, 1, 9),
  updatedAt: DateTime.utc(2026, 3, 2, 9),
  sportType: null,
);

final _memberA = ClubMember(
  id: 'member-a',
  clubId: 'club-a',
  userId: 'user-a',
  role: ClubMemberRole.admin,
  status: ClubMemberStatus.active,
  joinedAt: DateTime.utc(2026, 3, 15, 7),
);

final _runA = ClubRun(
  id: 'run-a',
  clubId: 'club-a',
  title: 'Thursday Hills',
  description: '6x2 min hills',
  scheduledAt: DateTime.utc(2026, 4, 4, 13),
  meetingPointLat: 42.37,
  meetingPointLng: -71.06,
  meetingPointName: 'Park Gate',
  distanceMeters: 9000,
  paceDescription: 'Easy to steady',
  createdBy: 'user-a',
  createdAt: DateTime.utc(2026, 3, 30, 8),
  updatedAt: DateTime.utc(2026, 3, 30, 8),
);

class FakeClubLocationService implements ClubLocationService {
  const FakeClubLocationService(this.location);

  final ClubCoordinates? location;

  @override
  Future<ClubCoordinates?> fetchCurrentLocation() async {
    return location;
  }
}

ProviderContainer _createContainer(
  RecordingClubRepository repository, {
  ClubLocationService? locationService,
}) {
  final container = ProviderContainer(
    overrides: [
      clubRepositoryProvider.overrideWithValue(repository),
      if (locationService != null)
        clubLocationServiceProvider.overrideWithValue(locationService),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void _listenClubEntityReads(
  ProviderContainer container, {
  required String clubId,
  required String activeSearchQuery,
}) {
  final myClubsSubscription = container.listen(myClubsProvider, (_, __) {});
  final detailSubscription = container.listen(
    clubDetailProvider(clubId),
    (_, __) {},
  );
  final membersSubscription = container.listen(
    clubMembersProvider(clubId),
    (_, __) {},
  );
  final nearbySubscription = container.listen(nearbyClubsProvider, (_, __) {});
  final searchSubscription = container.listen(
    clubSearchProvider(activeSearchQuery),
    (_, __) {},
  );
  addTearDown(myClubsSubscription.close);
  addTearDown(detailSubscription.close);
  addTearDown(membersSubscription.close);
  addTearDown(nearbySubscription.close);
  addTearDown(searchSubscription.close);
}

Future<void> _primeClubEntityReads(
  ProviderContainer container, {
  required String clubId,
  required String activeSearchQuery,
}) async {
  await container.read(myClubsProvider.future);
  await container.read(clubDetailProvider(clubId).future);
  await container.read(clubMembersProvider(clubId).future);
  await container.read(nearbyClubsProvider.future);
  await container.read(clubSearchProvider(activeSearchQuery).future);
}

void _expectSuccessTransition(List<AsyncValue<void>> states) {
  expect(states, hasLength(3));
  expect(states[0], const AsyncData<void>(null));
  expect(states[1].isLoading, isTrue);
  expect(states[1].hasError, isFalse);
  expect(states[2], const AsyncData<void>(null));
}

void _expectErrorTransition(
  List<AsyncValue<void>> states, {
  required Object expectedError,
}) {
  expect(states, hasLength(3));
  expect(states[0], const AsyncData<void>(null));
  expect(states[1].isLoading, isTrue);
  expect(states[1].hasError, isFalse);
  expect(states[2].hasError, isTrue);
  expect(states[2].error, same(expectedError));
}

void main() {
  group('clubs read providers', () {
    test('clubRepositoryProvider supports repository override', () {
      final repository = RecordingClubRepository();
      final container = _createContainer(repository);

      final resolved = container.read(clubRepositoryProvider);

      expect(resolved, same(repository));
    });

    test('myClubsProvider returns getMyClubs() verbatim', () async {
      final repository = RecordingClubRepository()
        ..myClubsToReturn = <Club>[_clubA, _clubB];
      final container = _createContainer(repository);

      final clubs = await container.read(myClubsProvider.future);

      expect(clubs, <Club>[_clubA, _clubB]);
      expect(repository.getMyClubsCallCount, 1);
    });

    test('clubDetailProvider loads one club by id', () async {
      final repository = RecordingClubRepository()..clubToReturn = _clubA;
      final container = _createContainer(repository);

      final club = await container.read(clubDetailProvider('club-a').future);

      expect(club, _clubA);
      expect(repository.getClubCallCount, 1);
      expect(repository.lastClubId, 'club-a');
    });

    test('clubMembersProvider returns exact members list', () async {
      final repository = RecordingClubRepository()
        ..clubMembersToReturn = <ClubMember>[_memberA];
      final container = _createContainer(repository);

      final members = await container.read(
        clubMembersProvider('club-a').future,
      );

      expect(members, <ClubMember>[_memberA]);
      expect(repository.getClubMembersCallCount, 1);
      expect(repository.lastMembersClubId, 'club-a');
    });

    test('clubSearchProvider trims empty query and short-circuits', () async {
      final repository = RecordingClubRepository()
        ..clubsToReturn = <Club>[_clubA];
      final container = _createContainer(repository);

      final clubs = await container.read(clubSearchProvider('   ').future);

      expect(clubs, <Club>[]);
      expect(repository.searchClubsCallCount, 0);
    });

    test(
      'clubSearchProvider forwards normalized query to repository',
      () async {
        final repository = RecordingClubRepository()
          ..clubsToReturn = <Club>[_clubB];
        final container = _createContainer(repository);

        final clubs = await container.read(
          clubSearchProvider(' bridge ').future,
        );

        expect(clubs, <Club>[_clubB]);
        expect(repository.searchClubsCallCount, 1);
        expect(repository.lastSearchQuery, 'bridge');
      },
    );

    test(
      'nearbyClubsProvider sorts by distance when location available and keeps repository order when denied',
      () async {
        final portlandClub = Club(
          id: 'club-portland',
          name: 'Portland Running Co.',
          description: null,
          avatarUrl: null,
          city: 'Portland',
          stateRegion: 'OR',
          country: 'US',
          locationLat: 45.5231,
          locationLng: -122.6765,
          source: ClubSource.autoDiscovered,
          sourceUrl: null,
          sourceId: 'rrca:portland-running-co',
          creatorId: null,
          claimedBy: null,
          visibility: ClubVisibility.public,
          memberCount: 10,
          createdAt: DateTime.utc(2026, 3, 30, 11),
          updatedAt: DateTime.utc(2026, 3, 30, 11),
          sportType: null,
        );
        final seattleClub = Club(
          id: 'club-seattle',
          name: 'Seattle Striders',
          description: null,
          avatarUrl: null,
          city: 'Seattle',
          stateRegion: 'WA',
          country: 'US',
          locationLat: 47.6062,
          locationLng: -122.3321,
          source: ClubSource.autoDiscovered,
          sourceUrl: null,
          sourceId: 'rrca:seattle-striders',
          creatorId: null,
          claimedBy: null,
          visibility: ClubVisibility.public,
          memberCount: 25,
          createdAt: DateTime.utc(2026, 3, 30, 11),
          updatedAt: DateTime.utc(2026, 3, 30, 11),
          sportType: null,
        );
        final newYorkClub = Club(
          id: 'club-nyc',
          name: 'NYC Flyers',
          description: null,
          avatarUrl: null,
          city: 'New York',
          stateRegion: 'NY',
          country: 'US',
          locationLat: 40.7128,
          locationLng: -74.006,
          source: ClubSource.autoDiscovered,
          sourceUrl: null,
          sourceId: 'rrca:nyc-flyers',
          creatorId: null,
          claimedBy: null,
          visibility: ClubVisibility.public,
          memberCount: 40,
          createdAt: DateTime.utc(2026, 3, 30, 11),
          updatedAt: DateTime.utc(2026, 3, 30, 11),
          sportType: null,
        );
        final noLocationClub = Club(
          id: 'club-unknown',
          name: 'No Location Club',
          description: null,
          avatarUrl: null,
          city: 'Unknown',
          stateRegion: null,
          country: 'US',
          locationLat: null,
          locationLng: null,
          source: ClubSource.autoDiscovered,
          sourceUrl: null,
          sourceId: 'rrca:no-location-club',
          creatorId: null,
          claimedBy: null,
          visibility: ClubVisibility.public,
          memberCount: 100,
          createdAt: DateTime.utc(2026, 3, 30, 11),
          updatedAt: DateTime.utc(2026, 3, 30, 11),
          sportType: null,
        );
        final repositoryOrder = <Club>[
          noLocationClub,
          newYorkClub,
          seattleClub,
          portlandClub,
        ];

        final repositoryWithLocation = RecordingClubRepository()
          ..clubsToReturn = repositoryOrder;
        final containerWithLocation = _createContainer(
          repositoryWithLocation,
          locationService: const FakeClubLocationService(
            ClubCoordinates(latitude: 45.52, longitude: -122.68),
          ),
        );

        final sortedByDistance = await containerWithLocation.read(
          nearbyClubsProvider.future,
        );

        expect(
          sortedByDistance.map((club) => club.id).toList(),
          <String>[
            'club-portland',
            'club-seattle',
            'club-nyc',
            'club-unknown',
          ],
        );
        expect(repositoryWithLocation.listClubsCallCount, 1);

        final repositoryDeniedLocation = RecordingClubRepository()
          ..clubsToReturn = repositoryOrder;
        final containerDeniedLocation = _createContainer(
          repositoryDeniedLocation,
          locationService: const FakeClubLocationService(null),
        );

        final unchangedOrder = await containerDeniedLocation.read(
          nearbyClubsProvider.future,
        );

        expect(unchangedOrder, repositoryOrder);
        expect(repositoryDeniedLocation.listClubsCallCount, 1);
      },
    );

    test('upcomingClubRunsProvider returns exact run list', () async {
      final repository = RecordingClubRepository()
        ..upcomingRunsToReturn = <ClubRun>[_runA];
      final container = _createContainer(repository);

      final runs = await container.read(
        upcomingClubRunsProvider('club-a').future,
      );

      expect(runs, <ClubRun>[_runA]);
      expect(repository.getUpcomingRunsCallCount, 1);
      expect(repository.lastUpcomingRunsClubId, 'club-a');
    });

    test('clubDetailProvider propagates repository errors', () async {
      final repository = RecordingClubRepository()
        ..getClubError = StateError('club detail failed');
      final container = _createContainer(repository);

      await expectLater(
        container.read(clubDetailProvider('club-a').future),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('club detail failed'),
          ),
        ),
      );
    });
  });

  group('club mutation controller', () {
    const activeSearchQuery = 'bridge';
    const targetClubId = 'club-a';

    test(
      'createClub routes payload, reports loading to success, and invalidates club entity caches',
      () async {
        final repository = RecordingClubRepository()
          ..clubsToReturn = <Club>[_clubA]
          ..myClubsToReturn = <Club>[_clubA]
          ..clubToReturn = _clubA
          ..clubMembersToReturn = <ClubMember>[_memberA]
          ..createdClubToReturn = _clubA;
        final container = _createContainer(repository);
        _listenClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );
        await _primeClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );

        expect(repository.getMyClubsCallCount, 1);
        expect(repository.getClubCallCount, 1);
        expect(repository.getClubMembersCallCount, 1);
        expect(repository.listClubsCallCount, 1);
        expect(repository.searchClubsCallCount, 1);

        final states = <AsyncValue<void>>[];
        final mutationStateSubscription = container.listen(
          clubMutationControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );
        addTearDown(mutationStateSubscription.close);

        const createInput = CreateClubInput(
          name: 'South End Pacers',
          description: 'Evening intervals',
          city: 'Boston',
          stateRegion: 'MA',
          country: 'US',
          locationLat: 42.34,
          locationLng: -71.07,
          visibility: ClubVisibility.private,
        );

        await container
            .read(clubMutationControllerProvider.notifier)
            .createClub(createInput);

        _expectSuccessTransition(states);
        expect(repository.createClubCallCount, 1);
        expect(repository.lastCreateClubInput?.name, 'South End Pacers');
        expect(
          repository.lastCreateClubInput?.description,
          'Evening intervals',
        );
        expect(repository.lastCreateClubInput?.city, 'Boston');
        expect(repository.lastCreateClubInput?.stateRegion, 'MA');
        expect(repository.lastCreateClubInput?.country, 'US');
        expect(repository.lastCreateClubInput?.locationLat, 42.34);
        expect(repository.lastCreateClubInput?.locationLng, -71.07);
        expect(
          repository.lastCreateClubInput?.visibility,
          ClubVisibility.private,
        );

        await _primeClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );

        expect(repository.getMyClubsCallCount, 2);
        expect(repository.getClubCallCount, 2);
        expect(repository.getClubMembersCallCount, 2);
        expect(repository.listClubsCallCount, 2);
        expect(repository.searchClubsCallCount, 2);
      },
    );

    test(
      'joinClub routes club id, reports loading to success, and invalidates club entity caches',
      () async {
        final repository = RecordingClubRepository()
          ..clubsToReturn = <Club>[_clubA]
          ..myClubsToReturn = <Club>[_clubA]
          ..clubToReturn = _clubA
          ..clubMembersToReturn = <ClubMember>[_memberA];
        final container = _createContainer(repository);
        _listenClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );
        await _primeClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );

        final states = <AsyncValue<void>>[];
        final mutationStateSubscription = container.listen(
          clubMutationControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );
        addTearDown(mutationStateSubscription.close);

        await container
            .read(clubMutationControllerProvider.notifier)
            .joinClub(targetClubId);

        _expectSuccessTransition(states);
        expect(repository.joinClubCallCount, 1);
        expect(repository.lastJoinedClubId, targetClubId);

        await _primeClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );

        expect(repository.getMyClubsCallCount, 2);
        expect(repository.getClubCallCount, 2);
        expect(repository.getClubMembersCallCount, 2);
        expect(repository.listClubsCallCount, 2);
        expect(repository.searchClubsCallCount, 2);
      },
    );

    test(
      'leaveClub routes club id, reports loading to success, and invalidates club entity caches',
      () async {
        final repository = RecordingClubRepository()
          ..clubsToReturn = <Club>[_clubA]
          ..myClubsToReturn = <Club>[_clubA]
          ..clubToReturn = _clubA
          ..clubMembersToReturn = <ClubMember>[_memberA];
        final container = _createContainer(repository);
        _listenClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );
        await _primeClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );

        final states = <AsyncValue<void>>[];
        final mutationStateSubscription = container.listen(
          clubMutationControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );
        addTearDown(mutationStateSubscription.close);

        await container
            .read(clubMutationControllerProvider.notifier)
            .leaveClub(targetClubId);

        _expectSuccessTransition(states);
        expect(repository.leaveClubCallCount, 1);
        expect(repository.lastLeftClubId, targetClubId);

        await _primeClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );

        expect(repository.getMyClubsCallCount, 2);
        expect(repository.getClubCallCount, 2);
        expect(repository.getClubMembersCallCount, 2);
        expect(repository.listClubsCallCount, 2);
        expect(repository.searchClubsCallCount, 2);
      },
    );

    test(
      'updateClub routes club payload, reports loading to success, and invalidates club entity caches',
      () async {
        final repository = RecordingClubRepository()
          ..clubsToReturn = <Club>[_clubA]
          ..myClubsToReturn = <Club>[_clubA]
          ..clubToReturn = _clubA
          ..clubMembersToReturn = <ClubMember>[_memberA];
        final container = _createContainer(repository);
        _listenClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );
        await _primeClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );

        final states = <AsyncValue<void>>[];
        final mutationStateSubscription = container.listen(
          clubMutationControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );
        addTearDown(mutationStateSubscription.close);

        final updatedClub = Club(
          id: _clubA.id,
          name: 'Downtown Run Club Updated',
          description: _clubA.description,
          avatarUrl: _clubA.avatarUrl,
          city: _clubA.city,
          stateRegion: _clubA.stateRegion,
          country: _clubA.country,
          locationLat: _clubA.locationLat,
          locationLng: _clubA.locationLng,
          source: _clubA.source,
          sourceUrl: _clubA.sourceUrl,
          sourceId: _clubA.sourceId,
          creatorId: _clubA.creatorId,
          claimedBy: _clubA.claimedBy,
          visibility: _clubA.visibility,
          memberCount: _clubA.memberCount,
          createdAt: _clubA.createdAt,
          updatedAt: _clubA.updatedAt,
          sportType: null,
        );

        await container
            .read(clubMutationControllerProvider.notifier)
            .updateClub(updatedClub);

        _expectSuccessTransition(states);
        expect(repository.updateClubCallCount, 1);
        expect(repository.lastUpdatedClub, updatedClub);

        await _primeClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );

        expect(repository.getMyClubsCallCount, 2);
        expect(repository.getClubCallCount, 2);
        expect(repository.getClubMembersCallCount, 2);
        expect(repository.listClubsCallCount, 2);
        expect(repository.searchClubsCallCount, 2);
      },
    );

    test(
      'deleteClub routes club id, reports loading to success, and invalidates club entity caches',
      () async {
        final repository = RecordingClubRepository()
          ..clubsToReturn = <Club>[_clubA]
          ..myClubsToReturn = <Club>[_clubA]
          ..clubToReturn = _clubA
          ..clubMembersToReturn = <ClubMember>[_memberA];
        final container = _createContainer(repository);
        _listenClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );
        await _primeClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );

        final states = <AsyncValue<void>>[];
        final mutationStateSubscription = container.listen(
          clubMutationControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );
        addTearDown(mutationStateSubscription.close);

        await container
            .read(clubMutationControllerProvider.notifier)
            .deleteClub(targetClubId);

        _expectSuccessTransition(states);
        expect(repository.deleteClubCallCount, 1);
        expect(repository.lastDeletedClubId, targetClubId);

        await _primeClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );

        expect(repository.getMyClubsCallCount, 2);
        expect(repository.getClubCallCount, 2);
        expect(repository.getClubMembersCallCount, 2);
        expect(repository.listClubsCallCount, 2);
        expect(repository.searchClubsCallCount, 2);
      },
    );

    test(
      'createClubRun routes payload, reports loading to success, and invalidates only upcoming runs',
      () async {
        final repository = RecordingClubRepository()
          ..clubsToReturn = <Club>[_clubA]
          ..myClubsToReturn = <Club>[_clubA]
          ..clubToReturn = _clubA
          ..clubMembersToReturn = <ClubMember>[_memberA]
          ..upcomingRunsToReturn = <ClubRun>[_runA]
          ..createdRunToReturn = _runA;
        final container = _createContainer(repository);

        _listenClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );
        final runsSubscription = container.listen(
          upcomingClubRunsProvider(targetClubId),
          (_, __) {},
        );
        addTearDown(runsSubscription.close);

        await _primeClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );
        await container.read(upcomingClubRunsProvider(targetClubId).future);

        expect(repository.getMyClubsCallCount, 1);
        expect(repository.getClubCallCount, 1);
        expect(repository.getClubMembersCallCount, 1);
        expect(repository.listClubsCallCount, 1);
        expect(repository.searchClubsCallCount, 1);
        expect(repository.getUpcomingRunsCallCount, 1);

        final states = <AsyncValue<void>>[];
        final mutationStateSubscription = container.listen(
          clubMutationControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );
        addTearDown(mutationStateSubscription.close);

        final runInput = CreateClubRunInput(
          clubId: targetClubId,
          title: 'Track Session',
          description: '8 x 400m',
          scheduledAt: DateTime.parse('2026-04-10T18:30:00.000Z'),
          meetingPointLat: 42.37,
          meetingPointLng: -71.06,
          meetingPointName: 'Track Oval',
          distanceMeters: 8000,
          paceDescription: 'Threshold',
        );

        await container
            .read(clubMutationControllerProvider.notifier)
            .createClubRun(runInput);

        _expectSuccessTransition(states);
        expect(repository.createClubRunCallCount, 1);
        expect(repository.lastCreateClubRunInput?.clubId, targetClubId);
        expect(repository.lastCreateClubRunInput?.title, 'Track Session');
        expect(repository.lastCreateClubRunInput?.description, '8 x 400m');
        expect(
          repository.lastCreateClubRunInput?.scheduledAt,
          DateTime.parse('2026-04-10T18:30:00.000Z'),
        );
        expect(repository.lastCreateClubRunInput?.meetingPointLat, 42.37);
        expect(repository.lastCreateClubRunInput?.meetingPointLng, -71.06);
        expect(
          repository.lastCreateClubRunInput?.meetingPointName,
          'Track Oval',
        );
        expect(repository.lastCreateClubRunInput?.distanceMeters, 8000);
        expect(repository.lastCreateClubRunInput?.paceDescription, 'Threshold');

        await _primeClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );
        await container.read(upcomingClubRunsProvider(targetClubId).future);

        expect(repository.getMyClubsCallCount, 1);
        expect(repository.getClubCallCount, 1);
        expect(repository.getClubMembersCallCount, 1);
        expect(repository.listClubsCallCount, 1);
        expect(repository.searchClubsCallCount, 1);
        expect(repository.getUpcomingRunsCallCount, 2);
      },
    );

    test(
      'failed joinClub reports AsyncError and does not refresh read caches',
      () async {
        final joinError = StateError('join failed');
        final repository = RecordingClubRepository()
          ..clubsToReturn = <Club>[_clubA]
          ..myClubsToReturn = <Club>[_clubA]
          ..clubToReturn = _clubA
          ..clubMembersToReturn = <ClubMember>[_memberA]
          ..joinClubError = joinError;
        final container = _createContainer(repository);
        _listenClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );
        await _primeClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );

        final states = <AsyncValue<void>>[];
        final mutationStateSubscription = container.listen(
          clubMutationControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );
        addTearDown(mutationStateSubscription.close);

        await expectLater(
          container
              .read(clubMutationControllerProvider.notifier)
              .joinClub(targetClubId),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('join failed'),
            ),
          ),
        );

        _expectErrorTransition(states, expectedError: joinError);
        expect(repository.joinClubCallCount, 1);
        expect(repository.lastJoinedClubId, targetClubId);

        await _primeClubEntityReads(
          container,
          clubId: targetClubId,
          activeSearchQuery: activeSearchQuery,
        );

        expect(repository.getMyClubsCallCount, 1);
        expect(repository.getClubCallCount, 1);
        expect(repository.getClubMembersCallCount, 1);
        expect(repository.listClubsCallCount, 1);
        expect(repository.searchClubsCallCount, 1);
      },
    );

    test(
      'joinClub stays safe when disposed during in-flight mutation',
      () async {
        final repository = RecordingClubRepository()
          ..joinClubCompleter = Completer<void>();
        final container = _createContainer(repository);

        final mutationFuture = container
            .read(clubMutationControllerProvider.notifier)
            .joinClub(targetClubId);

        container.dispose();
        repository.joinClubCompleter!.complete();

        await expectLater(mutationFuture, completes);
        expect(repository.joinClubCallCount, 1);
        expect(repository.lastJoinedClubId, targetClubId);
      },
    );
  });
}

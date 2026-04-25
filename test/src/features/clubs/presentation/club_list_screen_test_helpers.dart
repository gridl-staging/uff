part of 'club_list_screen_test.dart';

final _now = DateTime(2026, 3, 30);

Club _makeClub({
  required String id,
  required String name,
  String? city,
  int memberCount = 0,
  ClubSource source = ClubSource.userCreated,
  ClubVisibility visibility = ClubVisibility.public,
}) {
  return Club(
    id: id,
    name: name,
    description: null,
    avatarUrl: null,
    city: city,
    stateRegion: null,
    country: null,
    locationLat: null,
    locationLng: null,
    source: source,
    sourceUrl: null,
    sourceId: null,
    creatorId: null,
    claimedBy: null,
    visibility: visibility,
    memberCount: memberCount,
    createdAt: _now,
    updatedAt: _now,
    sportType: null,
  );
}

final _myClub1 = _makeClub(
  id: 'mc1',
  name: 'Morning Runners',
  city: 'Portland',
  memberCount: 12,
);
final _myClub2 = _makeClub(
  id: 'mc2',
  name: 'Trail Blazers',
  city: 'Bend',
  memberCount: 7,
);
final _nearbyClub1 = _makeClub(
  id: 'nc1',
  name: 'Downtown Pacers',
  city: 'Seattle',
  memberCount: 24,
);
final _nearbyClub2 = _makeClub(
  id: 'nc2',
  name: 'Lake Loop Crew',
  city: 'Portland',
  memberCount: 15,
);
final _nearbyAutoDiscoveredClub = _makeClub(
  id: 'auto1',
  name: 'Forest Park Striders',
  city: 'Portland',
  memberCount: 0,
  source: ClubSource.autoDiscovered,
);
final _nearbyUserCreatedClub = _makeClub(
  id: 'uc1',
  name: 'Neighborhood Pacers',
  city: 'Portland',
  memberCount: 12,
  source: ClubSource.userCreated,
);
final _searchResult = _makeClub(
  id: 'sr1',
  name: 'Found Club',
  city: 'Eugene',
  memberCount: 5,
);
const _goOtherShellBranchKey = Key('club_list_test_go_other_branch');
const _goClubsShellBranchKey = Key('club_list_test_go_clubs_branch');
const _testClubLocationService = _NoLocationClubLocationService();

class _NoLocationClubLocationService implements ClubLocationService {
  const _NoLocationClubLocationService();

  @override
  Future<ClubCoordinates?> fetchCurrentLocation() async {
    return null;
  }
}

Widget _buildTestApp({
  required RecordingClubRepository repository,
  List<Club>? myClubs,
  List<Club>? nearbyClubs,
}) {
  final repo = repository;
  if (myClubs != null) repo.myClubsToReturn = myClubs;
  if (nearbyClubs != null) repo.clubsToReturn = nearbyClubs;

  return ProviderScope(
    overrides: [
      clubRepositoryProvider.overrideWithValue(repo),
      clubLocationServiceProvider.overrideWithValue(_testClubLocationService),
    ],
    child: const MaterialApp(home: ClubListScreen()),
  );
}

Widget _buildRoutedTestApp({
  required RecordingClubRepository repository,
  List<Club>? myClubs,
  List<Club>? nearbyClubs,
}) {
  final repo = repository;
  if (myClubs != null) repo.myClubsToReturn = myClubs;
  if (nearbyClubs != null) repo.clubsToReturn = nearbyClubs;

  final router = GoRouter(
    initialLocation: ClubRoutes.clubListPath,
    routes: [
      GoRoute(
        path: ClubRoutes.clubListPath,
        builder: (_, __) => const ClubListScreen(),
      ),
      GoRoute(
        path: ClubRoutes.clubNewPath,
        builder: (_, __) => const Scaffold(body: Text('create-club-route')),
      ),
      GoRoute(
        path: ClubRoutes.clubDetailPathPattern,
        builder: (_, state) => Scaffold(
          body: Text('club-detail-route:${state.pathParameters['id']}'),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      clubRepositoryProvider.overrideWithValue(repo),
      clubLocationServiceProvider.overrideWithValue(_testClubLocationService),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Widget _buildShellRoutedTestApp({
  required RecordingClubRepository repository,
  List<Club>? myClubs,
  List<Club>? nearbyClubs,
}) {
  final repo = repository;
  if (myClubs != null) repo.myClubsToReturn = myClubs;
  if (nearbyClubs != null) repo.clubsToReturn = nearbyClubs;

  final router = GoRouter(
    initialLocation: ClubRoutes.clubListPath,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, __, navigationShell) => Scaffold(
          body: navigationShell,
          bottomNavigationBar: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                key: _goClubsShellBranchKey,
                onPressed: () => navigationShell.goBranch(0),
                child: const Text('Clubs branch'),
              ),
              TextButton(
                key: _goOtherShellBranchKey,
                onPressed: () => navigationShell.goBranch(1),
                child: const Text('Other branch'),
              ),
            ],
          ),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: ClubRoutes.clubListPath,
                builder: (_, __) => const ClubListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/other',
                builder: (_, __) => const Scaffold(
                  body: Center(child: Text('other-shell-route')),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      clubRepositoryProvider.overrideWithValue(repo),
      clubLocationServiceProvider.overrideWithValue(_testClubLocationService),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

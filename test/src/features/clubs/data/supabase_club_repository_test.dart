import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/clubs/data/club_repository.dart';
import 'package:uff/src/features/clubs/data/supabase_club_repository.dart';
import 'package:uff/src/features/clubs/domain/club_member.dart';
import 'package:uff/src/features/clubs/domain/club_sport_type.dart';

import '../../../test_helpers/supabase_query_test_doubles.dart';

// ## Test Scenarios
// - [positive] SupabaseClubRepository covers club and club-run reads/writes through one contract seam.
// - [negative] Zero-row write responses throw explicit StateError messages for guarded operations.
// - [negative] Discover/detail reads return no private-club data for a different authenticated user.
// - [negative] Club management mutations reject non-creator, non-admin, and non-organizer users.
// - [isolation] Auth switching changes visibility for private clubs and member listings without local cache leakage.
// - [isolation] Every repository operation that mutates or personalizes data requires an authenticated user session.
class MockGoTrueClient extends Mock implements GoTrueClient {}

// ignore: must_be_immutable, this test double extends a mutable recording base class
class _ThrowingInsertQueryBuilder extends RecordingSupabaseQueryBuilder {
  _ThrowingInsertQueryBuilder(this.error);

  final Error error;

  @override
  PostgrestFilterBuilder<dynamic> insert(
    Object values, {
    bool defaultToNull = true,
  }) {
    throw error;
  }
}

User _testUser({String id = 'user-1'}) {
  return User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-03-30T00:00:00.000Z',
    email: '$id@example.com',
  );
}

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
  late MockSupabaseClient mockClient;
  late MockGoTrueClient mockAuth;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockGoTrueClient();
    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(_testUser());
  });

  group('SupabaseClubRepository reads', () {
    test('getClub returns mapped row when visible', () async {
      final clubsBuilder = RecordingSupabaseQueryBuilder(
        selectRows: <Map<String, dynamic>>[_clubRow()],
      );
      when(() => mockClient.from('clubs')).thenAnswer((_) => clubsBuilder);

      final repository = SupabaseClubRepository(mockClient);
      final club = await repository.getClub('club-1');

      expect(club?.id, 'club-1');
      expect(clubsBuilder.selectBuilder.eqCalls, hasLength(1));
      expect(clubsBuilder.selectBuilder.eqCalls.first.column, 'id');
      expect(clubsBuilder.selectBuilder.eqCalls.first.value, 'club-1');
    });

    test('getClub returns null when row is not visible or missing', () async {
      final clubsBuilder = RecordingSupabaseQueryBuilder();
      when(() => mockClient.from('clubs')).thenAnswer((_) => clubsBuilder);

      final repository = SupabaseClubRepository(mockClient);
      final club = await repository.getClub('private-club');

      expect(club, isNull);
    });

    test('listClubs returns mapped clubs ordered by member_count', () async {
      final clubsBuilder = RecordingSupabaseQueryBuilder(
        selectRows: <Map<String, dynamic>>[
          _clubRow(),
          _clubRow(id: 'club-2'),
        ],
      );
      when(() => mockClient.from('clubs')).thenAnswer((_) => clubsBuilder);

      final repository = SupabaseClubRepository(mockClient);
      final clubs = await repository.listClubs();

      expect(clubs.map((club) => club.id).toList(), <String>[
        'club-1',
        'club-2',
      ]);
      expect(clubsBuilder.selectBuilder.lastOrderedColumn, 'member_count');
      expect(clubsBuilder.selectBuilder.lastOrderAscending, isFalse);
    });

    test('searchClubs uses ilike against name and maps rows', () async {
      final clubsBuilder = RecordingSupabaseQueryBuilder(
        selectRows: <Map<String, dynamic>>[_clubRow(id: 'club-2')],
      );
      when(() => mockClient.from('clubs')).thenAnswer((_) => clubsBuilder);

      final repository = SupabaseClubRepository(mockClient);
      final clubs = await repository.searchClubs('downtown');

      expect(clubs, hasLength(1));
      expect(clubs.single.id, 'club-2');
      expect(clubsBuilder.selectBuilder.lastIlikeColumn, 'name');
      expect(clubsBuilder.selectBuilder.lastIlikePattern, '%downtown%');
    });

    test(
      'searchClubs escapes ilike wildcard characters in user input',
      () async {
        final clubsBuilder = RecordingSupabaseQueryBuilder();
        when(() => mockClient.from('clubs')).thenAnswer((_) => clubsBuilder);

        final repository = SupabaseClubRepository(mockClient);
        final clubs = await repository.searchClubs('50%_off');

        expect(clubs, isEmpty);
        expect(clubsBuilder.selectBuilder.lastIlikeColumn, 'name');
        expect(clubsBuilder.selectBuilder.lastIlikePattern, r'%50\%\_off%');
      },
    );

    test(
      'getMyClubs returns only active memberships as the source of truth',
      () async {
        final membersBuilder = RecordingSupabaseQueryBuilder(
          selectRows: <Map<String, dynamic>>[
            <String, dynamic>{'clubs': _clubRow(id: 'club-active-1')},
            <String, dynamic>{'clubs': _clubRow(id: 'club-active-2')},
          ],
        );
        when(
          () => mockClient.from('club_members'),
        ).thenAnswer((_) => membersBuilder);

        final repository = SupabaseClubRepository(mockClient);
        final clubs = await repository.getMyClubs();

        expect(clubs.map((club) => club.id).toList(), <String>[
          'club-active-1',
          'club-active-2',
        ]);
        expect(membersBuilder.selectBuilder.eqCalls, hasLength(2));
        expect(membersBuilder.selectBuilder.eqCalls[0].column, 'user_id');
        expect(membersBuilder.selectBuilder.eqCalls[0].value, 'user-1');
        expect(membersBuilder.selectBuilder.eqCalls[1].column, 'status');
        expect(membersBuilder.selectBuilder.eqCalls[1].value, 'active');
      },
    );

    test(
      'getMyClubs throws when required joined club payload is missing',
      () async {
        final membersBuilder = RecordingSupabaseQueryBuilder(
          selectRows: <Map<String, dynamic>>[
            <String, dynamic>{'clubs': null},
          ],
        );
        when(
          () => mockClient.from('club_members'),
        ).thenAnswer((_) => membersBuilder);

        final repository = SupabaseClubRepository(mockClient);

        await expectLater(
          repository.getMyClubs(),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('joined club row payload'),
            ),
          ),
        );
      },
    );

    test('getClubMembers returns mapped members for a visible club', () async {
      final membersBuilder = RecordingSupabaseQueryBuilder(
        selectRows: <Map<String, dynamic>>[
          _clubMemberRow(role: 'admin', displayName: 'Admin Runner'),
          _clubMemberRow(id: 'member-2', displayName: '   ', avatarUrl: null),
        ],
      );
      when(
        () => mockClient.from('club_members'),
      ).thenAnswer((_) => membersBuilder);

      final repository = SupabaseClubRepository(mockClient);
      final members = await repository.getClubMembers('club-1');

      expect(members, hasLength(2));
      expect(members.first.role, ClubMemberRole.admin);
      expect(members.first.displayName, 'Admin Runner');
      expect(members[1].displayName, '   ');
      expect(members[1].avatarUrl, isNull);
      expect(
        membersBuilder.selectBuilder.lastSelectColumns,
        'id,club_id,user_id,role,status,joined_at,profiles!club_members_user_id_fkey(display_name,avatar_url)',
      );
      expect(membersBuilder.selectBuilder.lastOrderedColumn, 'joined_at');
      expect(membersBuilder.selectBuilder.lastOrderAscending, isTrue);
    });

    test(
      'getUpcomingClubRuns returns mapped runs ordered by schedule',
      () async {
        final runsBuilder = RecordingSupabaseQueryBuilder(
          selectRows: <Map<String, dynamic>>[
            _clubRunRow(),
            _clubRunRow(id: 'run-2', scheduledAt: '2026-04-03T10:30:00.000Z'),
          ],
        );
        when(() => mockClient.from('club_runs')).thenAnswer((_) => runsBuilder);

        final repository = SupabaseClubRepository(mockClient);
        final runs = await repository.getUpcomingClubRuns('club-1');

        expect(runs.map((run) => run.id).toList(), <String>['run-1', 'run-2']);
        expect(runsBuilder.selectBuilder.lastGteColumn, 'scheduled_at');
        final gteValue = runsBuilder.selectBuilder.lastGteValue! as String;
        expect(
          DateTime.tryParse(gteValue)?.toUtc().toIso8601String(),
          gteValue,
        );
        expect(runsBuilder.selectBuilder.lastOrderedColumn, 'scheduled_at');
        expect(runsBuilder.selectBuilder.lastOrderAscending, isTrue);
      },
    );

    test(
      '[negative] user B cannot discover user A private club rows',
      () async {
        when(() => mockAuth.currentUser).thenReturn(_testUser(id: 'user-b'));
        final emptyDiscoverBuilder = RecordingSupabaseQueryBuilder();
        final emptySearchBuilder = RecordingSupabaseQueryBuilder();
        final emptyDetailBuilder = RecordingSupabaseQueryBuilder();
        final clubBuilders = <RecordingSupabaseQueryBuilder>[
          emptyDiscoverBuilder,
          emptySearchBuilder,
          emptyDetailBuilder,
        ];
        when(
          () => mockClient.from('clubs'),
        ).thenAnswer((_) => clubBuilders.removeAt(0));

        final repository = SupabaseClubRepository(mockClient);
        final listed = await repository.listClubs();
        final searched = await repository.searchClubs('private');
        final detail = await repository.getClub('club-private-a');

        expect(listed, isEmpty);
        expect(searched, isEmpty);
        expect(detail, isNull);
      },
    );

    test(
      '[isolation] auth switch hides private member listings for user B',
      () async {
        when(() => mockAuth.currentUser).thenReturn(_testUser(id: 'user-a'));
        final visibleMembersBuilder = RecordingSupabaseQueryBuilder(
          selectRows: <Map<String, dynamic>>[
            _clubMemberRow(id: 'member-owner', userId: 'user-a', role: 'admin'),
          ],
        );
        when(
          () => mockClient.from('club_members'),
        ).thenAnswer((_) => visibleMembersBuilder);
        final repository = SupabaseClubRepository(mockClient);
        final ownerMembers = await repository.getClubMembers('club-private-a');

        when(() => mockAuth.currentUser).thenReturn(_testUser(id: 'user-b'));
        final hiddenMembersBuilder = RecordingSupabaseQueryBuilder();
        when(
          () => mockClient.from('club_members'),
        ).thenAnswer((_) => hiddenMembersBuilder);
        final outsiderMembers = await repository.getClubMembers(
          'club-private-a',
        );

        expect(ownerMembers, hasLength(1));
        expect(ownerMembers.single.userId, 'user-a');
        expect(outsiderMembers, isEmpty);
      },
    );
  });

  group('SupabaseClubRepository mutations', () {
    test(
      'createClub inserts club row, creates admin membership, and returns refreshed club state',
      () async {
        final createBuilder = RecordingSupabaseQueryBuilder(
          selectRows: <Map<String, dynamic>>[
            _clubRow(id: 'club-new', memberCount: 0),
          ],
        );
        final reloadBuilder = RecordingSupabaseQueryBuilder(
          selectRows: <Map<String, dynamic>>[
            _clubRow(id: 'club-new', memberCount: 1),
          ],
        );
        final clubBuilders = <RecordingSupabaseQueryBuilder>[
          createBuilder,
          reloadBuilder,
        ];
        final membersBuilder = RecordingSupabaseQueryBuilder(
          insertRows: <Map<String, dynamic>>[_clubMemberRow(id: 'member-new')],
        );
        when(
          () => mockClient.from('clubs'),
        ).thenAnswer((_) => clubBuilders.removeAt(0));
        when(
          () => mockClient.from('club_members'),
        ).thenAnswer((_) => membersBuilder);

        final repository = SupabaseClubRepository(mockClient);
        final club = await repository.createClub(
          const CreateClubInput(
            name: 'Uptown Milers',
            description: 'Community tempo runs',
            city: 'New York',
            stateRegion: 'NY',
          ),
        );

        expect(club.id, 'club-new');
        expect(club.memberCount, 1);
        expect(createBuilder.lastInsertPayload?['creator_id'], 'user-1');
        expect(createBuilder.lastInsertPayload?['source'], 'user_created');
        expect(createBuilder.lastInsertPayload?['visibility'], 'public');
        expect(createBuilder.lastInsertPayload?['sport_type'], isNull);
        expect(reloadBuilder.selectBuilder.eqCalls, hasLength(1));
        expect(reloadBuilder.selectBuilder.eqCalls.first.column, 'id');
        expect(reloadBuilder.selectBuilder.eqCalls.first.value, 'club-new');
        expect(membersBuilder.lastInsertPayload, <String, dynamic>{
          'club_id': 'club-new',
          'user_id': 'user-1',
          'role': 'admin',
          'status': 'active',
        });
      },
    );

    test(
      'createClub deletes inserted club row when membership insert fails',
      () async {
        final createdClubBuilder = RecordingSupabaseQueryBuilder(
          selectRows: <Map<String, dynamic>>[_clubRow(id: 'club-fail')],
        );
        final cleanupBuilder = RecordingSupabaseQueryBuilder(
          deleteRows: <Map<String, dynamic>>[
            <String, dynamic>{'id': 'club-fail'},
          ],
        );
        final clubsBuilders = <RecordingSupabaseQueryBuilder>[
          createdClubBuilder,
          cleanupBuilder,
        ];
        final membershipError = StateError('membership insert failed');
        final membersBuilder = _ThrowingInsertQueryBuilder(membershipError);
        when(
          () => mockClient.from('clubs'),
        ).thenAnswer((_) => clubsBuilders.removeAt(0));
        when(
          () => mockClient.from('club_members'),
        ).thenAnswer((_) => membersBuilder);

        final repository = SupabaseClubRepository(mockClient);

        await expectLater(
          repository.createClub(const CreateClubInput(name: 'Rollback Club')),
          throwsA(isA<StateError>()),
        );

        expect(cleanupBuilder.deleteCalled, isTrue);
        expect(cleanupBuilder.deleteBuilder.lastEqColumn, 'id');
        expect(cleanupBuilder.deleteBuilder.lastEqValue, 'club-fail');
      },
    );

    test('createClub includes sport_type in insert payload', () async {
      final createBuilder = RecordingSupabaseQueryBuilder(
        selectRows: <Map<String, dynamic>>[
          _clubRow(id: 'club-sport', memberCount: 0, sportType: 'cycling'),
        ],
      );
      final reloadBuilder = RecordingSupabaseQueryBuilder(
        selectRows: <Map<String, dynamic>>[
          _clubRow(id: 'club-sport', memberCount: 1, sportType: 'cycling'),
        ],
      );
      final clubBuilders = <RecordingSupabaseQueryBuilder>[
        createBuilder,
        reloadBuilder,
      ];
      final membersBuilder = RecordingSupabaseQueryBuilder(
        insertRows: <Map<String, dynamic>>[_clubMemberRow(id: 'member-sport')],
      );
      when(
        () => mockClient.from('clubs'),
      ).thenAnswer((_) => clubBuilders.removeAt(0));
      when(
        () => mockClient.from('club_members'),
      ).thenAnswer((_) => membersBuilder);

      final repository = SupabaseClubRepository(mockClient);
      final club = await repository.createClub(
        const CreateClubInput(
          name: 'Cycling Club',
          sportType: ClubSportType.cycling,
        ),
      );

      expect(club.sportType, ClubSportType.cycling);
      expect(createBuilder.lastInsertPayload?['sport_type'], 'cycling');
    });

    test('updateClub updates writable columns and updated_at', () async {
      final visibleClubBuilder = RecordingSupabaseQueryBuilder(
        selectRows: <Map<String, dynamic>>[_clubRow()],
      );
      final updateBuilder = RecordingSupabaseQueryBuilder(
        updateRows: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'club-1'},
        ],
      );
      final clubBuilders = <RecordingSupabaseQueryBuilder>[
        visibleClubBuilder,
        updateBuilder,
      ];
      when(
        () => mockClient.from('clubs'),
      ).thenAnswer((_) => clubBuilders.removeAt(0));
      final repository = SupabaseClubRepository(mockClient);

      await repository.updateClub(
        clubFromJson(
          _clubRow(
            name: 'Updated Name',
            description: 'Updated description',
            avatarUrl: 'https://cdn.example.com/new.png',
            city: 'Seattle',
            stateRegion: 'WA',
            visibility: 'private',
          ),
        ),
      );

      expect(updateBuilder.lastUpdatePayload?['name'], 'Updated Name');
      expect(updateBuilder.lastUpdatePayload?['visibility'], 'private');
      expect(updateBuilder.lastUpdatePayload?['sport_type'], isNull);
      final rawUpdatedAt = updateBuilder.lastUpdatePayload?['updated_at'];
      expect(rawUpdatedAt.runtimeType, String);
      final updatedAt = rawUpdatedAt as String;
      expect(
        DateTime.tryParse(updatedAt)?.toUtc().toIso8601String(),
        updatedAt,
      );
      expect(updateBuilder.updateBuilder.lastEqColumn, 'id');
      expect(updateBuilder.updateBuilder.lastEqValue, 'club-1');
    });

    test('updateClub throws when no row is affected', () async {
      final visibleClubBuilder = RecordingSupabaseQueryBuilder(
        selectRows: <Map<String, dynamic>>[_clubRow(id: 'missing')],
      );
      final updateBuilder = RecordingSupabaseQueryBuilder();
      final clubBuilders = <RecordingSupabaseQueryBuilder>[
        visibleClubBuilder,
        updateBuilder,
      ];
      when(
        () => mockClient.from('clubs'),
      ).thenAnswer((_) => clubBuilders.removeAt(0));
      final repository = SupabaseClubRepository(mockClient);

      await expectLater(
        repository.updateClub(clubFromJson(_clubRow(id: 'missing'))),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('update'),
          ),
        ),
      );
    });

    test('deleteClub throws when no row is deleted', () async {
      final visibleClubBuilder = RecordingSupabaseQueryBuilder(
        selectRows: <Map<String, dynamic>>[_clubRow(id: 'missing-club')],
      );
      final deleteBuilder = RecordingSupabaseQueryBuilder();
      final clubBuilders = <RecordingSupabaseQueryBuilder>[
        visibleClubBuilder,
        deleteBuilder,
      ];
      when(
        () => mockClient.from('clubs'),
      ).thenAnswer((_) => clubBuilders.removeAt(0));
      final repository = SupabaseClubRepository(mockClient);

      await expectLater(
        repository.deleteClub('missing-club'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('delete'),
          ),
        ),
      );
    });

    test('joinClub inserts active membership for public clubs', () async {
      final clubsBuilder = RecordingSupabaseQueryBuilder(
        selectRows: <Map<String, dynamic>>[_clubRow(id: 'club-public')],
      );
      final membersBuilder = RecordingSupabaseQueryBuilder(
        insertRows: <Map<String, dynamic>>[
          _clubMemberRow(id: 'member-joined', clubId: 'club-public'),
        ],
      );
      when(() => mockClient.from('clubs')).thenAnswer((_) => clubsBuilder);
      when(
        () => mockClient.from('club_members'),
      ).thenAnswer((_) => membersBuilder);
      final repository = SupabaseClubRepository(mockClient);

      await repository.joinClub('club-public');

      expect(membersBuilder.lastInsertPayload?['status'], 'active');
      expect(membersBuilder.lastInsertPayload?['role'], 'member');
      expect(membersBuilder.lastInsertPayload?['user_id'], 'user-1');
    });

    test('joinClub inserts pending membership for private clubs', () async {
      final clubsBuilder = RecordingSupabaseQueryBuilder(
        selectRows: <Map<String, dynamic>>[
          _clubRow(id: 'club-private', visibility: 'private'),
        ],
      );
      final membersBuilder = RecordingSupabaseQueryBuilder(
        insertRows: <Map<String, dynamic>>[
          _clubMemberRow(
            id: 'member-pending',
            clubId: 'club-private',
            status: 'pending',
          ),
        ],
      );
      when(() => mockClient.from('clubs')).thenAnswer((_) => clubsBuilder);
      when(
        () => mockClient.from('club_members'),
      ).thenAnswer((_) => membersBuilder);
      final repository = SupabaseClubRepository(mockClient);

      await repository.joinClub('club-private');

      expect(membersBuilder.lastInsertPayload?['status'], 'pending');
    });

    test('leaveClub deletes current user membership row', () async {
      final deleteBuilder = RecordingSupabaseQueryBuilder(
        deleteRows: <Map<String, dynamic>>[_clubMemberRow(id: 'member-delete')],
      );
      when(
        () => mockClient.from('club_members'),
      ).thenAnswer((_) => deleteBuilder);
      final repository = SupabaseClubRepository(mockClient);

      await repository.leaveClub('club-1');

      expect(deleteBuilder.deleteBuilder.eqCalls, hasLength(2));
      expect(deleteBuilder.deleteBuilder.eqCalls[0].column, 'club_id');
      expect(deleteBuilder.deleteBuilder.eqCalls[0].value, 'club-1');
      expect(deleteBuilder.deleteBuilder.eqCalls[1].column, 'user_id');
      expect(deleteBuilder.deleteBuilder.eqCalls[1].value, 'user-1');
    });

    test('leaveClub throws when no membership row is deleted', () async {
      final deleteBuilder = RecordingSupabaseQueryBuilder();
      when(
        () => mockClient.from('club_members'),
      ).thenAnswer((_) => deleteBuilder);
      final repository = SupabaseClubRepository(mockClient);

      await expectLater(
        repository.leaveClub('club-1'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('leave club'),
          ),
        ),
      );
    });

    test('createClubRun inserts creator and returns mapped row', () async {
      final visibleClubBuilder = RecordingSupabaseQueryBuilder(
        selectRows: <Map<String, dynamic>>[_clubRow()],
      );
      final runsBuilder = RecordingSupabaseQueryBuilder(
        selectRows: <Map<String, dynamic>>[_clubRunRow(id: 'run-new')],
      );
      when(
        () => mockClient.from('clubs'),
      ).thenAnswer((_) => visibleClubBuilder);
      when(() => mockClient.from('club_runs')).thenAnswer((_) => runsBuilder);
      final repository = SupabaseClubRepository(mockClient);

      final run = await repository.createClubRun(
        CreateClubRunInput(
          clubId: 'club-1',
          title: 'Track Workout',
          description: '8 x 400m',
          scheduledAt: DateTime.parse('2026-04-03T18:00:00.000Z'),
          meetingPointName: 'City Track',
          distanceMeters: 8000,
          paceDescription: 'Threshold',
        ),
      );

      expect(run.id, 'run-new');
      expect(runsBuilder.lastInsertPayload?['created_by'], 'user-1');
      expect(runsBuilder.lastInsertPayload?['club_id'], 'club-1');
      expect(runsBuilder.lastInsertPayload?['title'], 'Track Workout');
    });

    test(
      'club management mutations reject users without creator or elevated membership access',
      () async {
        when(() => mockAuth.currentUser).thenReturn(_testUser(id: 'user-b'));
        final clubBuilders = <RecordingSupabaseQueryBuilder>[
          RecordingSupabaseQueryBuilder(
            selectRows: <Map<String, dynamic>>[
              _clubRow(creatorId: 'club-owner'),
            ],
          ),
          RecordingSupabaseQueryBuilder(
            selectRows: <Map<String, dynamic>>[
              _clubRow(creatorId: 'club-owner'),
            ],
          ),
          RecordingSupabaseQueryBuilder(
            selectRows: <Map<String, dynamic>>[
              _clubRow(creatorId: 'club-owner'),
            ],
          ),
        ];
        final membershipBuilders = <RecordingSupabaseQueryBuilder>[
          RecordingSupabaseQueryBuilder(
            selectRows: <Map<String, dynamic>>[
              <String, dynamic>{'role': 'member'},
            ],
          ),
          RecordingSupabaseQueryBuilder(
            selectRows: <Map<String, dynamic>>[
              <String, dynamic>{'role': 'member'},
            ],
          ),
          RecordingSupabaseQueryBuilder(
            selectRows: <Map<String, dynamic>>[
              <String, dynamic>{'role': 'member'},
            ],
          ),
        ];
        when(
          () => mockClient.from('clubs'),
        ).thenAnswer((_) => clubBuilders.removeAt(0));
        when(
          () => mockClient.from('club_members'),
        ).thenAnswer((_) => membershipBuilders.removeAt(0));
        final repository = SupabaseClubRepository(mockClient);

        await expectLater(
          repository.updateClub(clubFromJson(_clubRow())),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('creator, admin, or organizer access'),
            ),
          ),
        );
        await expectLater(
          repository.deleteClub('club-1'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('creator, admin, or organizer access'),
            ),
          ),
        );
        await expectLater(
          repository.createClubRun(
            CreateClubRunInput(
              clubId: 'club-1',
              title: 'Unauthorized Run',
              scheduledAt: DateTime.parse('2026-04-03T18:00:00.000Z'),
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('creator, admin, or organizer access'),
            ),
          ),
        );
        verifyNever(() => mockClient.from('club_runs'));
      },
    );

    test(
      'all operations require authenticated session when user is missing',
      () async {
        when(() => mockAuth.currentUser).thenReturn(null);
        final repository = SupabaseClubRepository(mockClient);

        await expectLater(
          repository.createClub(const CreateClubInput(name: 'No Auth')),
          throwsA(isA<StateError>()),
        );
        await expectLater(repository.getMyClubs(), throwsA(isA<StateError>()));
        await expectLater(
          repository.joinClub('club-1'),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          repository.leaveClub('club-1'),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          repository.updateClub(clubFromJson(_clubRow(id: 'club-auth-check'))),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          repository.deleteClub('club-auth-check'),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          repository.createClubRun(
            CreateClubRunInput(
              clubId: 'club-1',
              title: 'No Auth Run',
              scheduledAt: DateTime.parse('2026-04-03T18:00:00.000Z'),
            ),
          ),
          throwsA(isA<StateError>()),
        );
        verifyNever(() => mockClient.from('clubs'));
        verifyNever(() => mockClient.from('club_members'));
        verifyNever(() => mockClient.from('club_runs'));
      },
    );
  });
}

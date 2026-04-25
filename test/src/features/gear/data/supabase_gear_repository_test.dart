import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show GoTrueClient, User;
import 'package:uff/src/features/gear/data/supabase_gear_repository.dart';
import 'package:uff/src/features/gear/domain/gear_item.dart';
import '../../../test_helpers/supabase_query_test_doubles.dart';

/// ## Test Scenarios
/// - [positive] loadGear orders by created_at descending
/// - [positive] createGear sends writable columns and binds to authenticated user
/// - [positive] createGear persists lifecycle fields via canonical columns
/// - [negative] Every gear mutation throws when no authenticated user
/// - [isolation] createGear ignores caller ownership and binds writes to the active session user
/// - [positive] updateGear filters by id and user_id, omits read-only columns
/// - [positive] deleteGear filters by id and user_id
/// - [error] updateGear throws StateError on zero affected rows
/// - [error] deleteGear throws StateError on zero affected rows

class _MockGoTrueClient extends Mock implements GoTrueClient {}

const _authenticatedUser = User(
  id: 'session-user',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-03-26T00:00:00Z',
);

Map<String, dynamic> _gearRow({
  String id = 'gear-1',
  String userId = 'user-1',
  String name = 'Pegasus 40',
  String gearType = 'shoe',
  num totalDistanceMeters = 5234.5,
  bool retired = false,
  String? startDate = '2024-03-05',
  String? brand = 'Nike',
  String? model = 'Pegasus 40',
  String? notes = 'Daily trainer',
}) => {
  'id': id,
  'user_id': userId,
  'name': name,
  'gear_type': gearType,
  'total_distance_meters': totalDistanceMeters,
  'retired': retired,
  'start_date': startDate,
  'brand': brand,
  'model': model,
  'notes': notes,
};

final _testGearItem = GearItem(
  id: 'gear-1',
  userId: 'user-1',
  name: 'Pegasus 40',
  gearType: GearType.shoe,
  totalDistanceMeters: 5234.5,
  retired: false,
  startDate: DateTime(2024, 3, 5),
  brand: 'Nike',
  model: 'Pegasus 40',
  notes: 'Daily trainer',
);

GearItem _gearItem({
  String id = 'gear-1',
  String userId = 'user-1',
  String name = 'Pegasus 40',
  GearType gearType = GearType.shoe,
  double totalDistanceMeters = 5234.5,
  bool retired = false,
  DateTime? startDate,
  String? brand = 'Nike',
  String? model = 'Pegasus 40',
  String? notes = 'Daily trainer',
}) {
  return GearItem(
    id: id,
    userId: userId,
    name: name,
    gearType: gearType,
    totalDistanceMeters: totalDistanceMeters,
    retired: retired,
    startDate: startDate ?? DateTime(2024, 3, 5),
    brand: brand,
    model: model,
    notes: notes,
  );
}

Future<void> _expectStateErrorMessage(
  Future<void> action,
  String expectedMessage,
) {
  return expectLater(
    action,
    throwsA(
      isA<StateError>().having(
        (error) => error.message,
        'message',
        expectedMessage,
      ),
    ),
  );
}

void main() {
  late MockSupabaseClient mockClient;
  late _MockGoTrueClient mockAuth;
  late SupabaseGearRepository repository;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = _MockGoTrueClient();
    when(() => mockClient.auth).thenReturn(mockAuth);
    repository = SupabaseGearRepository(mockClient);
  });

  group('SupabaseGearRepository', () {
    test('loadGear orders by created_at descending and maps rows', () async {
      final fakeBuilder = RecordingSupabaseQueryBuilder(
        selectRows: [
          _gearRow(id: 'gear-2', name: 'Aeroad', gearType: 'bike'),
          _gearRow(startDate: null, notes: null),
        ],
      );
      when(() => mockClient.from('gear')).thenAnswer((_) => fakeBuilder);

      final items = await repository.loadGear();

      expect(items, hasLength(2));
      expect(items[0].id, 'gear-2');
      expect(items[0].gearType, GearType.bike);
      expect(items[0].startDate, DateTime(2024, 3, 5));
      expect(items[0].notes, 'Daily trainer');
      expect(items[1].id, 'gear-1');
      expect(items[1].startDate, null);
      expect(items[1].notes, null);
      expect(fakeBuilder.selectBuilder.lastOrderedColumn, 'created_at');
      expect(fakeBuilder.selectBuilder.lastOrderAscending, isFalse);
    });

    test(
      'createGear sends only writable create columns and returns row',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          insertRows: [_gearRow(id: 'gear-created', userId: 'session-user')],
        );
        when(() => mockClient.from('gear')).thenAnswer((_) => fakeBuilder);
        when(() => mockAuth.currentUser).thenReturn(_authenticatedUser);

        final repository = SupabaseGearRepository(mockClient);
        final createdItem = await repository.createGear(_testGearItem);

        expect(createdItem.id, 'gear-created');
        expect(createdItem.userId, 'session-user');
        expect(createdItem.gearType, GearType.shoe);
        expect(createdItem.startDate, DateTime(2024, 3, 5));
        expect(createdItem.notes, 'Daily trainer');
        expect(fakeBuilder.lastInsertPayload!['user_id'], 'session-user');
        expect(fakeBuilder.lastInsertPayload!['name'], 'Pegasus 40');
        expect(fakeBuilder.lastInsertPayload!['gear_type'], 'shoe');
        expect(fakeBuilder.lastInsertPayload!['total_distance_meters'], 5234.5);
        expect(fakeBuilder.lastInsertPayload!['start_date'], '2024-03-05');
        expect(fakeBuilder.lastInsertPayload!['brand'], 'Nike');
        expect(fakeBuilder.lastInsertPayload!['model'], 'Pegasus 40');
        expect(fakeBuilder.lastInsertPayload!['notes'], 'Daily trainer');
        expect(fakeBuilder.lastInsertPayload!.containsKey('id'), isFalse);
        expect(fakeBuilder.lastInsertPayload!.containsKey('retired'), isFalse);
      },
    );

    test(
      'createGear ignores caller-supplied userId and binds to the auth session',
      () async {
        final fakeBuilder = RecordingSupabaseQueryBuilder(
          insertRows: [_gearRow(id: 'gear-created', userId: 'session-user')],
        );
        when(() => mockClient.from('gear')).thenAnswer((_) => fakeBuilder);
        when(() => mockAuth.currentUser).thenReturn(_authenticatedUser);

        final createdItem = await repository.createGear(
          _gearItem(userId: 'spoofed-owner-id'),
        );

        expect(fakeBuilder.lastInsertPayload!['user_id'], 'session-user');
        expect(createdItem.userId, 'session-user');
      },
    );

    test('createGear throws when no authenticated user is available', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      await _expectStateErrorMessage(
        repository.createGear(_testGearItem),
        'Gear mutations require an authenticated user session.',
      );
      verifyNever(() => mockClient.from(any()));
    });

    test('updateGear filters by id and omits server-managed columns', () async {
      final fakeBuilder = RecordingSupabaseQueryBuilder(
        updateRows: [_gearRow(id: 'gear-2')],
      );
      when(() => mockClient.from('gear')).thenAnswer((_) => fakeBuilder);
      when(() => mockAuth.currentUser).thenReturn(_authenticatedUser);

      await repository.updateGear(
        _gearItem(
          id: 'gear-2',
          name: 'Retired Peg',
          totalDistanceMeters: 9000,
          retired: true,
          model: null,
        ),
      );

      expect(fakeBuilder.lastUpdatePayload!['name'], 'Retired Peg');
      expect(fakeBuilder.lastUpdatePayload!['gear_type'], 'shoe');
      expect(fakeBuilder.lastUpdatePayload!['total_distance_meters'], 9000.0);
      expect(fakeBuilder.lastUpdatePayload!['start_date'], '2024-03-05');
      expect(fakeBuilder.lastUpdatePayload!['brand'], 'Nike');
      expect(fakeBuilder.lastUpdatePayload!['model'], isNull);
      expect(fakeBuilder.lastUpdatePayload!['notes'], 'Daily trainer');
      expect(fakeBuilder.lastUpdatePayload!['retired'], isTrue);
      expect(fakeBuilder.lastUpdatePayload!.containsKey('user_id'), isFalse);
      expect(fakeBuilder.updateBuilder.eqCalls, hasLength(2));
      expect(fakeBuilder.updateBuilder.eqCalls[0].column, 'id');
      expect(fakeBuilder.updateBuilder.eqCalls[0].value, 'gear-2');
      expect(fakeBuilder.updateBuilder.eqCalls[1].column, 'user_id');
      expect(fakeBuilder.updateBuilder.eqCalls[1].value, 'session-user');
      expect(fakeBuilder.updateBuilder.lastSelectColumns, 'id');
    });

    test('deleteGear filters deletion by id', () async {
      final fakeBuilder = RecordingSupabaseQueryBuilder(
        deleteRows: [_gearRow(id: 'gear-3')],
      );
      when(() => mockClient.from('gear')).thenAnswer((_) => fakeBuilder);
      when(() => mockAuth.currentUser).thenReturn(_authenticatedUser);

      await repository.deleteGear('gear-3');

      expect(fakeBuilder.deleteCalled, isTrue);
      expect(fakeBuilder.deleteBuilder.eqCalls, hasLength(2));
      expect(fakeBuilder.deleteBuilder.eqCalls[0].column, 'id');
      expect(fakeBuilder.deleteBuilder.eqCalls[0].value, 'gear-3');
      expect(fakeBuilder.deleteBuilder.eqCalls[1].column, 'user_id');
      expect(fakeBuilder.deleteBuilder.eqCalls[1].value, 'session-user');
      expect(fakeBuilder.deleteBuilder.lastSelectColumns, 'id');
    });

    test('updateGear throws when no rows are updated', () async {
      final fakeBuilder = RecordingSupabaseQueryBuilder();
      when(() => mockClient.from('gear')).thenAnswer((_) => fakeBuilder);
      when(() => mockAuth.currentUser).thenReturn(_authenticatedUser);

      await _expectStateErrorMessage(
        repository.updateGear(
          _gearItem(
            id: 'missing-gear',
            name: 'Missing Gear',
            totalDistanceMeters: 0,
          ),
        ),
        'Gear update must affect exactly one row for id missing-gear, but affected 0.',
      );
    });

    test('deleteGear throws when no rows are deleted', () async {
      final fakeBuilder = RecordingSupabaseQueryBuilder();
      when(() => mockClient.from('gear')).thenAnswer((_) => fakeBuilder);
      when(() => mockAuth.currentUser).thenReturn(_authenticatedUser);

      await _expectStateErrorMessage(
        repository.deleteGear('missing-gear'),
        'Gear delete must affect exactly one row for id missing-gear, but affected 0.',
      );
    });

    test(
      'updateGear and deleteGear throw when no authenticated user exists',
      () async {
        when(() => mockAuth.currentUser).thenReturn(null);

        await _expectStateErrorMessage(
          repository.updateGear(_testGearItem),
          'Gear mutations require an authenticated user session.',
        );
        await _expectStateErrorMessage(
          repository.deleteGear('gear-1'),
          'Gear mutations require an authenticated user session.',
        );
        verifyNever(() => mockClient.from(any()));
      },
    );
  });
}

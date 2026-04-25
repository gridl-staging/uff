import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/profile/data/supabase_privacy_zone_repository.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';

/// ## Test Scenarios
/// - [positive] loadZones returns mapped list ordered by created_at desc
/// - [positive] loadZones returns empty list when no zones exist
/// - [positive] createZone sends insert with user_id and returns created zone
/// - [negative] createZone throws StateError when no authenticated user exists
/// - [positive] updateZone sends only mutable fields filtered by id
/// - [positive] deleteZone calls delete filtered by id

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockUser extends Mock implements User {}

// ---------------------------------------------------------------------------
// Fake PostgREST builders
//
// Adapted from supabase_profile_repository_test.dart. Extended to support
// list returns (.order()), insert with payload capture, and delete.
// ---------------------------------------------------------------------------

/// Resolves to a single Map when awaited (e.g. after .single()).
class _FakeSingleBuilder extends Fake
    implements PostgrestTransformBuilder<Map<String, dynamic>> {
  _FakeSingleBuilder(this._data);
  final Map<String, dynamic> _data;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(Map<String, dynamic>) onValue, {
    Function? onError,
  }) => Future.value(_data).then(onValue, onError: onError);

  @override
  Future<Map<String, dynamic>> catchError(
    Function onError, {
    bool Function(Object)? test,
  }) => Future.value(_data).catchError(onError, test: test);

  @override
  Future<Map<String, dynamic>> whenComplete(FutureOr<void> Function() action) =>
      Future.value(_data).whenComplete(action);

  @override
  Stream<Map<String, dynamic>> asStream() => Stream.value(_data);

  @override
  Future<Map<String, dynamic>> timeout(
    Duration timeLimit, {
    FutureOr<Map<String, dynamic>> Function()? onTimeout,
  }) => Future.value(_data).timeout(timeLimit, onTimeout: onTimeout);
}

/// Resolves to a List<Map> when awaited (e.g. after .select().order()).
class _FakeListBuilder extends Fake
    implements PostgrestTransformBuilder<List<Map<String, dynamic>>> {
  _FakeListBuilder(this._data, {this.recordedOrder});
  final List<Map<String, dynamic>> _data;
  final _RecordedOrder? recordedOrder;

  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) {
    if (recordedOrder != null) {
      recordedOrder!
        ..column = column
        ..ascending = ascending;
    }
    return this;
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>>) onValue, {
    Function? onError,
  }) => Future.value(_data).then(onValue, onError: onError);

  @override
  Future<List<Map<String, dynamic>>> catchError(
    Function onError, {
    bool Function(Object)? test,
  }) => Future.value(_data).catchError(onError, test: test);

  @override
  Future<List<Map<String, dynamic>>> whenComplete(
    FutureOr<void> Function() action,
  ) => Future.value(_data).whenComplete(action);

  @override
  Stream<List<Map<String, dynamic>>> asStream() => Stream.value(_data);

  @override
  Future<List<Map<String, dynamic>>> timeout(
    Duration timeLimit, {
    FutureOr<List<Map<String, dynamic>>> Function()? onTimeout,
  }) => Future.value(_data).timeout(timeLimit, onTimeout: onTimeout);
}

/// Filter builder supporting .eq(), .select(), .single(), .order().
/// Also awaitable for void operations (update/delete without .select()).
class _RecordedFilter {
  String? eqColumn;
  Object? eqValue;
}

class _RecordedOrder {
  String? column;
  bool? ascending;
}

class _FakeFilterBuilder extends Fake
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  _FakeFilterBuilder({
    required this.recordedFilter,
    required this.recordedOrder,
    this.listData = const [],
    this.singleData,
  });

  final _RecordedFilter recordedFilter;
  final _RecordedOrder recordedOrder;
  final List<Map<String, dynamic>> listData;
  final Map<String, dynamic>? singleData;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(
    String column,
    Object value,
  ) {
    recordedFilter
      ..eqColumn = column
      ..eqValue = value;
    return this;
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([
    String columns = '*',
  ]) => this;

  @override
  PostgrestTransformBuilder<Map<String, dynamic>> single() =>
      _FakeSingleBuilder(singleData ?? listData.first);

  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) {
    recordedOrder
      ..column = column
      ..ascending = ascending;
    return _FakeListBuilder(listData, recordedOrder: recordedOrder);
  }

  // Awaitable for void operations (update .eq(), delete .eq()).
  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>>) onValue, {
    Function? onError,
  }) => Future.value(listData).then(onValue, onError: onError);

  @override
  Future<List<Map<String, dynamic>>> catchError(
    Function onError, {
    bool Function(Object)? test,
  }) => Future.value(listData).catchError(onError, test: test);

  @override
  Future<List<Map<String, dynamic>>> whenComplete(
    FutureOr<void> Function() action,
  ) => Future.value(listData).whenComplete(action);

  @override
  Stream<List<Map<String, dynamic>>> asStream() => Stream.value(listData);

  @override
  Future<List<Map<String, dynamic>>> timeout(
    Duration timeLimit, {
    FutureOr<List<Map<String, dynamic>>> Function()? onTimeout,
  }) => Future.value(listData).timeout(timeLimit, onTimeout: onTimeout);
}

/// Query builder dispatching .select(), .insert(), .update(), .delete().
// ignore: must_be_immutable, mutable fields capture payloads for assertions
class _FakeQueryBuilder extends Fake implements SupabaseQueryBuilder {
  _FakeQueryBuilder({this.listData = const [], this.singleData});

  final List<Map<String, dynamic>> listData;
  final Map<String, dynamic>? singleData;
  final _RecordedFilter recordedFilter = _RecordedFilter();
  final _RecordedOrder recordedOrder = _RecordedOrder();

  Map<String, dynamic>? lastInsertPayload;
  Map<String, dynamic>? lastUpdatePayload;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([
    String columns = '*',
  ]) => _FakeFilterBuilder(
    recordedFilter: recordedFilter,
    recordedOrder: recordedOrder,
    listData: listData,
    singleData: singleData,
  );

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> insert(
    Object values, {
    // ignore: deprecated_member_use, matching Supabase SDK signature
    ReturningOption? returning,
    bool defaultToNull = true,
  }) {
    lastInsertPayload = Map<String, dynamic>.from(values as Map);
    return _FakeFilterBuilder(
      recordedFilter: recordedFilter,
      recordedOrder: recordedOrder,
      listData: listData,
      singleData: singleData,
    );
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> update(
    Map<dynamic, dynamic> values, {
    // ignore: deprecated_member_use, matching Supabase SDK signature
    ReturningOption? returning,
  }) {
    lastUpdatePayload = Map<String, dynamic>.from(values);
    return _FakeFilterBuilder(
      recordedFilter: recordedFilter,
      recordedOrder: recordedOrder,
      listData: listData,
      singleData: singleData,
    );
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> delete({
    // ignore: deprecated_member_use, matching Supabase SDK signature
    ReturningOption? returning,
  }) => _FakeFilterBuilder(
    recordedFilter: recordedFilter,
    recordedOrder: recordedOrder,
    listData: listData,
    singleData: singleData,
  );
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

Map<String, dynamic> _zoneRow({
  String id = 'zone-1',
  String userId = 'user-1',
  String label = 'Home',
  double latitude = 51.5074,
  double longitude = -0.1278,
  int radiusMeters = 200,
}) => {
  'id': id,
  'user_id': userId,
  'label': label,
  'latitude': latitude,
  'longitude': longitude,
  'radius_meters': radiusMeters,
  'created_at': '2026-03-16T10:00:00Z',
  'updated_at': '2026-03-16T10:00:00Z',
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockSupabaseClient mockClient;
  late MockGoTrueClient mockAuth;
  late MockUser mockUser;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockGoTrueClient();
    mockUser = MockUser();

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user-1');
  });

  group('SupabasePrivacyZoneRepository', () {
    group('loadZones', () {
      test('returns mapped list ordered by created_at desc', () async {
        final fakeBuilder = _FakeQueryBuilder(
          listData: [
            _zoneRow(id: 'z1'),
            _zoneRow(id: 'z2', label: 'Work', latitude: 40.7128),
          ],
        );
        when(
          () => mockClient.from('privacy_zones'),
        ).thenAnswer((_) => fakeBuilder);

        final repo = SupabasePrivacyZoneRepository(mockClient);
        final zones = await repo.loadZones();

        expect(zones, hasLength(2));
        expect(zones[0].id, 'z1');
        expect(zones[0].label, 'Home');
        expect(zones[1].id, 'z2');
        expect(zones[1].latitude, 40.7128);
        expect(fakeBuilder.recordedOrder.column, 'created_at');
        expect(fakeBuilder.recordedOrder.ascending, isFalse);
      });

      test('returns empty list when no zones exist', () async {
        final fakeBuilder = _FakeQueryBuilder();
        when(
          () => mockClient.from('privacy_zones'),
        ).thenAnswer((_) => fakeBuilder);

        final repo = SupabasePrivacyZoneRepository(mockClient);
        final zones = await repo.loadZones();

        expect(zones, isEmpty);
      });
    });

    group('createZone', () {
      test('sends insert with user_id and returns created zone', () async {
        final createdRow = _zoneRow(
          id: 'new-zone-id',
          label: 'Gym',
          latitude: 48.8566,
          longitude: 2.3522,
          radiusMeters: 150,
        );
        final fakeBuilder = _FakeQueryBuilder(singleData: createdRow);
        when(
          () => mockClient.from('privacy_zones'),
        ).thenAnswer((_) => fakeBuilder);

        final repo = SupabasePrivacyZoneRepository(mockClient);
        final zone = await repo.createZone(
          label: 'Gym',
          latitude: 48.8566,
          longitude: 2.3522,
          radiusMeters: 150,
        );

        expect(zone.id, 'new-zone-id');
        expect(zone.label, 'Gym');
        expect(zone.latitude, 48.8566);
        expect(zone.radiusMeters, 150);

        // Verify user_id is included in the insert payload
        expect(fakeBuilder.lastInsertPayload!['user_id'], 'user-1');
        expect(fakeBuilder.lastInsertPayload!['label'], 'Gym');
        expect(fakeBuilder.lastInsertPayload!['latitude'], 48.8566);
        expect(fakeBuilder.lastInsertPayload!['longitude'], 2.3522);
        expect(fakeBuilder.lastInsertPayload!['radius_meters'], 150);
      });

      test('throws a StateError when no authenticated user exists', () async {
        when(() => mockAuth.currentUser).thenReturn(null);

        final repo = SupabasePrivacyZoneRepository(mockClient);

        await expectLater(
          () => repo.createZone(
            label: 'Gym',
            latitude: 48.8566,
            longitude: 2.3522,
            radiusMeters: 150,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Cannot create a privacy zone without an authenticated user.',
            ),
          ),
        );
        verifyNever(() => mockClient.from('privacy_zones'));
      });
    });

    group('updateZone', () {
      test('sends only mutable fields filtered by id', () async {
        final fakeBuilder = _FakeQueryBuilder();
        when(
          () => mockClient.from('privacy_zones'),
        ).thenAnswer((_) => fakeBuilder);

        final repo = SupabasePrivacyZoneRepository(mockClient);
        await repo.updateZone(
          const PrivacyZone(
            id: 'zone-1',
            userId: 'user-1',
            label: 'Updated Home',
            latitude: 51.51,
            longitude: -0.13,
            radiusMeters: 300,
          ),
        );

        expect(fakeBuilder.lastUpdatePayload!['label'], 'Updated Home');
        expect(fakeBuilder.lastUpdatePayload!['latitude'], 51.51);
        expect(fakeBuilder.lastUpdatePayload!['longitude'], -0.13);
        expect(fakeBuilder.lastUpdatePayload!['radius_meters'], 300);
        // Must NOT include id or user_id in update payload
        expect(fakeBuilder.lastUpdatePayload!.containsKey('id'), isFalse);
        expect(
          fakeBuilder.lastUpdatePayload!.containsKey('user_id'),
          isFalse,
        );
        expect(fakeBuilder.recordedFilter.eqColumn, 'id');
        expect(fakeBuilder.recordedFilter.eqValue, 'zone-1');
      });
    });

    group('deleteZone', () {
      test('calls delete filtered by id', () async {
        final fakeBuilder = _FakeQueryBuilder();
        when(
          () => mockClient.from('privacy_zones'),
        ).thenAnswer((_) => fakeBuilder);

        final repo = SupabasePrivacyZoneRepository(mockClient);
        // Should complete without error
        await repo.deleteZone('zone-1');

        expect(fakeBuilder.recordedFilter.eqColumn, 'id');
        expect(fakeBuilder.recordedFilter.eqValue, 'zone-1');
      });
    });
  });
}

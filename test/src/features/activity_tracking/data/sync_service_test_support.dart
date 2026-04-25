import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_repository.dart';

class MockTrackingRepository extends Mock implements TrackingRepository {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

/// NOTE(stuart): Document RecordedOperation.
class RecordedOperation {
  RecordedOperation({
    required this.table,
    required this.kind,
    this.payload,
    this.onConflict,
    this.eqColumn,
    this.eqValue,
  });

  final String table;
  final String kind;
  final Object? payload;
  final String? onConflict;
  final String? eqColumn;
  final Object? eqValue;
}

/// NOTE(stuart): Document FakeAwaitableFilterBuilder.
class FakeAwaitableFilterBuilder extends Fake
    implements PostgrestFilterBuilder<dynamic> {
  FakeAwaitableFilterBuilder({
    required this.table,
    required this.operations,
    this.responseData = const <Map<String, dynamic>>[],
  });

  final String table;
  final List<RecordedOperation> operations;
  final dynamic responseData;

  @override
  PostgrestFilterBuilder<dynamic> eq(String column, Object value) {
    operations.add(
      RecordedOperation(
        table: table,
        kind: 'eq',
        eqColumn: column,
        eqValue: value,
      ),
    );
    return this;
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(dynamic) onValue, {
    Function? onError,
  }) => Future<dynamic>.value(responseData).then(
    onValue,
    onError: onError,
  );

  @override
  Future<dynamic> catchError(
    Function onError, {
    bool Function(Object)? test,
  }) => Future<dynamic>.value(responseData).catchError(
    onError,
    test: test,
  );

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) =>
      Future<dynamic>.value(responseData).whenComplete(action);

  @override
  Stream<dynamic> asStream() => Stream<dynamic>.value(responseData);

  @override
  Future<dynamic> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) => Future<dynamic>.value(responseData).timeout(
    timeLimit,
    onTimeout: onTimeout,
  );
}

/// NOTE(stuart): Document FakeSelectFilterBuilder.
class FakeSelectFilterBuilder extends Fake
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  FakeSelectFilterBuilder({
    required this.table,
    required this.operations,
    required this.rows,
  });

  final String table;
  final List<RecordedOperation> operations;
  final List<Map<String, dynamic>> rows;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(
    String column,
    Object value,
  ) {
    operations.add(
      RecordedOperation(
        table: table,
        kind: 'eq',
        eqColumn: column,
        eqValue: value,
      ),
    );
    return this;
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>>) onValue, {
    Function? onError,
  }) => Future<List<Map<String, dynamic>>>.value(rows).then(
    onValue,
    onError: onError,
  );

  @override
  Future<List<Map<String, dynamic>>> catchError(
    Function onError, {
    bool Function(Object)? test,
  }) => Future<List<Map<String, dynamic>>>.value(rows).catchError(
    onError,
    test: test,
  );

  @override
  Future<List<Map<String, dynamic>>> whenComplete(
    FutureOr<void> Function() action,
  ) => Future<List<Map<String, dynamic>>>.value(rows).whenComplete(action);

  @override
  Stream<List<Map<String, dynamic>>> asStream() => Stream.value(rows);

  @override
  Future<List<Map<String, dynamic>>> timeout(
    Duration timeLimit, {
    FutureOr<List<Map<String, dynamic>>> Function()? onTimeout,
  }) => Future<List<Map<String, dynamic>>>.value(rows).timeout(
    timeLimit,
    onTimeout: onTimeout,
  );
}

/// NOTE(stuart): Document FakeSyncQueryBuilder.
class FakeSyncQueryBuilder extends Fake implements SupabaseQueryBuilder {
  FakeSyncQueryBuilder({
    required this.table,
    required this.operations,
    this.throwOnUpsert = false,
    this.selectRows = const <Map<String, dynamic>>[],
    this.insertError,
    this.upsertError,
    this.selectError,
  });

  final String table;
  final List<RecordedOperation> operations;
  final bool throwOnUpsert;
  final List<Map<String, dynamic>> selectRows;
  final Object? insertError;
  final Object? upsertError;
  final Object? selectError;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([
    String columns = '*',
  ]) {
    if (selectError != null) {
      _throwConfiguredError(selectError!);
    }
    operations.add(
      RecordedOperation(
        table: table,
        kind: 'select',
        payload: columns,
      ),
    );
    return FakeSelectFilterBuilder(
      table: table,
      operations: operations,
      rows: selectRows,
    );
  }

  @override
  PostgrestFilterBuilder<dynamic> upsert(
    Object values, {
    String? onConflict,
    bool ignoreDuplicates = false,
    bool defaultToNull = true,
  }) {
    if (upsertError != null) {
      _throwConfiguredError(upsertError!);
    }
    if (throwOnUpsert) {
      throw StateError('upsert failed for $table');
    }
    operations.add(
      RecordedOperation(
        table: table,
        kind: 'upsert',
        payload: values,
        onConflict: onConflict,
      ),
    );
    return FakeAwaitableFilterBuilder(table: table, operations: operations);
  }

  @override
  PostgrestFilterBuilder<dynamic> insert(
    Object values, {
    bool defaultToNull = true,
  }) {
    if (insertError != null) {
      _throwConfiguredError(insertError!);
    }
    operations.add(
      RecordedOperation(
        table: table,
        kind: 'insert',
        payload: values,
      ),
    );
    return FakeAwaitableFilterBuilder(table: table, operations: operations);
  }

  @override
  PostgrestFilterBuilder<dynamic> delete() {
    operations.add(RecordedOperation(table: table, kind: 'delete'));
    return FakeAwaitableFilterBuilder(table: table, operations: operations);
  }
}

/// NOTE(stuart): Document FakeStorageBucketApi.
class FakeStorageBucketApi extends Fake implements StorageFileApi {
  FakeStorageBucketApi({
    required this.bucketName,
    required this.operations,
    this.removeError,
  });

  final String bucketName;
  final List<RecordedOperation> operations;
  final Object? removeError;

  @override
  Future<List<FileObject>> remove(List<String> paths) async {
    if (removeError != null) {
      _throwConfiguredError(removeError!);
    }
    operations.add(
      RecordedOperation(
        table: bucketName,
        kind: 'storage_remove',
        payload: List<String>.from(paths),
      ),
    );
    return const <FileObject>[];
  }
}

class FakeSupabaseStorageClient extends Fake implements SupabaseStorageClient {
  FakeSupabaseStorageClient(this._buckets);

  final Map<String, StorageFileApi> _buckets;

  @override
  StorageFileApi from(String bucketId) {
    final bucket = _buckets[bucketId];
    if (bucket == null) {
      throw StateError('No fake storage bucket registered for $bucketId.');
    }
    return bucket;
  }
}

Never _throwConfiguredError(Object error) {
  if (error is Error) {
    throw error;
  }
  if (error is Exception) {
    throw error;
  }
  throw StateError(
    'Configured fake error for sync service tests must be Exception or Error, '
    'got ${error.runtimeType}.',
  );
}

Future<List<ConnectivityResult>> Function() buildConnectivityCheckSequence(
  List<List<ConnectivityResult>> states,
) {
  if (states.isEmpty) {
    throw ArgumentError.value(states, 'states', 'Must not be empty.');
  }

  var index = 0;
  return () async {
    final state = states[index < states.length ? index : states.length - 1];
    index += 1;
    return state;
  };
}

List<TrackingPoint> buildTestPoints({
  required int sessionId,
  required int count,
  DateTime? startAt,
}) {
  final start = startAt ?? DateTime(2026, 1, 1, 12);
  return List.generate(count, (index) {
    return TrackingPoint(
      sessionId: sessionId,
      timestamp: start.add(Duration(seconds: index * 5)),
      coordinate: GeoCoordinate(
        latitude: 37,
        longitude: -122.0 + (index * 0.0001),
      ),
      elevation: 5 + (index % 3).toDouble(),
      accuracy: 4,
      speed: 3.5,
    );
  });
}

// Query doubles intentionally record mutable call state and mirror SDK signatures.
// ignore_for_file: must_be_immutable
// ignore_for_file: strict_raw_type

import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class EqFilterCall {
  const EqFilterCall({
    required this.column,
    required this.value,
  });

  final String column;
  final Object value;
}

/// Awaits and exposes a single map response from a fake PostgREST query.
class AwaitablePostgrestMapBuilder extends Fake
    implements PostgrestTransformBuilder<Map<String, dynamic>> {
  AwaitablePostgrestMapBuilder(this._data);

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
  Future<Map<String, dynamic>> whenComplete(
    FutureOr<void> Function() action,
  ) => Future.value(_data).whenComplete(action);

  @override
  Stream<Map<String, dynamic>> asStream() => Stream.value(_data);

  @override
  Future<Map<String, dynamic>> timeout(
    Duration timeLimit, {
    FutureOr<Map<String, dynamic>> Function()? onTimeout,
  }) => Future.value(_data).timeout(timeLimit, onTimeout: onTimeout);
}

/// Fake [PostgrestFilterBuilder] that resolves to a single [Map] response.
///
/// Use this to mock `rpc<Map<String, dynamic>>('...')` calls.
class RecordingPostgrestMapBuilder extends Fake
    implements PostgrestFilterBuilder<Map<String, dynamic>> {
  RecordingPostgrestMapBuilder(this._data);

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
  Future<Map<String, dynamic>> whenComplete(
    FutureOr<void> Function() action,
  ) => Future.value(_data).whenComplete(action);

  @override
  Stream<Map<String, dynamic>> asStream() => Stream.value(_data);

  @override
  Future<Map<String, dynamic>> timeout(
    Duration timeLimit, {
    FutureOr<Map<String, dynamic>> Function()? onTimeout,
  }) => Future.value(_data).timeout(timeLimit, onTimeout: onTimeout);
}

/// Fake [PostgrestFilterBuilder] that resolves to a list of rows.
///
/// Use this to mock select queries and list-returning RPCs.
class RecordingPostgrestListBuilder extends Fake
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  RecordingPostgrestListBuilder(this._rows);

  final List<Map<String, dynamic>> _rows;
  String? lastSelectColumns;

  String? lastEqColumn;
  Object? lastEqValue;
  final List<EqFilterCall> eqCalls = <EqFilterCall>[];
  String? lastIlikeColumn;
  String? lastIlikePattern;
  String? lastGteColumn;
  Object? lastGteValue;
  String? lastNeqColumn;
  Object? lastNeqValue;
  String? lastInFilterColumn;
  List<Object?>? lastInFilterValues;
  String? lastOrderedColumn;
  bool? lastOrderAscending;
  int? lastRangeFrom;
  int? lastRangeTo;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([
    String columns = '*',
  ]) {
    lastSelectColumns = columns;
    return this;
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(
    String column,
    Object value,
  ) {
    eqCalls.add(EqFilterCall(column: column, value: value));
    lastEqColumn = column;
    lastEqValue = value;
    return this;
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> ilike(
    String column,
    String pattern,
  ) {
    lastIlikeColumn = column;
    lastIlikePattern = pattern;
    return this;
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> gte(
    String column,
    Object value,
  ) {
    lastGteColumn = column;
    lastGteValue = value;
    return this;
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> neq(
    String column,
    Object value,
  ) {
    lastNeqColumn = column;
    lastNeqValue = value;
    return this;
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> inFilter(
    String column,
    List values,
  ) {
    lastInFilterColumn = column;
    lastInFilterValues = List<Object?>.from(values);
    return this;
  }

  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) {
    lastOrderedColumn = column;
    lastOrderAscending = ascending;
    return this;
  }

  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> range(
    int from,
    int to, {
    String? foreignTable,
    String? referencedTable,
  }) {
    lastRangeFrom = from;
    lastRangeTo = to;
    return this;
  }

  @override
  PostgrestTransformBuilder<Map<String, dynamic>> single() {
    return AwaitablePostgrestMapBuilder(_rows.single);
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>>) onValue, {
    Function? onError,
  }) => Future.value(_rows).then(onValue, onError: onError);

  @override
  Future<List<Map<String, dynamic>>> catchError(
    Function onError, {
    bool Function(Object)? test,
  }) => Future.value(_rows).catchError(onError, test: test);

  @override
  Future<List<Map<String, dynamic>>> whenComplete(
    FutureOr<void> Function() action,
  ) => Future.value(_rows).whenComplete(action);

  @override
  Stream<List<Map<String, dynamic>>> asStream() => Stream.value(_rows);

  @override
  Future<List<Map<String, dynamic>>> timeout(
    Duration timeLimit, {
    FutureOr<List<Map<String, dynamic>>> Function()? onTimeout,
  }) => Future.value(_rows).timeout(timeLimit, onTimeout: onTimeout);
}

/// Fake Supabase query builder that records insert/update/delete payloads.
class RecordingSupabaseQueryBuilder extends Fake
    implements SupabaseQueryBuilder {
  RecordingSupabaseQueryBuilder({
    List<Map<String, dynamic>> selectRows = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>>? insertRows,
    List<Map<String, dynamic>>? updateRows,
    List<Map<String, dynamic>>? deleteRows,
  }) : selectBuilder = RecordingPostgrestListBuilder(selectRows),
       insertBuilder = RecordingPostgrestListBuilder(insertRows ?? selectRows),
       updateBuilder = RecordingPostgrestListBuilder(updateRows ?? const []),
       deleteBuilder = RecordingPostgrestListBuilder(deleteRows ?? const []);

  final RecordingPostgrestListBuilder selectBuilder;
  final RecordingPostgrestListBuilder insertBuilder;
  final RecordingPostgrestListBuilder updateBuilder;
  final RecordingPostgrestListBuilder deleteBuilder;

  Map<String, dynamic>? lastInsertPayload;
  Map<String, dynamic>? lastUpdatePayload;
  String? lastSelectColumns;
  bool deleteCalled = false;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([
    String columns = '*',
  ]) {
    lastSelectColumns = columns;
    return selectBuilder.select(columns);
  }

  @override
  PostgrestFilterBuilder insert(
    Object values, {
    bool defaultToNull = true,
  }) {
    lastInsertPayload = Map<String, dynamic>.from(values as Map);
    return insertBuilder;
  }

  @override
  PostgrestFilterBuilder update(Map values) {
    lastUpdatePayload = Map<String, dynamic>.from(values);
    return updateBuilder;
  }

  @override
  PostgrestFilterBuilder delete() {
    deleteCalled = true;
    return deleteBuilder;
  }
}

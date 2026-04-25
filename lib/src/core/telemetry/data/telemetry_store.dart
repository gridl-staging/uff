import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;

typedef JsonMap = Map<String, Object?>;

abstract class TelemetryStoreClient {
  Future<void> enqueue(JsonMap row);
  Future<List<JsonMap>> loadPending();
  Future<void> recordAttempt({
    required String eventId,
    required int attemptCount,
    required String lastAttemptStatus,
    DateTime? lastAttemptedAt,
  });
  Future<void> delete(String eventId);
  Future<void> clear();
}

/// TODO: Document TelemetryStore.
class TelemetryStore implements TelemetryStoreClient {
  TelemetryStore._(this._database);

  static const String _databaseFileName = 'telemetry.sqlite';
  static const String _queueTableName = 'telemetry_queue';

  static const String _eventIdColumn = 'event_id';
  static const String _capturedAtColumn = 'captured_at';
  static const String _contextColumn = 'context_json';
  static const String _metadataColumn = 'metadata_json';
  static const String _breadcrumbsColumn = 'breadcrumbs_json';
  static const String _attemptCountColumn = 'attempt_count';
  static const String _lastAttemptStatusColumn = 'last_attempt_status';
  static const String _lastAttemptedAtColumn = 'last_attempted_at';

  final _TelemetryStoreDatabase _database;
  bool _isClosed = false;

  static Future<TelemetryStore> open(String rootDirectoryPath) async {
    final rootDirectory = Directory(rootDirectoryPath);
    if (!rootDirectory.existsSync()) {
      rootDirectory.createSync(recursive: true);
    }

    final databasePath = path.join(rootDirectory.path, _databaseFileName);
    final database = _TelemetryStoreDatabase(
      NativeDatabase(File(databasePath)),
    );
    final store = TelemetryStore._(database);
    await store._ensureSchema();
    return store;
  }

  @override
  Future<void> enqueue(JsonMap row) async {
    _throwIfClosed();
    final lastAttemptedAt = row['lastAttemptedAt'] as String?;
    await _database.customStatement(
      '''
      INSERT INTO $_queueTableName (
        $_eventIdColumn,
        $_capturedAtColumn,
        $_contextColumn,
        $_metadataColumn,
        $_breadcrumbsColumn,
        $_attemptCountColumn,
        $_lastAttemptStatusColumn,
        $_lastAttemptedAtColumn
      )
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
      ''',
      <Object?>[
        _readRequiredString(row, 'eventId'),
        _readRequiredString(row, 'capturedAt'),
        _encodeMapField(_readRequiredMap(row, 'context')),
        _encodeMapField(_readRequiredMap(row, 'metadata')),
        _encodeListField(_readRequiredList(row, 'breadcrumbs')),
        _readRequiredInt(row, 'attemptCount'),
        _readRequiredString(row, 'lastAttemptStatus'),
        lastAttemptedAt,
      ],
    );
  }

  @override
  Future<List<JsonMap>> loadPending() async {
    _throwIfClosed();
    final result = await _database.customSelect(
      '''
      SELECT
        $_eventIdColumn,
        $_capturedAtColumn,
        $_contextColumn,
        $_metadataColumn,
        $_breadcrumbsColumn,
        $_attemptCountColumn,
        $_lastAttemptStatusColumn,
        $_lastAttemptedAtColumn
      FROM $_queueTableName
      ORDER BY rowid ASC
      ''',
    ).get();

    return result.map(_mapDatabaseRow).toList(growable: false);
  }

  @override
  Future<void> recordAttempt({
    required String eventId,
    required int attemptCount,
    required String lastAttemptStatus,
    DateTime? lastAttemptedAt,
  }) async {
    _throwIfClosed();
    final lastAttemptedAtIso = lastAttemptedAt?.toUtc().toIso8601String();
    await _database.customStatement(
      '''
      UPDATE $_queueTableName
      SET
        $_attemptCountColumn = ?2,
        $_lastAttemptStatusColumn = ?3,
        $_lastAttemptedAtColumn = ?4
      WHERE $_eventIdColumn = ?1
      ''',
      <Object?>[eventId, attemptCount, lastAttemptStatus, lastAttemptedAtIso],
    );
  }

  @override
  Future<void> delete(String eventId) async {
    _throwIfClosed();
    await _database.customStatement(
      '''
      DELETE FROM $_queueTableName
      WHERE $_eventIdColumn = ?1
      ''',
      <Object>[eventId],
    );
  }

  @override
  Future<void> clear() async {
    _throwIfClosed();
    await _database.customStatement('DELETE FROM $_queueTableName');
  }

  Future<void> close() async {
    if (_isClosed) {
      return;
    }

    await _database.close();
    _isClosed = true;
  }

  Future<void> _ensureSchema() async {
    await _database.customStatement(
      '''
      CREATE TABLE IF NOT EXISTS $_queueTableName (
        $_eventIdColumn TEXT PRIMARY KEY,
        $_capturedAtColumn TEXT NOT NULL,
        $_contextColumn TEXT NOT NULL,
        $_metadataColumn TEXT NOT NULL,
        $_breadcrumbsColumn TEXT NOT NULL,
        $_attemptCountColumn INTEGER NOT NULL,
        $_lastAttemptStatusColumn TEXT NOT NULL
      )
      ''',
    );

    // Migrate: add last_attempted_at column if it doesn't exist yet.
    // Uses PRAGMA table_info to check before ALTER TABLE so pre-existing
    // rows survive with a null default.
    final tableInfo = await _database
        .customSelect(
          'PRAGMA table_info($_queueTableName)',
        )
        .get();
    final columnNames = tableInfo
        .map((QueryRow row) => row.read<String>('name'))
        .toSet();
    if (!columnNames.contains(_lastAttemptedAtColumn)) {
      await _database.customStatement(
        'ALTER TABLE $_queueTableName '
        'ADD COLUMN $_lastAttemptedAtColumn TEXT',
      );
    }
  }

  JsonMap _mapDatabaseRow(QueryRow row) {
    return <String, Object?>{
      'eventId': row.read<String>(_eventIdColumn),
      'capturedAt': row.read<String>(_capturedAtColumn),
      'context': _decodeMapField(
        row.read<String>(_contextColumn),
        column: _contextColumn,
      ),
      'metadata': _decodeMapField(
        row.read<String>(_metadataColumn),
        column: _metadataColumn,
      ),
      'breadcrumbs': _decodeBreadcrumbsField(
        row.read<String>(_breadcrumbsColumn),
      ),
      'attemptCount': row.read<int>(_attemptCountColumn),
      'lastAttemptStatus': row.read<String>(_lastAttemptStatusColumn),
      'lastAttemptedAt': row.readNullable<String>(_lastAttemptedAtColumn),
    };
  }

  String _encodeMapField(JsonMap value) => jsonEncode(value);

  String _encodeListField(List<Object?> value) => jsonEncode(value);

  JsonMap _decodeMapField(String serializedValue, {required String column}) {
    final decodedValue = jsonDecode(serializedValue);
    if (decodedValue is! Map) {
      throw StateError(
        'Expected JSON object in $column, got ${decodedValue.runtimeType}.',
      );
    }

    return Map<String, Object?>.from(
      decodedValue.map(
        (Object? key, Object? value) => MapEntry<String, Object?>(
          key! as String,
          value,
        ),
      ),
    );
  }

  List<Object?> _decodeBreadcrumbsField(String serializedValue) {
    final decodedValue = jsonDecode(serializedValue);
    if (decodedValue is! List) {
      throw StateError(
        'Expected JSON array in $_breadcrumbsColumn, got ${decodedValue.runtimeType}.',
      );
    }

    return decodedValue.map(_mapDecodedBreadcrumbItem).toList(growable: false);
  }

  Object? _mapDecodedBreadcrumbItem(Object? item) {
    if (item is! Map) {
      return item;
    }

    return Map<String, Object?>.from(
      item.map(
        (Object? key, Object? value) => MapEntry<String, Object?>(
          key! as String,
          value,
        ),
      ),
    );
  }

  String _readRequiredString(JsonMap row, String key) {
    final value = row[key];
    if (value is String) {
      return value;
    }

    throw ArgumentError.value(value, key, 'Expected a String.');
  }

  int _readRequiredInt(JsonMap row, String key) {
    final value = row[key];
    if (value is int) {
      return value;
    }
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }

    throw ArgumentError.value(value, key, 'Expected an integer.');
  }

  JsonMap _readRequiredMap(JsonMap row, String key) {
    final value = row[key];
    if (value is Map<String, Object?>) {
      return value;
    }

    throw ArgumentError.value(value, key, 'Expected a Map<String, Object?>.');
  }

  List<Object?> _readRequiredList(JsonMap row, String key) {
    final value = row[key];
    if (value is List<Object?>) {
      return value;
    }

    throw ArgumentError.value(value, key, 'Expected a List<Object?>.');
  }

  void _throwIfClosed() {
    if (!_isClosed) {
      return;
    }

    throw StateError('TelemetryStore is already closed.');
  }
}

class _TelemetryStoreDatabase extends GeneratedDatabase {
  _TelemetryStoreDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      const <DatabaseSchemaEntity>[];
}

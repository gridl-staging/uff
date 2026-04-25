import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart'
    as tracking_domain;
import 'package:uff/src/features/photos/domain/pending_photo.dart';

part 'tracking_database.g.dart';

/// TODO: Document TrackingDatabase.
@DriftDatabase(tables: [TrackingSessions, TrackingPoints])
class TrackingDatabase extends _$TrackingDatabase {
  TrackingDatabase() : super(_openConnection());

  factory TrackingDatabase.forTesting(QueryExecutor executor) {
    return TrackingDatabase._(executor);
  }

  TrackingDatabase._(super.executor);

  static const String _trackingSessionSelectSql = '''
    SELECT
      id,
      status,
      created_at,
      updated_at,
      started_at,
      stopped_at,
      title,
      description,
      distance_meters,
      moving_time_seconds,
      elevation_gain_meters,
      remote_id,
      sport_type,
      visibility
    FROM tracking_sessions
  ''';

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _ensureColumn('tracking_sessions', 'remote_id', 'TEXT');
      await _ensureSyncQueueTable();
      await _ensurePendingPhotosTable();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(trackingSessions, trackingSessions.title);
        await migrator.addColumn(
          trackingSessions,
          trackingSessions.description,
        );
        await migrator.addColumn(
          trackingSessions,
          trackingSessions.distanceMeters,
        );
        await migrator.addColumn(
          trackingSessions,
          trackingSessions.movingTimeSeconds,
        );
        await migrator.addColumn(
          trackingSessions,
          trackingSessions.elevationGainMeters,
        );
      }
      if (from < 3) {
        await _ensureColumn('tracking_sessions', 'remote_id', 'TEXT');
        await _ensureSyncQueueTable();
      }
      if (from < 4) {
        await _ensureColumn('tracking_sessions', 'sport_type', 'TEXT');
        await _ensureSensorColumns();
      }
      if (from < 5) {
        await _ensureColumn('tracking_sessions', 'visibility', 'TEXT');
      }
      if (from < 6) {
        await _ensurePendingPhotosTable();
      }
      if (from < 7) {
        await _ensureColumn('pending_photos', 'latitude', 'REAL');
        await _ensureColumn('pending_photos', 'longitude', 'REAL');
      }
    },
  );

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final dbFile = File(
        path.join(documentsDirectory.path, 'activity_tracking.sqlite'),
      );
      return NativeDatabase(dbFile);
    });
  }

  Future<int> insertSession(TrackingSessionsCompanion companion) {
    return into(trackingSessions).insert(companion);
  }

  Future<List<tracking_domain.TrackingSessionRecord>>
  loadSavedSessions() async {
    final rows = await customSelect(
      '''
      $_trackingSessionSelectSql
      WHERE status = ?1
      ORDER BY started_at DESC
      ''',
      variables: [
        Variable.withInt(tracking_domain.TrackingSessionStatus.saved.index),
      ],
      readsFrom: {trackingSessions},
    ).get();
    return rows.map(_mapSessionQueryRow).toList(growable: false);
  }

  Future<tracking_domain.TrackingSessionRecord?> loadSession(int id) async {
    final row = await customSelect(
      '''
      $_trackingSessionSelectSql
      WHERE id = ?1
      LIMIT 1
      ''',
      variables: [Variable.withInt(id)],
      readsFrom: {trackingSessions},
    ).getSingleOrNull();

    if (row == null) {
      return null;
    }
    return _mapSessionQueryRow(row);
  }

  Future<void> saveSession(TrackingSessionsCompanion companion) {
    if (!companion.id.present) {
      throw ArgumentError.value(
        companion,
        'companion',
        'Session id is required.',
      );
    }

    final sessionId = companion.id.value;
    final sessionUpdate = companion.copyWith(id: const Value.absent());
    return (update(
      trackingSessions,
    )..where((table) => table.id.equals(sessionId))).write(sessionUpdate);
  }

  Future<tracking_domain.TrackingSessionRecord?> loadActiveSession() async {
    final row = await customSelect(
      '''
      $_trackingSessionSelectSql
      WHERE status IN (?1, ?2, ?3, ?4)
      ORDER BY updated_at DESC
      LIMIT 1
      ''',
      variables: [
        Variable.withInt(tracking_domain.TrackingSessionStatus.recording.index),
        Variable.withInt(tracking_domain.TrackingSessionStatus.paused.index),
        Variable.withInt(tracking_domain.TrackingSessionStatus.stopped.index),
        Variable.withInt(tracking_domain.TrackingSessionStatus.saving.index),
      ],
      readsFrom: {trackingSessions},
    ).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _mapSessionQueryRow(row);
  }

  Future<List<tracking_domain.TrackingPoint>> loadPoints(int sessionId) async {
    final query = select(trackingPoints)
      ..where((table) => table.sessionId.equals(sessionId))
      ..orderBy([
        (table) => OrderingTerm(expression: table.timestamp),
      ]);
    final points = await query.get();
    return points.map((point) => point.toDomain()).toList(growable: false);
  }

  Future<List<tracking_domain.SyncQueueEntry>> loadSyncQueueEntriesByStatus(
    tracking_domain.SyncQueueEntryStatus status,
  ) async {
    final rows = await customSelect(
      '''
      SELECT session_id, status, retry_count, last_error, queued_at
      FROM sync_queue
      WHERE status = ?1
      ORDER BY queued_at ASC
      ''',
      variables: [Variable.withInt(status.index)],
    ).get();
    return rows.map(_mapSyncQueueQueryRow).toList(growable: false);
  }

  Future<tracking_domain.SyncQueueEntry?> loadSyncQueueEntry(
    int sessionId,
  ) async {
    final row = await customSelect(
      '''
      SELECT session_id, status, retry_count, last_error, queued_at
      FROM sync_queue
      WHERE session_id = ?1
      LIMIT 1
      ''',
      variables: [Variable.withInt(sessionId)],
    ).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _mapSyncQueueQueryRow(row);
  }

  Future<void> upsertSyncQueueEntryRaw({
    required int sessionId,
    required tracking_domain.SyncQueueEntryStatus status,
    required DateTime queuedAt,
    required int retryCount,
    String? lastError,
  }) async {
    await customStatement(
      '''
      INSERT INTO sync_queue (
        session_id,
        status,
        retry_count,
        last_error,
        queued_at
      )
      VALUES (?1, ?2, ?3, ?4, ?5)
      ON CONFLICT(session_id) DO UPDATE SET
        status = excluded.status,
        retry_count = excluded.retry_count,
        last_error = excluded.last_error,
        queued_at = excluded.queued_at
      ''',
      [
        sessionId,
        status.index,
        retryCount,
        lastError,
        queuedAt.millisecondsSinceEpoch ~/ 1000,
      ],
    );
  }

  Future<void> updateSyncQueueEntryStatusRaw({
    required int sessionId,
    required tracking_domain.SyncQueueEntryStatus status,
    int? retryCount,
    String? lastError,
  }) async {
    final retryCountExpression = retryCount == null ? 'retry_count' : '?3';
    final retryCountArgument = retryCount ?? 0;
    await customStatement(
      '''
      UPDATE sync_queue
      SET
        status = ?2,
        retry_count = $retryCountExpression,
        last_error = ?4
      WHERE session_id = ?1
      ''',
      [
        sessionId,
        status.index,
        retryCountArgument,
        lastError,
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Pending photos — local queue for photos captured during recording.
  // Photos are stored on-device until the activity syncs and receives a
  // remoteId, at which point they're uploaded to Supabase Storage. See
  // chats/mar25_pm_6_midrun_photo_capture.md for the architecture rationale.
  // ---------------------------------------------------------------------------

  /// Inserts a pending photo row and returns its auto-generated id.
  Future<int> savePendingPhoto({
    required int sessionId,
    required String localPath,
    required DateTime capturedAt,
    double? latitude,
    double? longitude,
  }) async {
    final result = await customInsert(
      '''
      INSERT INTO pending_photos
        (session_id, local_path, captured_at, latitude, longitude)
      VALUES (?1, ?2, ?3, ?4, ?5)
      ''',
      variables: [
        Variable.withInt(sessionId),
        Variable.withString(localPath),
        // Store as Unix seconds — consistent with sync_queue's queued_at.
        Variable.withInt(capturedAt.millisecondsSinceEpoch ~/ 1000),
        latitude != null ? Variable.withReal(latitude) : const Variable(null),
        longitude != null ? Variable.withReal(longitude) : const Variable(null),
      ],
      updates: {},
    );
    return result;
  }

  /// Returns all pending photos for [sessionId], ordered by capture time
  /// (earliest first). Returns an empty list if no photos exist.
  Future<List<PendingPhoto>> loadPendingPhotos(int sessionId) async {
    final rows = await customSelect(
      '''
      SELECT id, session_id, local_path, captured_at, latitude, longitude
      FROM pending_photos
      WHERE session_id = ?1
      ORDER BY captured_at ASC
      ''',
      variables: [Variable.withInt(sessionId)],
    ).get();
    return rows.map(_mapPendingPhotoRow).toList(growable: false);
  }

  /// Deletes a single pending photo by its primary key.
  Future<void> deletePendingPhoto(int id) async {
    await customStatement(
      'DELETE FROM pending_photos WHERE id = ?1',
      [id],
    );
  }

  /// Deletes all pending photos for a session. Called when the user discards
  /// a recording. Does not affect photos from other sessions.
  Future<void> deleteAllPendingPhotosForSession(int sessionId) async {
    await customStatement(
      'DELETE FROM pending_photos WHERE session_id = ?1',
      [sessionId],
    );
  }

  /// Returns the number of pending photos for a session. Used together with
  /// the remote photo count to enforce the 20-photo-per-activity limit.
  Future<int> countPendingPhotosForSession(int sessionId) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS cnt FROM pending_photos WHERE session_id = ?1',
      variables: [Variable.withInt(sessionId)],
    ).getSingle();
    return row.read<int>('cnt');
  }

  PendingPhoto _mapPendingPhotoRow(QueryRow row) {
    return PendingPhoto(
      id: row.read<int>('id'),
      sessionId: row.read<int>('session_id'),
      localPath: row.read<String>('local_path'),
      // Stored as Unix seconds — convert back to DateTime.
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('captured_at') * 1000,
      ),
      latitude: row.readNullable<double>('latitude'),
      longitude: row.readNullable<double>('longitude'),
    );
  }

  /// Idempotently creates the pending_photos table for mid-run photo capture.
  Future<void> _ensurePendingPhotosTable() async {
    final tableRows = await customSelect(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name = 'pending_photos'
      ''',
    ).get();
    if (tableRows.isNotEmpty) {
      return;
    }

    await customStatement('''
      CREATE TABLE pending_photos (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        local_path TEXT NOT NULL,
        captured_at INTEGER NOT NULL,
        latitude REAL,
        longitude REAL
      )
    ''');
  }

  /// Idempotently adds [column] (with SQL type [columnDef]) to [table].
  Future<void> _ensureColumn(
    String table,
    String column,
    String columnDef,
  ) async {
    final columns = await customSelect(
      "PRAGMA table_info('$table')",
    ).get();
    final exists = columns.any((row) => row.data['name'] == column);
    if (exists) return;
    await customStatement(
      'ALTER TABLE $table ADD COLUMN $column $columnDef',
    );
  }

  Future<void> _ensureSyncQueueTable() async {
    final tableRows = await customSelect(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name = 'sync_queue'
      ''',
    ).get();
    if (tableRows.isNotEmpty) {
      return;
    }

    await customStatement('''
      CREATE TABLE sync_queue (
        session_id INTEGER NOT NULL
          REFERENCES tracking_sessions (id) ON DELETE CASCADE,
        status INTEGER NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        queued_at INTEGER NOT NULL,
        PRIMARY KEY (session_id)
      )
    ''');
  }

  Future<void> _ensureSensorColumns() async {
    await _ensureColumn('tracking_points', 'heart_rate_bpm', 'INTEGER');
    await _ensureColumn('tracking_points', 'cadence_rpm', 'REAL');
    await _ensureColumn('tracking_points', 'power_watts', 'INTEGER');
  }

  tracking_domain.TrackingSessionRecord _mapSessionQueryRow(QueryRow row) {
    return tracking_domain.TrackingSessionRecord(
      id: row.read<int>('id'),
      status:
          tracking_domain.TrackingSessionStatus.values[row.read<int>('status')],
      createdAt: row.read<DateTime>('created_at'),
      updatedAt: row.read<DateTime>('updated_at'),
      startedAt: row.readNullable<DateTime>('started_at'),
      stoppedAt: row.readNullable<DateTime>('stopped_at'),
      title: row.readNullable<String>('title'),
      description: row.readNullable<String>('description'),
      distanceMeters: row.readNullable<double>('distance_meters'),
      movingTimeSeconds: row.readNullable<int>('moving_time_seconds'),
      elevationGainMeters: row.readNullable<double>('elevation_gain_meters'),
      remoteId: row.readNullable<String>('remote_id'),
      sportType: row.readNullable<String>('sport_type'),
      visibility: row.readNullable<String>('visibility'),
    );
  }

  tracking_domain.SyncQueueEntry _mapSyncQueueQueryRow(QueryRow row) {
    return tracking_domain.SyncQueueEntry(
      sessionId: row.read<int>('session_id'),
      status:
          tracking_domain.SyncQueueEntryStatus.values[row.read<int>('status')],
      retryCount: row.read<int>('retry_count'),
      lastError: row.readNullable<String>('last_error'),
      queuedAt: row.read<DateTime>('queued_at'),
    );
  }
}

/// NOTE(stuart): Document TrackingSessions.
class TrackingSessions extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get status => intEnum<tracking_domain.TrackingSessionStatus>()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  DateTimeColumn get startedAt => dateTime().nullable()();

  DateTimeColumn get stoppedAt => dateTime().nullable()();

  TextColumn get title => text().nullable()();

  TextColumn get description => text().nullable()();

  RealColumn get distanceMeters => real().nullable()();

  IntColumn get movingTimeSeconds => integer().nullable()();

  RealColumn get elevationGainMeters => real().nullable()();

  TextColumn get remoteId => text().nullable()();

  TextColumn get sportType => text().nullable()();

  TextColumn get visibility => text().nullable()();
}

/// NOTE(stuart): Document TrackingPoints.
@DataClassName('TrackingPointsData')
class TrackingPoints extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get sessionId => integer().references(TrackingSessions, #id)();

  DateTimeColumn get timestamp => dateTime()();

  RealColumn get latitude => real()();

  RealColumn get longitude => real()();

  RealColumn get elevation => real().nullable()();

  RealColumn get accuracy => real().nullable()();

  RealColumn get speed => real().nullable()();

  IntColumn get heartRateBpm => integer().nullable()();

  RealColumn get cadenceRpm => real().nullable()();

  IntColumn get powerWatts => integer().nullable()();

  @override
  List<String> get customConstraints => [
    'UNIQUE(session_id, timestamp, latitude, longitude)',
  ];
}

/// NOTE(stuart): Document TrackingSessionRecordToCompanion.
extension TrackingSessionRecordToCompanion
    on tracking_domain.TrackingSessionRecord {
  TrackingSessionsCompanion toCompanion() {
    return TrackingSessionsCompanion(
      id: Value(id),
      status: Value(status),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      startedAt: Value(startedAt),
      stoppedAt: Value(stoppedAt),
      title: Value(title),
      description: Value(description),
      distanceMeters: Value(distanceMeters),
      movingTimeSeconds: Value(movingTimeSeconds),
      elevationGainMeters: Value(elevationGainMeters),
      sportType: Value(sportType),
      visibility: Value(visibility),
    );
  }
}

/// NOTE(stuart): Document TrackingPointDataRowMapper.
extension TrackingPointDataRowMapper on TrackingPointsData {
  tracking_domain.TrackingPoint toDomain() {
    return tracking_domain.TrackingPoint(
      sessionId: sessionId,
      timestamp: timestamp,
      coordinate: tracking_domain.GeoCoordinate(
        latitude: latitude,
        longitude: longitude,
      ),
      elevation: elevation,
      accuracy: accuracy,
      speed: speed,
      heartRateBpm: heartRateBpm,
      cadenceRpm: cadenceRpm,
      powerWatts: powerWatts,
    );
  }
}

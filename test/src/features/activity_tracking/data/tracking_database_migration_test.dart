import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart';

/// ## Test Scenarios
/// - [positive] Existing tracking tables upgrade cleanly to the new photo columns.
/// - [negative] Migration skips already-present columns without corrupting rows.
/// - [isolation] A fresh in-memory database migration does not depend on prior test state.

void main() {
  group('TrackingDatabase migration v2 -> v3', () {
    late TrackingDatabase database;

    setUp(() {
      database = TrackingDatabase.forTesting(
        NativeDatabase.memory(
          setup: (rawDatabase) {
            rawDatabase
              ..execute('''
                CREATE TABLE tracking_sessions (
                  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                  status INTEGER NOT NULL,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL,
                  started_at INTEGER,
                  stopped_at INTEGER,
                  title TEXT,
                  description TEXT,
                  distance_meters REAL,
                  moving_time_seconds INTEGER,
                  elevation_gain_meters REAL
                );
              ''')
              ..execute('''
                CREATE TABLE tracking_points (
                  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                  session_id INTEGER NOT NULL REFERENCES tracking_sessions (id),
                  timestamp INTEGER NOT NULL,
                  latitude REAL NOT NULL,
                  longitude REAL NOT NULL,
                  elevation REAL,
                  accuracy REAL,
                  speed REAL,
                  UNIQUE(session_id, timestamp, latitude, longitude)
                );
              ''')
              ..execute('PRAGMA user_version = 2;');
          },
        ),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('creates SyncQueue table and adds remoteId column', () async {
      await database.customSelect('SELECT 1').getSingle();

      final syncQueueTable = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'sync_queue'",
          )
          .get();
      expect(syncQueueTable, hasLength(1));

      final trackingSessionColumns = await database
          .customSelect(
            "PRAGMA table_info('tracking_sessions')",
          )
          .get();
      final hasRemoteIdColumn = trackingSessionColumns.any(
        (column) => column.data['name'] == 'remote_id',
      );
      expect(hasRemoteIdColumn, isTrue);
    });
  });

  group('TrackingDatabase migration v3 -> v4', () {
    late TrackingDatabase database;

    setUp(() {
      database = TrackingDatabase.forTesting(
        NativeDatabase.memory(
          setup: (rawDatabase) {
            rawDatabase
              ..execute('''
                CREATE TABLE tracking_sessions (
                  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                  status INTEGER NOT NULL,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL,
                  started_at INTEGER,
                  stopped_at INTEGER,
                  title TEXT,
                  description TEXT,
                  distance_meters REAL,
                  moving_time_seconds INTEGER,
                  elevation_gain_meters REAL,
                  remote_id TEXT
                );
              ''')
              ..execute('''
                CREATE TABLE tracking_points (
                  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                  session_id INTEGER NOT NULL REFERENCES tracking_sessions (id),
                  timestamp INTEGER NOT NULL,
                  latitude REAL NOT NULL,
                  longitude REAL NOT NULL,
                  elevation REAL,
                  accuracy REAL,
                  speed REAL,
                  UNIQUE(session_id, timestamp, latitude, longitude)
                );
              ''')
              ..execute('''
                CREATE TABLE sync_queue (
                  session_id INTEGER NOT NULL
                    REFERENCES tracking_sessions (id) ON DELETE CASCADE,
                  status INTEGER NOT NULL,
                  retry_count INTEGER NOT NULL DEFAULT 0,
                  last_error TEXT,
                  queued_at INTEGER NOT NULL,
                  PRIMARY KEY (session_id)
                );
              ''')
              ..execute('PRAGMA user_version = 3;');
          },
        ),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'adds sensor columns to tracking_points and sport_type to sessions',
      () async {
        // Trigger migration by touching the database
        await database.customSelect('SELECT 1').getSingle();

        // Verify sport_type column on tracking_sessions
        final sessionColumns = await database
            .customSelect(
              "PRAGMA table_info('tracking_sessions')",
            )
            .get();
        final hasSportType = sessionColumns.any(
          (column) => column.data['name'] == 'sport_type',
        );
        expect(hasSportType, isTrue);

        // Verify sensor columns on tracking_points
        final pointColumns = await database
            .customSelect(
              "PRAGMA table_info('tracking_points')",
            )
            .get();
        final columnNames = pointColumns
            .map((c) => c.data['name'] as String)
            .toSet();
        expect(columnNames, contains('heart_rate_bpm'));
        expect(columnNames, contains('cadence_rpm'));
        expect(columnNames, contains('power_watts'));
      },
    );

    test('preserves existing v3 data after migration', () async {
      // Insert v3 data before migration runs
      await database.customStatement('''
        INSERT INTO tracking_sessions (id, status, created_at, updated_at, remote_id)
        VALUES (1, 8, 1704067200, 1704067200, 'remote-1')
      ''');
      await database.customStatement('''
        INSERT INTO tracking_points
          (session_id, timestamp, latitude, longitude, elevation, speed)
        VALUES (1, 1704067200, 40.0, -74.0, 100.0, 3.5)
      ''');

      // Trigger migration
      await database.customSelect('SELECT 1').getSingle();

      // Verify session data survived
      final sessions = await database
          .customSelect(
            'SELECT * FROM tracking_sessions WHERE id = 1',
          )
          .get();
      expect(sessions, hasLength(1));
      expect(sessions.first.data['remote_id'], 'remote-1');

      // Verify point data survived with nulls for new columns
      final points = await database
          .customSelect(
            'SELECT * FROM tracking_points WHERE session_id = 1',
          )
          .get();
      expect(points, hasLength(1));
      expect(points.first.data['latitude'], 40.0);
      expect(points.first.data['speed'], 3.5);
      expect(points.first.data['heart_rate_bpm'], isNull);
      expect(points.first.data['cadence_rpm'], isNull);
      expect(points.first.data['power_watts'], isNull);
    });

    test(
      'round-trips sensor fields and sport_type through insert and query',
      () async {
        // Trigger migration
        await database.customSelect('SELECT 1').getSingle();

        // Insert session with sport_type
        await database.customStatement('''
        INSERT INTO tracking_sessions
          (id, status, created_at, updated_at, sport_type)
        VALUES (1, 8, 1704067200, 1704067200, 'ride')
      ''');

        // Insert point with sensor fields
        await database.customStatement('''
        INSERT INTO tracking_points
          (session_id, timestamp, latitude, longitude, heart_rate_bpm,
           cadence_rpm, power_watts)
        VALUES (1, 1704067200, 40.0, -74.0, 155, 85.5, 250)
      ''');

        // Query back
        final sessions = await database
            .customSelect(
              'SELECT sport_type FROM tracking_sessions WHERE id = 1',
            )
            .get();
        expect(sessions.first.data['sport_type'], 'ride');

        final points = await database.customSelect(
          '''
SELECT heart_rate_bpm, cadence_rpm, power_watts
FROM tracking_points WHERE session_id = 1''',
        ).get();
        expect(points.first.data['heart_rate_bpm'], 155);
        expect(points.first.data['cadence_rpm'], 85.5);
        expect(points.first.data['power_watts'], 250);
      },
    );
  });

  group('TrackingDatabase migration v4 -> v5', () {
    late TrackingDatabase database;

    setUp(() {
      database = TrackingDatabase.forTesting(
        NativeDatabase.memory(
          setup: (rawDatabase) {
            rawDatabase
              ..execute('''
                CREATE TABLE tracking_sessions (
                  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                  status INTEGER NOT NULL,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL,
                  started_at INTEGER,
                  stopped_at INTEGER,
                  title TEXT,
                  description TEXT,
                  distance_meters REAL,
                  moving_time_seconds INTEGER,
                  elevation_gain_meters REAL,
                  remote_id TEXT,
                  sport_type TEXT
                );
              ''')
              ..execute('''
                CREATE TABLE tracking_points (
                  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                  session_id INTEGER NOT NULL REFERENCES tracking_sessions (id),
                  timestamp INTEGER NOT NULL,
                  latitude REAL NOT NULL,
                  longitude REAL NOT NULL,
                  elevation REAL,
                  accuracy REAL,
                  speed REAL,
                  heart_rate_bpm INTEGER,
                  cadence_rpm REAL,
                  power_watts INTEGER,
                  UNIQUE(session_id, timestamp, latitude, longitude)
                );
              ''')
              ..execute('''
                CREATE TABLE sync_queue (
                  session_id INTEGER NOT NULL
                    REFERENCES tracking_sessions (id) ON DELETE CASCADE,
                  status INTEGER NOT NULL,
                  retry_count INTEGER NOT NULL DEFAULT 0,
                  last_error TEXT,
                  queued_at INTEGER NOT NULL,
                  PRIMARY KEY (session_id)
                );
              ''')
              ..execute('PRAGMA user_version = 4;');
          },
        ),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('adds visibility column to tracking_sessions', () async {
      await database.customSelect('SELECT 1').getSingle();

      final sessionColumns = await database
          .customSelect(
            "PRAGMA table_info('tracking_sessions')",
          )
          .get();
      final hasVisibility = sessionColumns.any(
        (column) => column.data['name'] == 'visibility',
      );
      expect(hasVisibility, isTrue);
    });

    test('preserves v4 session data with null visibility', () async {
      await database.customStatement('''
        INSERT INTO tracking_sessions (
          id,
          status,
          created_at,
          updated_at,
          title,
          sport_type
        ) VALUES (1, 5, 1704067200, 1704067300, 'Before visibility', 'run')
      ''');

      await database.customSelect('SELECT 1').getSingle();

      final sessionRows = await database
          .customSelect(
            'SELECT * FROM tracking_sessions WHERE id = 1',
          )
          .get();
      expect(sessionRows, hasLength(1));
      expect(sessionRows.first.data['title'], 'Before visibility');
      expect(sessionRows.first.data['sport_type'], 'run');
      expect(sessionRows.first.data['visibility'], isNull);
    });

    test('round-trips visibility through raw insert and query', () async {
      await database.customSelect('SELECT 1').getSingle();

      await database.customStatement('''
        INSERT INTO tracking_sessions (
          id,
          status,
          created_at,
          updated_at,
          visibility
        ) VALUES (1, 5, 1704067200, 1704067300, 'private')
      ''');

      final sessionRows = await database
          .customSelect(
            'SELECT visibility FROM tracking_sessions WHERE id = 1',
          )
          .get();
      expect(sessionRows, hasLength(1));
      expect(sessionRows.first.data['visibility'], 'private');
    });
  });

  group('TrackingDatabase migration v6 -> v7', () {
    late TrackingDatabase database;

    setUp(() {
      database = TrackingDatabase.forTesting(
        NativeDatabase.memory(
          setup: (rawDatabase) {
            rawDatabase
              ..execute('''
                CREATE TABLE tracking_sessions (
                  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                  status INTEGER NOT NULL,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL,
                  started_at INTEGER,
                  stopped_at INTEGER,
                  title TEXT,
                  description TEXT,
                  distance_meters REAL,
                  moving_time_seconds INTEGER,
                  elevation_gain_meters REAL,
                  remote_id TEXT,
                  sport_type TEXT,
                  visibility TEXT
                );
              ''')
              ..execute('''
                CREATE TABLE tracking_points (
                  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                  session_id INTEGER NOT NULL REFERENCES tracking_sessions (id),
                  timestamp INTEGER NOT NULL,
                  latitude REAL NOT NULL,
                  longitude REAL NOT NULL,
                  elevation REAL,
                  accuracy REAL,
                  speed REAL,
                  heart_rate_bpm INTEGER,
                  cadence_rpm REAL,
                  power_watts INTEGER,
                  UNIQUE(session_id, timestamp, latitude, longitude)
                );
              ''')
              ..execute('''
                CREATE TABLE sync_queue (
                  session_id INTEGER NOT NULL
                    REFERENCES tracking_sessions (id) ON DELETE CASCADE,
                  status INTEGER NOT NULL,
                  retry_count INTEGER NOT NULL DEFAULT 0,
                  last_error TEXT,
                  queued_at INTEGER NOT NULL,
                  PRIMARY KEY (session_id)
                );
              ''')
              ..execute('''
                CREATE TABLE pending_photos (
                  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                  session_id INTEGER NOT NULL,
                  local_path TEXT NOT NULL,
                  captured_at INTEGER NOT NULL
                );
              ''')
              ..execute('PRAGMA user_version = 6;');
          },
        ),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('adds latitude and longitude columns to pending_photos', () async {
      await database.customSelect('SELECT 1').getSingle();

      final columns = await database
          .customSelect("PRAGMA table_info('pending_photos')")
          .get();
      final columnNames = columns.map((c) => c.data['name'] as String).toSet();
      expect(columnNames, contains('latitude'));
      expect(columnNames, contains('longitude'));

      // Verify the column types are REAL
      final latCol = columns.firstWhere(
        (c) => c.data['name'] == 'latitude',
      );
      final lngCol = columns.firstWhere(
        (c) => c.data['name'] == 'longitude',
      );
      expect(latCol.data['type'], 'REAL');
      expect(lngCol.data['type'], 'REAL');
    });

    test(
      'preserves existing v6 pending_photos rows with null lat/lng',
      () async {
        // Insert a v6 row before migration
        await database.customStatement('''
        INSERT INTO pending_photos (id, session_id, local_path, captured_at)
        VALUES (1, 42, '/tmp/photos/42/abc.jpg', 1711612200)
      ''');

        // Trigger migration
        await database.customSelect('SELECT 1').getSingle();

        final rows = await database
            .customSelect(
              'SELECT * FROM pending_photos WHERE id = 1',
            )
            .get();
        expect(rows, hasLength(1));
        expect(rows.first.data['session_id'], 42);
        expect(rows.first.data['local_path'], '/tmp/photos/42/abc.jpg');
        expect(rows.first.data['captured_at'], 1711612200);
        expect(rows.first.data['latitude'], isNull);
        expect(rows.first.data['longitude'], isNull);
      },
    );
  });
}

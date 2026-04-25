import 'dart:io';

import 'package:drift/drift.dart'
    show DatabaseSchemaEntity, GeneratedDatabase, Table, TableInfo;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:uff/src/core/telemetry/data/telemetry_store.dart';

void main() {
  group('TelemetryStore', () {
    test(
      'legacy rows survive schema upgrade with null lastAttemptedAt default',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'telemetry_store_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final legacyDatabase = _TestDatabase(
          NativeDatabase(File(path.join(tempDir.path, 'telemetry.sqlite'))),
        );
        await legacyDatabase.customStatement(
          '''
          CREATE TABLE telemetry_queue (
            event_id TEXT PRIMARY KEY,
            captured_at TEXT NOT NULL,
            context_json TEXT NOT NULL,
            metadata_json TEXT NOT NULL,
            breadcrumbs_json TEXT NOT NULL,
            attempt_count INTEGER NOT NULL,
            last_attempt_status TEXT NOT NULL
          )
          ''',
        );
        await legacyDatabase.customStatement(
          '''
          INSERT INTO telemetry_queue (
            event_id,
            captured_at,
            context_json,
            metadata_json,
            breadcrumbs_json,
            attempt_count,
            last_attempt_status
          )
          VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
          ''',
          <Object>[
            'event-legacy',
            '2026-03-25T18:00:00.000Z',
            '{"appVersion":"1.2.3","buildNumber":"456","platform":"ios"}',
            '{"message":"legacy-row"}',
            '[]',
            1,
            'failed',
          ],
        );
        await legacyDatabase.close();

        final store = await TelemetryStore.open(tempDir.path);
        addTearDown(store.close);
        final loaded = await store.loadPending();

        expect(loaded, hasLength(1));
        final row = loaded.single;
        expect(row['eventId'], 'event-legacy');
        expect(row['capturedAt'], '2026-03-25T18:00:00.000Z');
        expect(row['context'], <String, Object?>{
          'appVersion': '1.2.3',
          'buildNumber': '456',
          'platform': 'ios',
        });
        expect(row['metadata'], <String, Object?>{'message': 'legacy-row'});
        expect(row['breadcrumbs'], const <Object?>[]);
        expect(row['attemptCount'], 1);
        expect(row['lastAttemptStatus'], 'failed');
        expect(row['lastAttemptedAt'], isNull);
      },
    );

    test(
      'enqueue data survives store recreation with breadcrumb snapshots',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'telemetry_store_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final storeA = await TelemetryStore.open(tempDir.path);
        await storeA.enqueue(<String, Object?>{
          'eventId': 'event-0001',
          'capturedAt': '2026-03-25T18:00:00.000Z',
          'context': <String, Object?>{
            'appVersion': '1.2.3',
            'buildNumber': '456',
            'platform': 'ios',
          },
          'metadata': <String, Object?>{'message': 'first'},
          'breadcrumbs': <Object?>[
            <String, Object?>{'message': 'crumb-a'},
            <String, Object?>{'message': 'crumb-b'},
          ],
          'attemptCount': 0,
          'lastAttemptStatus': 'never_attempted',
        });
        await storeA.close();

        final storeB = await TelemetryStore.open(tempDir.path);
        addTearDown(storeB.close);
        final loaded = await storeB.loadPending();

        expect(loaded, hasLength(1));
        final row = loaded.single;
        expect(row['eventId'], 'event-0001');
        expect(row['capturedAt'], '2026-03-25T18:00:00.000Z');
        expect(row['context'], <String, Object?>{
          'appVersion': '1.2.3',
          'buildNumber': '456',
          'platform': 'ios',
        });
        expect(row['metadata'], <String, Object?>{'message': 'first'});
        expect(row['breadcrumbs'], <Object?>[
          <String, Object?>{'message': 'crumb-a'},
          <String, Object?>{'message': 'crumb-b'},
        ]);
        expect(row['attemptCount'], 0);
        expect(row['lastAttemptStatus'], 'never_attempted');
        expect(row['lastAttemptedAt'], isNull);
      },
    );

    test(
      'retry bookkeeping fields persist and keep stable eventId across reloads',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'telemetry_store_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final storeA = await TelemetryStore.open(tempDir.path);
        await storeA.enqueue(<String, Object?>{
          'eventId': 'event-0099',
          'capturedAt': '2026-03-25T18:05:00.000Z',
          'context': <String, Object?>{
            'appVersion': '1.2.3',
            'buildNumber': '456',
            'platform': 'android',
          },
          'metadata': <String, Object?>{'message': 'retry-me'},
          'breadcrumbs': const <Object?>[],
          'attemptCount': 0,
          'lastAttemptStatus': 'never_attempted',
        });

        await storeA.recordAttempt(
          eventId: 'event-0099',
          attemptCount: 1,
          lastAttemptStatus: 'network_error',
        );
        await storeA.close();

        final storeB = await TelemetryStore.open(tempDir.path);
        addTearDown(storeB.close);
        final loaded = await storeB.loadPending();

        expect(loaded, hasLength(1));
        final row = loaded.single;
        expect(row['eventId'], 'event-0099');
        expect(row['attemptCount'], 1);
        expect(row['lastAttemptStatus'], 'network_error');
      },
    );

    test(
      'enqueue without lastAttemptedAt loads back with null lastAttemptedAt',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'telemetry_store_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final store = await TelemetryStore.open(tempDir.path);
        addTearDown(store.close);
        await store.enqueue(<String, Object?>{
          'eventId': 'event-no-attempt-ts',
          'capturedAt': '2026-03-25T18:00:00.000Z',
          'context': <String, Object?>{
            'appVersion': '1.2.3',
            'buildNumber': '456',
            'platform': 'ios',
          },
          'metadata': <String, Object?>{'message': 'no-attempt'},
          'breadcrumbs': const <Object?>[],
          'attemptCount': 0,
          'lastAttemptStatus': 'never_attempted',
        });

        final loaded = await store.loadPending();
        expect(loaded, hasLength(1));
        expect(loaded.single['lastAttemptedAt'], isNull);
      },
    );

    test(
      'recordAttempt persists non-null lastAttemptedAt across store recreation',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'telemetry_store_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final storeA = await TelemetryStore.open(tempDir.path);
        await storeA.enqueue(<String, Object?>{
          'eventId': 'event-attempt-ts',
          'capturedAt': '2026-03-25T18:00:00.000Z',
          'context': <String, Object?>{
            'appVersion': '1.2.3',
            'buildNumber': '456',
            'platform': 'android',
          },
          'metadata': <String, Object?>{'message': 'will-retry'},
          'breadcrumbs': const <Object?>[],
          'attemptCount': 0,
          'lastAttemptStatus': 'never_attempted',
        });

        final attemptTimestamp = DateTime.utc(2026, 3, 25, 18, 5);
        await storeA.recordAttempt(
          eventId: 'event-attempt-ts',
          attemptCount: 1,
          lastAttemptStatus: 'failed',
          lastAttemptedAt: attemptTimestamp,
        );
        await storeA.close();

        final storeB = await TelemetryStore.open(tempDir.path);
        addTearDown(storeB.close);
        final loaded = await storeB.loadPending();

        expect(loaded, hasLength(1));
        final row = loaded.single;
        expect(row['eventId'], 'event-attempt-ts');
        expect(row['attemptCount'], 1);
        expect(row['lastAttemptStatus'], 'failed');
        expect(row['lastAttemptedAt'], '2026-03-25T18:05:00.000Z');
      },
    );

    test(
      'enqueue with explicit lastAttemptedAt round-trips through loadPending',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'telemetry_store_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final store = await TelemetryStore.open(tempDir.path);
        addTearDown(store.close);
        await store.enqueue(<String, Object?>{
          'eventId': 'event-roundtrip',
          'capturedAt': '2026-03-25T18:00:00.000Z',
          'context': <String, Object?>{
            'appVersion': '1.2.3',
            'buildNumber': '456',
            'platform': 'ios',
          },
          'metadata': <String, Object?>{'message': 'pre-set'},
          'breadcrumbs': const <Object?>[],
          'attemptCount': 2,
          'lastAttemptStatus': 'failed',
          'lastAttemptedAt': '2026-03-25T17:55:00.000Z',
        });

        final loaded = await store.loadPending();
        expect(loaded, hasLength(1));
        final row = loaded.single;
        expect(row['lastAttemptedAt'], '2026-03-25T17:55:00.000Z');
        expect(row['attemptCount'], 2);
        expect(row['lastAttemptStatus'], 'failed');
      },
    );

    test('clear removes queued rows durably across store recreation', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'telemetry_store_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final storeA = await TelemetryStore.open(tempDir.path);
      await storeA.enqueue(<String, Object?>{
        'eventId': 'event-clear-me',
        'capturedAt': '2026-03-25T18:10:00.000Z',
        'context': <String, Object?>{
          'appVersion': '1.2.3',
          'buildNumber': '456',
          'platform': 'ios',
        },
        'metadata': <String, Object?>{'message': 'clear-me'},
        'breadcrumbs': const <Object?>[],
        'attemptCount': 0,
        'lastAttemptStatus': 'never_attempted',
      });
      await storeA.close();

      final storeB = await TelemetryStore.open(tempDir.path);
      await storeB.clear();
      await storeB.close();

      final storeC = await TelemetryStore.open(tempDir.path);
      addTearDown(storeC.close);

      expect(await storeC.loadPending(), isEmpty);
    });
  });
}

class _TestDatabase extends GeneratedDatabase {
  _TestDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      const <DatabaseSchemaEntity>[];
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/core/telemetry/lazy_telemetry_store_client.dart';

import 'telemetry_test_support.dart';

// ## Test Scenarios
// - [positive] RetryingAsyncLoader retries creation after a failed first load
// - [positive] LazyTelemetryStoreClient opens the store only on first use and reuses it across operations
// - [edge] Disposing LazyTelemetryStoreClient before first use does not open the store
// - [negative] LazyTelemetryStoreClient rejects operations after disposal

Directory _createTempTelemetryDirectory() {
  final directory = Directory.systemTemp.createTempSync(
    'uff-lazy-telemetry-store-',
  );
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return directory;
}

Matcher _throwsDisposedStateError() {
  return throwsA(
    isA<StateError>().having(
      (StateError error) => error.message,
      'message',
      'Telemetry store provider is already disposed.',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RetryingAsyncLoader', () {
    test('retries creation after a failed first load', () async {
      var createCallCount = 0;
      final loader = RetryingAsyncLoader<int>(() async {
        createCallCount += 1;
        if (createCallCount == 1) {
          throw StateError('first load failed');
        }
        return 42;
      });

      await expectLater(
        loader.load(),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            'first load failed',
          ),
        ),
      );
      expect(loader.cachedFuture, isNull);

      final value = await loader.load();

      expect(value, 42);
      expect(createCallCount, 2);
    });
  });

  group('LazyTelemetryStoreClient', () {
    test(
      'opens the store only on first use and reuses it across operations',
      () async {
        final directory = _createTempTelemetryDirectory();
        var loadRootDirectoryPathCallCount = 0;
        final client = LazyTelemetryStoreClient(
          loadRootDirectoryPath: () async {
            loadRootDirectoryPathCallCount += 1;
            return directory.path;
          },
        );
        final queuedRow = buildQueuedEventRow(
          eventId: 'event-0001',
          capturedAt: '2026-03-29T18:00:00.000Z',
          breadcrumbs: const <JsonMap>[
            <String, Object?>{
              'message': 'opened lazily',
              'metadata': <String, Object?>{'source': 'test'},
            },
          ],
          metadata: const <String, Object?>{'source': 'lazy-client-test'},
        );

        expect(loadRootDirectoryPathCallCount, 0);

        await client.enqueue(queuedRow);
        final pendingRows = await client.loadPending();
        await client.clear();
        final pendingRowsAfterClear = await client.loadPending();

        expect(loadRootDirectoryPathCallCount, 1);
        expect(pendingRows, <JsonMap>[queuedRow]);
        expect(pendingRowsAfterClear, const <JsonMap>[]);

        await client.dispose();
      },
    );

    test('disposing before first use does not open the store', () async {
      final directory = _createTempTelemetryDirectory();
      var loadRootDirectoryPathCallCount = 0;
      final client = LazyTelemetryStoreClient(
        loadRootDirectoryPath: () async {
          loadRootDirectoryPathCallCount += 1;
          return directory.path;
        },
      );

      await client.dispose();

      expect(loadRootDirectoryPathCallCount, 0);
      await expectLater(client.loadPending(), _throwsDisposedStateError());
    });

    test('rejects operations after disposal', () async {
      final directory = _createTempTelemetryDirectory();
      final client = LazyTelemetryStoreClient(
        loadRootDirectoryPath: () async => directory.path,
      );

      await client.loadPending();
      await client.dispose();

      await expectLater(client.clear(), _throwsDisposedStateError());
    });
  });
}

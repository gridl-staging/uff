import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/core/telemetry/data/telemetry_store.dart' hide JsonMap;
import 'package:uff/src/core/telemetry/domain/telemetry_retry_policy.dart';
import 'package:uff/src/core/telemetry/service/telemetry_service.dart';
import 'package:uff/src/core/telemetry/service/telemetry_uploader.dart'
    hide JsonMap;

typedef JsonMap = Map<String, Object?>;

JsonMap deepCopyJsonMap(JsonMap source) {
  return source.map((String key, Object? value) {
    if (value is Map<String, Object?>) {
      return MapEntry<String, Object?>(key, deepCopyJsonMap(value));
    }
    if (value is List<Object?>) {
      return MapEntry<String, Object?>(
        key,
        value
            .map((Object? item) {
              if (item is Map<String, Object?>) {
                return deepCopyJsonMap(item);
              }
              return item;
            })
            .toList(growable: false),
      );
    }
    return MapEntry<String, Object?>(key, value);
  });
}

class FakeClock {
  FakeClock(this._currentTime);

  DateTime _currentTime;

  DateTime now() => _currentTime;

  void advance(Duration delta) {
    _currentTime = _currentTime.add(delta);
  }
}

/// TODO: Document FakeTelemetryStore.
class FakeTelemetryStore implements TelemetryStoreClient {
  final List<JsonMap> enqueuedRows = <JsonMap>[];
  final List<JsonMap> pendingRows = <JsonMap>[];
  final List<AttemptBookkeepingUpdate> attemptUpdates =
      <AttemptBookkeepingUpdate>[];
  final List<String> deletedEventIds = <String>[];
  int clearCallCount = 0;

  @override
  Future<void> enqueue(JsonMap row) async {
    final snapshot = deepCopyJsonMap(row);
    enqueuedRows.add(snapshot);
    pendingRows.add(snapshot);
  }

  @override
  Future<List<JsonMap>> loadPending() async {
    return pendingRows.map(deepCopyJsonMap).toList(growable: false);
  }

  @override
  Future<void> recordAttempt({
    required String eventId,
    required int attemptCount,
    required String lastAttemptStatus,
    DateTime? lastAttemptedAt,
  }) async {
    attemptUpdates.add(
      AttemptBookkeepingUpdate(
        eventId: eventId,
        attemptCount: attemptCount,
        lastAttemptStatus: lastAttemptStatus,
        lastAttemptedAt: lastAttemptedAt,
      ),
    );

    for (final row in pendingRows) {
      if (row['eventId'] == eventId) {
        row['attemptCount'] = attemptCount;
        row['lastAttemptStatus'] = lastAttemptStatus;
        row['lastAttemptedAt'] = lastAttemptedAt?.toUtc().toIso8601String();
      }
    }
  }

  @override
  Future<void> delete(String eventId) async {
    deletedEventIds.add(eventId);
    pendingRows.removeWhere((JsonMap row) => row['eventId'] == eventId);
  }

  @override
  Future<void> clear() async {
    clearCallCount += 1;
    pendingRows.clear();
    enqueuedRows.clear();
  }
}

class AttemptBookkeepingUpdate {
  const AttemptBookkeepingUpdate({
    required this.eventId,
    required this.attemptCount,
    required this.lastAttemptStatus,
    this.lastAttemptedAt,
  });

  final String eventId;
  final int attemptCount;
  final String lastAttemptStatus;
  final DateTime? lastAttemptedAt;
}

/// In-memory TelemetryUploader fake for contract tests.
class FakeTelemetryUploader implements TelemetryUploader {
  FakeTelemetryUploader({
    List<bool>? uploadOutcomes,
    List<Object>? uploadResponses,
  }) : _uploadOutcomes = uploadOutcomes ?? <bool>[],
       _uploadResponses = uploadResponses ?? <Object>[];

  final List<bool> _uploadOutcomes;
  final List<Object> _uploadResponses;
  final List<String> uploadedEventIds = <String>[];

  @override
  Future<bool> upload(JsonMap row) async {
    uploadedEventIds.add(row['eventId']! as String);

    if (_uploadResponses.isNotEmpty) {
      final response = _responseForAttempt(_uploadResponses);
      if (response is bool) {
        return response;
      }
      _throwStoredFailure(response);
    }

    if (_uploadOutcomes.isEmpty) {
      return true;
    }

    return _responseForAttempt(_uploadOutcomes);
  }

  T _responseForAttempt<T>(List<T> responses) {
    final attemptIndex = uploadedEventIds.length - 1;
    if (attemptIndex >= responses.length) {
      return responses.last;
    }

    return responses[attemptIndex];
  }

  Never _throwStoredFailure(Object failure) {
    if (failure is Error) {
      throw failure;
    }
    if (failure is Exception) {
      throw failure;
    }

    throw StateError(
      'FakeTelemetryUploader failures must be Error or Exception.',
    );
  }
}

/// Fixed context source fake for telemetry tests.
class FakeAppBuildPlatformContextSource
    implements AppBuildPlatformContextSource {
  FakeAppBuildPlatformContextSource({
    required this.appVersion,
    required this.buildNumber,
    required this.platform,
  });

  final String appVersion;
  final String buildNumber;
  final String platform;

  @override
  JsonMap read() => <String, Object?>{
    'appVersion': appVersion,
    'buildNumber': buildNumber,
    'platform': platform,
  };
}

class FakeTelemetryScrubber {
  FakeTelemetryScrubber({required this.scrubbedMetadata});

  final JsonMap scrubbedMetadata;
  final List<JsonMap> invocations = <JsonMap>[];

  JsonMap scrub(JsonMap input) {
    invocations.add(deepCopyJsonMap(input));
    return deepCopyJsonMap(scrubbedMetadata);
  }
}

/// In-memory persistence fake for telemetry enablement tests.
class FakeTelemetryEnablementPersistence {
  FakeTelemetryEnablementPersistence({
    this.persistedValue,
    this.readError,
    this.writeError,
  });

  bool? persistedValue;
  Object? readError;
  Object? writeError;
  int clearQueueCallCount = 0;

  Future<bool?> read() async {
    if (readError != null) {
      _throwStoredFailure(readError!);
    }
    return persistedValue;
  }

  Future<void> write({required bool isEnabled}) async {
    if (writeError != null) {
      _throwStoredFailure(writeError!);
    }
    persistedValue = isEnabled;
  }

  Future<void> clearQueue() async {
    clearQueueCallCount += 1;
  }

  Never _throwStoredFailure(Object failure) {
    if (failure is Error) {
      throw failure;
    }
    if (failure is Exception) {
      throw failure;
    }

    throw StateError(
      'FakeTelemetryEnablementPersistence failures must be Error or Exception.',
    );
  }
}

String Function() buildEventIdGenerator({String prefix = 'event'}) {
  var current = 0;
  return () {
    current += 1;
    return '$prefix-${current.toString().padLeft(4, '0')}';
  };
}

JsonMap buildQueuedEventRow({
  required String eventId,
  required String capturedAt,
  required List<JsonMap> breadcrumbs,
  required JsonMap metadata,
  int attemptCount = 0,
  String lastAttemptStatus = 'never_attempted',
  String? lastAttemptedAt,
  JsonMap? context,
}) {
  return <String, Object?>{
    'eventId': eventId,
    'capturedAt': capturedAt,
    'context':
        context ??
        <String, Object?>{
          'appVersion': '1.2.3',
          'buildNumber': '456',
          'platform': 'ios',
        },
    'metadata': deepCopyJsonMap(metadata),
    'breadcrumbs': breadcrumbs.map(deepCopyJsonMap).toList(growable: false),
    'attemptCount': attemptCount,
    'lastAttemptStatus': lastAttemptStatus,
    'lastAttemptedAt': lastAttemptedAt,
  };
}

Matcher hasSharedContextEnvelope({
  required String appVersion,
  required String buildNumber,
  required String platform,
}) {
  return allOf(
    isA<Map<String, Object?>>(),
    containsPair('appVersion', appVersion),
    containsPair('buildNumber', buildNumber),
    containsPair('platform', platform),
  );
}

Matcher hasOnlyFiniteScalarValues() {
  return predicate<Map<String, Object?>>((Map<String, Object?> map) {
    for (final value in map.values) {
      if (value == null || value is bool || value is String) {
        continue;
      }
      if (value is num && value.isFinite) {
        continue;
      }
      return false;
    }
    return true;
  }, 'contains only finite scalar values');
}

List<String> breadcrumbMessagesFromEvent(JsonMap eventRow) {
  final breadcrumbs = eventRow['breadcrumbs']! as List<Object?>;
  return breadcrumbs
      .map(
        (Object? raw) => (raw! as Map<String, Object?>)['message']! as String,
      )
      .toList(growable: false);
}

/// Shared builder for TelemetryService used across service test files.
TelemetryService buildTelemetryService({
  required DateTime Function() now,
  required String Function() eventIdFactory,
  required FakeTelemetryStore store,
  required FakeTelemetryUploader uploader,
  required FakeAppBuildPlatformContextSource contextSource,
  required JsonMap Function(JsonMap metadata) scrubMetadata,
  required bool Function() isTelemetryEnabled,
  required bool Function() isAuthAvailable,
  TelemetryRetryPolicy retryPolicy = const TelemetryRetryPolicy(),
}) {
  return TelemetryService(
    dependencies: TelemetryServiceDependencies(
      now: now,
      eventIdFactory: eventIdFactory,
      io: TelemetryIO(store: store, uploader: uploader),
      contextSource: contextSource,
      scrubMetadata: scrubMetadata,
      flushConfig: TelemetryFlushConfig(
        isAuthAvailable: isAuthAvailable,
        retryPolicy: retryPolicy,
      ),
    ),
    isTelemetryEnabled: isTelemetryEnabled,
  );
}

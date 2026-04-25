import 'package:meta/meta.dart';

enum TrackingSessionStatus {
  idle,
  recording,
  paused,
  stopped,
  saving,
  saved,
  discarded,
}

enum GpsSignalQuality { red, amber, green }

const double kGpsAccuracyGoodThresholdMeters = 10.0;

// Zero accuracy means the platform returned a fix with no real measurement;
// treat it as unknown (red) rather than falsely excellent.
GpsSignalQuality classifyGpsAccuracy(double? accuracyMeters) {
  if (accuracyMeters == null ||
      accuracyMeters.isNaN ||
      accuracyMeters.isInfinite ||
      accuracyMeters <= 0.0) {
    return GpsSignalQuality.red;
  }
  if (accuracyMeters <= kGpsAccuracyGoodThresholdMeters) {
    return GpsSignalQuality.green;
  }
  return GpsSignalQuality.amber;
}

enum SyncQueueEntryStatus {
  queued,
  processing,
  successful,
  failed,
}

const Set<TrackingSessionStatus> _recordingStatuses = {
  TrackingSessionStatus.recording,
  TrackingSessionStatus.paused,
  TrackingSessionStatus.stopped,
  TrackingSessionStatus.saving,
};

const String publicTrackingSessionVisibility = 'public';
const String followersTrackingSessionVisibility = 'followers';
const String privateTrackingSessionVisibility = 'private';

const Set<String> supportedTrackingSessionVisibilityValues = {
  publicTrackingSessionVisibility,
  followersTrackingSessionVisibility,
  privateTrackingSessionVisibility,
};

String normalizeTrackingSessionVisibility(String? visibility) {
  if (supportedTrackingSessionVisibilityValues.contains(visibility)) {
    return visibility!;
  }
  return publicTrackingSessionVisibility;
}

String? supportedTrackingSessionVisibilityOrNull(String? visibility) {
  if (supportedTrackingSessionVisibilityValues.contains(visibility)) {
    return visibility;
  }
  return null;
}

extension TrackingSessionStatusExtensions on TrackingSessionStatus {
  bool get isFinalized =>
      this == TrackingSessionStatus.saved ||
      this == TrackingSessionStatus.discarded ||
      this == TrackingSessionStatus.idle;

  bool get isActive => _recordingStatuses.contains(this);

  bool get isTerminalStopCandidate =>
      this == TrackingSessionStatus.stopped ||
      this == TrackingSessionStatus.saving;
}

@immutable
class GeoCoordinate {
  const GeoCoordinate({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

/// NOTE(stuart): Document TrackingSessionRecord.
@immutable
class TrackingSessionRecord {
  const TrackingSessionRecord({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.stoppedAt,
    this.title,
    this.description,
    this.distanceMeters,
    this.movingTimeSeconds,
    this.elevationGainMeters,
    this.remoteId,
    this.sportType,
    this.visibility,
  });

  final int id;
  final TrackingSessionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? stoppedAt;
  final String? title;
  final String? description;
  final double? distanceMeters;
  final int? movingTimeSeconds;
  final double? elevationGainMeters;
  final String? remoteId;
  final String? sportType;
  final String? visibility;

  TrackingSessionRecord copyWith({
    TrackingSessionStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? startedAt,
    DateTime? stoppedAt,
    String? remoteId,
    String? sportType,
    String? visibility,
    TrackingSessionRecordUpdates? updates,
  }) {
    return TrackingSessionRecord(
      id: id,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      startedAt: startedAt ?? this.startedAt,
      stoppedAt: stoppedAt ?? this.stoppedAt,
      title: updates == null
          ? title
          : updates.clearTitle
          ? null
          : updates.title ?? title,
      description: updates == null
          ? description
          : updates.clearDescription
          ? null
          : updates.description ?? description,
      distanceMeters: updates == null
          ? distanceMeters
          : updates.clearDistanceMeters
          ? null
          : updates.distanceMeters ?? distanceMeters,
      movingTimeSeconds: updates == null
          ? movingTimeSeconds
          : updates.clearMovingTimeSeconds
          ? null
          : updates.movingTimeSeconds ?? movingTimeSeconds,
      elevationGainMeters: updates == null
          ? elevationGainMeters
          : updates.clearElevationGainMeters
          ? null
          : updates.elevationGainMeters ?? elevationGainMeters,
      remoteId: remoteId ?? this.remoteId,
      sportType: sportType ?? this.sportType,
      visibility: visibility ?? this.visibility,
    );
  }
}

/// NOTE(stuart): Document SyncQueueEntry.
@immutable
class SyncQueueEntry {
  const SyncQueueEntry({
    required this.sessionId,
    required this.status,
    required this.retryCount,
    required this.queuedAt,
    this.lastError,
  });

  final int sessionId;
  final SyncQueueEntryStatus status;
  final int retryCount;
  final String? lastError;
  final DateTime queuedAt;
}

/// NOTE(stuart): Document TrackingSessionRecordUpdates.
@immutable
class TrackingSessionRecordUpdates {
  const TrackingSessionRecordUpdates({
    this.title,
    this.description,
    this.distanceMeters,
    this.movingTimeSeconds,
    this.elevationGainMeters,
    this.clearTitle = false,
    this.clearDescription = false,
    this.clearDistanceMeters = false,
    this.clearMovingTimeSeconds = false,
    this.clearElevationGainMeters = false,
  });

  final String? title;
  final String? description;
  final double? distanceMeters;
  final int? movingTimeSeconds;
  final double? elevationGainMeters;
  final bool clearTitle;
  final bool clearDescription;
  final bool clearDistanceMeters;
  final bool clearMovingTimeSeconds;
  final bool clearElevationGainMeters;
}

/// NOTE(stuart): Document TrackingPoint.
@immutable
class TrackingPoint {
  const TrackingPoint({
    required this.sessionId,
    required this.timestamp,
    required this.coordinate,
    this.elevation,
    this.accuracy,
    this.speed,
    this.heartRateBpm,
    this.cadenceRpm,
    this.powerWatts,
  });

  final int sessionId;
  final DateTime timestamp;
  final GeoCoordinate coordinate;
  final double? elevation;
  final double? accuracy;
  final double? speed;
  final int? heartRateBpm;
  final double? cadenceRpm;
  final int? powerWatts;

  double get latitude => coordinate.latitude;
  double get longitude => coordinate.longitude;
}

/// NOTE(stuart): Document TrackingStateTransition.
@immutable
class TrackingStateTransition {
  const TrackingStateTransition({required this.from, required this.to});

  final TrackingSessionStatus from;
  final TrackingSessionStatus to;

  bool get isAllowed => const {
    TrackingSessionStatus.idle: {
      TrackingSessionStatus.recording,
    },
    TrackingSessionStatus.recording: {
      TrackingSessionStatus.paused,
      TrackingSessionStatus.stopped,
    },
    TrackingSessionStatus.paused: {
      TrackingSessionStatus.recording,
      TrackingSessionStatus.stopped,
    },
    TrackingSessionStatus.stopped: {
      TrackingSessionStatus.saving,
      TrackingSessionStatus.discarded,
    },
    TrackingSessionStatus.saving: {
      TrackingSessionStatus.idle,
    },
    TrackingSessionStatus.saved: {
      TrackingSessionStatus.idle,
    },
    TrackingSessionStatus.discarded: {
      TrackingSessionStatus.idle,
    },
  }[from]!.contains(to);
}

class InvalidTrackingTransition implements Exception {
  const InvalidTrackingTransition(this.transition);

  final TrackingStateTransition transition;

  @override
  String toString() {
    return 'Invalid transition: ${transition.from.name} -> ${transition.to.name}';
  }
}

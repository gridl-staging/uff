import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/data/sync_payload_builder.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

// ## Test Scenarios
// - [positive] buildActivityPayload returns the expected sync payload keys and values
// - [edge] resolveStartedAt falls back from startedAt to first point to createdAt
// - [edge] resolveFinishedAt falls back from stoppedAt to last point to startedAt
// - [positive] buildTrackPointRows maps track-point fields and rounds cadence for sync
// - [positive] buildSplitRows maps split number, distance, duration, and nullable pace
void main() {
  group('sync_payload_builder', () {
    test(
      'buildActivityPayload maps a minimal session payload with known values',
      () {
        final session = TrackingSessionRecord(
          id: 11,
          status: TrackingSessionStatus.saved,
          createdAt: DateTime.utc(2026, 2, 1, 10),
          updatedAt: DateTime.utc(2026, 2, 1, 10, 5),
          startedAt: DateTime.utc(2026, 2, 1, 10, 0, 10),
          stoppedAt: DateTime.utc(2026, 2, 1, 10, 5, 10),
          title: 'Tempo',
          description: 'steady effort',
          visibility: followersTrackingSessionVisibility,
        );
        final metrics = ProcessedActivityMetrics(
          session: session,
          trackSummary: const TrackSummary(
            distanceMeters: 1234.5,
            movingTime: Duration(seconds: 400),
            averagePace: ActivityPace(
              perKilometer: Duration(minutes: 5),
              perMile: Duration(minutes: 8),
            ),
            elevationGainMeters: 42,
          ),
          splits: const <ActivitySplit>[],
          autoPause: const AutoPauseResult(
            windows: <AutoPauseWindow>[],
            totalMovingDuration: Duration(seconds: 400),
          ),
        );

        final payload = buildActivityPayload(
          session: session,
          metrics: metrics,
          cleanedPoints: const <TrackingPoint>[],
          remoteId: 'remote-11',
          userId: 'user-11',
        );

        expect(
          payload,
          <String, dynamic>{
            'id': 'remote-11',
            'user_id': 'user-11',
            'sport_type': 'workout',
            'started_at': '2026-02-01T10:00:10.000Z',
            'finished_at': '2026-02-01T10:05:10.000Z',
            'distance_meters': 1234.5,
            'duration_seconds': 400,
            'elevation_gain_meters': 42.0,
            'avg_pace_seconds_per_km': 300.0,
            'title': 'Tempo',
            'description': 'steady effort',
            'visibility': followersTrackingSessionVisibility,
          },
        );
      },
    );

    test('resolveStartedAt falls back to first point and then createdAt', () {
      final firstPointTimestamp = DateTime.utc(2026, 3, 1, 9, 0, 5);
      final secondPointTimestamp = DateTime.utc(2026, 3, 1, 9, 0, 10);
      final sessionWithoutStartedAt = TrackingSessionRecord(
        id: 12,
        status: TrackingSessionStatus.saved,
        createdAt: DateTime.utc(2026, 3, 1, 9),
        updatedAt: DateTime.utc(2026, 3, 1, 9, 1),
      );
      final points = <TrackingPoint>[
        TrackingPoint(
          sessionId: 12,
          timestamp: firstPointTimestamp,
          coordinate: const GeoCoordinate(latitude: 37, longitude: -122),
        ),
        TrackingPoint(
          sessionId: 12,
          timestamp: secondPointTimestamp,
          coordinate: const GeoCoordinate(latitude: 37.1, longitude: -122.1),
        ),
      ];

      final startedFromPoints = resolveStartedAt(
        sessionWithoutStartedAt,
        points,
      );
      final startedFromCreatedAt = resolveStartedAt(
        sessionWithoutStartedAt,
        const <TrackingPoint>[],
      );

      expect(startedFromPoints, firstPointTimestamp);
      expect(startedFromCreatedAt, DateTime.utc(2026, 3, 1, 9));
    });

    test('resolveFinishedAt falls back to last point and then startedAt', () {
      final firstPointTimestamp = DateTime.utc(2026, 3, 1, 9, 0, 5);
      final lastPointTimestamp = DateTime.utc(2026, 3, 1, 9, 0, 15);
      final sessionWithoutStoppedAt = TrackingSessionRecord(
        id: 13,
        status: TrackingSessionStatus.saved,
        createdAt: DateTime.utc(2026, 3, 1, 9),
        updatedAt: DateTime.utc(2026, 3, 1, 9, 1),
      );
      final points = <TrackingPoint>[
        TrackingPoint(
          sessionId: 13,
          timestamp: firstPointTimestamp,
          coordinate: const GeoCoordinate(latitude: 37, longitude: -122),
        ),
        TrackingPoint(
          sessionId: 13,
          timestamp: lastPointTimestamp,
          coordinate: const GeoCoordinate(latitude: 37.1, longitude: -122.1),
        ),
      ];

      final finishedFromPoints = resolveFinishedAt(
        sessionWithoutStoppedAt,
        points,
        DateTime.utc(2026, 3, 1, 9),
      );
      final finishedFromStartedAt = resolveFinishedAt(
        sessionWithoutStoppedAt,
        const <TrackingPoint>[],
        DateTime.utc(2026, 3, 1, 9, 2),
      );

      expect(finishedFromPoints, lastPointTimestamp);
      expect(finishedFromStartedAt, DateTime.utc(2026, 3, 1, 9, 2));
    });

    test('buildTrackPointRows maps track point fields and rounds cadence', () {
      final points = <TrackingPoint>[
        TrackingPoint(
          sessionId: 14,
          timestamp: DateTime.utc(2026, 4, 1, 7),
          coordinate: const GeoCoordinate(latitude: 40, longitude: -73),
          elevation: 10.5,
          speed: 3.6,
          heartRateBpm: 145,
          cadenceRpm: 88.6,
          powerWatts: 250,
        ),
        TrackingPoint(
          sessionId: 14,
          timestamp: DateTime.utc(2026, 4, 1, 7, 0, 5),
          coordinate: const GeoCoordinate(latitude: 40.1, longitude: -73.1),
          elevation: 10,
          speed: 3.2,
          heartRateBpm: 142,
        ),
      ];

      final rows = buildTrackPointRows(
        remoteId: 'remote-14',
        cleanedPoints: points,
      );

      expect(rows, hasLength(2));
      expect(
        rows[0],
        <String, dynamic>{
          'activity_id': 'remote-14',
          'timestamp': '2026-04-01T07:00:00.000Z',
          'latitude': 40.0,
          'longitude': -73.0,
          'elevation': 10.5,
          'speed': 3.6,
          'heart_rate': 145,
          'cadence': 89,
          'power': 250,
        },
      );
      expect(rows[1]['cadence'], null);
      expect(normalizeCadenceForSync(90.4), 90);
      expect(normalizeCadenceForSync(90.6), 91);
    });

    test('buildSplitRows maps split fields including nullable pace', () {
      final session = TrackingSessionRecord(
        id: 15,
        status: TrackingSessionStatus.saved,
        createdAt: DateTime.utc(2026, 5, 1, 8),
        updatedAt: DateTime.utc(2026, 5, 1, 8, 30),
      );
      final metrics = ProcessedActivityMetrics(
        session: session,
        trackSummary: const TrackSummary(
          distanceMeters: 2000,
          movingTime: Duration(seconds: 600),
          averagePace: ActivityPace(
            perKilometer: Duration(seconds: 300),
            perMile: Duration(seconds: 480),
          ),
          elevationGainMeters: 15,
        ),
        splits: const <ActivitySplit>[
          ActivitySplit(
            index: 1,
            unit: SplitUnit.kilometer,
            splitDuration: Duration(seconds: 305),
            cumulativeDuration: Duration(seconds: 305),
            cumulativeDistanceMeters: 1000,
            pace: Duration(seconds: 305),
          ),
          ActivitySplit(
            index: 2,
            unit: SplitUnit.kilometer,
            splitDuration: Duration(seconds: 295),
            cumulativeDuration: Duration(seconds: 600),
            cumulativeDistanceMeters: 2000,
            pace: null,
          ),
        ],
        autoPause: const AutoPauseResult(
          windows: <AutoPauseWindow>[],
          totalMovingDuration: Duration(seconds: 600),
        ),
      );

      final rows = buildSplitRows(
        remoteId: 'remote-15',
        processedMetrics: metrics,
      );

      expect(
        rows,
        <Map<String, dynamic>>[
          <String, dynamic>{
            'activity_id': 'remote-15',
            'split_number': 1,
            'distance_meters': 1000.0,
            'duration_seconds': 305,
            'avg_pace_seconds_per_km': 305.0,
            'elevation_change_meters': null,
          },
          <String, dynamic>{
            'activity_id': 'remote-15',
            'split_number': 2,
            'distance_meters': 1000.0,
            'duration_seconds': 295,
            'avg_pace_seconds_per_km': null,
            'elevation_change_meters': null,
          },
        ],
      );
    });
  });
}

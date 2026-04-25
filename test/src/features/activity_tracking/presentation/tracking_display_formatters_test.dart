import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';

void main() {
  group('formatDuration', () {
    test('formats null as placeholder', () {
      expect(formatDuration(null), '--');
    });

    test('formats boundary and large values with zero padding', () {
      expect(formatDuration(Duration.zero), '00:00:00');
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '01:02:03',
      );
      expect(formatDuration(const Duration(seconds: 59)), '00:00:59');
      expect(
        formatDuration(const Duration(hours: 99, minutes: 59, seconds: 59)),
        '99:59:59',
      );
    });
  });

  group('formatDistanceKilometers', () {
    test('formats null as placeholder', () {
      expect(formatDistanceKilometers(null), '-- km');
    });

    test('formats meters as kilometers with fixed precision', () {
      expect(formatDistanceKilometers(0), '0.00 km');
      expect(formatDistanceKilometers(1000), '1.00 km');
      expect(formatDistanceKilometers(1500.5), '1.50 km');
      expect(formatDistanceKilometers(42195), '42.20 km');
      expect(formatDistanceKilometers(0.1), '0.00 km');
    });
  });

  group('formatDistance', () {
    test('uses preferred units to choose kilometers vs miles', () {
      expect(formatDistance(1609.344, preferredUnits: 'metric'), '1.61 km');
      expect(formatDistance(1609.344, preferredUnits: 'imperial'), '1.00 mi');
      expect(formatDistance(null, preferredUnits: 'imperial'), '-- mi');
    });
  });

  group('formatPace', () {
    test('formats null as placeholder', () {
      expect(formatPace(null), '--:--');
    });

    test('formats pace boundaries and representative values', () {
      expect(formatPace(Duration.zero), '00:00 /km');
      expect(formatPace(const Duration(minutes: 5, seconds: 30)), '05:30 /km');
      expect(formatPace(const Duration(minutes: 10)), '10:00 /km');
      expect(formatPace(const Duration(minutes: 59, seconds: 59)), '59:59 /km');
    });
  });

  group('formatPaceForPreferredUnits', () {
    test('uses preferred units to choose kilometer vs mile pace labels', () {
      expect(
        formatPaceForPreferredUnits(
          pacePerKilometer: const Duration(minutes: 5, seconds: 30),
          pacePerMile: const Duration(minutes: 8, seconds: 51),
          preferredUnits: 'metric',
        ),
        '05:30 /km',
      );
      expect(
        formatPaceForPreferredUnits(
          pacePerKilometer: const Duration(minutes: 5, seconds: 30),
          pacePerMile: const Duration(minutes: 8, seconds: 51),
          preferredUnits: 'imperial',
        ),
        '08:51 /mi',
      );
    });

    test('formats explicit pace units for split rows', () {
      expect(
        formatPaceForUnit(
          const Duration(minutes: 8, seconds: 2),
          SplitUnit.mile,
        ),
        '08:02 /mi',
      );
    });
  });

  group('formatDateLabel', () {
    test('formats null as placeholder', () {
      expect(formatDateLabel(null), '--');
    });

    test('formats local datetime with zero padding', () {
      expect(formatDateLabel(DateTime(2024, 1, 2, 3, 4)), '2024-01-02 03:04');
    });

    test('converts UTC datetime to local components deterministically', () {
      final utcInput = DateTime.utc(2024, 1, 1, 0, 5);
      final local = utcInput.toLocal();
      final expected =
          '${local.year}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')} '
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';

      expect(formatDateLabel(utcInput), expected);
    });
  });

  group('generateDefaultActivityTitle', () {
    test('generates Morning Run for 5 AM - 11 AM', () {
      expect(
        generateDefaultActivityTitle(startedAt: DateTime(2025, 3, 15, 5)),
        'Morning Run',
      );
      expect(
        generateDefaultActivityTitle(startedAt: DateTime(2025, 3, 15, 11)),
        'Morning Run',
      );
    });

    test('generates Lunch Run for 12 PM - 1 PM', () {
      expect(
        generateDefaultActivityTitle(startedAt: DateTime(2025, 3, 15, 12)),
        'Lunch Run',
      );
      expect(
        generateDefaultActivityTitle(startedAt: DateTime(2025, 3, 15, 13)),
        'Lunch Run',
      );
    });

    test('generates Afternoon Run for 2 PM - 4 PM', () {
      expect(
        generateDefaultActivityTitle(startedAt: DateTime(2025, 3, 15, 14)),
        'Afternoon Run',
      );
      expect(
        generateDefaultActivityTitle(startedAt: DateTime(2025, 3, 15, 16)),
        'Afternoon Run',
      );
    });

    test('generates Evening Run for 5 PM - 8 PM', () {
      expect(
        generateDefaultActivityTitle(startedAt: DateTime(2025, 3, 15, 17)),
        'Evening Run',
      );
      expect(
        generateDefaultActivityTitle(startedAt: DateTime(2025, 3, 15, 20)),
        'Evening Run',
      );
    });

    test('generates Night Run for 9 PM - 4 AM', () {
      expect(
        generateDefaultActivityTitle(startedAt: DateTime(2025, 3, 15, 21)),
        'Night Run',
      );
      expect(
        generateDefaultActivityTitle(startedAt: DateTime(2025, 3, 15, 4)),
        'Night Run',
      );
      expect(
        generateDefaultActivityTitle(startedAt: DateTime(2025, 3, 15, 0)),
        'Night Run',
      );
    });

    test('uses sport type when provided', () {
      expect(
        generateDefaultActivityTitle(
          startedAt: DateTime(2025, 3, 15, 8),
          sportType: 'ride',
        ),
        'Morning Ride',
      );
      expect(
        generateDefaultActivityTitle(
          startedAt: DateTime(2025, 3, 15, 18),
          sportType: 'walk',
        ),
        'Evening Walk',
      );
    });

    test('defaults to Run when sport type is null or empty', () {
      expect(
        generateDefaultActivityTitle(
          startedAt: DateTime(2025, 3, 15, 8),
          sportType: null,
        ),
        'Morning Run',
      );
      expect(
        generateDefaultActivityTitle(
          startedAt: DateTime(2025, 3, 15, 8),
          sportType: '',
        ),
        'Morning Run',
      );
    });
  });

  group('formatElevation', () {
    test('formats null as placeholder in metric', () {
      expect(formatElevation(null), '-- m');
    });

    test('formats null as placeholder in imperial', () {
      expect(formatElevation(null, preferredUnits: 'imperial'), '-- ft');
    });

    test('formats meters with rounding for metric users', () {
      expect(formatElevation(0), '0 m');
      expect(formatElevation(125.7), '126 m');
      expect(formatElevation(1000), '1000 m');
    });

    test('converts meters to feet for imperial users', () {
      // 100m = 328.084 ft → rounds to 328
      expect(formatElevation(100, preferredUnits: 'imperial'), '328 ft');
      // 500m = 1640.42 ft → rounds to 1640
      expect(formatElevation(500, preferredUnits: 'imperial'), '1640 ft');
    });

    test('defaults to metric when preferredUnits is null', () {
      expect(formatElevation(250, preferredUnits: null), '250 m');
    });
  });

  group('paceColor', () {
    test('maps null and threshold boundaries to expected colors', () {
      expect(paceColor(null), Colors.grey);
      expect(paceColor(const Duration(minutes: 9, seconds: 59)), Colors.green);
      expect(paceColor(const Duration(minutes: 10)), Colors.orange);
      expect(
        paceColor(const Duration(minutes: 11, seconds: 59)),
        Colors.orange,
      );
      expect(paceColor(const Duration(minutes: 12)), Colors.red);
    });
  });

  group('toRoutePoints', () {
    test('returns empty list for empty input', () {
      expect(toRoutePoints(const []), isEmpty);
    });

    test('maps a single tracking point to a single route point', () {
      final point = TrackingPoint(
        sessionId: 1,
        timestamp: DateTime.utc(2024),
        coordinate: const GeoCoordinate(latitude: 40.7128, longitude: -74.006),
      );

      final routePoints = toRoutePoints([point]);

      expect(routePoints.length, 1);
      expect(routePoints.first.latitude, 40.7128);
      expect(routePoints.first.longitude, -74.006);
    });

    test('maps multiple tracking points preserving count and coordinates', () {
      final points = [
        TrackingPoint(
          sessionId: 42,
          timestamp: DateTime.utc(2024),
          coordinate: const GeoCoordinate(
            latitude: 37.7749,
            longitude: -122.4194,
          ),
        ),
        TrackingPoint(
          sessionId: 42,
          timestamp: DateTime.utc(2024, 1, 1, 0, 1),
          coordinate: const GeoCoordinate(
            latitude: 37.7755,
            longitude: -122.4188,
          ),
        ),
      ];

      final routePoints = toRoutePoints(points);

      expect(routePoints.length, 2);
      expect(routePoints[0].latitude, 37.7749);
      expect(routePoints[0].longitude, -122.4194);
      expect(routePoints[1].latitude, 37.7755);
      expect(routePoints[1].longitude, -122.4188);
    });
  });
}

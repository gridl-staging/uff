// Scenario tags use markdown-style brackets (for example [negative]) that are
// parsed as references by this lint, so we ignore it for the file header block.
// ignore_for_file: comment_references

import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/social/data/supabase_social_activity_repository.dart';
import 'package:uff/src/features/social/domain/remote_activity_track_point.dart';
import 'package:uff/src/features/social/domain/social_activity_detail.dart';

import 'supabase_smoke_helpers.dart';

/// ## Test Scenarios
/// - [positive] Owner detail read returns exact seeded coordinates for all points.
/// - [negative] Viewer detail read masks inside-zone coordinates while direct
///   raw `track_points` reads remain denied for the viewer.
/// - [isolation] Each run uses fresh owner/viewer accounts and cleanup.
void main() {
  group('Privacy-zone masking smoke test', skip: skipReason, () {
    SmokeTestUser? owner;
    SmokeTestUser? viewer;
    SupabaseSocialActivityRepository? ownerRepository;
    SupabaseSocialActivityRepository? viewerRepository;

    setUp(() async {
      owner = await createSignedInTestUser(displayName: 'Masking Owner');
      viewer = await createSignedInTestUser(displayName: 'Masking Viewer');
      ownerRepository = SupabaseSocialActivityRepository(owner!.client);
      viewerRepository = SupabaseSocialActivityRepository(viewer!.client);
    });

    tearDown(() async {
      final usersToCleanup = <SmokeTestUser>[
        if (owner != null) owner!,
        if (viewer != null) viewer!,
      ];
      if (usersToCleanup.isNotEmpty) {
        await cleanupSmokeTestUsers(usersToCleanup);
      }
      owner = null;
      viewer = null;
      ownerRepository = null;
      viewerRepository = null;
    });

    test(
      'owner sees raw track points while viewer sees masked in-zone coordinates with non-coordinate parity',
      () async {
        final ownerUser = _requireTestUser(owner, label: 'owner');
        final viewerUser = _requireTestUser(viewer, label: 'viewer');
        final ownerActivityRepository = _requireRepository(
          ownerRepository,
          label: 'owner',
        );
        final viewerActivityRepository = _requireRepository(
          viewerRepository,
          label: 'viewer',
        );

        final fixture = await _seedOwnerMaskingFixture(ownerUser);
        await _expectRawTrackPointAccess(
          ownerUser: ownerUser,
          viewerUser: viewerUser,
          fixture: fixture,
        );

        final ownerDetail = await _loadVisibleDetail(
          repository: ownerActivityRepository,
          activityId: fixture.activityId,
          readerLabel: 'owner',
        );
        final viewerDetail = await _loadVisibleDetail(
          repository: viewerActivityRepository,
          activityId: fixture.activityId,
          readerLabel: 'viewer',
        );

        expect(ownerDetail.trackPoints, hasLength(2));
        expect(viewerDetail.trackPoints, hasLength(2));
        _expectTrackPointCoordinates(
          trackPoints: ownerDetail.trackPoints,
          latitudes: <double?>[_insideZoneLatitude, _outsideZoneLatitude],
          longitudes: <double?>[_insideZoneLongitude, _outsideZoneLongitude],
        );
        _expectTrackPointCoordinates(
          trackPoints: viewerDetail.trackPoints,
          latitudes: <double?>[null, _outsideZoneLatitude],
          longitudes: <double?>[null, _outsideZoneLongitude],
        );

        _expectMappedNonCoordinateTrackPointFields(
          actualTrackPoints: ownerDetail.trackPoints,
          expectedRows: fixture.expectedRows,
        );
        _expectMappedNonCoordinateTrackPointFields(
          actualTrackPoints: viewerDetail.trackPoints,
          expectedRows: fixture.expectedRows,
        );
      },
    );
  });
}

class _MaskingFixture {
  const _MaskingFixture({
    required this.activityId,
    required this.expectedRows,
  });

  final String activityId;
  final List<Map<String, Object?>> expectedRows;
}

const _insideZoneLatitude = 40.7128;
const _insideZoneLongitude = -74.0060;
const _outsideZoneLatitude = 40.7228;
const _outsideZoneLongitude = -74.0160;
const _zoneRadiusMeters = 200;

SmokeTestUser _requireTestUser(SmokeTestUser? user, {required String label}) {
  if (user == null) {
    fail('Expected setUp to initialize the $label user.');
  }
  return user;
}

SupabaseSocialActivityRepository _requireRepository(
  SupabaseSocialActivityRepository? repository, {
  required String label,
}) {
  if (repository == null) {
    fail('Expected setUp to initialize the $label repository.');
  }
  return repository;
}

Future<_MaskingFixture> _seedOwnerMaskingFixture(
  SmokeTestUser ownerUser,
) async {
  final activityId = await seedActivityForCurrentUser(
    ownerUser.client,
    visibility: 'public',
    startedAt: DateTime.utc(2026, 3, 19, 14),
    title: 'Masking Proof Activity',
  );
  await seedPrivacyZoneForCurrentUser(
    ownerUser.client,
    label: 'Owner Home Zone',
    // ignore: avoid_redundant_argument_values, reason: keep the in-zone latitude explicit for this masking proof
    latitude: _insideZoneLatitude,
    // ignore: avoid_redundant_argument_values, reason: keep the in-zone longitude explicit for this masking proof
    longitude: _insideZoneLongitude,
    // ignore: avoid_redundant_argument_values, reason: keep the 200-meter zone radius explicit for this masking proof
    radiusMeters: _zoneRadiusMeters,
  );

  final fixtureRows = _trackPointFixtureRows(activityId);
  await ownerUser.client.from('track_points').insert(fixtureRows);

  final ownerRawRows = await _loadOwnerRawTrackPointRows(
    ownerUser,
    activityId: activityId,
  );
  expect(ownerRawRows, hasLength(fixtureRows.length));
  final expectedRows = _expectedRowsWithGeneratedIds(
    fixtureRows: fixtureRows,
    ownerRawRows: ownerRawRows,
  );
  return _MaskingFixture(activityId: activityId, expectedRows: expectedRows);
}

List<Map<String, Object?>> _trackPointFixtureRows(String activityId) => [
  {
    'activity_id': activityId,
    'timestamp': DateTime.utc(2026, 3, 19, 14).toIso8601String(),
    'latitude': _insideZoneLatitude,
    'longitude': _insideZoneLongitude,
    'elevation': 8.5,
    'heart_rate': 145,
    'cadence': 84,
    'power': 210,
    'speed': 3.25,
    'distance': 0,
    'temperature': 17,
  },
  {
    'activity_id': activityId,
    'timestamp': DateTime.utc(2026, 3, 19, 14, 4).toIso8601String(),
    'latitude': _outsideZoneLatitude,
    'longitude': _outsideZoneLongitude,
    'elevation': 12.75,
    'heart_rate': 152,
    'cadence': 88,
    'power': 228,
    'speed': 3.55,
    'distance': 1000,
    'temperature': 18,
  },
];

Future<List<Map<String, dynamic>>> _loadOwnerRawTrackPointRows(
  SmokeTestUser ownerUser, {
  required String activityId,
}) async {
  final rows = await ownerUser.client
      .from('track_points')
      .select(_trackPointSelectColumns)
      .eq('activity_id', activityId)
      .order('timestamp', ascending: true);
  return rows.map(Map<String, dynamic>.from).toList();
}

const _trackPointSelectColumns =
    'id,activity_id,timestamp,latitude,longitude,elevation,'
    'heart_rate,cadence,power,speed,distance,temperature';

List<Map<String, Object?>> _expectedRowsWithGeneratedIds({
  required List<Map<String, Object?>> fixtureRows,
  required List<Map<String, dynamic>> ownerRawRows,
}) {
  return <Map<String, Object?>>[
    for (var index = 0; index < fixtureRows.length; index++)
      <String, Object?>{
        ...fixtureRows[index],
        'id': ownerRawRows[index]['id'],
      },
  ];
}

Future<void> _expectRawTrackPointAccess({
  required SmokeTestUser ownerUser,
  required SmokeTestUser viewerUser,
  required _MaskingFixture fixture,
}) async {
  final ownerRawRows = await _loadOwnerRawTrackPointRows(
    ownerUser,
    activityId: fixture.activityId,
  );
  expect(ownerRawRows, hasLength(2));
  expect(
    ownerRawRows.map((row) => _optionalDouble(row['latitude'])).toList(),
    <double?>[_insideZoneLatitude, _outsideZoneLatitude],
  );
  expect(
    ownerRawRows.map((row) => _optionalDouble(row['longitude'])).toList(),
    <double?>[_insideZoneLongitude, _outsideZoneLongitude],
  );

  final viewerRawRows = await viewerUser.client
      .from('track_points')
      .select('id')
      .eq('activity_id', fixture.activityId);
  expect(viewerRawRows, isEmpty);
}

Future<SocialActivityDetail> _loadVisibleDetail({
  required SupabaseSocialActivityRepository repository,
  required String activityId,
  required String readerLabel,
}) async {
  final detail = await repository.loadActivityDetail(activityId);
  expect(detail?.activityId, activityId);
  if (detail == null) {
    fail('Expected $readerLabel detail read to be visible.');
  }
  return detail;
}

void _expectTrackPointCoordinates({
  required List<RemoteActivityTrackPoint> trackPoints,
  required List<double?> latitudes,
  required List<double?> longitudes,
}) {
  expect(trackPoints.map((point) => point.latitude).toList(), latitudes);
  expect(trackPoints.map((point) => point.longitude).toList(), longitudes);
}

void _expectMappedNonCoordinateTrackPointFields({
  required List<RemoteActivityTrackPoint> actualTrackPoints,
  required List<Map<String, Object?>> expectedRows,
}) {
  expect(actualTrackPoints.length, expectedRows.length);
  for (var index = 0; index < expectedRows.length; index++) {
    final actual = actualTrackPoints[index];
    final expected = expectedRows[index];
    expect(actual.id, expected['id']);
    expect(actual.activityId, expected['activity_id']);
    expect(
      actual.timestamp,
      DateTime.parse(_requiredString(expected['timestamp'])),
    );
    expect(
      actual.elevation,
      closeTo(_requiredDouble(expected['elevation']), 0.000001),
    );
    expect(actual.heartRate, expected['heart_rate']);
    expect(actual.cadence, expected['cadence']);
    expect(actual.power, expected['power']);
    expect(actual.speed, closeTo(_requiredDouble(expected['speed']), 0.000001));
    expect(
      actual.distance,
      closeTo(_requiredDouble(expected['distance']), 0.000001),
    );
    expect(actual.temperature, expected['temperature']);
  }
}

double? _optionalDouble(Object? value) => (value as num?)?.toDouble();

String _requiredString(Object? value) {
  if (value is! String) {
    fail('Expected fixture value to be a String.');
  }
  return value;
}

double _requiredDouble(Object? value) {
  if (value is! num) {
    fail('Expected fixture value to be numeric.');
  }
  return value.toDouble();
}

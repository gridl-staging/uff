part of 'fixtures.dart';

@visibleForTesting
Future<PickedPhoto> loadPhotoFixture(
  String fixturePath, {
  String? fileName,
}) async {
  final resolvedFileName = fileName ?? _fileNameFromPath(fixturePath);
  final bytes = await _loadFixtureBytes(
    assetPath: fixturePath,
    fileFallbackPath: _resolveFixtureFilePath(fixturePath),
  );
  return PickedPhoto(fileName: resolvedFileName, bytes: bytes);
}

@visibleForTesting
Future<List<PickedPhoto>> loadPhotoFixtures(List<String> fixturePaths) async {
  final photos = <PickedPhoto>[];
  for (final path in fixturePaths) {
    photos.add(await loadPhotoFixture(path));
  }
  return photos;
}

Future<List<Object>> buildPhotoPickerFixtureOverrides(
  List<String> fixturePaths,
) async {
  return [
    buildPhotoPickerFixtureOverride(await loadPhotoFixtures(fixturePaths)),
  ];
}

@visibleForTesting
Object buildPhotoPickerFixtureOverride(List<PickedPhoto> pickedPhotos) {
  return photoPickerServiceProvider.overrideWithValue(
    FixturePhotoPickerService(pickedPhotos: pickedPhotos),
  );
}

const _photoGalleryPollInterval = Duration(milliseconds: 250);
// Local Supabase storage uploads and signed-URL refreshes can lag on emulator
// runs, so give the photo gallery a wider polling budget before failing.
const _maxPhotoGalleryPollAttempts = 240;
const _maxPhotoUploadStartPollAttempts = 24;

/// Scrolls the activity detail ListView until the photo section is visible.
///
/// The photo gallery sits below the summary card in the detail ListView. On
/// smaller viewports or activities with more metadata content, the section
/// may be beyond the lazy-build threshold and invisible until scrolled into
/// view. Call this after navigating to the detail screen and before
/// interacting with any photo-section widgets.
Future<void> revealActivityDetailPhotoSection(
  PatrolIntegrationTester $,
) async {
  await _scrollUntilAnyFinderHitTestable(
    $,
    description: 'activity detail photo section',
    candidateFinders: [
      find.byKey(ActivityDetailScreen.photoSectionKey),
      find.byKey(ActivityDetailScreen.photoEmptyStateKey),
      find.byKey(ActivityDetailScreen.photoAddButtonKey),
      find.byKey(ActivityDetailScreen.photoUnsyncedMessageKey),
    ],
    maxAttempts: _maxDetailScrollAttempts,
    delta: _detailScrollDelta,
    settleDuration: _detailScrollSettleDuration,
  );
}

/// Enters saved-detail edit mode and reveals the photo section controls.
///
/// `ActivityDetailScreen` is intentionally read-first. For synced activities
/// with zero photos, the photo section stays hidden in view mode and only
/// becomes actionable after the explicit overflow-menu Edit action. Release
/// smoke tests that need add/delete controls should use this helper so they
/// track the same contract as the screen spec and widget tests.
Future<void> revealActivityDetailPhotoSectionInEditMode(
  PatrolIntegrationTester $,
) async {
  final overflowMenuFinder = find.byKey(
    ActivityDetailScreen.overflowMenuButtonKey,
  );
  final editButtonFinder = find.byKey(ActivityDetailScreen.editButtonKey);

  await $(overflowMenuFinder).waitUntilVisible();
  await $(overflowMenuFinder).tap();
  await $(editButtonFinder).waitUntilVisible();
  await $(editButtonFinder).tap();
  await revealActivityDetailPhotoSection($);
}

Future<void> waitForPhotoThumbnailToAppear(PatrolIntegrationTester $) async {
  final sectionFinder = find.byKey(ActivityDetailScreen.photoSectionKey);
  final thumbnailFinder = _detailPhotoThumbnailFinder(sectionFinder);
  final uploadMutationFinder = _detailPhotoUploadMutationFinder(sectionFinder);
  final uploadErrorFinder = _detailPhotoUploadErrorFinder(sectionFinder);
  // The photo section may be rendered below the visible viewport after a photo
  // is added, so check existence rather than hit-testability.
  await $(sectionFinder).waitUntilExists();

  for (var attempt = 0; attempt < _maxPhotoGalleryPollAttempts; attempt++) {
    final hasThumbnail = thumbnailFinder.evaluate().isNotEmpty;
    if (hasThumbnail) {
      return;
    }

    final uploadErrorWidgets = uploadErrorFinder
        .evaluate()
        .map((element) => _textWidgetLabel(element.widget))
        .where((text) => text.trim().isNotEmpty)
        .toList(growable: false);
    if (uploadErrorWidgets.isNotEmpty) {
      throw StateError(
        'Photo upload failed before thumbnail render: ${uploadErrorWidgets.join(" | ")}',
      );
    }

    final hasUploadMutation = uploadMutationFinder.evaluate().isNotEmpty;
    final isEmptyStateVisible = find
        .byKey(ActivityDetailScreen.photoEmptyStateKey)
        .evaluate()
        .isNotEmpty;
    if (!hasUploadMutation &&
        isEmptyStateVisible &&
        attempt >= _maxPhotoUploadStartPollAttempts) {
      throw StateError(
        'Photo upload never started after selecting gallery source; empty state remained visible.',
      );
    }

    await $.tester.pump(_photoGalleryPollInterval);
  }

  final finalUploadMutationState = uploadMutationFinder.evaluate().isNotEmpty;
  final finalEmptyStateVisible = find
      .byKey(ActivityDetailScreen.photoEmptyStateKey)
      .evaluate()
      .isNotEmpty;
  throw StateError(
    'Timed out waiting for a photo thumbnail. '
    'uploadMutationVisible=$finalUploadMutationState '
    'emptyStateVisible=$finalEmptyStateVisible.',
  );
}

Future<void> tapFirstPhotoThumbnail(PatrolIntegrationTester $) async {
  await waitForPhotoThumbnailToAppear($);

  final sectionFinder = find.byKey(ActivityDetailScreen.photoSectionKey);
  final thumbnailFinder = _detailPhotoThumbnailFinder(sectionFinder);

  if (thumbnailFinder.evaluate().isEmpty) {
    throw StateError('No photo thumbnails are visible to tap.');
  }

  // Scroll the thumbnail into the visible/hit-testable area before tapping —
  // it may be off-screen if the detail page has enough content above.
  await $(thumbnailFinder.first).scrollTo();
  await $(thumbnailFinder.first).tap();
}

Future<void> waitForPhotoThumbnailToDisappear(PatrolIntegrationTester $) async {
  final sectionFinder = find.byKey(ActivityDetailScreen.photoSectionKey);
  final thumbnailFinder = _detailPhotoThumbnailFinder(sectionFinder);
  final deleteErrorFinder = _detailPhotoDeleteErrorFinder(sectionFinder);
  await $(sectionFinder).waitUntilExists();

  for (var attempt = 0; attempt < _maxPhotoGalleryPollAttempts; attempt++) {
    if (thumbnailFinder.evaluate().isEmpty) {
      return;
    }

    final deleteErrorWidgets = deleteErrorFinder
        .evaluate()
        .map((element) => _textWidgetLabel(element.widget))
        .where((text) => text.trim().isNotEmpty)
        .toList(growable: false);
    if (deleteErrorWidgets.isNotEmpty) {
      throw StateError(
        'Photo delete failed before thumbnail removal: ${deleteErrorWidgets.join(" | ")}',
      );
    }

    await $.tester.pump(_photoGalleryPollInterval);
  }

  throw StateError('Timed out waiting for photo thumbnails to disappear.');
}

/// Polls the `activity_photos` table until at least one row exists for
/// [remoteActivityId], returning the first photo's ID.
///
/// This helper encapsulates the Supabase query and `tester.pump` polling
/// that test files are not allowed to use directly (banned by
/// `scripts/check_e2e_standards.sh`).
Future<String> waitForPhotoMetadataPersisted(
  PatrolIntegrationTester $, {
  required String remoteActivityId,
  int maxAttempts = 20,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final rows = await Supabase.instance.client
        .from('activity_photos')
        .select('id')
        .eq('activity_id', remoteActivityId)
        .order('sort_order', ascending: true);
    if (rows.isNotEmpty) {
      return rows.first['id'] as String;
    }
    await $.tester.pump(_photoGalleryPollInterval);
  }

  throw StateError(
    'Timed out waiting for photo metadata row for activity $remoteActivityId.',
  );
}

Finder _detailPhotoThumbnailFinder(Finder sectionFinder) {
  return find.descendant(
    of: sectionFinder,
    matching: find.byWidgetPredicate(
      (widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('detail_photo_thumbnail_');
      },
      description: 'activity detail photo thumbnail',
    ),
  );
}

Finder _detailPhotoUploadMutationFinder(Finder sectionFinder) {
  return find.descendant(
    of: sectionFinder,
    matching: find.byWidgetPredicate(
      (widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('detail_photo_upload_') &&
            !key.value.startsWith('detail_photo_upload_error_');
      },
      description: 'activity detail photo upload mutation row',
    ),
  );
}

Finder _detailPhotoUploadErrorFinder(Finder sectionFinder) {
  return find.descendant(
    of: sectionFinder,
    matching: find.byWidgetPredicate(
      (widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('detail_photo_upload_error_');
      },
      description: 'activity detail photo upload error row',
    ),
  );
}

Finder _detailPhotoDeleteErrorFinder(Finder sectionFinder) {
  return find.descendant(
    of: sectionFinder,
    matching: find.byWidgetPredicate(
      (widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('detail_photo_delete_error_');
      },
      description: 'activity detail photo delete error row',
    ),
  );
}

/// TODO: Document FixturePhotoPickerService.
class FixturePhotoPickerService extends PhotoPickerService {
  FixturePhotoPickerService({
    List<PickedPhoto> pickedPhotos = const [],
    Map<PhotoPickSource, List<PickedPhoto>>? pickedPhotosBySource,
  }) : _pickedPhotos = pickedPhotos
           .map(_copyPickedPhoto)
           .toList(growable: false),
       _pickedPhotosBySource = _copyPickedPhotosBySource(pickedPhotosBySource);

  final List<PickedPhoto> _pickedPhotos;
  final Map<PhotoPickSource, List<PickedPhoto>> _pickedPhotosBySource;

  @override
  Future<List<PickedPhoto>> pickPhotos({
    required PhotoPickSource source,
    int maxSelection = 20,
    bool offerCrop = false,
  }) async {
    final selectedPhotos = _pickedPhotosBySource[source] ?? _pickedPhotos;
    if (maxSelection <= 0 || selectedPhotos.isEmpty) {
      return const <PickedPhoto>[];
    }

    return selectedPhotos
        .take(maxSelection)
        .map(_copyPickedPhoto)
        .toList(growable: false);
  }
}

Map<PhotoPickSource, List<PickedPhoto>> _copyPickedPhotosBySource(
  Map<PhotoPickSource, List<PickedPhoto>>? pickedPhotosBySource,
) {
  if (pickedPhotosBySource == null || pickedPhotosBySource.isEmpty) {
    return const <PhotoPickSource, List<PickedPhoto>>{};
  }
  return pickedPhotosBySource.map(
    (source, photos) => MapEntry(
      source,
      photos.map(_copyPickedPhoto).toList(growable: false),
    ),
  );
}

PickedPhoto _copyPickedPhoto(PickedPhoto photo) {
  return PickedPhoto(
    fileName: photo.fileName,
    bytes: Uint8List.fromList(photo.bytes),
  );
}

String _fileNameFromPath(String fixturePath) {
  final segments = fixturePath.split(_pathSeparatorPattern);
  final fileName = segments.last;
  if (fileName.isEmpty) {
    throw ArgumentError.value(
      fixturePath,
      'fixturePath',
      'must include a file name',
    );
  }
  return fileName;
}

@immutable
class SeededSyncedActivity {
  const SeededSyncedActivity({
    required this.localSessionId,
    required this.remoteActivityId,
  });

  final int localSessionId;
  final String remoteActivityId;
}

typedef RemoteActivityInserter =
    Future<void> Function(
      Map<String, dynamic> payload,
    );

@immutable
class SyncedActivitySeedDependencies {
  const SyncedActivitySeedDependencies({
    required this.currentUserId,
    required this.insertRemoteActivity,
    this.remoteIdGenerator = generateUuidV4,
  });

  final String? currentUserId;
  final RemoteActivityInserter insertRemoteActivity;
  final String Function() remoteIdGenerator;
}

Future<SeededSyncedActivity> seedSyncedActivity(
  PatrolIntegrationTester $, {
  required double distanceMeters,
  int movingTimeSeconds = 1800,
  DateTime? startedAt,
  List<TrackingPoint> points = const [],
}) {
  final client = Supabase.instance.client;
  return seedSyncedActivityInContainer(
    _containerOf($),
    dependencies: SyncedActivitySeedDependencies(
      currentUserId: client.auth.currentUser?.id,
      insertRemoteActivity: (payload) async {
        await client.from('activities').insert(payload);
      },
    ),
    distanceMeters: distanceMeters,
    movingTimeSeconds: movingTimeSeconds,
    startedAt: startedAt,
    points: points,
  );
}

@visibleForTesting
Future<SeededSyncedActivity> seedSyncedActivityInContainer(
  ProviderContainer container, {
  required SyncedActivitySeedDependencies dependencies,
  required double distanceMeters,
  int movingTimeSeconds = 1800,
  DateTime? startedAt,
  List<TrackingPoint> points = const [],
}) async {
  final userId = dependencies.currentUserId?.trim();
  if (userId == null || userId.isEmpty) {
    throw StateError(
      'Cannot seed synced activity without an authenticated Supabase user.',
    );
  }

  final localSessionId = await seedActivityInContainer(
    container,
    distanceMeters: distanceMeters,
    movingTimeSeconds: movingTimeSeconds,
    startedAt: startedAt,
    points: points,
  );

  final remoteActivityId = dependencies.remoteIdGenerator();
  final repository = container.read(trackingRepositoryProvider);
  final seededSession = await repository.loadSession(localSessionId);
  if (seededSession == null) {
    throw StateError(
      'Failed to load seeded session $localSessionId before remote insert.',
    );
  }

  await dependencies.insertRemoteActivity(
    _buildSeededActivityPayload(
      remoteActivityId: remoteActivityId,
      userId: userId,
      session: seededSession,
    ),
  );
  await repository.updateSessionRemoteId(localSessionId, remoteActivityId);
  container.invalidate(savedActivitiesProvider);

  // Keep a listener on the activity detail provider so autoDispose does not
  // clean it up between seed-time and the moment the detail screen widget
  // mounts. Without this, container.read() resolves the future but the
  // provider is immediately eligible for disposal, re-triggering the
  // profileProvider network call when the widget re-reads the provider.
  // The subscription lives until the container is disposed at test teardown.
  final activityDetail = activityDetailProvider(localSessionId);
  await (container..listen(activityDetail, (_, __) {})).read(
    activityDetail.future,
  );

  return SeededSyncedActivity(
    localSessionId: localSessionId,
    remoteActivityId: remoteActivityId,
  );
}

Map<String, dynamic> _buildSeededActivityPayload({
  required String remoteActivityId,
  required String userId,
  required TrackingSessionRecord session,
}) {
  final startedAt = (session.startedAt ?? session.createdAt).toUtc();
  final finishedAt = (session.stoppedAt ?? startedAt).toUtc();
  final durationSeconds =
      session.movingTimeSeconds ?? finishedAt.difference(startedAt).inSeconds;

  return <String, dynamic>{
    'id': remoteActivityId,
    'user_id': userId,
    'sport_type': _toSupportedRemoteSportType(session.sportType),
    'started_at': startedAt.toIso8601String(),
    'finished_at': finishedAt.toIso8601String(),
    'distance_meters': session.distanceMeters ?? 0.0,
    'duration_seconds': durationSeconds,
    'elevation_gain_meters': session.elevationGainMeters,
    'title': session.title,
    'description': session.description,
    'visibility': normalizeTrackingSessionVisibility(session.visibility),
  };
}

String _toSupportedRemoteSportType(String? sportType) {
  if (sportType == 'ride') {
    return 'ride';
  }
  return 'run';
}

@immutable
class SeededRemoteActivityPhoto {
  const SeededRemoteActivityPhoto({
    required this.photoId,
    required this.storagePath,
    required this.sortOrder,
  });

  final String photoId;
  final String storagePath;
  final int sortOrder;
}

typedef UploadSeededPhotoStorageObject =
    Future<void> Function({
      required String path,
      required Uint8List bytes,
    });
typedef InsertSeededPhotoMetadata =
    Future<String> Function(Map<String, dynamic> payload);

@immutable
class SeededRemoteActivityPhotoDependencies {
  const SeededRemoteActivityPhotoDependencies({
    required this.currentUserId,
    required this.uploadStorageObject,
    required this.insertPhotoMetadata,
    this.photoIdGenerator = generateUuidV4,
  });

  final String? currentUserId;
  final UploadSeededPhotoStorageObject uploadStorageObject;
  final InsertSeededPhotoMetadata insertPhotoMetadata;
  final String Function() photoIdGenerator;
}

/// Seeds a remote `activity_photos` row plus storage object for [activityId].
///
/// E2E social-photo tests need remote-detail photo data without going through
/// the owner edit UI for every visibility variant. Keep the arrangement in this
/// helper so Patrol files stay on visible navigation/assertions only.
Future<SeededRemoteActivityPhoto> seedRemoteActivityPhoto({
  required String activityId,
  String fixturePath = 'e2e_test/test_data/photo_a.jpg',
  Uint8List? photoBytes,
  String? fileName,
  int sortOrder = 0,
  SeededRemoteActivityPhotoDependencies? dependencies,
}) async {
  final resolvedDependencies =
      dependencies ?? _buildSeededRemoteActivityPhotoDependencies();
  final userId = resolvedDependencies.currentUserId?.trim();
  if (userId == null || userId.isEmpty) {
    throw StateError(
      'Cannot seed remote activity photo without an authenticated Supabase user.',
    );
  }

  final photoId = resolvedDependencies.photoIdGenerator();
  final resolvedFileName =
      fileName ?? '${photoId}_${_fileNameFromPath(fixturePath)}';
  final resolvedPhotoBytes =
      photoBytes ??
      await _loadFixtureBytes(
        assetPath: fixturePath,
        fileFallbackPath: _resolveFixtureFilePath(fixturePath),
      );
  final storagePath = '$userId/$activityId/$resolvedFileName';

  await resolvedDependencies.uploadStorageObject(
    path: storagePath,
    bytes: resolvedPhotoBytes,
  );
  final insertedPhotoId = await resolvedDependencies.insertPhotoMetadata({
    'activity_id': activityId,
    'user_id': userId,
    'storage_path': storagePath,
    'thumbnail_path': null,
    'sort_order': sortOrder,
  });

  return SeededRemoteActivityPhoto(
    photoId: insertedPhotoId,
    storagePath: storagePath,
    sortOrder: sortOrder,
  );
}

SeededRemoteActivityPhotoDependencies
_buildSeededRemoteActivityPhotoDependencies() {
  final client = Supabase.instance.client;
  return SeededRemoteActivityPhotoDependencies(
    currentUserId: client.auth.currentUser?.id,
    uploadStorageObject:
        ({required String path, required Uint8List bytes}) async {
          await client.storage
              .from('activity-photos')
              .uploadBinary(
                path,
                bytes,
                fileOptions: const FileOptions(upsert: true),
              );
        },
    insertPhotoMetadata: (payload) async {
      final inserted = await client
          .from('activity_photos')
          .insert(payload)
          .select('id')
          .single();
      return inserted['id'] as String;
    },
  );
}

typedef LoadPhotoRowsForActivity =
    Future<List<Map<String, dynamic>>> Function({
      required String activityId,
      required String userId,
    });
typedef DeletePhotoRowsForActivity =
    Future<void> Function({
      required String activityId,
      required String userId,
    });
typedef DeletePhotoStorageObjects = Future<void> Function(List<String> paths);

@immutable
class SeededPhotoCleanupDependencies {
  const SeededPhotoCleanupDependencies({
    required this.currentUserId,
    required this.loadPhotoRowsForActivity,
    required this.deletePhotoRowsForActivity,
    required this.deleteStorageObjects,
  });

  final String? currentUserId;
  final LoadPhotoRowsForActivity loadPhotoRowsForActivity;
  final DeletePhotoRowsForActivity deletePhotoRowsForActivity;
  final DeletePhotoStorageObjects deleteStorageObjects;
}

Future<void> cleanupSeededPhotoArtifacts({
  required Iterable<String> remoteActivityIds,
  SeededPhotoCleanupDependencies? dependencies,
}) async {
  final resolvedDependencies =
      dependencies ?? _buildSeededPhotoCleanupDependencies();
  final userId = resolvedDependencies.currentUserId?.trim();
  if (userId == null || userId.isEmpty) {
    return;
  }

  final normalizedActivityIds = <String>{};
  final storagePaths = <String>{};
  for (final remoteActivityId in remoteActivityIds) {
    final normalizedActivityId = remoteActivityId.trim();
    if (normalizedActivityId.isEmpty) {
      continue;
    }
    normalizedActivityIds.add(normalizedActivityId);

    final rows = await resolvedDependencies.loadPhotoRowsForActivity(
      activityId: normalizedActivityId,
      userId: userId,
    );
    for (final row in rows) {
      _appendPhotoStoragePathIfPresent(storagePaths, row['storage_path']);
      _appendPhotoStoragePathIfPresent(storagePaths, row['thumbnail_path']);
    }
  }

  if (storagePaths.isNotEmpty) {
    await resolvedDependencies.deleteStorageObjects(
      storagePaths.toList(growable: false),
    );
  }

  for (final activityId in normalizedActivityIds) {
    await resolvedDependencies.deletePhotoRowsForActivity(
      activityId: activityId,
      userId: userId,
    );
  }
}

SeededPhotoCleanupDependencies _buildSeededPhotoCleanupDependencies() {
  final client = Supabase.instance.client;
  return SeededPhotoCleanupDependencies(
    currentUserId: client.auth.currentUser?.id,
    loadPhotoRowsForActivity:
        ({
          required String activityId,
          required String userId,
        }) async {
          final rows = await client
              .from('activity_photos')
              .select('storage_path,thumbnail_path')
              .eq('activity_id', activityId)
              .eq('user_id', userId);
          return rows.cast<Map<String, dynamic>>();
        },
    deletePhotoRowsForActivity:
        ({
          required String activityId,
          required String userId,
        }) {
          return client
              .from('activity_photos')
              .delete()
              .eq('activity_id', activityId)
              .eq('user_id', userId);
        },
    deleteStorageObjects: (paths) async {
      if (paths.isEmpty) {
        return;
      }
      await client.storage.from('activity-photos').remove(paths);
    },
  );
}

void _appendPhotoStoragePathIfPresent(Set<String> target, Object? pathValue) {
  if (pathValue is! String) {
    return;
  }
  final normalizedPath = pathValue.trim();
  if (normalizedPath.isEmpty) {
    return;
  }
  target.add(normalizedPath);
}

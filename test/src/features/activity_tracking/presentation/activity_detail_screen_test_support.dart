import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/data/activity_gear_assignment_repository.dart';
import 'package:uff/src/features/activity_tracking/domain/activity_processing_models.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/data/tracking_database.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/photos/application/pending_photo_service.dart';
import 'package:uff/src/features/analytics/application/analytics_providers.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart';
import 'package:uff/src/features/photos/data/photo_picker_service.dart';
import 'package:uff/src/features/photos/data/photo_repository.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';

import '../application/tracking_controller_test_support.dart';
import '../../../test_helpers/mapbox_platform_channel_stub.dart';
import '../../../test_helpers/saved_activities_probe.dart';

const activityId = 77;
const activityDetailExitRouteText = 'Activity Detail Exit Route';

void configureActivityDetailScreenTests() {
  setUpMapboxPlatformChannelStub();
}

class MockActivityDetailLoader extends Mock {
  Future<ActivityDetailData?> call();
}

class SaveAttemptTrackingRepository extends FakeTrackingRepository {
  SaveAttemptTrackingRepository() : super(throwOnSaveSession: true);

  int saveAttemptCount = 0;

  @override
  Future<void> saveSession(TrackingSessionRecord session) async {
    saveAttemptCount += 1;
    await super.saveSession(session);
  }
}

/// NOTE(stuart): Document RecordingActivityGearAssignmentRepository.
class RecordingActivityGearAssignmentRepository
    implements ActivityGearAssignmentRepository {
  RecordingActivityGearAssignmentRepository({
    Map<String, String?>? assignedGearByRemoteActivityId,
    this.loadError,
    this.updateError,
  }) : _assignedGearByRemoteActivityId =
           assignedGearByRemoteActivityId ?? <String, String?>{};

  final Map<String, String?> _assignedGearByRemoteActivityId;

  Exception? loadError;
  Exception? updateError;
  int loadCallCount = 0;
  int updateCallCount = 0;
  String? lastLoadedRemoteActivityId;
  String? lastUpdatedRemoteActivityId;
  String? lastUpdatedGearId;
  Completer<void>? updateCompleter;

  @override
  Future<String?> loadAssignedGearId(String remoteActivityId) async {
    loadCallCount += 1;
    lastLoadedRemoteActivityId = remoteActivityId;
    if (loadError case final Exception error) {
      throw error;
    }
    return _assignedGearByRemoteActivityId[remoteActivityId];
  }

  @override
  Future<void> updateAssignedGearId(
    String remoteActivityId,
    String? gearId,
  ) async {
    updateCallCount += 1;
    lastUpdatedRemoteActivityId = remoteActivityId;
    lastUpdatedGearId = gearId;
    if (updateError case final Exception error) {
      throw error;
    }
    if (updateCompleter case final Completer<void> completer) {
      await completer.future;
    }
    _assignedGearByRemoteActivityId[remoteActivityId] = gearId;
  }
}

/// Fake sync service that always throws on remote deletes.
class ThrowingSyncService extends FakeSyncService {
  @override
  Future<void> deleteRemoteActivity(String remoteActivityId) async {
    throw StateError('Remote delete failed for $remoteActivityId');
  }
}

/// Fake sync service where remote delete blocks until `completeDelete` runs,
/// so tests can observe in-flight state.
class SlowSyncService extends FakeSyncService {
  final _deleteCompleter = Completer<void>();

  @override
  Future<void> deleteRemoteActivity(String remoteActivityId) async {
    deletedRemoteActivityIds.add(remoteActivityId);
    await _deleteCompleter.future;
  }

  void completeDelete() => _deleteCompleter.complete();
}

/// A single entry in the ordered call log shared between
/// [SequencingSpyRepository] and [SequencingSpySyncService].
class SequencingCallRecord {
  SequencingCallRecord(this.method, {this.session, this.sessionId});

  final String method;
  final TrackingSessionRecord? session;
  final int? sessionId;
}

/// Spy repository that records ordered saveSession, loadSession, and
/// finalizeSession calls for recording-path sequencing assertions.
class SequencingSpyRepository extends FakeTrackingRepository {
  final List<SequencingCallRecord> callLog = [];

  @override
  Future<void> saveSession(TrackingSessionRecord session) async {
    callLog.add(SequencingCallRecord('saveSession', session: session));
    await super.saveSession(session);
  }

  @override
  FutureOr<TrackingSessionRecord?> loadSession(int sessionId) async {
    final result = await super.loadSession(sessionId);
    callLog.add(
      SequencingCallRecord(
        'loadSession',
        session: result,
        sessionId: sessionId,
      ),
    );
    return result;
  }

  @override
  Future<void> finalizeSession(int sessionId) async {
    callLog.add(SequencingCallRecord('finalizeSession', sessionId: sessionId));
    await super.finalizeSession(sessionId);
  }
}

/// Spy sync service that records queueForSync calls into a shared call log
/// owned by [SequencingSpyRepository].
class SequencingSpySyncService extends FakeSyncService {
  SequencingSpySyncService(this.callLog);

  final List<SequencingCallRecord> callLog;

  @override
  Future<void> queueForSync(int sessionId) async {
    callLog.add(SequencingCallRecord('queueForSync', sessionId: sessionId));
    await super.queueForSync(sessionId);
  }
}

class CountingActivityDetailLoader {
  CountingActivityDetailLoader(this.detailData);

  final ActivityDetailData detailData;
  int callCount = 0;

  Future<ActivityDetailData?> call() async {
    callCount += 1;
    return detailData;
  }
}

ActivityDetailData buildTestActivityDetailData({
  required int activityId,
  TrackingSessionStatus status = TrackingSessionStatus.saved,
  String? remoteId,
  String? title = 'Morning Tempo',
  String? description = 'Steady effort with final push.',
  String? visibility,
}) {
  final session = TrackingSessionRecord(
    id: activityId,
    status: status,
    createdAt: DateTime(2025, 1, 10, 7, 30),
    updatedAt: DateTime(2025, 1, 10, 8, 2),
    startedAt: DateTime(2025, 1, 10, 7, 30),
    stoppedAt: DateTime(2025, 1, 10, 8, 2),
    title: title,
    description: description,
    remoteId: remoteId,
    visibility: visibility,
  );

  return ActivityDetailData(
    session: session,
    cleanedPoints: [
      TrackingPoint(
        sessionId: activityId,
        timestamp: DateTime(2025, 1, 10, 7, 30),
        coordinate: const GeoCoordinate(latitude: 40.7128, longitude: -74.0060),
      ),
      TrackingPoint(
        sessionId: activityId,
        timestamp: DateTime(2025, 1, 10, 7, 46),
        coordinate: const GeoCoordinate(latitude: 40.7198, longitude: -73.9980),
      ),
    ],
    processedMetrics: ProcessedActivityMetrics(
      session: session,
      trackSummary: const TrackSummary(
        distanceMeters: 3420,
        movingTime: Duration(minutes: 32, seconds: 15),
        averagePace: ActivityPace(
          perKilometer: Duration(minutes: 9, seconds: 26),
          perMile: Duration(minutes: 15, seconds: 12),
        ),
        elevationGainMeters: 88.4,
      ),
      splits: const [],
      autoPause: const AutoPauseResult(
        windows: [],
        totalMovingDuration: Duration(minutes: 32, seconds: 15),
      ),
    ),
  );
}

Future<void> pumpActivityDetailScreen(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
  bool includeDefaultSyncEntryOverride = true,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    _buildActivityDetailProviderScope(
      overrides: overrides,
      includeDefaultSyncEntryOverride: includeDefaultSyncEntryOverride,
      child: const MaterialApp(
        home: ActivityDetailScreen(activityId: activityId),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Widget buildPoppableActivityDetailScreen({
  List<Override> overrides = const <Override>[],
  bool includeDefaultSyncEntryOverride = true,
}) {
  return _buildActivityDetailProviderScope(
    overrides: overrides,
    includeDefaultSyncEntryOverride: includeDefaultSyncEntryOverride,
    child: MaterialApp(
      initialRoute: '/detail',
      routes: {
        '/': (_) => const Scaffold(body: Text(activityDetailExitRouteText)),
        '/detail': (_) => const ActivityDetailScreen(activityId: activityId),
      },
    ),
  );
}

/// Builds a poppable activity detail screen with [SavedActivitiesProbe] on the
/// detail route so tests can assert `savedActivitiesProvider` invalidation
/// without counting route-exit rebuilds as a false positive.
Widget buildPoppableDeleteTestScreen({
  List<Override> overrides = const <Override>[],
  bool includeDefaultSyncEntryOverride = true,
}) {
  return _buildActivityDetailProviderScope(
    overrides: overrides,
    includeDefaultSyncEntryOverride: includeDefaultSyncEntryOverride,
    child: MaterialApp(
      initialRoute: '/detail',
      routes: {
        '/': (_) => const Scaffold(body: Text(activityDetailExitRouteText)),
        '/detail': (_) => const Stack(
          children: [
            ActivityDetailScreen(activityId: activityId),
            SavedActivitiesProbe(),
          ],
        ),
      },
    ),
  );
}

ProviderScope _buildActivityDetailProviderScope({
  required Widget child,
  List<Override> overrides = const <Override>[],
  bool includeDefaultSyncEntryOverride = true,
}) {
  return ProviderScope(
    overrides: [
      ...defaultActivityDetailTestOverrides(
        includeDefaultSyncEntryOverride: includeDefaultSyncEntryOverride,
      ),
      ...overrides,
    ],
    child: child,
  );
}

List<Override> defaultActivityDetailTestOverrides({
  bool includeDefaultSyncEntryOverride = true,
}) {
  return [
    if (includeDefaultSyncEntryOverride)
      // The photo section now watches activitySyncEntryProvider during most
      // detail-screen builds. Keep widget tests hermetic by default so they do
      // not instantiate the real Drift-backed repository unless a test explicitly
      // opts into sync-state behavior.
      activitySyncEntryProvider(activityId).overrideWith((_) async => null),
    activityTssProvider(activityId).overrideWith((_) async => null),
    activityIntervalSummaryProvider(activityId).overrideWith((_) async => null),
  ];
}

Finder _detailScreenScrollableFinder() {
  return find
      .descendant(
        of: find.byType(ActivityDetailScreen),
        matching: find.byType(Scrollable),
      )
      .first;
}

Finder activityDetailRouteMapRegionFinder() {
  return find.byKey(ActivityDetailScreen.routeMapBoundaryKey);
}

double readActivityDetailScrollOffset(WidgetTester tester) {
  final scrollable = tester.state<ScrollableState>(
    _detailScreenScrollableFinder(),
  );
  return scrollable.position.pixels;
}

ScrollPhysics? readActivityDetailScrollPhysics(WidgetTester tester) {
  final listView = tester.widget<ListView>(
    find
        .descendant(
          of: find.byType(ActivityDetailScreen),
          matching: find.byType(ListView),
        )
        .first,
  );
  return listView.physics;
}

Offset mapCenterDragStart(WidgetTester tester) {
  return tester.getCenter(activityDetailRouteMapRegionFinder());
}

Offset mapAboveDragStart(WidgetTester tester, {double verticalPadding = 20}) {
  final mapRect = tester.getRect(activityDetailRouteMapRegionFinder());
  return Offset(mapRect.center.dx, mapRect.top - verticalPadding);
}

Offset mapBelowDragStart(WidgetTester tester, {double verticalPadding = 20}) {
  final mapRect = tester.getRect(activityDetailRouteMapRegionFinder());
  return Offset(mapRect.center.dx, mapRect.bottom + verticalPadding);
}

Future<void> dragFromOffset(
  WidgetTester tester, {
  required Offset start,
  required Offset delta,
}) async {
  final gesture = await tester.startGesture(start);
  await tester.pump();
  await gesture.moveBy(delta);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> enterActivityDetailEditMode(WidgetTester tester) async {
  await tester.tap(find.byKey(ActivityDetailScreen.overflowMenuButtonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ActivityDetailScreen.editButtonKey));
  await tester.pumpAndSettle();
}

Future<void> openActivityDetailOverflowMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(ActivityDetailScreen.overflowMenuButtonKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> scrollToActivityDetailKey(
  WidgetTester tester,
  Key key, {
  bool settleAfterDrag = true,
}) async {
  final finder = find.byKey(key);
  final scrollableFinder = _detailScreenScrollableFinder();

  // The saved-detail map now claims gestures that begin inside its bounds.
  // Scroll helpers must therefore drag from the lower viewport rather than the
  // scrollable center, which overlaps the map near the top of the screen.
  for (var attempt = 0; attempt < 20 && finder.evaluate().isEmpty; attempt++) {
    final scrollableRect = tester.getRect(scrollableFinder);
    final dragStart = Offset(
      scrollableRect.center.dx,
      scrollableRect.bottom - 40,
    );
    await tester.dragFrom(dragStart, const Offset(0, -250));
    if (settleAfterDrag) {
      await tester.pumpAndSettle();
    } else {
      // Pending upload tiles keep an indeterminate spinner alive forever, so a
      // full settle would time out even though the scroll itself completed.
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> scrollToVisibilitySelector(WidgetTester tester) {
  return scrollToActivityDetailKey(
    tester,
    ActivityDetailScreen.visibilitySegmentedButtonKey,
  );
}

Future<void> scrollToGearDropdown(WidgetTester tester) {
  return scrollToActivityDetailKey(
    tester,
    ActivityDetailScreen.gearDropdownKey,
  );
}

Future<void> scrollToSaveButton(WidgetTester tester) async {
  await scrollToActivityDetailKey(tester, ActivityDetailScreen.saveButtonKey);
  await tester.ensureVisible(find.byKey(ActivityDetailScreen.saveButtonKey));
  await tester.pump();
}

Future<void> scrollToDeleteButton(WidgetTester tester) {
  return scrollToActivityDetailKey(
    tester,
    ActivityDetailScreen.deleteButtonKey,
  );
}

Future<void> scrollToTitleField(WidgetTester tester) {
  return scrollToActivityDetailKey(tester, ActivityDetailScreen.titleFieldKey);
}

/// Opens the saved-detail overflow menu and taps Delete to show the
/// confirmation dialog. Call [WidgetTester.pumpAndSettle] after this to let
/// the dialog animation finish.
Future<void> openDeleteConfirmationDialog(WidgetTester tester) async {
  await openActivityDetailOverflowMenu(tester);
  await tester.tap(find.byKey(ActivityDetailScreen.deleteButtonKey));
  await tester.pumpAndSettle();
}

/// Opens the delete confirmation dialog and taps the confirm button.
Future<void> confirmDeleteActivity(WidgetTester tester) async {
  await openDeleteConfirmationDialog(tester);
  await tester.tap(find.byKey(ActivityDetailScreen.deleteConfirmButtonKey));
}

Future<void> openPhotoSourcePicker(WidgetTester tester) async {
  if (find.byKey(ActivityDetailScreen.photoAddButtonKey).evaluate().isEmpty) {
    await enterActivityDetailEditMode(tester);
  }
  await scrollToActivityDetailKey(
    tester,
    ActivityDetailScreen.photoAddButtonKey,
  );
  await tester.tap(find.byKey(ActivityDetailScreen.photoAddButtonKey));
  await tester.pumpAndSettle();
}

Future<void> selectPhotoSource(
  WidgetTester tester,
  PhotoPickSource source,
) async {
  await tester.tap(find.byKey(_photoSourceOptionKey(source)));
  await tester.pumpAndSettle();
}

Key _photoSourceOptionKey(PhotoPickSource source) {
  return switch (source) {
    PhotoPickSource.gallery => ActivityDetailScreen.photoSourceGalleryOptionKey,
    PhotoPickSource.camera => ActivityDetailScreen.photoSourceCameraOptionKey,
  };
}

Future<void> selectGearOption(WidgetTester tester, String label) async {
  final dropdownFinder = find.byKey(ActivityDetailScreen.gearDropdownKey);
  await scrollToGearDropdown(tester);
  await tester.ensureVisible(dropdownFinder);
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
  await tester.pumpAndSettle();
  await tester.tap(dropdownFinder);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pump();
}

Override overrideActivityPhotoListProvider({
  required String remoteActivityId,
  required List<ActivityPhoto> photos,
}) {
  return activityPhotoListProvider(
    remoteActivityId,
  ).overrideWith((_) async => photos);
}

Override overrideActivityPhotoControllerProvider({
  required String remoteActivityId,
  required ActivityPhotoControllerState state,
}) {
  return activityPhotoControllerProvider(
    remoteActivityId,
  ).overrideWithValue(state);
}

Override overrideActivityPhotoViewerShareHelperProvider(
  ActivityPhotoViewerShareHelper helper,
) {
  return activityPhotoViewerShareHelperProvider.overrideWithValue(helper);
}

Override overrideActivitySyncEntryProvider(SyncQueueEntry? syncEntry) {
  return activitySyncEntryProvider(
    activityId,
  ).overrideWith((_) async => syncEntry);
}

ActivityPhoto buildTestActivityPhoto({
  required String id,
  required String activityId,
  int sortOrder = 0,
  String? signedThumbnailUrl = 'https://example.com/thumb.jpg',
  String? signedStorageUrl = 'https://example.com/full.jpg',
  double? latitude,
  double? longitude,
}) {
  return ActivityPhoto(
    id: id,
    activityId: activityId,
    userId: 'user-1',
    storagePath: 'user-1/$activityId/$id.jpg',
    thumbnailPath: 'user-1/$activityId/${id}_thumb.jpg',
    sortOrder: sortOrder,
    createdAt: DateTime.utc(2026, 3, 17, 12, sortOrder),
    signedThumbnailUrl: signedThumbnailUrl,
    signedStorageUrl: signedStorageUrl,
    latitude: latitude,
    longitude: longitude,
  );
}

PickedPhoto buildPickedPhoto({
  required String fileName,
  List<int> bytes = const [1, 2, 3],
}) {
  return PickedPhoto(fileName: fileName, bytes: Uint8List.fromList(bytes));
}

/// TODO: Document RecordingPhotoPickerService.
class RecordingPhotoPickerService extends PhotoPickerService {
  RecordingPhotoPickerService({
    this.pickedPhotos = const <PickedPhoto>[],
    Map<PhotoPickSource, List<PickedPhoto>>? pickedPhotosBySource,
    this.pickPhotosError,
    Map<PhotoPickSource, Object>? pickPhotosErrorBySource,
  }) : _pickedPhotosBySource = _copyPickedPhotosBySource(pickedPhotosBySource),
       _pickPhotosErrorBySource = pickPhotosErrorBySource;

  static Map<PhotoPickSource, List<PickedPhoto>> _copyPickedPhotosBySource(
    Map<PhotoPickSource, List<PickedPhoto>>? pickedPhotosBySource,
  ) {
    if (pickedPhotosBySource == null || pickedPhotosBySource.isEmpty) {
      return const <PhotoPickSource, List<PickedPhoto>>{};
    }
    return pickedPhotosBySource.map(
      (source, photos) => MapEntry(source, photos.toList(growable: false)),
    );
  }

  final Map<PhotoPickSource, List<PickedPhoto>> _pickedPhotosBySource;
  final Map<PhotoPickSource, Object>? _pickPhotosErrorBySource;
  List<PickedPhoto> pickedPhotos;
  Object? pickPhotosError;
  int pickPhotosCallCount = 0;
  int? lastMaxSelection;
  bool? lastOfferCrop;
  PhotoPickSource? lastSource;
  final List<PhotoPickSource> requestedSources = <PhotoPickSource>[];
  final List<bool> requestedOfferCrop = <bool>[];

  @override
  Future<List<PickedPhoto>> pickPhotos({
    required PhotoPickSource source,
    int maxSelection = 20,
    bool offerCrop = false,
  }) async {
    pickPhotosCallCount += 1;
    lastMaxSelection = maxSelection;
    lastOfferCrop = offerCrop;
    lastSource = source;
    requestedSources.add(source);
    requestedOfferCrop.add(offerCrop);
    final sourceError = _pickPhotosErrorBySource?[source];
    if (sourceError != null) {
      if (sourceError is Error) {
        throw sourceError;
      }
      if (sourceError is Exception) {
        throw sourceError;
      }
      throw Exception(sourceError.toString());
    }
    if (pickPhotosError case final Object error) {
      if (error is Error) {
        throw error;
      }
      if (error is Exception) {
        throw error;
      }
      throw Exception(error.toString());
    }

    final sourcePhotos = _pickedPhotosBySource[source];
    final selectedPhotos = sourcePhotos ?? pickedPhotos;
    return selectedPhotos.take(maxSelection).toList(growable: false);
  }
}

/// TODO: Document RecordingPhotoRepository.
class RecordingPhotoRepository implements PhotoRepository {
  List<ActivityPhoto> photosToReturn = [];
  final Map<String, Completer<ActivityPhoto>> uploadCompletersByFileName = {};
  final Map<String, Object> deleteErrorsByPhotoId = {};
  final List<String> uploadedFileNames = [];
  final List<int> uploadedSortOrders = [];
  int loadCallCount = 0;
  int uploadCallCount = 0;
  int deleteCallCount = 0;
  String? lastLoadedActivityId;
  ActivityPhoto? lastDeletedPhoto;

  @override
  Future<List<ActivityPhoto>> loadActivityPhotos(String activityId) async {
    loadCallCount += 1;
    lastLoadedActivityId = activityId;
    return photosToReturn;
  }

  @override
  Future<ActivityPhoto> uploadPhoto({
    required String activityId,
    required Uint8List bytes,
    required String fileName,
    required int sortOrder,
    double? latitude,
    double? longitude,
  }) {
    uploadCallCount += 1;
    uploadedFileNames.add(fileName);
    uploadedSortOrders.add(sortOrder);
    final completer = uploadCompletersByFileName[fileName];
    if (completer != null) {
      return completer.future;
    }

    final id = 'uploaded-$fileName';
    final uploadedPhoto = buildTestActivityPhoto(
      id: id,
      activityId: activityId,
      sortOrder: sortOrder,
    );
    photosToReturn = [...photosToReturn, uploadedPhoto]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return Future<ActivityPhoto>.value(uploadedPhoto);
  }

  @override
  Future<void> deletePhoto(ActivityPhoto photo) async {
    deleteCallCount += 1;
    lastDeletedPhoto = photo;
    final deleteError = deleteErrorsByPhotoId[photo.id];
    if (deleteError != null) {
      if (deleteError is Error) {
        throw deleteError;
      }
      if (deleteError is Exception) {
        throw deleteError;
      }
      throw Exception(deleteError.toString());
    }
    photosToReturn = photosToReturn
        .where((item) => item.id != photo.id)
        .toList(growable: false);
  }
}

/// TODO: Document RecordingActivityPhotoViewerShareHelper.
class RecordingActivityPhotoViewerShareHelper
    extends ActivityPhotoViewerShareHelper {
  RecordingActivityPhotoViewerShareHelper({this.completer, this.error});

  Completer<void>? completer;
  Object? error;
  int callCount = 0;
  String? lastResolvedViewerPhotoUrl;
  String? lastFileLabel;

  @override
  Future<void> shareResolvedViewerPhoto({
    required String resolvedViewerPhotoUrl,
    required String fileLabel,
  }) async {
    callCount += 1;
    lastResolvedViewerPhotoUrl = resolvedViewerPhotoUrl;
    lastFileLabel = fileLabel;

    if (completer case final Completer<void> pendingCompleter) {
      await pendingCompleter.future;
    }

    if (error case final Object shareError) {
      if (shareError is Error) {
        throw shareError;
      }
      if (shareError is Exception) {
        throw shareError;
      }
      throw Exception(shareError.toString());
    }
  }
}

/// Minimal Auth notifier that returns a fixed state for test overrides.
class FakeAuthNotifier extends Auth {
  FakeAuthNotifier(this._state);
  final AuthState _state;

  @override
  FutureOr<AuthState> build() => _state;
}

const defaultTestViewerUserId = 'test-viewer-user-id';

List<Override> defaultAuthOverrides({String userId = defaultTestViewerUserId}) {
  return [
    authProvider.overrideWith(
      () => FakeAuthNotifier(
        AuthState.authenticated(userId: userId, email: '$userId@test.com'),
      ),
    ),
  ];
}

class _NoopTrackingDatabase implements TrackingDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('noop test stub');
  }
}

/// TODO: Document DiscardSpyPendingPhotoService.
class DiscardSpyPendingPhotoService extends PendingPhotoService {
  DiscardSpyPendingPhotoService()
    : super(
        db: _NoopTrackingDatabase(),
        photoPickerService: const PhotoPickerService(),
        compressPhoto: _identityCompressor,
        pendingPhotosDirectory: Directory.systemTemp,
        uuidGenerator: () => 'test-photo-uuid',
      );

  static Future<Uint8List> _identityCompressor(Uint8List bytes) async => bytes;

  int discardCallCount = 0;
  final List<int> discardedSessionIds = <int>[];

  @override
  Future<void> discardPendingPhotos(int sessionId) async {
    discardCallCount += 1;
    discardedSessionIds.add(sessionId);
  }
}

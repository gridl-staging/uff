import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/activity_tracking/presentation/activity_detail_screen.dart';
import 'package:uff/src/features/maps/presentation/map_view.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart';
import 'package:uff/src/features/photos/data/photo_picker_service.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';

import 'activity_detail_screen_test_support.dart';

/// ## Test Scenarios
/// - [positive] renders photo section after Summary card
/// - [positive] synced activity with photos shows thumbnails
/// - [positive] marker candidates come only from synced photos with coordinates
/// - [negative] coordinate-less photos never surface through marker inputs
/// - [negative] unsynced photos never surface through marker inputs
/// - [isolation] rebuilding detail flow for a different synced activity clears
///   stale marker candidates instead of reusing prior photo state

const _unsyncedPhotoGuidanceCopy =
    'Photos will be available after this activity finishes syncing.';
const _queuedSyncPhotoGuidanceCopy =
    'Activity sync is queued. Photos will be available when sync finishes.';
const _processingSyncPhotoGuidanceCopy =
    'Activity sync is in progress. Photos will be available when sync finishes.';
const _failedSyncPhotoGuidanceCopy =
    'Activity sync has not succeeded yet. Photos will be available after a successful sync.';
const _syncedPhotoEmptyStateCopy =
    'No photos yet. Add your first photo to this activity.';
const _photoSourcePickerTitle = 'Add photo';
const _photoShareFailureCopy =
    'Unable to share photo right now. Please try again.';

void main() {
  configureActivityDetailScreenTests();

  group('photo gallery shell', () {
    testWidgets('renders photo section after Summary card', (
      tester,
    ) async {
      const remoteActivityId = 'remote-photos-1';
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: remoteActivityId,
        ),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          overrideActivityPhotoListProvider(
            remoteActivityId: remoteActivityId,
            photos: const [],
          ),
          overrideActivityPhotoControllerProvider(
            remoteActivityId: remoteActivityId,
            state: const ActivityPhotoControllerState(),
          ),
        ],
      );

      await enterActivityDetailEditMode(tester);
      // The photo section is below Summary in a lazy ListView, so scroll
      // to it before asserting existence.
      await scrollToActivityDetailKey(
        tester,
        ActivityDetailScreen.photoSectionKey,
      );

      expect(find.byKey(ActivityDetailScreen.photoSectionKey), findsOneWidget);

      expect(
        find.byKey(ActivityDetailScreen.photoEmptyStateKey),
        findsOneWidget,
      );
    });

    testWidgets('shows unsynced guidance copy and hides add CTA', (
      tester,
    ) async {
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(activityId: activityId),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
        ],
      );

      await scrollToActivityDetailKey(
        tester,
        ActivityDetailScreen.photoUnsyncedMessageKey,
      );

      expect(
        find.byKey(ActivityDetailScreen.photoUnsyncedMessageKey),
        findsOneWidget,
      );
      expect(find.text(_unsyncedPhotoGuidanceCopy), findsOneWidget);
      expect(find.byKey(ActivityDetailScreen.photoAddButtonKey), findsNothing);
    });

    testWidgets('shows synced empty state and photo key contract', (
      tester,
    ) async {
      const remoteActivityId = 'remote-photos-2';
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: remoteActivityId,
        ),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          overrideActivityPhotoListProvider(
            remoteActivityId: remoteActivityId,
            photos: const [],
          ),
          overrideActivityPhotoControllerProvider(
            remoteActivityId: remoteActivityId,
            state: const ActivityPhotoControllerState(),
          ),
        ],
      );

      await enterActivityDetailEditMode(tester);
      await scrollToActivityDetailKey(
        tester,
        ActivityDetailScreen.photoSectionKey,
      );

      expect(find.byKey(ActivityDetailScreen.photoSectionKey), findsOneWidget);
      expect(
        find.byKey(ActivityDetailScreen.photoAddButtonKey),
        findsOneWidget,
      );
      expect(
        find.byKey(ActivityDetailScreen.photoEmptyStateKey),
        findsOneWidget,
      );
      expect(find.text(_syncedPhotoEmptyStateCopy), findsOneWidget);
      expect(
        find.byKey(ActivityDetailScreen.photoUnsyncedMessageKey),
        findsNothing,
      );
    });

    testWidgets(
      'keeps photo uploads blocked until the activity sync entry succeeds',
      (tester) async {
        const remoteActivityId = 'remote-photos-pending-sync';
        final detailLoader = CountingActivityDetailLoader(
          buildTestActivityDetailData(
            activityId: activityId,
            remoteId: remoteActivityId,
          ),
        );

        await pumpActivityDetailScreen(
          tester,
          includeDefaultSyncEntryOverride: false,
          overrides: [
            activityDetailProvider(
              activityId,
            ).overrideWith((_) => detailLoader()),
            overrideActivitySyncEntryProvider(
              SyncQueueEntry(
                sessionId: activityId,
                status: SyncQueueEntryStatus.queued,
                retryCount: 0,
                queuedAt: DateTime(2026, 3, 25, 15),
              ),
            ),
          ],
        );

        await scrollToActivityDetailKey(
          tester,
          ActivityDetailScreen.photoUnsyncedMessageKey,
        );

        expect(
          find.byKey(ActivityDetailScreen.photoUnsyncedMessageKey),
          findsOneWidget,
        );
        expect(find.text(_queuedSyncPhotoGuidanceCopy), findsOneWidget);
        expect(
          find.byKey(ActivityDetailScreen.photoAddButtonKey),
          findsNothing,
        );
      },
    );

    testWidgets(
      'shows failed-sync guidance when the activity has not synced successfully',
      (tester) async {
        const remoteActivityId = 'remote-photos-failed-sync';
        final detailLoader = CountingActivityDetailLoader(
          buildTestActivityDetailData(
            activityId: activityId,
            remoteId: remoteActivityId,
          ),
        );

        await pumpActivityDetailScreen(
          tester,
          includeDefaultSyncEntryOverride: false,
          overrides: [
            activityDetailProvider(
              activityId,
            ).overrideWith((_) => detailLoader()),
            overrideActivitySyncEntryProvider(
              SyncQueueEntry(
                sessionId: activityId,
                status: SyncQueueEntryStatus.failed,
                retryCount: 2,
                queuedAt: DateTime(2026, 3, 25, 15),
                lastError: 'hosted insert failed',
              ),
            ),
          ],
        );

        await scrollToActivityDetailKey(
          tester,
          ActivityDetailScreen.photoUnsyncedMessageKey,
        );

        expect(
          find.byKey(ActivityDetailScreen.photoUnsyncedMessageKey),
          findsOneWidget,
        );
        expect(find.text(_failedSyncPhotoGuidanceCopy), findsOneWidget);
        expect(
          find.byKey(ActivityDetailScreen.photoAddButtonKey),
          findsNothing,
        );
      },
    );

    testWidgets(
      'shows processing-sync guidance while the activity is still syncing',
      (tester) async {
        const remoteActivityId = 'remote-photos-processing-sync';
        final detailLoader = CountingActivityDetailLoader(
          buildTestActivityDetailData(
            activityId: activityId,
            remoteId: remoteActivityId,
          ),
        );

        await pumpActivityDetailScreen(
          tester,
          includeDefaultSyncEntryOverride: false,
          overrides: [
            activityDetailProvider(
              activityId,
            ).overrideWith((_) => detailLoader()),
            overrideActivitySyncEntryProvider(
              SyncQueueEntry(
                sessionId: activityId,
                status: SyncQueueEntryStatus.processing,
                retryCount: 0,
                queuedAt: DateTime(2026, 3, 25, 15),
              ),
            ),
          ],
        );

        await scrollToActivityDetailKey(
          tester,
          ActivityDetailScreen.photoUnsyncedMessageKey,
        );

        expect(
          find.byKey(ActivityDetailScreen.photoUnsyncedMessageKey),
          findsOneWidget,
        );
        expect(find.text(_processingSyncPhotoGuidanceCopy), findsOneWidget);
        expect(
          find.byKey(ActivityDetailScreen.photoAddButtonKey),
          findsNothing,
        );
      },
    );

    testWidgets('renders persisted photo thumbnail using stable key helper', (
      tester,
    ) async {
      const remoteActivityId = 'remote-photos-3';
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: remoteActivityId,
        ),
      );
      final photo = buildTestActivityPhoto(
        id: 'photo-3',
        activityId: remoteActivityId,
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          overrideActivityPhotoListProvider(
            remoteActivityId: remoteActivityId,
            photos: [photo],
          ),
          overrideActivityPhotoControllerProvider(
            remoteActivityId: remoteActivityId,
            state: const ActivityPhotoControllerState(),
          ),
        ],
      );

      await scrollToActivityDetailKey(
        tester,
        ActivityDetailScreen.photoThumbnailKey(photo.id),
      );

      expect(
        find.byKey(ActivityDetailScreen.photoThumbnailKey(photo.id)),
        findsOneWidget,
      );
    });
  });

  group('photo upload flow', () {
    testWidgets(
      'tapping add CTA requires one source selection before upload path',
      (
        tester,
      ) async {
        const remoteActivityId = 'remote-photos-upload-1';
        final detailLoader = CountingActivityDetailLoader(
          buildTestActivityDetailData(
            activityId: activityId,
            remoteId: remoteActivityId,
          ),
        );
        final pickerService = RecordingPhotoPickerService(
          pickedPhotos: [
            buildPickedPhoto(fileName: 'first.jpg'),
            buildPickedPhoto(fileName: 'second.jpg'),
          ],
        );
        final photoRepository = RecordingPhotoRepository();

        await pumpActivityDetailScreen(
          tester,
          overrides: [
            activityDetailProvider(
              activityId,
            ).overrideWith((_) => detailLoader()),
            photoPickerServiceProvider.overrideWithValue(pickerService),
            photoRepositoryProvider.overrideWithValue(photoRepository),
          ],
        );

        await openPhotoSourcePicker(tester);
        expect(
          find.byKey(ActivityDetailScreen.photoSourceSheetKey),
          findsOneWidget,
        );
        expect(find.text(_photoSourcePickerTitle), findsOneWidget);
        expect(
          find.byKey(ActivityDetailScreen.photoSourceGalleryOptionKey),
          findsOneWidget,
        );
        expect(
          find.byKey(ActivityDetailScreen.photoSourceCameraOptionKey),
          findsOneWidget,
        );

        await selectPhotoSource(tester, PhotoPickSource.gallery);

        expect(pickerService.pickPhotosCallCount, 1);
        expect(
          pickerService.lastMaxSelection,
          maxActivityPhotosPerActivity,
        );
        expect(pickerService.lastSource, PhotoPickSource.gallery);
        expect(pickerService.lastOfferCrop, true);
        expect(photoRepository.uploadCallCount, 2);
        expect(photoRepository.uploadedFileNames, ['first.jpg', 'second.jpg']);
      },
    );

    testWidgets(
      'gallery upload keeps remaining photos when one crop is canceled upstream',
      (
        tester,
      ) async {
        const remoteActivityId = 'remote-photos-upload-gallery-cancelled-one';
        final detailLoader = CountingActivityDetailLoader(
          buildTestActivityDetailData(
            activityId: activityId,
            remoteId: remoteActivityId,
          ),
        );
        final pickerService = RecordingPhotoPickerService(
          pickedPhotos: [
            buildPickedPhoto(fileName: 'first.jpg'),
            buildPickedPhoto(fileName: 'third.jpg'),
          ],
        );
        final photoRepository = RecordingPhotoRepository();

        await pumpActivityDetailScreen(
          tester,
          overrides: [
            activityDetailProvider(
              activityId,
            ).overrideWith((_) => detailLoader()),
            photoPickerServiceProvider.overrideWithValue(pickerService),
            photoRepositoryProvider.overrideWithValue(photoRepository),
          ],
        );

        await openPhotoSourcePicker(tester);
        await selectPhotoSource(tester, PhotoPickSource.gallery);

        expect(pickerService.pickPhotosCallCount, 1);
        expect(pickerService.lastSource, PhotoPickSource.gallery);
        expect(pickerService.lastOfferCrop, true);
        expect(photoRepository.uploadCallCount, 2);
        expect(photoRepository.uploadedFileNames, ['first.jpg', 'third.jpg']);
        expect(photoRepository.uploadedFileNames.contains('second.jpg'), false);
      },
    );

    testWidgets(
      'camera source selection uses the same upload submission path',
      (
        tester,
      ) async {
        const remoteActivityId = 'remote-photos-upload-camera-shared';
        final detailLoader = CountingActivityDetailLoader(
          buildTestActivityDetailData(
            activityId: activityId,
            remoteId: remoteActivityId,
          ),
        );
        final pickerService = RecordingPhotoPickerService(
          pickedPhotos: [
            buildPickedPhoto(fileName: 'camera.jpg'),
          ],
        );
        final photoRepository = RecordingPhotoRepository();

        await pumpActivityDetailScreen(
          tester,
          overrides: [
            activityDetailProvider(
              activityId,
            ).overrideWith((_) => detailLoader()),
            photoPickerServiceProvider.overrideWithValue(pickerService),
            photoRepositoryProvider.overrideWithValue(photoRepository),
          ],
        );

        await openPhotoSourcePicker(tester);
        await selectPhotoSource(tester, PhotoPickSource.camera);

        expect(pickerService.pickPhotosCallCount, 1);
        expect(
          pickerService.lastMaxSelection,
          maxActivityPhotosPerActivity,
        );
        expect(pickerService.lastSource, PhotoPickSource.camera);
        expect(pickerService.lastOfferCrop, false);
        expect(photoRepository.uploadCallCount, 1);
        expect(photoRepository.uploadedFileNames, ['camera.jpg']);
      },
    );

    testWidgets(
      'camera cancel keeps the shared flow and skips upload submission',
      (
        tester,
      ) async {
        const remoteActivityId = 'remote-photos-upload-camera-cancel';
        final detailLoader = CountingActivityDetailLoader(
          buildTestActivityDetailData(
            activityId: activityId,
            remoteId: remoteActivityId,
          ),
        );
        final pickerService = RecordingPhotoPickerService(
          pickedPhotosBySource: {
            PhotoPickSource.gallery: [
              buildPickedPhoto(fileName: 'gallery.jpg'),
            ],
            PhotoPickSource.camera: const [],
          },
        );
        final photoRepository = RecordingPhotoRepository();

        await pumpActivityDetailScreen(
          tester,
          overrides: [
            activityDetailProvider(
              activityId,
            ).overrideWith((_) => detailLoader()),
            photoPickerServiceProvider.overrideWithValue(pickerService),
            photoRepositoryProvider.overrideWithValue(photoRepository),
          ],
        );

        await openPhotoSourcePicker(tester);
        await selectPhotoSource(tester, PhotoPickSource.camera);

        expect(pickerService.pickPhotosCallCount, 1);
        expect(pickerService.lastSource, PhotoPickSource.camera);
        expect(photoRepository.uploadCallCount, 0);
      },
    );

    testWidgets('camera picker errors show snackbar without uploading', (
      tester,
    ) async {
      const remoteActivityId = 'remote-photos-upload-camera-error';
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: remoteActivityId,
        ),
      );
      final pickerService = RecordingPhotoPickerService(
        pickPhotosErrorBySource: {
          PhotoPickSource.camera: StateError('camera failed'),
        },
      );
      final photoRepository = RecordingPhotoRepository();

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          photoPickerServiceProvider.overrideWithValue(pickerService),
          photoRepositoryProvider.overrideWithValue(photoRepository),
        ],
      );

      await openPhotoSourcePicker(tester);
      await selectPhotoSource(tester, PhotoPickSource.camera);

      expect(
        find.text('Unable to add photos right now. Please try again.'),
        findsOneWidget,
      );
      expect(pickerService.pickPhotosCallCount, 1);
      expect(pickerService.lastSource, PhotoPickSource.camera);
      expect(photoRepository.uploadCallCount, 0);
    });

    testWidgets('shows snackbar when adding photos throws', (tester) async {
      const remoteActivityId = 'remote-photos-upload-throws';
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: remoteActivityId,
        ),
      );
      final pickerService = RecordingPhotoPickerService(
        pickPhotosError: StateError('picker failed'),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          photoPickerServiceProvider.overrideWithValue(pickerService),
        ],
      );

      await openPhotoSourcePicker(tester);
      await selectPhotoSource(tester, PhotoPickSource.gallery);

      expect(
        find.text('Unable to add photos right now. Please try again.'),
        findsOneWidget,
      );
      expect(pickerService.pickPhotosCallCount, 1);
      expect(pickerService.lastSource, PhotoPickSource.gallery);
    });

    testWidgets('renders pending upload mutation state with stable keys', (
      tester,
    ) async {
      const remoteActivityId = 'remote-photos-upload-2';
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: remoteActivityId,
        ),
      );
      const uploadMutationId = 'pending-upload-1';

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          overrideActivityPhotoListProvider(
            remoteActivityId: remoteActivityId,
            photos: const [],
          ),
          overrideActivityPhotoControllerProvider(
            remoteActivityId: remoteActivityId,
            state: const ActivityPhotoControllerState(
              uploadMutationsByLocalId: {
                uploadMutationId: PhotoMutation(
                  status: PhotoMutationStatus.pending,
                ),
              },
            ),
          ),
        ],
        settle: false,
      );

      await scrollToActivityDetailKey(
        tester,
        ActivityDetailScreen.photoUploadMutationTileKey(uploadMutationId),
        settleAfterDrag: false,
      );

      expect(
        find.byKey(
          ActivityDetailScreen.photoUploadMutationTileKey(uploadMutationId),
        ),
        findsOneWidget,
      );
      expect(find.text('Uploading photo...'), findsOneWidget);
    });

    testWidgets('renders failed upload state and 20-photo cap messaging', (
      tester,
    ) async {
      const remoteActivityId = 'remote-photos-upload-3';
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: remoteActivityId,
        ),
      );
      const uploadMutationId = 'failed-upload-1';

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          overrideActivityPhotoListProvider(
            remoteActivityId: remoteActivityId,
            photos: const [],
          ),
          overrideActivityPhotoControllerProvider(
            remoteActivityId: remoteActivityId,
            state: const ActivityPhotoControllerState(
              uploadMutationsByLocalId: {
                uploadMutationId: PhotoMutation(
                  status: PhotoMutationStatus.failed,
                  errorMessage: activityPhotoLimitReachedMessage,
                ),
              },
            ),
          ),
        ],
      );

      await scrollToActivityDetailKey(
        tester,
        ActivityDetailScreen.photoUploadMutationErrorKey(uploadMutationId),
      );

      expect(
        find.byKey(
          ActivityDetailScreen.photoUploadMutationTileKey(uploadMutationId),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ActivityDetailScreen.photoUploadMutationErrorKey(uploadMutationId),
        ),
        findsOneWidget,
      );
      expect(find.text(activityPhotoLimitReachedMessage), findsOneWidget);
    });
  });

  group('photo viewer and delete flow', () {
    testWidgets('tapping persisted thumbnail opens full-screen viewer', (
      tester,
    ) async {
      const remoteActivityId = 'remote-photos-viewer-1';
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: remoteActivityId,
        ),
      );
      final photo = buildTestActivityPhoto(
        id: 'photo-viewer-1',
        activityId: remoteActivityId,
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          overrideActivityPhotoListProvider(
            remoteActivityId: remoteActivityId,
            photos: [photo],
          ),
          overrideActivityPhotoControllerProvider(
            remoteActivityId: remoteActivityId,
            state: const ActivityPhotoControllerState(),
          ),
        ],
      );

      await enterActivityDetailEditMode(tester);
      final thumbnailFinder = find.byKey(
        ActivityDetailScreen.photoThumbnailKey(photo.id),
      );
      await scrollToActivityDetailKey(
        tester,
        ActivityDetailScreen.photoThumbnailKey(photo.id),
      );
      await tester.tap(thumbnailFinder);
      await tester.pumpAndSettle();

      expect(find.byKey(ActivityDetailScreen.photoViewerKey), findsOneWidget);
      expect(
        find.byKey(ActivityDetailScreen.photoViewerImageKey(photo.id)),
        findsOneWidget,
      );
      expect(
        find.byKey(ActivityDetailScreen.photoViewerDeleteButtonKey),
        findsOneWidget,
      );
      expect(
        find.byKey(ActivityDetailScreen.photoViewerShareButtonKey),
        findsOneWidget,
      );
    });

    testWidgets('viewer renders safely when signed URLs are missing', (
      tester,
    ) async {
      const remoteActivityId = 'remote-photos-viewer-2';
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: remoteActivityId,
        ),
      );
      final photo = buildTestActivityPhoto(
        id: 'photo-viewer-2',
        activityId: remoteActivityId,
        signedThumbnailUrl: null,
        signedStorageUrl: null,
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          overrideActivityPhotoListProvider(
            remoteActivityId: remoteActivityId,
            photos: [photo],
          ),
          overrideActivityPhotoControllerProvider(
            remoteActivityId: remoteActivityId,
            state: const ActivityPhotoControllerState(),
          ),
        ],
      );

      final thumbnailFinder = find.byKey(
        ActivityDetailScreen.photoThumbnailKey(photo.id),
      );
      await scrollToActivityDetailKey(
        tester,
        ActivityDetailScreen.photoThumbnailKey(photo.id),
      );
      await tester.tap(thumbnailFinder);
      await tester.pumpAndSettle();

      expect(find.byKey(ActivityDetailScreen.photoViewerKey), findsOneWidget);
      expect(
        find.byKey(ActivityDetailScreen.photoViewerUnavailableKey),
        findsOneWidget,
      );
      expect(
        find.byKey(ActivityDetailScreen.photoViewerShareButtonKey),
        findsNothing,
      );
      expect(
        find.text('Photo preview is unavailable right now.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'share action stays hidden when only thumbnail fallback URL exists',
      (tester) async {
        const remoteActivityId = 'remote-photos-viewer-thumbnail-only';
        final detailLoader = CountingActivityDetailLoader(
          buildTestActivityDetailData(
            activityId: activityId,
            remoteId: remoteActivityId,
          ),
        );
        final photo = buildTestActivityPhoto(
          id: 'photo-viewer-thumbnail-only',
          activityId: remoteActivityId,
          signedThumbnailUrl: 'https://example.com/thumb-only.jpg',
          signedStorageUrl: null,
        );

        await pumpActivityDetailScreen(
          tester,
          overrides: [
            activityDetailProvider(
              activityId,
            ).overrideWith((_) => detailLoader()),
            overrideActivityPhotoListProvider(
              remoteActivityId: remoteActivityId,
              photos: [photo],
            ),
            overrideActivityPhotoControllerProvider(
              remoteActivityId: remoteActivityId,
              state: const ActivityPhotoControllerState(),
            ),
          ],
        );

        final thumbnailFinder = find.byKey(
          ActivityDetailScreen.photoThumbnailKey(photo.id),
        );
        await scrollToActivityDetailKey(
          tester,
          ActivityDetailScreen.photoThumbnailKey(photo.id),
        );
        await tester.tap(thumbnailFinder);
        await tester.pumpAndSettle();

        expect(find.byKey(ActivityDetailScreen.photoViewerKey), findsOneWidget);
        expect(
          find.byKey(ActivityDetailScreen.photoViewerShareButtonKey),
          findsNothing,
        );
      },
    );

    testWidgets('share action shows loading and blocks repeat taps in flight', (
      tester,
    ) async {
      const remoteActivityId = 'remote-photos-viewer-share-loading';
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: remoteActivityId,
        ),
      );
      final photo = buildTestActivityPhoto(
        id: 'photo-share-loading',
        activityId: remoteActivityId,
      );
      final shareCompleter = Completer<void>();
      final shareHelper = RecordingActivityPhotoViewerShareHelper(
        completer: shareCompleter,
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          overrideActivityPhotoListProvider(
            remoteActivityId: remoteActivityId,
            photos: [photo],
          ),
          overrideActivityPhotoControllerProvider(
            remoteActivityId: remoteActivityId,
            state: const ActivityPhotoControllerState(),
          ),
          overrideActivityPhotoViewerShareHelperProvider(shareHelper),
        ],
      );

      final thumbnailFinder = find.byKey(
        ActivityDetailScreen.photoThumbnailKey(photo.id),
      );
      await scrollToActivityDetailKey(
        tester,
        ActivityDetailScreen.photoThumbnailKey(photo.id),
      );
      await tester.tap(thumbnailFinder);
      await tester.pumpAndSettle();

      final shareButtonFinder = find.byKey(
        ActivityDetailScreen.photoViewerShareButtonKey,
      );
      await tester.tap(shareButtonFinder);
      await tester.pump();

      expect(shareHelper.callCount, 1);
      expect(
        find.byKey(ActivityDetailScreen.photoViewerShareLoadingKey),
        findsOneWidget,
      );

      await tester.tap(shareButtonFinder);
      await tester.pump();
      expect(shareHelper.callCount, 1);

      shareCompleter.complete();
      await tester.pumpAndSettle();

      expect(
        find.byKey(ActivityDetailScreen.photoViewerShareLoadingKey),
        findsNothing,
      );
    });

    testWidgets(
      'successful share passes resolved URL and deterministic label',
      (
        tester,
      ) async {
        const remoteActivityId = 'remote-photos-viewer-share-success';
        final detailLoader = CountingActivityDetailLoader(
          buildTestActivityDetailData(
            activityId: activityId,
            remoteId: remoteActivityId,
          ),
        );
        final photo = buildTestActivityPhoto(
          id: 'photo-share-success',
          activityId: remoteActivityId,
        );
        final shareHelper = RecordingActivityPhotoViewerShareHelper();

        await pumpActivityDetailScreen(
          tester,
          overrides: [
            activityDetailProvider(
              activityId,
            ).overrideWith((_) => detailLoader()),
            overrideActivityPhotoListProvider(
              remoteActivityId: remoteActivityId,
              photos: [photo],
            ),
            overrideActivityPhotoControllerProvider(
              remoteActivityId: remoteActivityId,
              state: const ActivityPhotoControllerState(),
            ),
            overrideActivityPhotoViewerShareHelperProvider(shareHelper),
          ],
        );

        final thumbnailFinder = find.byKey(
          ActivityDetailScreen.photoThumbnailKey(photo.id),
        );
        await scrollToActivityDetailKey(
          tester,
          ActivityDetailScreen.photoThumbnailKey(photo.id),
        );
        await tester.tap(thumbnailFinder);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(ActivityDetailScreen.photoViewerShareButtonKey),
        );
        await tester.pumpAndSettle();

        expect(shareHelper.callCount, 1);
        expect(
          shareHelper.lastResolvedViewerPhotoUrl,
          'https://example.com/full.jpg',
        );
        expect(shareHelper.lastFileLabel, 'photo-share-success.jpg');
      },
    );

    testWidgets('share failures surface snackbar copy', (tester) async {
      const remoteActivityId = 'remote-photos-viewer-share-failure';
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: remoteActivityId,
        ),
      );
      final photo = buildTestActivityPhoto(
        id: 'photo-share-failure',
        activityId: remoteActivityId,
      );
      final shareHelper = RecordingActivityPhotoViewerShareHelper(
        error: StateError('share failed'),
      );

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          overrideActivityPhotoListProvider(
            remoteActivityId: remoteActivityId,
            photos: [photo],
          ),
          overrideActivityPhotoControllerProvider(
            remoteActivityId: remoteActivityId,
            state: const ActivityPhotoControllerState(),
          ),
          overrideActivityPhotoViewerShareHelperProvider(shareHelper),
        ],
      );

      final thumbnailFinder = find.byKey(
        ActivityDetailScreen.photoThumbnailKey(photo.id),
      );
      await scrollToActivityDetailKey(
        tester,
        ActivityDetailScreen.photoThumbnailKey(photo.id),
      );
      await tester.tap(thumbnailFinder);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(ActivityDetailScreen.photoViewerShareButtonKey),
      );
      await tester.pumpAndSettle();

      expect(shareHelper.callCount, 1);
      expect(find.text(_photoShareFailureCopy), findsOneWidget);
    });

    testWidgets('successful delete closes viewer and removes thumbnail', (
      tester,
    ) async {
      const remoteActivityId = 'remote-photos-viewer-delete-success';
      final detailLoader = CountingActivityDetailLoader(
        buildTestActivityDetailData(
          activityId: activityId,
          remoteId: remoteActivityId,
        ),
      );
      final photo = buildTestActivityPhoto(
        id: 'photo-delete-success',
        activityId: remoteActivityId,
      );
      final photoRepository = RecordingPhotoRepository()
        ..photosToReturn = [photo];

      await pumpActivityDetailScreen(
        tester,
        overrides: [
          activityDetailProvider(
            activityId,
          ).overrideWith((_) => detailLoader()),
          photoRepositoryProvider.overrideWithValue(photoRepository),
        ],
      );

      await enterActivityDetailEditMode(tester);
      final thumbnailFinder = find.byKey(
        ActivityDetailScreen.photoThumbnailKey(photo.id),
      );
      await scrollToActivityDetailKey(
        tester,
        ActivityDetailScreen.photoThumbnailKey(photo.id),
      );
      await tester.tap(thumbnailFinder);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(ActivityDetailScreen.photoViewerDeleteButtonKey),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ActivityDetailScreen.photoDeleteConfirmKey));
      await tester.pumpAndSettle();

      expect(photoRepository.deleteCallCount, 1);
      expect(find.byKey(ActivityDetailScreen.photoViewerKey), findsNothing);
      expect(thumbnailFinder, findsNothing);
      expect(
        find.byKey(ActivityDetailScreen.photoEmptyStateKey),
        findsOneWidget,
      );
    });

    testWidgets(
      'delete confirmation surfaces recoverable failures and keeps photo visible',
      (tester) async {
        const remoteActivityId = 'remote-photos-viewer-3';
        final detailLoader = CountingActivityDetailLoader(
          buildTestActivityDetailData(
            activityId: activityId,
            remoteId: remoteActivityId,
          ),
        );
        final photo = buildTestActivityPhoto(
          id: 'photo-viewer-3',
          activityId: remoteActivityId,
        );
        final photoRepository = RecordingPhotoRepository()
          ..photosToReturn = [photo]
          ..deleteErrorsByPhotoId[photo.id] = StateError('delete failed');

        await pumpActivityDetailScreen(
          tester,
          overrides: [
            activityDetailProvider(
              activityId,
            ).overrideWith((_) => detailLoader()),
            photoRepositoryProvider.overrideWithValue(photoRepository),
          ],
        );

        await enterActivityDetailEditMode(tester);
        final thumbnailFinder = find.byKey(
          ActivityDetailScreen.photoThumbnailKey(photo.id),
        );
        await scrollToActivityDetailKey(
          tester,
          ActivityDetailScreen.photoThumbnailKey(photo.id),
        );
        await tester.tap(thumbnailFinder);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(ActivityDetailScreen.photoViewerDeleteButtonKey),
        );
        await tester.pumpAndSettle();

        expect(find.text('Delete photo?'), findsOneWidget);
        await tester.tap(
          find.byKey(ActivityDetailScreen.photoDeleteConfirmKey),
        );
        await tester.pumpAndSettle();

        expect(photoRepository.deleteCallCount, 1);

        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          thumbnailFinder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(thumbnailFinder, findsOneWidget);
        expect(
          find.byKey(
            ActivityDetailScreen.photoDeleteMutationErrorKey(photo.id),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('delete failed'), findsOneWidget);
      },
    );
  });

  group('photo map markers', () {
    testWidgets(
      'marker candidates come only from synced photos with coordinates',
      (tester) async {
        const remoteActivityId = 'remote-markers-1';
        final geoPhoto = buildTestActivityPhoto(
          id: 'geo-1',
          activityId: remoteActivityId,
          sortOrder: 0,
          latitude: 40.7128,
          longitude: -74.0060,
        );
        final noGeoPhoto = buildTestActivityPhoto(
          id: 'no-geo-1',
          activityId: remoteActivityId,
          sortOrder: 1,
        );

        await pumpActivityDetailScreen(
          tester,
          overrides: [
            activityDetailProvider(activityId).overrideWith(
              (_) async => buildTestActivityDetailData(
                activityId: activityId,
                remoteId: remoteActivityId,
              ),
            ),
            overrideActivityPhotoListProvider(
              remoteActivityId: remoteActivityId,
              photos: [geoPhoto, noGeoPhoto],
            ),
            overrideActivityPhotoControllerProvider(
              remoteActivityId: remoteActivityId,
              state: const ActivityPhotoControllerState(),
            ),
          ],
        );

        final mapView = tester.widget<MapView>(find.byType(MapView));
        expect(mapView.photoMarkers.length, 1);
        expect(mapView.photoMarkers.first.latitude, 40.7128);
        expect(mapView.photoMarkers.first.longitude, -74.0060);
        expect(mapView.photoMarkers.first.photoId, 'geo-1');
      },
    );

    testWidgets(
      'coordinate-less photos never surface through marker inputs',
      (tester) async {
        const remoteActivityId = 'remote-markers-2';
        final noGeoPhoto1 = buildTestActivityPhoto(
          id: 'no-geo-a',
          activityId: remoteActivityId,
          sortOrder: 0,
        );
        final noGeoPhoto2 = buildTestActivityPhoto(
          id: 'no-geo-b',
          activityId: remoteActivityId,
          sortOrder: 1,
          latitude: 40.7128,
          // longitude is null — still not map-eligible
        );

        await pumpActivityDetailScreen(
          tester,
          overrides: [
            activityDetailProvider(activityId).overrideWith(
              (_) async => buildTestActivityDetailData(
                activityId: activityId,
                remoteId: remoteActivityId,
              ),
            ),
            overrideActivityPhotoListProvider(
              remoteActivityId: remoteActivityId,
              photos: [noGeoPhoto1, noGeoPhoto2],
            ),
            overrideActivityPhotoControllerProvider(
              remoteActivityId: remoteActivityId,
              state: const ActivityPhotoControllerState(),
            ),
          ],
        );

        final mapView = tester.widget<MapView>(find.byType(MapView));
        expect(mapView.photoMarkers, isEmpty);
      },
    );

    testWidgets(
      'unsynced activity passes no photo markers to MapView',
      (tester) async {
        await pumpActivityDetailScreen(
          tester,
          overrides: [
            activityDetailProvider(activityId).overrideWith(
              (_) async => buildTestActivityDetailData(
                activityId: activityId,
                // No remoteId means unsynced
              ),
            ),
          ],
        );

        final mapView = tester.widget<MapView>(find.byType(MapView));
        expect(mapView.photoMarkers, isEmpty);
      },
    );

    testWidgets(
      'synced activity wires onPhotoMarkerTapped callback to MapView',
      (tester) async {
        const remoteActivityId = 'remote-markers-tap';
        final geoPhoto = buildTestActivityPhoto(
          id: 'tap-1',
          activityId: remoteActivityId,
          sortOrder: 0,
          latitude: 40.7128,
          longitude: -74.0060,
        );

        await pumpActivityDetailScreen(
          tester,
          overrides: [
            activityDetailProvider(activityId).overrideWith(
              (_) async => buildTestActivityDetailData(
                activityId: activityId,
                remoteId: remoteActivityId,
              ),
            ),
            overrideActivityPhotoListProvider(
              remoteActivityId: remoteActivityId,
              photos: [geoPhoto],
            ),
            overrideActivityPhotoControllerProvider(
              remoteActivityId: remoteActivityId,
              state: const ActivityPhotoControllerState(),
            ),
          ],
        );

        final mapView = tester.widget<MapView>(find.byType(MapView));
        mapView.onPhotoMarkerTapped!.call(geoPhoto.id);
        await tester.pumpAndSettle();

        expect(find.byKey(ActivityDetailScreen.photoViewerKey), findsOneWidget);
      },
    );

    testWidgets(
      'marker tap opens viewer from the rendered marker photo list even if the '
      'photo provider is invalidated before tap handling',
      (tester) async {
        const remoteActivityId = 'remote-markers-tap-invalidated';
        final geoPhoto = buildTestActivityPhoto(
          id: 'tap-invalidated-1',
          activityId: remoteActivityId,
          sortOrder: 0,
          latitude: 40.7128,
          longitude: -74.0060,
        );
        var currentPhotos = <ActivityPhoto>[geoPhoto];

        await pumpActivityDetailScreen(
          tester,
          overrides: [
            activityDetailProvider(activityId).overrideWith(
              (_) async => buildTestActivityDetailData(
                activityId: activityId,
                remoteId: remoteActivityId,
              ),
            ),
            activityPhotoListProvider(remoteActivityId).overrideWith(
              (_) async => currentPhotos,
            ),
            overrideActivityPhotoControllerProvider(
              remoteActivityId: remoteActivityId,
              state: const ActivityPhotoControllerState(),
            ),
          ],
        );

        final mapView = tester.widget<MapView>(find.byType(MapView));
        final onPhotoMarkerTapped = mapView.onPhotoMarkerTapped;
        if (onPhotoMarkerTapped == null) {
          fail('Expected onPhotoMarkerTapped to be wired for synced activity.');
        }

        final container = ProviderScope.containerOf(
          tester.element(find.byType(ActivityDetailScreen)),
        );
        currentPhotos = const <ActivityPhoto>[];
        container.invalidate(activityPhotoListProvider(remoteActivityId));
        await container.read(
          activityPhotoListProvider(remoteActivityId).future,
        );

        onPhotoMarkerTapped.call(geoPhoto.id);
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.byKey(ActivityDetailScreen.photoViewerKey), findsOneWidget);
      },
    );

    testWidgets(
      'unsynced activity does not wire onPhotoMarkerTapped to MapView',
      (tester) async {
        await pumpActivityDetailScreen(
          tester,
          overrides: [
            activityDetailProvider(activityId).overrideWith(
              (_) async => buildTestActivityDetailData(
                activityId: activityId,
              ),
            ),
          ],
        );

        final mapView = tester.widget<MapView>(find.byType(MapView));
        expect(mapView.onPhotoMarkerTapped, isNull);
      },
    );

    testWidgets(
      'rebuilding detail flow for a different synced activity clears stale '
      'marker candidates instead of reusing prior photo state',
      (tester) async {
        const remoteActivityIdA = 'remote-iso-a';
        const remoteActivityIdB = 'remote-iso-b';

        final photoA = buildTestActivityPhoto(
          id: 'photo-a',
          activityId: remoteActivityIdA,
          sortOrder: 0,
          latitude: 10.0,
          longitude: 20.0,
        );
        final photoB = buildTestActivityPhoto(
          id: 'photo-b',
          activityId: remoteActivityIdB,
          sortOrder: 0,
          latitude: 30.0,
          longitude: 40.0,
        );

        // Start with activity A. Both photo lists are present in the scope
        // but only the one matching the detail's remoteId should surface.
        var currentRemoteId = remoteActivityIdA;

        await pumpActivityDetailScreen(
          tester,
          overrides: [
            activityDetailProvider(activityId).overrideWith(
              (_) async => buildTestActivityDetailData(
                activityId: activityId,
                remoteId: currentRemoteId,
              ),
            ),
            overrideActivityPhotoListProvider(
              remoteActivityId: remoteActivityIdA,
              photos: [photoA],
            ),
            overrideActivityPhotoListProvider(
              remoteActivityId: remoteActivityIdB,
              photos: [photoB],
            ),
            overrideActivityPhotoControllerProvider(
              remoteActivityId: remoteActivityIdA,
              state: const ActivityPhotoControllerState(),
            ),
            overrideActivityPhotoControllerProvider(
              remoteActivityId: remoteActivityIdB,
              state: const ActivityPhotoControllerState(),
            ),
          ],
        );

        final mapViewA = tester.widget<MapView>(find.byType(MapView));
        expect(mapViewA.photoMarkers.length, 1);
        expect(mapViewA.photoMarkers.first.photoId, 'photo-a');
        expect(mapViewA.photoMarkers.first.latitude, 10.0);

        // Switch to activity B by invalidating the detail provider.
        currentRemoteId = remoteActivityIdB;
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ActivityDetailScreen)),
        );
        container.invalidate(activityDetailProvider(activityId));
        await tester.pumpAndSettle();

        final mapViewB = tester.widget<MapView>(find.byType(MapView));
        expect(mapViewB.photoMarkers.length, 1);
        expect(mapViewB.photoMarkers.first.photoId, 'photo-b');
        expect(mapViewB.photoMarkers.first.latitude, 30.0);
      },
    );
  });
}

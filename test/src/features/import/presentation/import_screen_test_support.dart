import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';
import 'package:uff/src/features/import/application/import_pipeline.dart';
import 'package:uff/src/features/import/data/strava_zip_importer.dart';
import 'package:uff/src/features/import/domain/zip_import_result.dart';
import 'package:uff/src/features/import/presentation/import_screen.dart';

import '../../../test_helpers/saved_activities_probe.dart';

class MockImportPipeline extends Mock implements ImportPipeline {}

class MockStravaZipImporter extends Mock implements StravaZipImporter {}

/// NOTE(stuart): Document TestFilePicker.
class TestFilePicker extends FilePicker {
  TestFilePicker({this.result});

  FilePickerResult? result;
  PickFilesCall? lastPickFilesCall;
  int pickFilesCallCount = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    pickFilesCallCount += 1;
    lastPickFilesCall = PickFilesCall(
      type: type,
      allowedExtensions: allowedExtensions,
      withData: withData,
    );
    return result;
  }
}

class PickFilesCall {
  const PickFilesCall({
    required this.type,
    required this.allowedExtensions,
    required this.withData,
  });

  final FileType type;
  final List<String>? allowedExtensions;
  final bool withData;
}

TrackingSessionRecord buildImportScreenSessionRecord({required int id}) {
  return TrackingSessionRecord(
    id: id,
    status: TrackingSessionStatus.saved,
    createdAt: DateTime(2024, 1, 1, 12),
    updatedAt: DateTime(2024, 1, 1, 12),
    sportType: 'ride',
    distanceMeters: 5000,
    movingTimeSeconds: 1800,
  );
}

Future<void> pumpImportScreen(
  WidgetTester tester, {
  required List<dynamic> overrides,
  bool includeSavedActivitiesProbe = false,
  ThemeData? theme,
  ThemeData? darkTheme,
  ThemeMode? themeMode,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: theme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        home: includeSavedActivitiesProbe
            ? const Stack(
                children: [
                  ImportScreen(),
                  SavedActivitiesProbe(),
                ],
              )
            : const ImportScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpZipImportScreen(
  WidgetTester tester, {
  required MockStravaZipImporter zipImporter,
  ImportPipeline? pipeline,
  List<dynamic> overrides = const [],
  bool includeSavedActivitiesProbe = false,
}) async {
  await pumpImportScreen(
    tester,
    overrides: [
      importPipelineProvider.overrideWithValue(
        pipeline ?? MockImportPipeline(),
      ),
      stravaZipImporterProvider.overrideWithValue(zipImporter),
      ...overrides,
    ],
    includeSavedActivitiesProbe: includeSavedActivitiesProbe,
  );
}

Future<void> tapPickFileButton(
  WidgetTester tester, {
  bool settle = true,
  Duration? pumpFor,
}) async {
  await tester.tap(find.byKey(ImportScreen.pickFileButtonKey));
  await tester.pump();
  if (pumpFor != null) {
    await tester.pump(pumpFor);
  }
  if (settle) {
    await tester.pumpAndSettle();
  }
}

void stubZipImportResult(
  MockStravaZipImporter zipImporter,
  ZipImportResult result,
) {
  when(
    () => zipImporter.importZip(
      any(),
      onProgress: any(named: 'onProgress'),
    ),
  ).thenAnswer((_) async => result);
}

void stubZipImportError(
  MockStravaZipImporter zipImporter,
  Object error,
) {
  when(
    () => zipImporter.importZip(
      any(),
      onProgress: any(named: 'onProgress'),
    ),
  ).thenThrow(error);
}

TestFilePicker setSinglePickedFile({
  required String name,
  required Uint8List? bytes,
}) {
  final filePicker = TestFilePicker(
    result: FilePickerResult([
      PlatformFile(
        name: name,
        size: bytes?.length ?? 0,
        bytes: bytes,
      ),
    ]),
  );
  FilePicker.platform = filePicker;
  return filePicker;
}

TestFilePicker setPickedImportFile({
  required String name,
  required List<int>? bytes,
}) {
  return setSinglePickedFile(
    name: name,
    bytes: bytes == null ? null : Uint8List.fromList(bytes),
  );
}

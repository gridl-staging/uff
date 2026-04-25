import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uff/src/features/photos/data/photo_crop_service.dart';

/// ## Test Scenarios
/// - [positive] `cropPhoto` passes free-form crop settings and 2048px max size.
/// - [negative] `cropPhoto` returns null when the user cancels crop.
/// - [isolation] `cropPhoto` returns a new file handle for the cropper output path.
class RecordingImageCropper extends ImageCropper {
  String? lastSourcePath;
  int? lastMaxWidth;
  int? lastMaxHeight;
  List<PlatformUiSettings>? lastUiSettings;
  CroppedFile? nextResult;

  @override
  Future<CroppedFile?> cropImage({
    required String sourcePath,
    int? maxWidth,
    int? maxHeight,
    CropAspectRatio? aspectRatio,
    ImageCompressFormat compressFormat = ImageCompressFormat.jpg,
    int compressQuality = 90,
    List<PlatformUiSettings>? uiSettings,
  }) async {
    lastSourcePath = sourcePath;
    lastMaxWidth = maxWidth;
    lastMaxHeight = maxHeight;
    lastUiSettings = uiSettings;
    return nextResult;
  }
}

void main() {
  late RecordingImageCropper cropper;
  late PhotoCropService service;
  late Directory tempDirectory;

  setUp(() {
    cropper = RecordingImageCropper();
    service = PhotoCropService(imageCropper: cropper);
    tempDirectory = Directory.systemTemp.createTempSync('photo_crop_service_');
  });

  tearDown(() {
    if (tempDirectory.existsSync()) {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test(
    'cropPhoto passes free-form crop settings and 2048px max output',
    () async {
      final sourceFile = File('${tempDirectory.path}/source.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final croppedFile = File('${tempDirectory.path}/cropped.jpg')
        ..writeAsBytesSync([9, 9, 9]);
      cropper.nextResult = CroppedFile(croppedFile.path);

      final result = await service.cropPhoto(XFile(sourceFile.path));

      expect(result?.path, croppedFile.path);
      expect(result?.name, 'cropped.jpg');
      expect(cropper.lastSourcePath, sourceFile.path);
      expect(cropper.lastMaxWidth, 2048);
      expect(cropper.lastMaxHeight, 2048);
      final uiSettings = cropper.lastUiSettings!;
      final androidSettings = uiSettings.whereType<AndroidUiSettings>().single;
      final iosSettings = uiSettings.whereType<IOSUiSettings>().single;
      expect(androidSettings.lockAspectRatio, false);
      expect(iosSettings.aspectRatioLockEnabled, false);
    },
  );

  test('cropPhoto returns null when the user cancels crop', () async {
    final sourceFile = File('${tempDirectory.path}/source.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    cropper.nextResult = null;

    final result = await service.cropPhoto(XFile(sourceFile.path));

    expect(result, isNull);
  });
}

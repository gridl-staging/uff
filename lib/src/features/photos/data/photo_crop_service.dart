import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

const int _maxCroppedPhotoDimension = 2048;

/// Centralized wrapper around ImageCropper so the picker pipeline has one
/// place that defines crop behavior and output size policy.
class PhotoCropService {
  PhotoCropService({ImageCropper? imageCropper})
    : _imageCropper = imageCropper ?? ImageCropper();

  final ImageCropper _imageCropper;

  Future<XFile?> cropPhoto(XFile photoFile) async {
    final croppedFile = await _imageCropper.cropImage(
      sourcePath: photoFile.path,
      maxWidth: _maxCroppedPhotoDimension,
      maxHeight: _maxCroppedPhotoDimension,
      uiSettings: [
        AndroidUiSettings(lockAspectRatio: false),
        // ignore: avoid_redundant_argument_values, reason: keep free-form policy explicit for iOS cropper config contract tests
        IOSUiSettings(aspectRatioLockEnabled: false),
      ],
    );
    if (croppedFile == null) {
      return null;
    }
    return XFile(croppedFile.path);
  }
}

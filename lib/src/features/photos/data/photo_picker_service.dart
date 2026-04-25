import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:uff/src/features/photos/data/photo_crop_service.dart';

@immutable
class PickedPhoto {
  const PickedPhoto({
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;
}

enum PhotoPickSource {
  gallery,
  camera,
}

class PhotoPickerService {
  const PhotoPickerService();

  Future<List<PickedPhoto>> pickPhotos({
    required PhotoPickSource source,
    int maxSelection = 20,
    bool offerCrop = false,
  }) {
    throw UnimplementedError(
      'PhotoPickerService.pickPhotos must be overridden by a concrete service.',
    );
  }
}

/// TODO: Document ImagePickerPhotoPickerService.
class ImagePickerPhotoPickerService extends PhotoPickerService {
  ImagePickerPhotoPickerService({
    ImagePicker? imagePicker,
    PhotoCropService? photoCropService,
  }) : _imagePicker = imagePicker ?? ImagePicker(),
       _photoCropService = photoCropService ?? PhotoCropService();

  final ImagePicker _imagePicker;
  final PhotoCropService _photoCropService;

  @override
  Future<List<PickedPhoto>> pickPhotos({
    required PhotoPickSource source,
    int maxSelection = 20,
    bool offerCrop = false,
  }) async {
    if (maxSelection <= 0) {
      return const <PickedPhoto>[];
    }

    final pickedFiles = await _pickFiles(source);
    if (pickedFiles.isEmpty) {
      return const <PickedPhoto>[];
    }

    final selectedFiles = pickedFiles.take(maxSelection);
    final photos = <PickedPhoto>[];
    for (final file in selectedFiles) {
      final selectedFile = await _resolveSelectedFile(
        file,
        offerCrop: offerCrop,
      );
      if (selectedFile == null) {
        continue;
      }
      photos.add(
        PickedPhoto(
          fileName: _resolvedPickedPhotoFileName(
            originalFile: file,
            selectedFile: selectedFile,
          ),
          bytes: await selectedFile.readAsBytes(),
        ),
      );
    }

    return photos;
  }

  Future<XFile?> _resolveSelectedFile(
    XFile pickedFile, {
    required bool offerCrop,
  }) async {
    if (!offerCrop) {
      return pickedFile;
    }
    try {
      final croppedFile = await _photoCropService.cropPhoto(pickedFile);
      if (croppedFile == null) {
        // User canceled crop for this photo only.
        return null;
      }
      return croppedFile;
    } on Object {
      // Crop errors should not block upload. Use original bytes as fallback.
      return pickedFile;
    }
  }

  Future<List<XFile>> _pickFiles(PhotoPickSource source) async {
    switch (source) {
      case PhotoPickSource.gallery:
        return _imagePicker.pickMultiImage();
      case PhotoPickSource.camera:
        final pickedCameraFile = await _imagePicker.pickImage(
          source: ImageSource.camera,
        );
        if (pickedCameraFile == null) {
          return const <XFile>[];
        }
        return <XFile>[pickedCameraFile];
    }
  }

  String _resolvedPickedPhotoFileName({
    required XFile originalFile,
    required XFile selectedFile,
  }) {
    final originalName = _resolvedXFileName(originalFile);
    final selectedName = _resolvedXFileName(selectedFile);
    final selectedExtension = path.extension(selectedName);
    if (selectedExtension.isEmpty) {
      return originalName;
    }

    final originalBaseName = path.basenameWithoutExtension(originalName);
    if (originalBaseName.isEmpty) {
      return selectedName;
    }
    return '$originalBaseName$selectedExtension';
  }

  String _resolvedXFileName(XFile file) {
    final fileName = file.name;
    if (fileName.isNotEmpty) {
      return fileName;
    }
    return path.basename(file.path);
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uff/src/features/photos/data/photo_crop_service.dart';
import 'package:uff/src/features/photos/data/photo_picker_service.dart';

/// ## Test Scenarios
/// - [positive] Gallery picks preserve order and honor `maxSelection`.
/// - [positive] Camera picks return one wrapped `PickedPhoto`.
/// - [positive] `offerCrop=true` routes each selected file through crop service.
/// - [negative] Crop usage stays isolated to the gallery pick path and never leaks into camera picks.
/// - [edge] Crop cancellation drops only that photo from the final selection.
/// - [error] Crop failures fall back to uncropped bytes.
/// - [positive] `offerCrop=false` bypasses crop service calls.
/// - [edge] Camera cancellation returns an empty list.
/// - [edge] Zero `maxSelection` short-circuits plugin calls.
/// - [isolation] Separate picker sessions do not reuse previous crop decisions.

class MockImagePicker extends Mock implements ImagePicker {}

class MockPhotoCropService extends Mock implements PhotoCropService {}

XFile _pickedFile(
  Directory tempDirectory,
  String name,
  List<int> bytes,
) {
  final file = File('${tempDirectory.path}/$name')..writeAsBytesSync(bytes);
  return XFile(file.path);
}

void main() {
  late MockImagePicker mockImagePicker;
  late MockPhotoCropService mockPhotoCropService;
  late ImagePickerPhotoPickerService service;
  late Directory tempDirectory;

  setUp(() {
    mockImagePicker = MockImagePicker();
    mockPhotoCropService = MockPhotoCropService();
    service = ImagePickerPhotoPickerService(
      imagePicker: mockImagePicker,
      photoCropService: mockPhotoCropService,
    );
    tempDirectory = Directory.systemTemp.createTempSync(
      'photo_picker_service_test',
    );
  });

  tearDown(() {
    if (tempDirectory.existsSync()) {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  group('ImagePickerPhotoPickerService', () {
    test(
      'uses gallery picker and preserves file order up to maxSelection',
      () async {
        when(
          () => mockImagePicker.pickMultiImage(),
        ).thenAnswer(
          (_) async => <XFile>[
            _pickedFile(tempDirectory, 'gallery_a.jpg', [1, 2]),
            _pickedFile(tempDirectory, 'gallery_b.png', [3, 4]),
          ],
        );

        final pickedPhotos = await service.pickPhotos(
          source: PhotoPickSource.gallery,
          maxSelection: 1,
        );

        expect(
          pickedPhotos.map((photo) => photo.fileName).toList(),
          ['gallery_a.jpg'],
        );
        expect(
          pickedPhotos.map((photo) => photo.bytes).toList(),
          [
            Uint8List.fromList([1, 2]),
          ],
        );
        verify(() => mockImagePicker.pickMultiImage()).called(1);
        verifyNever(
          () => mockImagePicker.pickImage(source: ImageSource.camera),
        );
      },
    );

    test(
      'offerCrop true routes each selected file through crop service',
      () async {
        final first = _pickedFile(tempDirectory, 'gallery_a.jpg', [1, 2]);
        final second = _pickedFile(tempDirectory, 'gallery_b.png', [3, 4]);
        final firstCropped = _pickedFile(
          tempDirectory,
          'gallery_a_cropped.jpg',
          [9, 9],
        );
        final secondCropped = _pickedFile(
          tempDirectory,
          'gallery_b_cropped.jpg',
          [8, 8],
        );
        when(
          () => mockImagePicker.pickMultiImage(),
        ).thenAnswer((_) async => <XFile>[first, second]);
        when(() => mockPhotoCropService.cropPhoto(first)).thenAnswer(
          (_) async => firstCropped,
        );
        when(() => mockPhotoCropService.cropPhoto(second)).thenAnswer(
          (_) async => secondCropped,
        );

        final pickedPhotos = await service.pickPhotos(
          source: PhotoPickSource.gallery,
          offerCrop: true,
        );

        expect(
          pickedPhotos.map((photo) => photo.fileName).toList(),
          ['gallery_a.jpg', 'gallery_b.jpg'],
        );
        expect(
          pickedPhotos.map((photo) => photo.bytes).toList(),
          [
            Uint8List.fromList([9, 9]),
            Uint8List.fromList([8, 8]),
          ],
        );
        verify(() => mockPhotoCropService.cropPhoto(first)).called(1);
        verify(() => mockPhotoCropService.cropPhoto(second)).called(1);
      },
    );

    test('crop cancellation drops only that photo', () async {
      final first = _pickedFile(tempDirectory, 'gallery_a.jpg', [1, 2]);
      final second = _pickedFile(tempDirectory, 'gallery_b.png', [3, 4]);
      final secondCropped = _pickedFile(
        tempDirectory,
        'gallery_b_cropped.png',
        [8, 8],
      );
      when(
        () => mockImagePicker.pickMultiImage(),
      ).thenAnswer((_) async => <XFile>[first, second]);
      when(() => mockPhotoCropService.cropPhoto(first)).thenAnswer(
        (_) async => null,
      );
      when(() => mockPhotoCropService.cropPhoto(second)).thenAnswer(
        (_) async => secondCropped,
      );

      final pickedPhotos = await service.pickPhotos(
        source: PhotoPickSource.gallery,
        offerCrop: true,
      );

      expect(
        pickedPhotos.map((photo) => photo.fileName).toList(),
        ['gallery_b.png'],
      );
      expect(
        pickedPhotos.map((photo) => photo.bytes).toList(),
        [
          Uint8List.fromList([8, 8]),
        ],
      );
      verify(() => mockPhotoCropService.cropPhoto(first)).called(1);
      verify(() => mockPhotoCropService.cropPhoto(second)).called(1);
    });

    test('crop failures fall back to uncropped bytes', () async {
      final first = _pickedFile(tempDirectory, 'gallery_a.jpg', [1, 2]);
      when(
        () => mockImagePicker.pickMultiImage(),
      ).thenAnswer((_) async => <XFile>[first]);
      when(
        () => mockPhotoCropService.cropPhoto(first),
      ).thenThrow(StateError('crop failed'));

      final pickedPhotos = await service.pickPhotos(
        source: PhotoPickSource.gallery,
        offerCrop: true,
      );

      expect(
        pickedPhotos.map((photo) => photo.fileName).toList(),
        ['gallery_a.jpg'],
      );
      expect(
        pickedPhotos.map((photo) => photo.bytes).toList(),
        [
          Uint8List.fromList([1, 2]),
        ],
      );
      verify(() => mockPhotoCropService.cropPhoto(first)).called(1);
    });

    test('offerCrop false bypasses crop calls', () async {
      final first = _pickedFile(tempDirectory, 'gallery_a.jpg', [1, 2]);
      when(
        () => mockImagePicker.pickMultiImage(),
      ).thenAnswer((_) async => <XFile>[first]);

      final pickedPhotos = await service.pickPhotos(
        source: PhotoPickSource.gallery,
        offerCrop: false,
      );

      expect(
        pickedPhotos.map((photo) => photo.fileName).toList(),
        ['gallery_a.jpg'],
      );
      expect(
        pickedPhotos.map((photo) => photo.bytes).toList(),
        [
          Uint8List.fromList([1, 2]),
        ],
      );
      verifyNever(() => mockPhotoCropService.cropPhoto(first));
    });

    test(
      'uses camera picker and wraps the captured image in one-photo list',
      () async {
        when(
          () => mockImagePicker.pickImage(source: ImageSource.camera),
        ).thenAnswer(
          (_) async => _pickedFile(tempDirectory, 'camera.jpg', [9, 8, 7]),
        );

        final pickedPhotos = await service.pickPhotos(
          source: PhotoPickSource.camera,
        );

        expect(
          pickedPhotos.map((photo) => photo.fileName).toList(),
          ['camera.jpg'],
        );
        expect(
          pickedPhotos.map((photo) => photo.bytes).toList(),
          [
            Uint8List.fromList([9, 8, 7]),
          ],
        );
        verify(
          () => mockImagePicker.pickImage(source: ImageSource.camera),
        ).called(1);
        verifyNever(() => mockImagePicker.pickMultiImage());
      },
    );

    test('returns empty list when camera capture is cancelled', () async {
      when(
        () => mockImagePicker.pickImage(source: ImageSource.camera),
      ).thenAnswer((_) async => null);

      final pickedPhotos = await service.pickPhotos(
        source: PhotoPickSource.camera,
      );

      expect(pickedPhotos, isEmpty);
      verify(
        () => mockImagePicker.pickImage(source: ImageSource.camera),
      ).called(1);
      verifyNever(() => mockImagePicker.pickMultiImage());
    });

    test('skips plugin calls entirely when maxSelection is zero', () async {
      final pickedPhotos = await service.pickPhotos(
        source: PhotoPickSource.camera,
        maxSelection: 0,
      );

      expect(pickedPhotos, isEmpty);
      verifyNever(() => mockImagePicker.pickImage(source: ImageSource.camera));
      verifyNever(() => mockImagePicker.pickMultiImage());
    });
  });
}

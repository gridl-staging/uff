import 'dart:typed_data';

import 'package:uff/src/features/photos/domain/activity_photo.dart';

abstract interface class PhotoRepository {
  Future<List<ActivityPhoto>> loadActivityPhotos(String activityId);

  Future<ActivityPhoto> uploadPhoto({
    required String activityId,
    required Uint8List bytes,
    required String fileName,
    required int sortOrder,
    double? latitude,
    double? longitude,
  });

  Future<void> deletePhoto(ActivityPhoto photo);
}

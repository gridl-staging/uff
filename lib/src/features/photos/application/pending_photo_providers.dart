import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/photos/application/pending_photo_service.dart';
import 'package:uff/src/features/photos/application/photo_providers.dart'
    show photoPickerServiceProvider;
import 'package:uff/src/utils/uuid.dart';

/// Provides the [PendingPhotoService] singleton, wired to the real tracking
/// database, camera picker, image compressor, and app documents directory.
///
/// Override individual dependencies in tests via ProviderScope overrides.
final pendingPhotoServiceProvider = FutureProvider<PendingPhotoService>((
  ref,
) async {
  // The pending photos directory lives under the app's documents directory
  // so it persists across app launches but is cleaned up on app uninstall.
  final appDir = await getApplicationDocumentsDirectory();
  final pendingPhotosDir = Directory('${appDir.path}/pending_photos');

  return PendingPhotoService(
    db: ref.read(trackingDatabaseProvider),
    photoPickerService: ref.read(photoPickerServiceProvider),
    compressPhoto: _defaultCompressPhoto,
    pendingPhotosDirectory: pendingPhotosDir,
    uuidGenerator: generateUuidV4,
  );
});

/// Compresses photo bytes for local storage. Uses the same parameters as
/// SupabasePhotoRepository._defaultCompressPhotoBytes (2048px, quality 85)
/// so the file written to disk is upload-ready — no re-compression needed
/// when the activity syncs and photos are uploaded.
Future<Uint8List> _defaultCompressPhoto(Uint8List bytes) async {
  try {
    return await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 2048,
      minHeight: 2048,
      quality: 85,
    );
  } on Object {
    // Compression failed (e.g., corrupt image data). Fall back to the raw
    // bytes rather than losing the photo entirely.
    return bytes;
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';

final syncStatusProvider = StreamProvider<SyncQueueStatus>((ref) {
  return ref.watch(syncServiceProvider).syncStatus;
});

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/data/sync_service.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

const activityDeletionFailureMessage =
    'Unable to delete activity. Please try again.';

Future<bool> confirmActivityDeletion(
  BuildContext context, {
  Key? dialogKey,
  Key? cancelButtonKey,
  Key? confirmButtonKey,
}) async {
  final shouldDelete = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      key: dialogKey,
      title: const Text('Delete activity?'),
      content: const Text('This action is permanent and cannot be undone.'),
      actions: [
        TextButton(
          key: cancelButtonKey,
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: confirmButtonKey,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  return (shouldDelete ?? false) && context.mounted;
}

void showActivityDeletionFailureSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text(activityDeletionFailureMessage)),
  );
}

Future<bool> performActivityDeletion(
  WidgetRef ref,
  TrackingSessionRecord session,
) async {
  final syncService = ref.read(syncServiceProvider);
  final repository = ref.read(trackingRepositoryProvider);

  try {
    final remoteId = session.remoteId;
    if (remoteId != null) {
      await syncService.deleteRemoteActivity(remoteId);
    }
    await repository.deleteActivity(session.id);
    ref.invalidate(savedActivitiesProvider);
    return true;
  } on Object {
    return false;
  }
}

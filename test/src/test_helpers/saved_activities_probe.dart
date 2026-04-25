import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';

class SavedActivitiesProbe extends ConsumerWidget {
  const SavedActivitiesProbe({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(savedActivitiesProvider);
    return const SizedBox.shrink();
  }
}

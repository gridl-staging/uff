import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider;
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/data/kudos_repository.dart';
import 'package:uff/src/features/social/data/supabase_kudos_repository.dart';
import 'package:uff/src/features/social/domain/activity_kudos.dart';

part 'social_kudos_providers.g.dart';

@riverpod
KudosRepository kudosRepository(Ref ref) {
  return SupabaseKudosRepository(Supabase.instance.client);
}

@riverpod
Future<ActivityKudosSummary> activityKudos(Ref ref, String activityId) {
  return ref.read(kudosRepositoryProvider).loadActivityKudos(activityId);
}

/// Optimistic viewer-kudos state keyed by remote activity id.
@riverpod
class OptimisticKudosByActivity extends _$OptimisticKudosByActivity {
  @override
  Map<String, bool> build() => const <String, bool>{};

  void setViewerHasKudo({
    required String activityId,
    required bool viewerHasKudo,
  }) {
    state = <String, bool>{
      ...state,
      activityId: viewerHasKudo,
    };
  }
}

/// In-flight kudos toggles keyed by remote activity id.
final NotifierProvider<KudosToggleInFlightByActivityNotifier, Map<String, bool>>
kudosToggleInFlightByActivityProvider =
    NotifierProvider.autoDispose<
      KudosToggleInFlightByActivityNotifier,
      Map<String, bool>
    >(KudosToggleInFlightByActivityNotifier.new);

/// Tracks which activity ids currently have an in-flight kudos mutation.
class KudosToggleInFlightByActivityNotifier
    extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const <String, bool>{};

  void setInFlight({
    required String activityId,
    required bool inFlight,
  }) {
    final next = <String, bool>{...state};
    if (inFlight) {
      next[activityId] = true;
    } else {
      next.remove(activityId);
    }
    state = next;
  }
}

/// Single mutation path for kudos toggles across social and owner detail flows.
@riverpod
class KudosToggleController extends _$KudosToggleController {
  @override
  FutureOr<void> build() {}

  Future<void> toggleKudos({
    required String activityId,
    required bool viewerHasKudo,
  }) async {
    final toggledViewerHasKudo = !viewerHasKudo;
    // UI callers read only the notifier, so keep this autoDispose controller
    // alive until shared feed/detail caches and in-flight state are updated.
    final mutationKeepAlive = ref.keepAlive();
    ref
        .read(optimisticKudosByActivityProvider.notifier)
        .setViewerHasKudo(
          activityId: activityId,
          viewerHasKudo: toggledViewerHasKudo,
        );
    _setToggleInFlight(activityId: activityId, inFlight: true);
    try {
      state = const AsyncLoading<void>();
      final nextState = await AsyncValue.guard(
        () => ref
            .read(kudosRepositoryProvider)
            .toggleKudos(
              activityId: activityId,
              viewerHasKudo: viewerHasKudo,
            ),
      );
      if (!ref.mounted) {
        return;
      }
      state = nextState;
      if (!nextState.hasError) {
        _invalidateAfterToggle(activityId);
        return;
      }
      // Revert optimistic state when toggle mutation fails.
      ref
          .read(optimisticKudosByActivityProvider.notifier)
          .setViewerHasKudo(
            activityId: activityId,
            viewerHasKudo: viewerHasKudo,
          );
    } finally {
      if (ref.mounted) {
        _setToggleInFlight(activityId: activityId, inFlight: false);
      }
      mutationKeepAlive.close();
    }
  }

  void _setToggleInFlight({
    required String activityId,
    required bool inFlight,
  }) {
    ref
        .read(kudosToggleInFlightByActivityProvider.notifier)
        .setInFlight(activityId: activityId, inFlight: inFlight);
  }

  void _invalidateAfterToggle(String activityId) {
    ref
      ..invalidate(socialFeedProvider)
      ..invalidate(remoteActivityDetailProvider(activityId))
      ..invalidate(activityKudosProvider(activityId));
  }
}

@immutable
class ProjectedKudosState {
  const ProjectedKudosState({
    required this.kudosCount,
    required this.viewerHasKudo,
  });

  final int kudosCount;
  final bool viewerHasKudo;
}

ProjectedKudosState projectKudosState({
  required int sourceKudosCount,
  required bool sourceViewerHasKudo,
  required bool? optimisticViewerHasKudo,
}) {
  final viewerHasKudo = optimisticViewerHasKudo ?? sourceViewerHasKudo;
  final delta = switch ((sourceViewerHasKudo, viewerHasKudo)) {
    (true, false) => -1,
    (false, true) => 1,
    _ => 0,
  };
  return ProjectedKudosState(
    kudosCount: (sourceKudosCount + delta).clamp(0, 1 << 30),
    viewerHasKudo: viewerHasKudo,
  );
}

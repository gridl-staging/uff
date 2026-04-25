import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uff/src/features/photos/application/photo_providers.dart';
import 'package:uff/src/features/photos/domain/activity_photo.dart';
import 'package:uff/src/features/social/data/social_activity_repository.dart';
import 'package:uff/src/features/social/data/supabase_social_activity_repository.dart';
import 'package:uff/src/features/social/domain/social_activity_detail.dart';
import 'package:uff/src/features/social/domain/social_activity_summary.dart';

part 'social_activity_providers.g.dart';

const int socialFeedPageSize = 20;
const Object _unchangedLoadMoreError = Object();

/// Provider payload for remote activity detail plus signed photo data.
@immutable
class RemoteActivityDetailData {
  const RemoteActivityDetailData({
    required this.detail,
    required this.photos,
  });

  final SocialActivityDetail detail;
  final List<ActivityPhoto> photos;
}

/// Immutable feed page state owned by [socialFeedProvider].
@immutable
class SocialFeedState {
  const SocialFeedState({
    required this.activities,
    required this.isRefreshing,
    required this.isLoadingMore,
    required this.hasReachedEnd,
    required this.loadMoreError,
  });

  final List<SocialActivitySummary> activities;
  final bool isRefreshing;
  final bool isLoadingMore;
  final bool hasReachedEnd;
  final Object? loadMoreError;

  SocialFeedState copyWith({
    List<SocialActivitySummary>? activities,
    bool? isRefreshing,
    bool? isLoadingMore,
    bool? hasReachedEnd,
    Object? loadMoreError = _unchangedLoadMoreError,
  }) {
    return SocialFeedState(
      activities: activities ?? this.activities,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasReachedEnd: hasReachedEnd ?? this.hasReachedEnd,
      loadMoreError: identical(loadMoreError, _unchangedLoadMoreError)
          ? this.loadMoreError
          : loadMoreError,
    );
  }
}

@riverpod
SocialActivityRepository socialActivityRepository(Ref ref) {
  return SupabaseSocialActivityRepository(Supabase.instance.client);
}

/// TODO: Document SocialFeed.
@riverpod
class SocialFeed extends _$SocialFeed {
  int _refreshEpoch = 0;

  @override
  Future<SocialFeedState> build() async {
    final initialPage = await _loadPage(offset: 0);
    return _stateFromRows(initialPage);
  }

  Future<void> refresh() async {
    final previousState = state.value;
    if (previousState?.isRefreshing ?? false) {
      return;
    }
    _refreshEpoch++;
    if (previousState != null) {
      state = AsyncData(
        previousState.copyWith(
          isRefreshing: true,
          loadMoreError: null,
        ),
      );
    } else {
      state = const AsyncLoading<SocialFeedState>();
    }

    final refreshedState = await AsyncValue.guard(() async {
      final refreshedRows = await _loadPage(offset: 0);
      return _stateFromRows(refreshedRows);
    });
    if (!ref.mounted) {
      return;
    }
    if (refreshedState.hasError && previousState != null) {
      state = AsyncData(previousState.copyWith(isRefreshing: false));
      return;
    }
    state = refreshedState;
  }

  Future<void> loadMore() async {
    final currentState = state.value;
    if (currentState == null ||
        currentState.isRefreshing ||
        currentState.isLoadingMore ||
        currentState.hasReachedEnd) {
      return;
    }

    final epochAtStart = _refreshEpoch;
    state = AsyncData(
      currentState.copyWith(
        isLoadingMore: true,
        loadMoreError: null,
      ),
    );
    try {
      final nextPageRows = await _loadPage(
        offset: currentState.activities.length,
      );
      if (!ref.mounted || _refreshEpoch != epochAtStart) {
        return;
      }
      state = AsyncData(
        currentState.copyWith(
          activities: <SocialActivitySummary>[
            ...currentState.activities,
            ...nextPageRows,
          ],
          isLoadingMore: false,
          hasReachedEnd: nextPageRows.length < socialFeedPageSize,
          loadMoreError: null,
        ),
      );
    } on Object catch (error) {
      if (!ref.mounted || _refreshEpoch != epochAtStart) {
        return;
      }
      state = AsyncData(
        currentState.copyWith(
          isLoadingMore: false,
          loadMoreError: error,
        ),
      );
    }
  }

  Future<List<SocialActivitySummary>> _loadPage({required int offset}) {
    return ref
        .read(socialActivityRepositoryProvider)
        .loadFeedActivities(
          offset: offset,
          limit: socialFeedPageSize,
        );
  }

  SocialFeedState _stateFromRows(List<SocialActivitySummary> rows) {
    return SocialFeedState(
      activities: rows,
      isRefreshing: false,
      isLoadingMore: false,
      hasReachedEnd: rows.length < socialFeedPageSize,
      loadMoreError: null,
    );
  }
}

@riverpod
Future<List<SocialActivitySummary>> viewedUserActivityList(
  Ref ref,
  String userId,
) {
  return ref.read(socialActivityRepositoryProvider).loadUserActivities(userId);
}

@riverpod
Future<RemoteActivityDetailData?> remoteActivityDetail(
  Ref ref,
  String activityId,
) async {
  final detail = await ref
      .read(socialActivityRepositoryProvider)
      .loadActivityDetail(activityId);
  if (detail == null) {
    return null;
  }

  final photos = await ref.watch(activityPhotoListProvider(activityId).future);
  return RemoteActivityDetailData(detail: detail, photos: photos);
}

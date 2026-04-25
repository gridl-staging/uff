import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uff/src/features/social/application/social_activity_providers.dart';
import 'package:uff/src/features/social/data/follow_repository.dart';
import 'package:uff/src/features/social/data/supabase_follow_repository.dart';
import 'package:uff/src/features/social/data/supabase_user_search_repository.dart';
import 'package:uff/src/features/social/data/user_search_repository.dart';
import 'package:uff/src/features/social/domain/relationship_counts.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/domain/viewed_user_profile_header.dart';

part 'social_providers.g.dart';

@riverpod
FollowRepository followRepository(Ref ref) {
  return SupabaseFollowRepository(Supabase.instance.client);
}

@riverpod
UserSearchRepository userSearchRepository(Ref ref) {
  return SupabaseUserSearchRepository(Supabase.instance.client);
}

@riverpod
Future<List<SocialUserSummary>> followers(Ref ref) {
  return ref.read(followRepositoryProvider).getFollowers();
}

@riverpod
Future<List<SocialUserSummary>> following(Ref ref) {
  return ref.read(followRepositoryProvider).getFollowing();
}

@riverpod
Future<List<SocialUserSummary>> pendingRequests(Ref ref) {
  return ref.read(followRepositoryProvider).getPendingRequests();
}

@riverpod
Future<RelationshipCounts> relationshipCounts(Ref ref) {
  return ref.read(followRepositoryProvider).getRelationshipCounts();
}

@riverpod
Future<List<SocialUserSummary>> userSearch(Ref ref, String query) {
  final normalizedQuery = _normalizeSearchQuery(query);
  if (normalizedQuery == null) {
    return Future.value(const <SocialUserSummary>[]);
  }
  return ref.read(userSearchRepositoryProvider).searchUsers(normalizedQuery);
}

@riverpod
Future<ViewedUserProfileHeader?> viewedUserProfileHeader(
  Ref ref,
  String userId,
) {
  return ref.read(followRepositoryProvider).getViewedUserProfileHeader(userId);
}

/// Handles follow mutations and refreshes dependent relationship caches.
@riverpod
class FollowActionController extends _$FollowActionController {
  @override
  FutureOr<void> build() {}

  Future<void> sendFollowRequest(
    String targetUserId, {
    String? activeSearchQuery,
  }) async {
    await _runMutation(
      () => ref.read(followRepositoryProvider).sendFollowRequest(targetUserId),
      activeSearchQuery: activeSearchQuery,
    );
  }

  Future<void> acceptFollowRequest(
    String followId, {
    String? activeSearchQuery,
  }) async {
    await _runMutation(
      () => ref.read(followRepositoryProvider).acceptFollowRequest(followId),
      activeSearchQuery: activeSearchQuery,
    );
  }

  Future<void> rejectFollowRequest(
    String followId, {
    String? activeSearchQuery,
  }) async {
    await _runMutation(
      () => ref.read(followRepositoryProvider).rejectFollowRequest(followId),
      activeSearchQuery: activeSearchQuery,
    );
  }

  Future<void> unfollow(
    String targetUserId, {
    String? activeSearchQuery,
  }) async {
    await _runMutation(
      () => ref.read(followRepositoryProvider).unfollow(targetUserId),
      activeSearchQuery: activeSearchQuery,
    );
  }

  Future<void> _runMutation(
    Future<void> Function() mutation, {
    required String? activeSearchQuery,
  }) async {
    // UI callers read only the notifier, so keep this autoDispose controller
    // alive until the mutation can refresh shared relationship/search caches.
    final mutationKeepAlive = ref.keepAlive();
    state = const AsyncLoading<void>();
    try {
      final nextState = await AsyncValue.guard(mutation);
      if (!ref.mounted) {
        return;
      }
      state = nextState;
      if (!nextState.hasError) {
        _invalidateCoreQueries(activeSearchQuery: activeSearchQuery);
      }
    } finally {
      mutationKeepAlive.close();
    }
  }

  void _invalidateCoreQueries({required String? activeSearchQuery}) {
    ref
      ..invalidate(followersProvider)
      ..invalidate(followingProvider)
      ..invalidate(pendingRequestsProvider)
      ..invalidate(relationshipCountsProvider)
      ..invalidate(viewedUserProfileHeaderProvider)
      ..invalidate(viewedUserActivityListProvider)
      ..invalidate(socialFeedProvider)
      // Relationship mutations from non-search surfaces (requests/lists)
      // must still refresh search results to avoid stale follow-state rows.
      ..invalidate(userSearchProvider);

    final normalizedQuery = activeSearchQuery == null
        ? null
        : _normalizeSearchQuery(activeSearchQuery);
    if (normalizedQuery == null) {
      return;
    }

    // Keep explicit-key invalidation for compatibility with existing callers
    // that may pass unnormalized active query strings.
    ref.invalidate(userSearchProvider(normalizedQuery));
    final rawQuery = activeSearchQuery;
    if (rawQuery != null && normalizedQuery != rawQuery) {
      ref.invalidate(userSearchProvider(rawQuery));
    }
  }
}

String? _normalizeSearchQuery(String query) {
  final trimmedQuery = query.trim();
  if (trimmedQuery.isEmpty) {
    return null;
  }
  return trimmedQuery;
}

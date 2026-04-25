import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';
import 'package:uff/src/features/social/presentation/social_user_follow_action.dart';
import 'package:uff/src/features/social/presentation/social_user_row.dart';

enum SocialRelationshipListType { followers, following }

/// TODO: Document SocialRelationshipListScreen.
class SocialRelationshipListScreen extends ConsumerWidget {
  const SocialRelationshipListScreen({required this.listType, super.key});

  final SocialRelationshipListType listType;

  static const loadingIndicatorKey = Key('social_relationship_list_loading');
  static const errorStateKey = Key('social_relationship_list_error');
  static const retryButtonKey = Key('social_relationship_list_retry');
  static const emptyStateKey = Key('social_relationship_list_empty');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relationshipsAsync = _providerForListType(ref);

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForListType),
        actions: [
          IconButton(
            tooltip: 'Find People',
            icon: const Icon(Icons.search),
            onPressed: () => context.push(SocialRoutes.searchPath),
          ),
        ],
      ),
      body: _buildBody(context, relationshipsAsync, ref),
    );
  }

  AsyncValue<List<SocialUserSummary>> _providerForListType(WidgetRef ref) {
    return switch (listType) {
      SocialRelationshipListType.followers => ref.watch(followersProvider),
      SocialRelationshipListType.following => ref.watch(followingProvider),
    };
  }

  String get _titleForListType {
    return switch (listType) {
      SocialRelationshipListType.followers => 'Followers',
      SocialRelationshipListType.following => 'Following',
    };
  }

  String get _emptyCopyForListType {
    return switch (listType) {
      SocialRelationshipListType.followers => 'No followers yet',
      SocialRelationshipListType.following =>
        'You are not following anyone yet',
    };
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<SocialUserSummary>> state,
    WidgetRef ref,
  ) {
    if (state.hasError && !state.hasValue) {
      return Center(
        key: errorStateKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Something went wrong'),
            const SizedBox(height: 8),
            FilledButton(
              key: retryButtonKey,
              onPressed: () => _invalidateListProvider(ref),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state.isLoading) {
      return const Center(
        key: loadingIndicatorKey,
        child: CircularProgressIndicator(),
      );
    }

    final users = state.value ?? const [];
    if (users.isEmpty) {
      return Center(
        key: emptyStateKey,
        child: Text(_emptyCopyForListType),
      );
    }

    // Bottom safe area inset — pushed route with no bottom nav bar.
    return ListView.builder(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      itemCount: users.length,
      itemBuilder: (context, index) => SocialUserRow(
        user: users[index],
        onTap: () {
          context.push(
            SocialRoutes.viewedUserProfilePath(users[index].userId),
          );
        },
        onFollowAction: buildSocialUserFollowAction(
          ref: ref,
          user: users[index],
          allowUnfollow: true,
        ),
      ),
    );
  }

  void _invalidateListProvider(WidgetRef ref) {
    switch (listType) {
      case SocialRelationshipListType.followers:
        ref.invalidate(followersProvider);
        return;
      case SocialRelationshipListType.following:
        ref.invalidate(followingProvider);
        return;
    }
  }
}

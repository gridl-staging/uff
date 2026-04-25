import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';
import 'package:uff/src/features/social/presentation/social_user_follow_action.dart';
import 'package:uff/src/features/social/presentation/social_user_row.dart';

/// Search screen for finding and following other users.
///
/// Delegates search to [userSearchProvider] and mutations to
/// [followActionControllerProvider].
class RelationshipSearchScreen extends ConsumerStatefulWidget {
  const RelationshipSearchScreen({super.key});

  static const searchFieldKey = Key('relationship_search_field');
  static const promptStateKey = Key('relationship_search_prompt');
  static const loadingIndicatorKey = Key('relationship_search_loading');
  static const errorStateKey = Key('relationship_search_error');
  static const retryButtonKey = Key('relationship_search_retry');
  static const emptyResultsKey = Key('relationship_search_empty');

  @override
  ConsumerState<RelationshipSearchScreen> createState() =>
      _RelationshipSearchScreenState();
}

/// TODO: Document _RelationshipSearchScreenState.
class _RelationshipSearchScreenState
    extends ConsumerState<RelationshipSearchScreen> {
  final _searchController = TextEditingController();

  /// The current active (trimmed, non-empty) query, or null if no search
  /// has been submitted yet.
  String? _activeQuery;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _submitSearch() {
    final trimmed = _searchController.text.trim();
    setState(() => _activeQuery = trimmed.isEmpty ? null : trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find People'),
        actions: [
          IconButton(
            tooltip: 'Follow Requests',
            icon: const Icon(Icons.mark_email_unread_outlined),
            onPressed: () => context.push(SocialRoutes.requestsPath),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              key: RelationshipSearchScreen.searchFieldKey,
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search by name…',
                prefixIcon: Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submitSearch(),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_activeQuery == null) {
      return const Center(
        key: RelationshipSearchScreen.promptStateKey,
        child: Text('Search for people to follow'),
      );
    }

    final searchAsync = ref.watch(userSearchProvider(_activeQuery!));

    // Manual state dispatch: Riverpod 3.x family providers may stay in
    // AsyncLoading with an embedded error rather than transitioning to
    // AsyncError, so .when(error:) would never fire. Check hasError first.
    if (searchAsync.hasError && !searchAsync.hasValue) {
      return Center(
        key: RelationshipSearchScreen.errorStateKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Something went wrong'),
            const SizedBox(height: 8),
            FilledButton(
              key: RelationshipSearchScreen.retryButtonKey,
              onPressed: () =>
                  ref.invalidate(userSearchProvider(_activeQuery!)),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (searchAsync.isLoading) {
      return const Center(
        key: RelationshipSearchScreen.loadingIndicatorKey,
        child: CircularProgressIndicator(),
      );
    }

    final users = searchAsync.value ?? const [];
    if (users.isEmpty) {
      return const Center(
        key: RelationshipSearchScreen.emptyResultsKey,
        child: Text('No users found'),
      );
    }

    // Bottom safe area inset — pushed route with no bottom nav bar.
    return ListView.builder(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom,
      ),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return SocialUserRow(
          user: user,
          onTap: () {
            context.push(SocialRoutes.viewedUserProfilePath(user.userId));
          },
          onFollowAction: buildSocialUserFollowAction(
            ref: ref,
            user: user,
            activeSearchQuery: _activeQuery,
            allowUnfollow: true,
          ),
        );
      },
    );
  }
}

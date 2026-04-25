import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/social/application/social_providers.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';
import 'package:uff/src/features/social/presentation/social_user_follow_action.dart';
import 'package:uff/src/features/social/presentation/social_user_row.dart';

/// TODO: Document PendingFollowRequestsScreen.
class PendingFollowRequestsScreen extends ConsumerWidget {
  const PendingFollowRequestsScreen({super.key});

  static const loadingIndicatorKey = Key('pending_requests_loading');
  static const errorStateKey = Key('pending_requests_error');
  static const retryButtonKey = Key('pending_requests_retry');
  static const emptyStateKey = Key('pending_requests_empty');

  /// Per-user reject button key.
  static Key rejectButtonKey(String userId) =>
      ValueKey('pending_reject_$userId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Follow Requests'),
        actions: [
          IconButton(
            tooltip: 'Find People',
            icon: const Icon(Icons.search),
            onPressed: () => context.push(SocialRoutes.searchPath),
          ),
        ],
      ),
      body: _buildBody(context, pendingAsync, ref),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<SocialUserSummary>> state,
    WidgetRef ref,
  ) {
    // Check error first — non-family providers transition to AsyncError
    // normally, but check hasError defensively for consistency.
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
              onPressed: () => ref.invalidate(pendingRequestsProvider),
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
      return const Center(
        key: emptyStateKey,
        child: Text('No pending requests'),
      );
    }

    return ListView.builder(
      // Bottom safe area inset — pushed route with no bottom nav bar.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom,
      ),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return _PendingRequestRow(user: user);
      },
    );
  }
}

/// A row for a pending follow request with accept (via SocialUserRow) and
/// reject actions.
class _PendingRequestRow extends ConsumerWidget {
  const _PendingRequestRow({required this.user});

  final SocialUserSummary user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followId = user.relationship.followId;
    final onFollowAction = buildSocialUserFollowAction(ref: ref, user: user);
    final canRejectRequest =
        user.relationship.status == FollowRelationshipStatus.incomingPending &&
        followId != null;

    return Row(
      children: [
        Expanded(
          child: SocialUserRow(
            user: user,
            onTap: () {
              context.push(SocialRoutes.viewedUserProfilePath(user.userId));
            },
            onFollowAction: onFollowAction,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            key: PendingFollowRequestsScreen.rejectButtonKey(user.userId),
            icon: const Icon(Icons.close),
            onPressed: !canRejectRequest
                ? null
                : () {
                    ref
                        .read(followActionControllerProvider.notifier)
                        .rejectFollowRequest(followId);
                  },
          ),
        ),
      ],
    );
  }
}

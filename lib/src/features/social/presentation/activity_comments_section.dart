import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/social/application/social_comments_providers.dart';
import 'package:uff/src/features/social/domain/activity_comment.dart';

/// Shared comments UI surface consumed by both the local and remote
/// activity detail screens. Reads `activityCommentsProvider(activityId)`
/// as the single source of truth for comment data.
///
/// Uses `authProvider` only to compare the signed-in user id against
/// `ActivityComment.author.userId` for delete affordance visibility.
///
/// Mirrors the `FeedScreen.build` / `ActivityHistoryScreen._refreshActivities`
/// retry-refresh pattern instead of maintaining a second comment cache.
class ActivityCommentsSection extends ConsumerStatefulWidget {
  const ActivityCommentsSection({required this.activityId, super.key});

  final String activityId;

  // --- Static key helpers ---
  static const sectionShellKey = Key('comments_section_shell');
  static const loadingStateKey = Key('comments_section_loading');
  static const emptyStateKey = Key('comments_section_empty');
  static const errorStateKey = Key('comments_section_error');
  static const commentListKey = Key('comments_section_list');
  static const refreshSurfaceKey = Key('comments_section_refresh');
  static const composerFieldKey = Key('comments_section_composer');
  static const submitActionKey = Key('comments_section_submit');
  static const retryActionKey = Key('comments_section_retry');

  static Key commentRowKey(String commentId) =>
      Key('comments_section_row_$commentId');

  static Key commentDeleteKey(String commentId) =>
      Key('comments_section_delete_$commentId');

  @override
  ConsumerState<ActivityCommentsSection> createState() =>
      _ActivityCommentsSectionState();
}

/// Renders comments for an activity and handles add/delete operations.
///
/// Displays comments from `activityCommentsProvider(activityId)` with loading,
/// error, and empty states. The composer controller manages input for new
/// comments, which `addCommentControllerProvider` submits and clears on
/// success. Delete buttons appear only for comment authors (determined by
/// comparing `authProvider` user ID to `ActivityComment.author.userId`) and
/// route through `deleteCommentControllerProvider`.
///
/// Operation errors surface through the controller providers' `AsyncValue`
/// states. Pull-to-refresh via `_refreshComments` allows retrying failed
/// loads.
class _ActivityCommentsSectionState
    extends ConsumerState<ActivityCommentsSection> {
  final TextEditingController _composerController = TextEditingController();

  @override
  void dispose() {
    _composerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(
      activityCommentsProvider(widget.activityId),
    );
    final isAddInFlight = ref.watch(addCommentControllerProvider).isLoading;
    final isDeleteInFlight = ref
        .watch(deleteCommentControllerProvider)
        .isLoading;

    return Card(
      key: ActivityCommentsSection.sectionShellKey,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Comments', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            commentsAsync.when(
              loading: () => const Center(
                key: ActivityCommentsSection.loadingStateKey,
                child: CircularProgressIndicator(),
              ),
              error: (_, __) => _buildErrorState(),
              data: (comments) => _buildLoadedContent(
                comments,
                isAddInFlight: isAddInFlight,
                isDeleteInFlight: isDeleteInFlight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshComments() async {
    try {
      final _ = await ref.refresh(
        activityCommentsProvider(widget.activityId).future,
      );
    } on Object {
      // Keep the visible error/data state when refresh fails.
    }
  }

  Widget _buildErrorState() {
    return RefreshIndicator(
      key: ActivityCommentsSection.refreshSurfaceKey,
      onRefresh: _refreshComments,
      child: ListView(
        primary: false,
        shrinkWrap: true,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Column(
            key: ActivityCommentsSection.errorStateKey,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Unable to load comments.'),
              const SizedBox(height: 8),
              ElevatedButton(
                key: ActivityCommentsSection.retryActionKey,
                onPressed: () => ref.invalidate(
                  activityCommentsProvider(widget.activityId),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadedContent(
    List<ActivityComment> comments, {
    required bool isAddInFlight,
    required bool isDeleteInFlight,
  }) {
    final viewerUserId = _resolveViewerUserId();
    final commentsChildren = comments.isEmpty
        ? <Widget>[
            const Padding(
              key: ActivityCommentsSection.emptyStateKey,
              padding: EdgeInsets.only(bottom: 8),
              child: Text('No comments yet.'),
            ),
          ]
        : comments
              .map(
                (comment) => _buildCommentRow(
                  comment,
                  viewerUserId: viewerUserId,
                  isDeleteInFlight: isDeleteInFlight,
                ),
              )
              .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        RefreshIndicator(
          key: ActivityCommentsSection.refreshSurfaceKey,
          onRefresh: _refreshComments,
          child: ListView(
            key: ActivityCommentsSection.commentListKey,
            primary: false,
            shrinkWrap: true,
            physics: const AlwaysScrollableScrollPhysics(),
            children: commentsChildren,
          ),
        ),
        const SizedBox(height: 8),
        _buildComposer(isAddInFlight: isAddInFlight),
      ],
    );
  }

  Widget _buildCommentRow(
    ActivityComment comment, {
    required String? viewerUserId,
    required bool isDeleteInFlight,
  }) {
    final isAuthor =
        viewerUserId != null && comment.author.userId == viewerUserId;

    return ListTile(
      key: ActivityCommentsSection.commentRowKey(comment.commentId),
      title: Text(comment.author.displayName ?? comment.author.userId),
      subtitle: Text(comment.body),
      trailing: isAuthor
          ? IconButton(
              key: ActivityCommentsSection.commentDeleteKey(
                comment.commentId,
              ),
              icon: const Icon(Icons.delete_outline),
              onPressed: isDeleteInFlight
                  ? null
                  : () => _deleteComment(comment),
            )
          : null,
    );
  }

  Widget _buildComposer({required bool isAddInFlight}) {
    final canSubmit =
        !isAddInFlight && _composerController.text.trim().isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: TextField(
            key: ActivityCommentsSection.composerFieldKey,
            controller: _composerController,
            onChanged: (_) => setState(() {}),
            enabled: !isAddInFlight,
            decoration: const InputDecoration(
              hintText: 'Add a comment...',
              isDense: true,
            ),
          ),
        ),
        IconButton(
          key: ActivityCommentsSection.submitActionKey,
          icon: isAddInFlight
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          onPressed: canSubmit ? _submitComment : null,
        ),
      ],
    );
  }

  String? _resolveViewerUserId() {
    final authState = ref.watch(authProvider).asData?.value;
    if (authState case Authenticated(:final userId)) {
      return userId;
    }
    return null;
  }

  Future<void> _submitComment() async {
    final body = _composerController.text.trim();
    if (body.isEmpty) {
      return;
    }
    try {
      await ref
          .read(addCommentControllerProvider.notifier)
          .addComment(
            activityId: widget.activityId,
            body: body,
          );
      if (mounted) {
        setState(_composerController.clear);
      }
    } on Object {
      // Error state is surfaced through the controller's AsyncValue.
    }
  }

  Future<void> _deleteComment(ActivityComment comment) async {
    try {
      await ref
          .read(deleteCommentControllerProvider.notifier)
          .deleteComment(
            activityId: widget.activityId,
            commentId: comment.commentId,
          );
    } on Object {
      // Error state is surfaced through the controller's AsyncValue.
    }
  }
}

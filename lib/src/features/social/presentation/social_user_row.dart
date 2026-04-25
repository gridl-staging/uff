import 'package:flutter/material.dart';
import 'package:uff/src/common_widgets/trusted_avatar_widget.dart';
import 'package:uff/src/features/social/domain/follow_relationship.dart';
import 'package:uff/src/features/social/domain/social_user_summary.dart';
import 'package:uff/src/features/social/presentation/social_user_display_name.dart';

/// Shared row widget for displaying a social user with a follow-action button.
///
/// Used across search results, pending requests, and followers/following lists.
class SocialUserRow extends StatelessWidget {
  const SocialUserRow({
    required this.user,
    required this.onFollowAction,
    this.onTap,
    super.key,
  });

  final SocialUserSummary user;

  /// Called when the user taps the follow-action button.
  final VoidCallback? onFollowAction;
  final VoidCallback? onTap;

  /// Stable key for the row container, keyed by user id.
  static Key userRowKey(String userId) => ValueKey('social_user_row_$userId');

  /// Stable key for the action button, keyed by user id.
  static Key actionButtonKey(String userId) =>
      ValueKey('social_user_action_$userId');

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: userRowKey(user.userId),
      onTap: onTap,
      leading: TrustedAvatarWidget(
        avatarUrl: user.avatarUrl,
        displayName: user.displayName,
      ),
      title: Text(
        socialUserDisplayNameOrId(
          userId: user.userId,
          displayName: user.displayName,
        ),
      ),
      trailing: SocialUserFollowActionButton(
        buttonKey: actionButtonKey(user.userId),
        status: user.relationship.status,
        onPressed: onFollowAction,
      ),
    );
  }
}

/// Button that adapts its label and style based on the follow relationship.
class SocialUserFollowActionButton extends StatelessWidget {
  const SocialUserFollowActionButton({
    required this.buttonKey,
    required this.status,
    required this.onPressed,
    super.key,
  });

  final Key buttonKey;
  final FollowRelationshipStatus status;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final (label, filled) = switch (status) {
      FollowRelationshipStatus.none => ('Follow', true),
      FollowRelationshipStatus.outgoingPending => ('Requested', false),
      FollowRelationshipStatus.incomingPending => ('Accept', true),
      FollowRelationshipStatus.following => ('Following', false),
    };

    return filled
        ? FilledButton(key: buttonKey, onPressed: onPressed, child: Text(label))
        : OutlinedButton(
            key: buttonKey,
            onPressed: onPressed,
            child: Text(label),
          );
  }
}

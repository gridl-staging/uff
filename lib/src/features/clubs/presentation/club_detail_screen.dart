import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/common_widgets/trusted_avatar_widget.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/clubs/application/club_providers.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/domain/club_member.dart';
import 'package:uff/src/features/clubs/domain/club_run.dart';
import 'package:uff/src/features/clubs/presentation/club_routes.dart';
import 'package:uff/src/features/social/presentation/social_routes.dart';
import 'package:uff/src/features/social/presentation/social_user_display_name.dart';

part 'club_detail_screen_sections.dart';

/// Detail screen for a single club, showing header, membership actions,
/// member list, upcoming runs, and admin controls.
class ClubDetailScreen extends ConsumerStatefulWidget {
  const ClubDetailScreen({required this.clubId, super.key});

  final String clubId;

  static const _maxDisplayedMembers = 10;
  static const _maxDisplayedRuns = 5;

  // Key constants for testability
  static const headerKey = Key('club_detail_header');
  static const joinButtonKey = Key('club_detail_join_button');
  static const memberListSectionKey = Key('club_detail_member_list_section');
  static const runsSectionKey = Key('club_detail_runs_section');
  static const loadingIndicatorKey = Key('club_detail_loading_indicator');
  static const errorStateKey = Key('club_detail_error_state');
  static const retryButtonKey = Key('club_detail_retry_button');
  static const emptyMembersKey = Key('club_detail_empty_members');
  static const emptyRunsKey = Key('club_detail_empty_runs');
  static const membersLoadingIndicatorKey = Key(
    'club_detail_members_loading_indicator',
  );
  static const runsLoadingIndicatorKey = Key(
    'club_detail_runs_loading_indicator',
  );
  static const membersRetryButtonKey = Key('club_detail_members_retry_button');
  static const runsRetryButtonKey = Key('club_detail_runs_retry_button');
  static const adminSectionKey = Key('club_detail_admin_section');
  static const overflowMenuButtonKey = Key('club_detail_overflow_menu_button');
  static const leaveMenuItemKey = Key('club_detail_leave_menu_item');
  static const editMenuItemKey = Key('club_detail_edit_menu_item');
  static const scheduleRunButtonKey = Key('club_detail_schedule_run_button');
  static const manageMembersButtonKey = Key(
    'club_detail_manage_members_button',
  );
  static const claimClubButtonKey = Key('club_detail_claim_club_button');
  static const leaveConfirmDialogKey = Key('club_detail_leave_confirm_dialog');

  static Key memberItemKey(String memberId) =>
      Key('club_detail_member_$memberId');
  static Key runItemKey(String runId) => Key('club_detail_run_$runId');

  @override
  ConsumerState<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

enum _ClubOverflowAction { edit, leave }

/// TODO: Document _ClubDetailScreenState.
class _ClubDetailScreenState extends ConsumerState<ClubDetailScreen> {
  String? get _currentUserId {
    final authState = ref.watch(authProvider).asData?.value;
    if (authState case Authenticated(:final userId)) {
      return userId;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final clubAsync = ref.watch(clubDetailProvider(widget.clubId));

    return clubAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: CircularProgressIndicator(
            key: ClubDetailScreen.loadingIndicatorKey,
          ),
        ),
      ),
      error: (_, __) => Scaffold(appBar: AppBar(), body: _buildErrorState()),
      data: (club) {
        if (club == null) {
          return Scaffold(appBar: AppBar(), body: _buildErrorState());
        }
        return _buildClubContent(club);
      },
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        key: ClubDetailScreen.errorStateKey,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Unable to load club. Please try again.'),
          const SizedBox(height: 12),
          OutlinedButton(
            key: ClubDetailScreen.retryButtonKey,
            onPressed: () => ref.invalidate(clubDetailProvider(widget.clubId)),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildClubContent(Club club) {
    final membersAsync = ref.watch(clubMembersProvider(widget.clubId));
    final runsAsync = ref.watch(upcomingClubRunsProvider(widget.clubId));
    final contentState = _resolveClubContentState(
      club: club,
      membersAsync: membersAsync,
    );

    if (contentState.hasPendingMembersState) {
      return _buildMembersPendingScaffold(
        club: club,
        runsAsync: runsAsync,
        contentState: contentState,
      );
    }

    return _buildMembersLoadedScaffold(
      club: club,
      runsAsync: runsAsync,
      contentState: contentState,
    );
  }

  _ClubContentState _resolveClubContentState({
    required Club club,
    required AsyncValue<List<ClubMember>> membersAsync,
  }) {
    final membersData = membersAsync.asData?.value;
    final isMembersLoading = membersAsync.isLoading && membersData == null;
    final hasMembersLoadError = membersAsync.hasError && membersData == null;
    final currentUserId = _currentUserId;
    final members = membersData ?? const <ClubMember>[];
    final currentMembership = _findActiveMembershipForUser(
      members,
      currentUserId,
    );
    final isAdmin = _canManageClub(
      club: club,
      currentMembership: currentMembership,
      userId: currentUserId,
    );
    return _ClubContentState(
      members: members,
      currentMembership: currentMembership,
      isAdmin: isAdmin,
      isMembersLoading: isMembersLoading,
      hasMembersLoadError: hasMembersLoadError,
    );
  }

  Widget _buildMembersPendingScaffold({
    required Club club,
    required AsyncValue<List<ClubRun>> runsAsync,
    required _ClubContentState contentState,
  }) {
    return Scaffold(
      appBar: AppBar(
        title: Text(club.name),
        actions: _buildOverflowActions(
          club: club,
          currentMembership: null,
          isAdmin: contentState.isAdmin,
        ),
      ),
      body: ListView(
        children: [
          _buildHeader(club),
          if (_isUnclaimedAutoDiscovered(club)) _buildClaimButton(),
          if (contentState.isAdmin) _buildAdminSection(),
          if (contentState.isMembersLoading)
            _buildMembersLoadingSection()
          else
            _buildMembersErrorSection(),
          _buildRunsSectionFromAsync(runsAsync),
        ],
      ),
    );
  }

  Widget _buildMembersLoadedScaffold({
    required Club club,
    required AsyncValue<List<ClubRun>> runsAsync,
    required _ClubContentState contentState,
  }) {
    return Scaffold(
      appBar: AppBar(
        title: Text(club.name),
        actions: _buildOverflowActions(
          club: club,
          currentMembership: contentState.currentMembership,
          isAdmin: contentState.isAdmin,
        ),
      ),
      body: ListView(
        children: [
          _buildHeader(club),
          _buildMembershipAction(club, contentState.currentMembership),
          if (_isUnclaimedAutoDiscovered(club)) _buildClaimButton(),
          if (contentState.isAdmin) _buildAdminSection(),
          _buildMembersSection(contentState.members),
          _buildRunsSectionFromAsync(runsAsync),
        ],
      ),
    );
  }

  List<Widget> _buildOverflowActions({
    required Club club,
    required ClubMember? currentMembership,
    required bool isAdmin,
  }) {
    final hasLeaveAction = currentMembership != null;
    final hasEditAction = isAdmin;
    if (!hasLeaveAction && !hasEditAction) {
      return const <Widget>[];
    }

    return <Widget>[
      PopupMenuButton<_ClubOverflowAction>(
        key: ClubDetailScreen.overflowMenuButtonKey,
        onSelected: (action) => _onOverflowActionSelected(action, club),
        itemBuilder: (context) => <PopupMenuEntry<_ClubOverflowAction>>[
          if (hasEditAction)
            const PopupMenuItem<_ClubOverflowAction>(
              key: ClubDetailScreen.editMenuItemKey,
              value: _ClubOverflowAction.edit,
              child: Text('Edit'),
            ),
          if (hasLeaveAction)
            const PopupMenuItem<_ClubOverflowAction>(
              key: ClubDetailScreen.leaveMenuItemKey,
              value: _ClubOverflowAction.leave,
              child: Text('Leave Club'),
            ),
        ],
      ),
    ];
  }

  void _onOverflowActionSelected(_ClubOverflowAction action, Club club) {
    switch (action) {
      case _ClubOverflowAction.edit:
        context.push(ClubRoutes.clubEditPath(club.id), extra: club);
      case _ClubOverflowAction.leave:
        _confirmLeave(club.id);
    }
  }

  Widget _buildMembershipAction(Club club, ClubMember? currentMembership) {
    if (currentMembership != null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton(
        key: ClubDetailScreen.joinButtonKey,
        onPressed: () =>
            ref.read(clubMutationControllerProvider.notifier).joinClub(club.id),
        child: const Text('Join'),
      ),
    );
  }

  Future<void> _confirmLeave(String clubId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: ClubDetailScreen.leaveConfirmDialogKey,
        title: const Text('Leave club?'),
        content: const Text('Are you sure you want to leave this club?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && mounted) {
      try {
        await ref
            .read(clubMutationControllerProvider.notifier)
            .leaveClub(clubId);
      } on Object {
        if (mounted) {
          _showErrorSnackBar('Unable to leave club. Please try again.');
        }
        return;
      }
      if (mounted) {
        context.go(ClubRoutes.clubListPath);
      }
    }
  }

  Widget _buildClaimButton() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton(
        key: ClubDetailScreen.claimClubButtonKey,
        onPressed: null, // Disabled - claiming not yet implemented.
        child: Text('Claim this club'),
      ),
    );
  }

  Widget _buildAdminSection() {
    return Padding(
      key: ClubDetailScreen.adminSectionKey,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Admin',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: ClubDetailScreen.scheduleRunButtonKey,
                onPressed: () =>
                    context.push(ClubRoutes.clubRunNewPath(widget.clubId)),
                icon: const Icon(Icons.calendar_today),
                label: const Text('Schedule Run'),
              ),
              OutlinedButton.icon(
                key: ClubDetailScreen.manageMembersButtonKey,
                onPressed: () => _showPlaceholderSnackbar('Manage Members'),
                icon: const Icon(Icons.people),
                label: const Text('Manage Members'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPlaceholderSnackbar(String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action coming in a future update')),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildMembersLoadingSection() => _buildSectionLoading(
    sectionKey: ClubDetailScreen.memberListSectionKey,
    title: 'Members',
    loadingIndicatorKey: ClubDetailScreen.membersLoadingIndicatorKey,
  );

  Widget _buildMembersErrorSection() => _buildSectionError(
    sectionKey: ClubDetailScreen.memberListSectionKey,
    title: 'Members',
    errorMessage: 'Unable to load members',
    retryButtonKey: ClubDetailScreen.membersRetryButtonKey,
    onRetry: () => ref.invalidate(clubMembersProvider(widget.clubId)),
  );

  ClubMember? _findActiveMembershipForUser(
    List<ClubMember> members,
    String? userId,
  ) {
    if (userId == null) return null;
    for (final member in members) {
      if (member.userId == userId && member.status == ClubMemberStatus.active) {
        return member;
      }
    }
    return null;
  }

  bool _canManageClub({
    required Club club,
    required ClubMember? currentMembership,
    required String? userId,
  }) {
    if (userId == null) {
      return false;
    }
    return club.creatorId == userId || _isAdminOrOrganizer(currentMembership);
  }

  bool _isAdminOrOrganizer(ClubMember? member) {
    return member != null &&
        (member.role == ClubMemberRole.admin ||
            member.role == ClubMemberRole.organizer);
  }

  bool _isUnclaimedAutoDiscovered(Club club) {
    return club.source == ClubSource.autoDiscovered && club.claimedBy == null;
  }
}

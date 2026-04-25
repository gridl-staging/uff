part of 'club_detail_screen.dart';

/// TODO: Document _ClubDetailScreenSections.
extension _ClubDetailScreenSections on _ClubDetailScreenState {
  Widget _buildHeader(Club club) {
    return Padding(
      key: ClubDetailScreen.headerKey,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.groups, size: 48),
          const SizedBox(height: 8),
          Text(
            club.name,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          if (club.description != null) ...[
            const SizedBox(height: 8),
            Text(club.description!),
          ],
          if (club.city != null) ...[
            const SizedBox(height: 4),
            Text(club.city!),
          ],
          const SizedBox(height: 4),
          Text('${club.memberCount} members'),
        ],
      ),
    );
  }

  Widget _buildMembersSection(List<ClubMember> members) {
    final displayMembers = members
        .take(ClubDetailScreen._maxDisplayedMembers)
        .toList();

    return Column(
      key: ClubDetailScreen.memberListSectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Members',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        if (displayMembers.isEmpty)
          const Padding(
            key: ClubDetailScreen.emptyMembersKey,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No members yet'),
          )
        else
          ...displayMembers.map(
            (member) => ListTile(
              key: ClubDetailScreen.memberItemKey(member.id),
              onTap: () => context.push(
                SocialRoutes.viewedUserProfilePath(member.userId),
              ),
              leading: TrustedAvatarWidget(
                avatarUrl: member.avatarUrl,
                displayName: member.displayName,
              ),
              title: Text(
                socialUserDisplayNameOrId(
                  userId: member.userId,
                  displayName: member.displayName,
                ),
              ),
              subtitle: Text(member.role.databaseValue),
            ),
          ),
      ],
    );
  }

  Widget _buildRunsSection(List<ClubRun> runs) {
    final displayRuns = runs.take(ClubDetailScreen._maxDisplayedRuns).toList();

    return Column(
      key: ClubDetailScreen.runsSectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Upcoming Runs',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        if (displayRuns.isEmpty)
          const Padding(
            key: ClubDetailScreen.emptyRunsKey,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No upcoming runs'),
          )
        else
          ...displayRuns.map(
            (run) => ListTile(
              key: ClubDetailScreen.runItemKey(run.id),
              leading: const Icon(Icons.directions_run),
              title: Text(run.title),
            ),
          ),
      ],
    );
  }

  Widget _buildRunsSectionFromAsync(AsyncValue<List<ClubRun>> runsAsync) {
    final runsData = runsAsync.asData?.value;
    final isRunsLoading = runsAsync.isLoading && runsData == null;
    final hasRunsLoadError = runsAsync.hasError && runsData == null;

    if (isRunsLoading) {
      return _buildRunsLoadingSection();
    }
    if (hasRunsLoadError) {
      return _buildRunsErrorSection();
    }
    return _buildRunsSection(runsData ?? const <ClubRun>[]);
  }

  Widget _buildRunsLoadingSection() => _buildSectionLoading(
    sectionKey: ClubDetailScreen.runsSectionKey,
    title: 'Upcoming Runs',
    loadingIndicatorKey: ClubDetailScreen.runsLoadingIndicatorKey,
  );

  Widget _buildRunsErrorSection() => _buildSectionError(
    sectionKey: ClubDetailScreen.runsSectionKey,
    title: 'Upcoming Runs',
    errorMessage: 'Unable to load upcoming runs',
    retryButtonKey: ClubDetailScreen.runsRetryButtonKey,
    onRetry: () => ref.invalidate(upcomingClubRunsProvider(widget.clubId)),
  );

  Widget _buildSectionLoading({
    required Key sectionKey,
    required String title,
    required Key loadingIndicatorKey,
  }) {
    return Column(
      key: sectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(title),
        Padding(
          key: loadingIndicatorKey,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const CircularProgressIndicator(),
        ),
      ],
    );
  }

  Widget _buildSectionError({
    required Key sectionKey,
    required String title,
    required String errorMessage,
    required Key retryButtonKey,
    required VoidCallback onRetry,
  }) {
    return Column(
      key: sectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(child: Text(errorMessage)),
              TextButton(
                key: retryButtonKey,
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// TODO: Document _ClubContentState.
class _ClubContentState {
  const _ClubContentState({
    required this.members,
    required this.currentMembership,
    required this.isAdmin,
    required this.isMembersLoading,
    required this.hasMembersLoadError,
  });

  final List<ClubMember> members;
  final ClubMember? currentMembership;
  final bool isAdmin;
  final bool isMembersLoading;
  final bool hasMembersLoadError;

  bool get hasPendingMembersState => isMembersLoading || hasMembersLoadError;
}

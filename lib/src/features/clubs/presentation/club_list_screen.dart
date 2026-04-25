import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/clubs/application/club_providers.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/presentation/club_routes.dart';

/// Club list screen displayed inside the shell's Clubs tab.
///
/// Shows "My Clubs" and "Discover" sections by default. When the user types
/// in the search field, a 300ms debounce fires and the UI switches to showing
/// search results from `clubSearchProvider` while hiding the default sections.
class ClubListScreen extends ConsumerStatefulWidget {
  const ClubListScreen({super.key});

  static const myClubsSectionKey = Key('club_list_my_clubs_section');
  static const discoverSectionKey = Key('club_list_discover_section');
  static const searchFieldKey = Key('club_list_search_field');
  static const createClubFabKey = Key('club_list_create_club_fab');
  static const loadingIndicatorKey = Key('club_list_loading_indicator');
  static const emptyMyClubsKey = Key('club_list_empty_my_clubs');
  static const emptyDiscoverKey = Key('club_list_empty_discover');
  static const errorStateKey = Key('club_list_error_state');
  static const retryButtonKey = Key('club_list_retry_button');

  static Key clubCardKey(String id) => Key('club_list_card_$id');

  @override
  ConsumerState<ClubListScreen> createState() => _ClubListScreenState();
}

/// TODO: Document _ClubListScreenState.
class _ClubListScreenState extends ConsumerState<ClubListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;
  GoRouter? _router;
  String _debouncedQuery = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (identical(_router, router)) {
      return;
    }
    _router?.routerDelegate.removeListener(_handleRouteChange);
    _router = router;
    _router?.routerDelegate.addListener(_handleRouteChange);
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_handleRouteChange);
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _debouncedQuery = value.trim();
        });
      }
    });
  }

  bool get _isSearching => _debouncedQuery.isNotEmpty;

  void _handleRouteChange() {
    final currentPath = _router?.routerDelegate.currentConfiguration.uri.path;
    if (currentPath == null || currentPath == ClubRoutes.clubListPath) {
      return;
    }
    _clearSearchState();
  }

  void _clearSearchState() {
    _debounceTimer?.cancel();
    if (_searchController.text.isEmpty && _debouncedQuery.isEmpty) {
      return;
    }
    _searchController.clear();
    setState(() {
      _debouncedQuery = '';
    });
  }

  Future<void> _onRefreshDefault() async {
    ref
      ..invalidate(myClubsProvider)
      ..invalidate(nearbyClubsProvider);

    await Future.wait<void>([
      ref.read(myClubsProvider.future),
      ref.read(nearbyClubsProvider.future),
    ]);
  }

  Future<void> _onRefreshSearch() async {
    final query = _debouncedQuery;
    final provider = clubSearchProvider(query);
    ref.invalidate(provider);
    await ref.read(provider.future);
  }

  Future<void> _retryLoadTask() async {
    if (_isSearching) {
      await _onRefreshSearch();
      return;
    }
    await _onRefreshDefault();
  }

  void _retryLoad() {
    unawaited(
      _retryLoadTask().onError<Object>((_, __) {
        return;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        key: ClubListScreen.createClubFabKey,
        onPressed: () => context.push(ClubRoutes.clubNewPath),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: ClubListScreen.searchFieldKey,
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search clubs',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _isSearching
                ? _buildSearchResults()
                : _buildDefaultSections(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    final searchResults = ref.watch(clubSearchProvider(_debouncedQuery));

    return searchResults.when(
      skipError: true,
      loading: () => const Center(
        child: CircularProgressIndicator(
          key: ClubListScreen.loadingIndicatorKey,
        ),
      ),
      error: (_, __) => _buildErrorBody(),
      data: (clubs) => RefreshIndicator(
        onRefresh: _onRefreshSearch,
        child: clubs.isEmpty
            ? _buildSearchEmptyResults()
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: clubs.length,
                itemBuilder: (_, index) => _ClubCard(club: clubs[index]),
              ),
      ),
    );
  }

  Widget _buildSearchEmptyResults() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: constraints.maxHeight,
              child: const Center(child: Text('No clubs found')),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDefaultSections() {
    final myClubs = ref.watch(myClubsProvider);
    final nearby = ref.watch(nearbyClubsProvider);

    // If both are loading, show a single loading indicator.
    if (myClubs.isLoading && !myClubs.hasValue) {
      return const Center(
        child: CircularProgressIndicator(
          key: ClubListScreen.loadingIndicatorKey,
        ),
      );
    }

    // If either has an error and no data, show error state.
    if (myClubs.hasError && !myClubs.hasValue) {
      return _buildErrorBody();
    }
    if (nearby.hasError && !nearby.hasValue) {
      return _buildErrorBody();
    }

    final myClubsList = myClubs.asData?.value ?? const <Club>[];
    final nearbyList = nearby.asData?.value ?? const <Club>[];

    return RefreshIndicator(
      onRefresh: _onRefreshDefault,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildSectionHeader('My Clubs', ClubListScreen.myClubsSectionKey),
          if (myClubsList.isEmpty)
            const Padding(
              key: ClubListScreen.emptyMyClubsKey,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text("You haven't joined any clubs yet"),
            )
          else
            ...myClubsList.map((club) => _ClubCard(club: club)),
          const SizedBox(height: 16),
          _buildSectionHeader('Discover', ClubListScreen.discoverSectionKey),
          if (nearbyList.isEmpty)
            const Padding(
              key: ClubListScreen.emptyDiscoverKey,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text('No clubs found nearby'),
            )
          else
            ...nearbyList.map((club) => _ClubCard(club: club)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Key key) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildErrorBody() {
    return Center(
      child: Column(
        key: ClubListScreen.errorStateKey,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Unable to load clubs. Please try again.'),
          const SizedBox(height: 12),
          OutlinedButton(
            key: ClubListScreen.retryButtonKey,
            onPressed: _retryLoad,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// TODO: Document _ClubCard.
class _ClubCard extends StatelessWidget {
  const _ClubCard({required this.club});

  final Club club;

  @override
  Widget build(BuildContext context) {
    final isAutoDiscovered = club.source == ClubSource.autoDiscovered;
    return Card(
      key: ClubListScreen.clubCardKey(club.id),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(isAutoDiscovered ? Icons.public : Icons.groups),
        title: Text(club.name),
        subtitle: Text(
          [
            if (club.city != null) club.city!,
            '${club.memberCount} members',
          ].join(' · '),
        ),
        trailing: isAutoDiscovered
            ? Chip(
                label: const Text('Auto-discovered'),
                backgroundColor: Theme.of(context).chipTheme.backgroundColor,
              )
            : null,
        onTap: () => context.push(ClubRoutes.clubDetailPath(club.id)),
      ),
    );
  }
}

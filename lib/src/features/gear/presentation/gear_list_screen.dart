import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/activity_tracking/presentation/tracking_display_formatters.dart';
import 'package:uff/src/features/gear/application/gear_providers.dart';
import 'package:uff/src/features/gear/domain/gear_item.dart';
import 'package:uff/src/features/gear/presentation/gear_routes.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';

/// TODO: Document GearListScreen.
class GearListScreen extends ConsumerWidget {
  const GearListScreen({super.key});

  static const addButtonKey = Key('gear_list_add_button');
  static const loadingIndicatorKey = Key('gear_list_loading_indicator');
  static const emptyStateKey = Key('gear_list_empty_state');
  static const errorMessageKey = Key('gear_list_error_message');
  static const retryButtonKey = Key('gear_list_retry_button');

  static Key gearCardKey(String id) => Key('gear_list_card_$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gearList = ref.watch(gearListProvider);
    final preferredUnits = ref
        .watch(profileProvider)
        .asData
        ?.value
        ?.preferredUnits;

    Future<void> refreshGearList() => _refreshGearList(ref);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gear'),
        actions: [
          IconButton(
            key: addButtonKey,
            onPressed: () => context.push(GearRoutes.gearNewPath),
            icon: const Icon(Icons.add),
            tooltip: 'Add Gear',
          ),
        ],
      ),
      body: gearList.when(
        skipError: true,
        loading: () => const Center(
          child: CircularProgressIndicator(key: loadingIndicatorKey),
        ),
        error: (_, __) => _buildErrorBody(ref: ref, onRefresh: refreshGearList),
        data: (items) => items.isEmpty
            ? _buildEmptyBody(onRefresh: refreshGearList)
            : _buildPopulatedBody(
                context: context,
                items: items,
                preferredUnits: preferredUnits,
                onRefresh: refreshGearList,
              ),
      ),
    );
  }

  Future<void> _refreshGearList(WidgetRef ref) async {
    try {
      final _ = await ref.refresh(gearListProvider.future);
    } on Object {
      // Keep the visible error state when refresh fails.
    }
  }

  Widget _buildErrorBody({
    required WidgetRef ref,
    required Future<void> Function() onRefresh,
  }) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                key: errorMessageKey,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Unable to load gear. Please try again.'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: retryButtonKey,
                    onPressed: () => ref.invalidate(gearListProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyBody({required Future<void> Function() onRefresh}) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: const CustomScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'No gear yet. Add your first shoe or bike.',
                key: emptyStateKey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopulatedBody({
    required BuildContext context,
    required List<GearItem> items,
    required String? preferredUnits,
    required Future<void> Function() onRefresh,
  }) {
    final activeItems = items.where((item) => !item.retired).toList();
    final retiredItems = items.where((item) => item.retired).toList();
    final listChildren = <Widget>[
      ...activeItems.map(
        (item) => _GearListCard(
          key: gearCardKey(item.id),
          item: item,
          preferredUnits: preferredUnits,
        ),
      ),
      if (retiredItems.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Retired', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Opacity(
          opacity: 0.5,
          child: Column(
            children: retiredItems
                .map(
                  (item) => _GearListCard(
                    key: gearCardKey(item.id),
                    item: item,
                    preferredUnits: preferredUnits,
                  ),
                )
                .toList(),
          ),
        ),
      ],
    ];

    // Bottom safe area inset — this is a pushed route with no bottom nav bar.
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomInset),
        children: listChildren,
      ),
    );
  }
}

/// TODO: Document _GearListCard.
class _GearListCard extends StatelessWidget {
  const _GearListCard({
    required this.item,
    required this.preferredUnits,
    super.key,
  });

  final GearItem item;
  final String? preferredUnits;

  @override
  Widget build(BuildContext context) {
    final brandModelSegment = <String>[
      if (item.brand case final String brand) brand.trim(),
      if (item.model case final String model) model.trim(),
    ].where((segment) => segment.isNotEmpty).join(' ');
    final subtitleSegments = <String>[
      if (brandModelSegment.isNotEmpty) brandModelSegment,
      item.gearTypeLabel,
      // formatDistance chooses km vs mi using preferred_units.dart constants.
      formatDistance(item.totalDistanceMeters, preferredUnits: preferredUnits),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: Icon(_iconForGearType(item.gearType)),
        title: Text(item.name),
        subtitle: Text(subtitleSegments.join(' · ')),
        trailing: item.retired
            ? Chip(
                label: const Text('Retired'),
                backgroundColor: Theme.of(context).chipTheme.backgroundColor,
              )
            : null,
        onTap: () =>
            context.push(GearRoutes.gearDetailPath(item.id), extra: item),
      ),
    );
  }

  IconData _iconForGearType(GearType gearType) {
    switch (gearType) {
      case GearType.shoe:
        return Icons.directions_run;
      case GearType.bike:
        return Icons.pedal_bike;
      case GearType.component:
        return Icons.build;
    }
  }
}

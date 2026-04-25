import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/profile/application/privacy_zone_form_controller.dart';
import 'package:uff/src/features/profile/application/privacy_zone_providers.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';
import 'package:uff/src/features/profile/presentation/profile_routes.dart';

/// Lists saved privacy zones and provides entry points to add/edit them.
class PrivacyZonesScreen extends ConsumerWidget {
  const PrivacyZonesScreen({super.key});

  static const explanationCardKey = Key('privacy_zones_explanation_card');
  static const addPrivacyZoneButtonKey = Key('privacy_zones_add_button');
  static const emptyStateKey = Key('privacy_zones_empty_state');
  static const errorMessageKey = Key('privacy_zones_error_message');
  static const String explanationCardMessage =
      'Route points are masked server-side inside saved privacy zones.';

  static ValueKey<String> zoneRowKey(String zoneId) =>
      ValueKey<String>('privacy_zone_row_$zoneId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacyZonesAsync = ref.watch(privacyZonesProvider);
    Future<void> refreshPrivacyZones() async {
      try {
        final _ = await ref.refresh(privacyZonesProvider.future);
      } on Object {
        // Keep the visible error state when refresh fails.
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Zones'),
        actions: [
          IconButton(
            key: addPrivacyZoneButtonKey,
            icon: const Icon(Icons.add),
            onPressed: () => context.push(ProfileRoutes.privacyZonesNewPath),
          ),
        ],
      ),
      body: privacyZonesAsync.when(
        skipError: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => RefreshIndicator(
          onRefresh: refreshPrivacyZones,
          child: const CustomScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Failed to load privacy zones. Please try again.',
                        key: errorMessageKey,
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text('Pull down to refresh.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        data: (zones) =>
            _PrivacyZonesContent(zones: zones, onRefresh: refreshPrivacyZones),
      ),
    );
  }
}

/// TODO: Document _PrivacyZonesContent.
class _PrivacyZonesContent extends ConsumerWidget {
  const _PrivacyZonesContent({required this.zones, required this.onRefresh});

  final List<PrivacyZone> zones;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            key: PrivacyZonesScreen.explanationCardKey,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(PrivacyZonesScreen.explanationCardMessage),
            ),
          ),
          const SizedBox(height: 16),
          if (zones.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No privacy zones yet.',
                key: PrivacyZonesScreen.emptyStateKey,
              ),
            )
          else
            ...zones.map(
              (zone) => Dismissible(
                key: ValueKey<String>('privacy_zone_dismiss_${zone.id}'),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmDelete(context, ref, zone.id),
                background: Container(
                  alignment: Alignment.centerRight,
                  color: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                child: Card(
                  key: PrivacyZonesScreen.zoneRowKey(zone.id),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(zone.label),
                    subtitle: Text(_formatCoordinates(zone)),
                    trailing: Text(_formatRadius(zone.radiusMeters)),
                    onTap: () => context.push(
                      ProfileRoutes.privacyZoneDetailPath(zone.id),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String zoneId,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Privacy Zone'),
        content: const Text(
          'Are you sure you want to delete this privacy zone?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) {
      return false;
    }

    return ref
        .read(privacyZoneFormControllerProvider.notifier)
        .deleteZone(zoneId);
  }

  String _formatCoordinates(PrivacyZone zone) {
    final latitude = zone.latitude.toStringAsFixed(4);
    final longitude = zone.longitude.toStringAsFixed(4);
    return '$latitude, $longitude';
  }

  String _formatRadius(int radiusMeters) {
    return '$radiusMeters m';
  }
}

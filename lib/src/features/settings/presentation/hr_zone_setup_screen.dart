import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/core/presentation/button_progress_indicator.dart';
import 'package:uff/src/features/analytics/domain/hr_zone_calculator.dart';
import 'package:uff/src/features/analytics/domain/sport_type.dart';
import 'package:uff/src/features/profile/data/profile.dart';
import 'package:uff/src/features/profile/data/profile_provider.dart';

const _loadErrorMessage =
    'Unable to load heart rate zones right now. Please retry.';
const _invalidLthrMessage = 'Enter a valid LTHR value.';
const _saveErrorMessage = 'Unable to save heart rate zones right now.';

/// LTHR setup screen for heart-rate zone calculations.
class HrZoneSetupScreen extends ConsumerStatefulWidget {
  const HrZoneSetupScreen({super.key});

  static const loadingStateKey = Key('hr_zone_setup_loading_state');
  static const loadErrorStateKey = Key('hr_zone_setup_load_error_state');
  static const retryButtonKey = Key('hr_zone_setup_retry_button');
  static const lthrInputKey = Key('hr_zone_setup_lthr_input');
  static const zoneBreakdownKey = Key('hr_zone_setup_zone_breakdown');
  static const saveButtonKey = Key('hr_zone_setup_save_button');
  static const clearButtonKey = Key('hr_zone_setup_clear_button');

  @override
  ConsumerState<HrZoneSetupScreen> createState() => _HrZoneSetupScreenState();
}

/// TODO: Document _HrZoneSetupScreenState.
class _HrZoneSetupScreenState extends ConsumerState<HrZoneSetupScreen> {
  final _lthrController = TextEditingController();

  int? _lastHydratedLthrBpm;
  String? _validationMessage;
  bool _isSaving = false;

  @override
  void dispose() {
    _lthrController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Heart Rate Zones')),
      body: profileAsync.when(
        loading: () => const Center(
          key: HrZoneSetupScreen.loadingStateKey,
          child: CircularProgressIndicator(),
        ),
        error: (_, __) => Center(
          key: HrZoneSetupScreen.loadErrorStateKey,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(_loadErrorMessage, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  key: HrZoneSetupScreen.retryButtonKey,
                  onPressed: () => ref.invalidate(profileProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('No profile found.'));
          }
          _hydrateLthrFromProfile(profile);
          return _buildForm(profile);
        },
      ),
    );
  }

  Widget _buildForm(Profile profile) {
    final zoneBreakdown = _fiveZoneBreakdownForInput(_lthrController.text);
    // Include bottom safe area inset — pushed route with no bottom nav bar.
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      children: [
        const Text(
          'Set your lactate threshold heart rate to personalize heart-rate zones.',
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: HrZoneSetupScreen.lthrInputKey,
          controller: _lthrController,
          enabled: !_isSaving,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'LTHR (bpm)',
            errorText: _validationMessage,
          ),
          onChanged: (_) {
            if (_validationMessage == null) {
              return;
            }
            setState(() {
              _validationMessage = null;
            });
          },
        ),
        if (zoneBreakdown != null) ...[
          const SizedBox(height: 24),
          _buildZoneBreakdown(zoneBreakdown),
        ],
        const SizedBox(height: 24),
        ElevatedButton(
          key: HrZoneSetupScreen.saveButtonKey,
          onPressed: _isSaving ? null : () => _save(profile),
          child: _isSaving
              ? const ButtonProgressIndicator()
              : const Text('Save'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: HrZoneSetupScreen.clearButtonKey,
          onPressed: _isSaving ? null : () => _clear(profile),
          child: const Text('Clear LTHR'),
        ),
      ],
    );
  }

  Widget _buildZoneBreakdown(List<_DisplayZone> zones) {
    return Card(
      key: HrZoneSetupScreen.zoneBreakdownKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Computed zones',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final zone in zones) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Zone ${zone.number} · ${zone.name}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(zone.rangeLabel),
                ],
              ),
              if (zone != zones.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  void _hydrateLthrFromProfile(Profile profile) {
    if (_lastHydratedLthrBpm == profile.lthrBpm) {
      return;
    }

    final lthrText = profile.lthrBpm?.toString() ?? '';
    _lthrController.value = TextEditingValue(
      text: lthrText,
      selection: TextSelection.collapsed(offset: lthrText.length),
    );
    _validationMessage = null;
    _lastHydratedLthrBpm = profile.lthrBpm;
  }

  Future<void> _save(Profile profile) async {
    final validationMessage = _validateLthrInput(_lthrController.text);
    if (validationMessage != null) {
      setState(() {
        _validationMessage = validationMessage;
      });
      return;
    }

    final lthrBpm = int.parse(_lthrController.text.trim());
    await _updateProfile(profile.copyWith(lthrBpm: lthrBpm));
  }

  Future<void> _clear(Profile profile) async {
    await _updateProfile(profile.copyWith(lthrBpm: null));
  }

  Future<void> _updateProfile(Profile profile) async {
    setState(() {
      _isSaving = true;
    });

    try {
      await ref.read(profileProvider.notifier).updateProfile(profile);
      if (!mounted) {
        return;
      }

      if (ref.read(profileProvider).hasError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(_saveErrorMessage)));
        return;
      }

      setState(() {
        _validationMessage = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  List<_DisplayZone>? _fiveZoneBreakdownForInput(String rawLthrInput) {
    final lthrBpm = int.tryParse(rawLthrInput.trim());
    if (lthrBpm == null) {
      return null;
    }

    if (_validateLthrInput(rawLthrInput) != null) {
      return null;
    }

    // Use the same running-zone calculator that analytics relies on so the
    // previewed ranges and the saved LTHR stay on one math contract.
    final calculatedZones = HrZoneCalculator.forLthr(lthrBpm, SportType.run);
    return [
      _DisplayZone(
        number: 1,
        name: 'Recovery',
        rangeLabel: _formatClosedRange(
          lowerBpm: calculatedZones.zones[0].lowerBpm,
          upperBpm: calculatedZones.zones[0].upperBpm!,
        ),
      ),
      _DisplayZone(
        number: 2,
        name: 'Aerobic',
        rangeLabel: _formatClosedRange(
          lowerBpm: calculatedZones.zones[1].lowerBpm,
          upperBpm: calculatedZones.zones[1].upperBpm!,
        ),
      ),
      _DisplayZone(
        number: 3,
        name: 'Tempo',
        rangeLabel: _formatClosedRange(
          lowerBpm: calculatedZones.zones[2].lowerBpm,
          upperBpm: calculatedZones.zones[2].upperBpm!,
        ),
      ),
      _DisplayZone(
        number: 4,
        name: 'Threshold',
        rangeLabel: _formatClosedRange(
          lowerBpm: calculatedZones.zones[3].lowerBpm,
          upperBpm: calculatedZones.zones[3].upperBpm!,
        ),
      ),
      _DisplayZone(
        number: 5,
        name: 'VO2max',
        rangeLabel: '${calculatedZones.zones[4].lowerBpm}+ bpm',
      ),
    ];
  }

  void _showSaveFailureSnackBar() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(_saveErrorMessage)));
  }
}

String? _validateLthrInput(String rawLthrInput) {
  final parsedLthr = int.tryParse(rawLthrInput.trim());
  if (parsedLthr == null) {
    return _invalidLthrMessage;
  }

  for (final sport in SportType.values) {
    try {
      HrZoneCalculator.forLthr(parsedLthr, sport);
    } on Object catch (error, stackTrace) {
      if (error is ArgumentError) {
        return _invalidLthrMessage;
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  return null;
}

String _formatClosedRange({required int lowerBpm, required int upperBpm}) {
  return '$lowerBpm-$upperBpm bpm';
}

class _DisplayZone {
  const _DisplayZone({
    required this.number,
    required this.name,
    required this.rangeLabel,
  });

  final int number;
  final String name;
  final String rangeLabel;
}

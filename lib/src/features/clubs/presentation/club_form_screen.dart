import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/core/presentation/button_progress_indicator.dart';
import 'package:uff/src/core/presentation/discard_changes_dialog.dart';
import 'package:uff/src/features/clubs/application/club_providers.dart';
import 'package:uff/src/features/clubs/data/club_repository.dart';
import 'package:uff/src/features/clubs/domain/club.dart';
import 'package:uff/src/features/clubs/domain/club_sport_type.dart';
import 'package:uff/src/features/clubs/presentation/club_routes.dart';

/// Creates a new club or edits an existing one.
class ClubFormScreen extends ConsumerStatefulWidget {
  const ClubFormScreen({this.existingClub, super.key});

  static const nameFieldKey = Key('club_form_name_field');
  static const descriptionFieldKey = Key('club_form_description_field');
  static const cityFieldKey = Key('club_form_city_field');
  static const stateRegionFieldKey = Key('club_form_state_region_field');
  static const sportTypeFieldKey = Key('club_form_sport_type_field');
  static const visibilitySegmentedButtonKey = Key(
    'club_form_visibility_segmented_button',
  );
  static const saveButtonKey = Key('club_form_save_button');

  final Club? existingClub;

  @override
  ConsumerState<ClubFormScreen> createState() => _ClubFormScreenState();
}

/// TODO: Document _ClubFormScreenState.
class _ClubFormScreenState extends ConsumerState<ClubFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateRegionController = TextEditingController();

  ClubVisibility _selectedVisibility = ClubVisibility.public;
  ClubSportType? _sportType;
  bool _isSaving = false;
  bool _allowNextPop = false;
  _ClubFormSnapshot _savedSnapshot = const _ClubFormSnapshot.empty();

  Iterable<TextEditingController> get _controllers => <TextEditingController>[
    _nameController,
    _descriptionController,
    _cityController,
    _stateRegionController,
  ];

  bool get _isEditMode => widget.existingClub != null;
  bool get _hasUnsavedChanges => _captureSnapshot() != _savedSnapshot;
  bool get _canPop => _allowNextPop || (!_isSaving && !_hasUnsavedChanges);

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_handleFormValueChanged);
    }

    final existing = widget.existingClub;
    if (existing != null) {
      _nameController.text = existing.name;
      _descriptionController.text = existing.description ?? '';
      _cityController.text = existing.city ?? '';
      _stateRegionController.text = existing.stateRegion ?? '';
      _selectedVisibility = existing.visibility;
      _sportType = existing.sportType;
    }
    _savedSnapshot = _captureSnapshot();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller
        ..removeListener(_handleFormValueChanged)
        ..dispose();
    }
    super.dispose();
  }

  void _handleFormValueChanged() {
    if (!mounted) return;
    setState(() {});
  }

  bool _hasValidForm() {
    return _formKey.currentState?.validate() ?? false;
  }

  Future<void> _save() async {
    if (_isSaving || !_hasValidForm()) return;

    await _runMutation(
      action: () async {
        if (_isEditMode) {
          final existing = widget.existingClub!;
          final updated = Club(
            id: existing.id,
            name: _nameController.text.trim(),
            description: normalizeOptionalClubText(_descriptionController.text),
            avatarUrl: existing.avatarUrl,
            city: normalizeOptionalClubText(_cityController.text),
            stateRegion: normalizeOptionalClubText(_stateRegionController.text),
            country: existing.country,
            locationLat: existing.locationLat,
            locationLng: existing.locationLng,
            source: existing.source,
            sourceUrl: existing.sourceUrl,
            sourceId: existing.sourceId,
            creatorId: existing.creatorId,
            claimedBy: existing.claimedBy,
            visibility: _selectedVisibility,
            memberCount: existing.memberCount,
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt,
            sportType: _sportType,
          );
          await ref
              .read(clubMutationControllerProvider.notifier)
              .updateClub(updated);
        } else {
          final input = CreateClubInput(
            name: _nameController.text.trim(),
            description: normalizeOptionalClubText(_descriptionController.text),
            city: normalizeOptionalClubText(_cityController.text),
            stateRegion: normalizeOptionalClubText(_stateRegionController.text),
            visibility: _selectedVisibility,
            sportType: _sportType,
          );
          await ref
              .read(clubMutationControllerProvider.notifier)
              .createClub(input);
        }
      },
    );
  }

  Future<void> _runMutation({required Future<void> Function() action}) async {
    setState(() {
      _isSaving = true;
    });

    try {
      await action();
      if (mounted) {
        _savedSnapshot = _captureSnapshot();
        _allowNextPop = true;
        _navigateBack();
      }
    } on Object {
      _showErrorSnackBar('Unable to save club. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  _ClubFormSnapshot _captureSnapshot() {
    return _ClubFormSnapshot(
      name: _nameController.text,
      description: _descriptionController.text,
      city: _cityController.text,
      stateRegion: _stateRegionController.text,
      visibility: _selectedVisibility,
      sportType: _sportType,
    );
  }

  String _sportTypeLabel(ClubSportType sportType) {
    return switch (sportType) {
      ClubSportType.running => 'Running',
      ClubSportType.cycling => 'Cycling',
      ClubSportType.hiking => 'Hiking',
      ClubSportType.walking => 'Walking',
      ClubSportType.trailRunning => 'Trail Running',
    };
  }

  void _navigateBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    context.go(ClubRoutes.clubListPath);
  }

  Future<void> _handlePopInvoked(bool didPop, Object? result) async {
    if (didPop || _isSaving || !_hasUnsavedChanges) return;

    final shouldDiscard = await showDiscardChangesDialog(context);
    if (!shouldDiscard || !mounted) return;

    setState(() {
      _allowNextPop = true;
    });
    _navigateBack();
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: _handlePopInvoked,
      child: Scaffold(
        appBar: AppBar(title: Text(_isEditMode ? 'Edit Club' : 'New Club')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: _buildFormFields(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFormFields() {
    return [
      TextFormField(
        key: ClubFormScreen.nameFieldKey,
        controller: _nameController,
        decoration: const InputDecoration(labelText: 'Name'),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Name is required';
          }
          if (value.trim().length > 100) {
            return 'Name must be 100 characters or fewer';
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        key: ClubFormScreen.descriptionFieldKey,
        controller: _descriptionController,
        decoration: const InputDecoration(labelText: 'Description (optional)'),
        maxLines: 3,
        validator: (value) {
          if (value != null && value.trim().length > 2000) {
            return 'Description must be 2000 characters or fewer';
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        key: ClubFormScreen.cityFieldKey,
        controller: _cityController,
        decoration: const InputDecoration(labelText: 'City (optional)'),
      ),
      const SizedBox(height: 16),
      TextFormField(
        key: ClubFormScreen.stateRegionFieldKey,
        controller: _stateRegionController,
        decoration: const InputDecoration(
          labelText: 'State / Region (optional)',
        ),
      ),
      const SizedBox(height: 16),
      _buildSportTypeDropdown(),
      const SizedBox(height: 16),
      const Text('Join setting'),
      const SizedBox(height: 8),
      SegmentedButton<ClubVisibility>(
        key: ClubFormScreen.visibilitySegmentedButtonKey,
        segments: const [
          ButtonSegment(value: ClubVisibility.public, label: Text('Open')),
          ButtonSegment(
            value: ClubVisibility.private,
            label: Text('Request membership approval'),
          ),
        ],
        selected: {_selectedVisibility},
        onSelectionChanged: _isSaving
            ? null
            : (selection) {
                setState(() {
                  _selectedVisibility = selection.first;
                });
              },
      ),
      const SizedBox(height: 24),
      ElevatedButton(
        key: ClubFormScreen.saveButtonKey,
        onPressed: _isSaving ? null : _save,
        child: _isSaving ? const ButtonProgressIndicator() : const Text('Save'),
      ),
    ];
  }

  Widget _buildSportTypeDropdown() {
    return DropdownButtonFormField<ClubSportType?>(
      key: ClubFormScreen.sportTypeFieldKey,
      value: _sportType,
      decoration: const InputDecoration(labelText: 'Sport Type (optional)'),
      items: <DropdownMenuItem<ClubSportType?>>[
        const DropdownMenuItem<ClubSportType?>(
          value: null,
          child: Text('None'),
        ),
        ...ClubSportType.values.map(
          (sportType) => DropdownMenuItem<ClubSportType?>(
            value: sportType,
            child: Text(_sportTypeLabel(sportType)),
          ),
        ),
      ],
      onChanged: _isSaving
          ? null
          : (value) {
              setState(() {
                _sportType = value;
              });
            },
    );
  }
}

/// Captures form state for unsaved-changes detection.
@immutable
class _ClubFormSnapshot {
  const _ClubFormSnapshot({
    required this.name,
    required this.description,
    required this.city,
    required this.stateRegion,
    required this.visibility,
    required this.sportType,
  });

  const _ClubFormSnapshot.empty()
    : name = '',
      description = '',
      city = '',
      stateRegion = '',
      visibility = ClubVisibility.public,
      sportType = null;

  final String name;
  final String description;
  final String city;
  final String stateRegion;
  final ClubVisibility visibility;
  final ClubSportType? sportType;

  @override
  bool operator ==(Object other) {
    return other is _ClubFormSnapshot &&
        other.name == name &&
        other.description == description &&
        other.city == city &&
        other.stateRegion == stateRegion &&
        other.visibility == visibility &&
        other.sportType == sportType;
  }

  @override
  int get hashCode =>
      Object.hash(name, description, city, stateRegion, visibility, sportType);
}

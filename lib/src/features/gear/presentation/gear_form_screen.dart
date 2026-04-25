import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/core/presentation/button_progress_indicator.dart';
import 'package:uff/src/core/presentation/discard_changes_dialog.dart';
import 'package:uff/src/features/auth/data/auth_provider.dart';
import 'package:uff/src/features/auth/data/auth_state.dart';
import 'package:uff/src/features/gear/application/gear_providers.dart';
import 'package:uff/src/features/gear/domain/gear_item.dart';
import 'package:uff/src/features/gear/presentation/gear_routes.dart';

/// Creates a new gear item or edits an existing one.
class GearFormScreen extends ConsumerStatefulWidget {
  const GearFormScreen({this.existingItem, super.key});

  static const nameFieldKey = Key('gear_form_name_field');
  static const brandFieldKey = Key('gear_form_brand_field');
  static const modelFieldKey = Key('gear_form_model_field');
  static const typeSegmentedButtonKey = Key('gear_form_type_segmented_button');
  static const startDateButtonKey = Key('gear_form_start_date_button');
  static const initialDistanceFieldKey = Key(
    'gear_form_initial_distance_field',
  );
  static const notesFieldKey = Key('gear_form_notes_field');
  static const saveButtonKey = Key('gear_form_save_button');
  static const retireButtonKey = Key('gear_form_retire_button');
  static const deleteButtonKey = Key('gear_form_delete_button');
  static const deleteConfirmDialogKey = Key('gear_form_delete_confirm_dialog');

  final GearItem? existingItem;

  @override
  ConsumerState<GearFormScreen> createState() => _GearFormScreenState();
}

/// TODO: Document _GearFormScreenState.
class _GearFormScreenState extends ConsumerState<GearFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _initialDistanceController = TextEditingController();
  final _notesController = TextEditingController();

  GearType _selectedType = GearType.shoe;
  DateTime? _selectedStartDate;
  bool _isSaving = false;
  bool _allowNextPop = false;
  _GearFormSnapshot _savedSnapshot = const _GearFormSnapshot.empty();

  bool get _isEditMode => widget.existingItem != null;
  bool get _hasUnsavedChanges => _captureSnapshot() != _savedSnapshot;
  bool get _canPop => _allowNextPop || (!_isSaving && !_hasUnsavedChanges);

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_handleFormValueChanged);
    _brandController.addListener(_handleFormValueChanged);
    _modelController.addListener(_handleFormValueChanged);
    _initialDistanceController.addListener(_handleFormValueChanged);
    _notesController.addListener(_handleFormValueChanged);

    final existingItem = widget.existingItem;
    if (existingItem != null) {
      _nameController.text = existingItem.name;
      _brandController.text = existingItem.brand ?? '';
      _modelController.text = existingItem.model ?? '';
      _initialDistanceController.text = _formatDistanceForInput(
        existingItem.totalDistanceMeters,
      );
      _notesController.text = existingItem.notes ?? '';
      _selectedType = existingItem.gearType;
      _selectedStartDate = _toDateOnly(existingItem.startDate);
    }
    _savedSnapshot = _captureSnapshot();
  }

  @override
  void dispose() {
    _nameController.removeListener(_handleFormValueChanged);
    _brandController.removeListener(_handleFormValueChanged);
    _modelController.removeListener(_handleFormValueChanged);
    _initialDistanceController.removeListener(_handleFormValueChanged);
    _notesController.removeListener(_handleFormValueChanged);
    _nameController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _initialDistanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _handleFormValueChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  bool _hasValidForm() {
    return _formKey.currentState?.validate() ?? false;
  }

  Future<void> _saveGear() async {
    if (_isSaving || !_hasValidForm()) {
      return;
    }

    final existingItem = widget.existingItem;
    final repository = ref.read(gearRepositoryProvider);
    await _runMutation(
      errorMessage: 'Unable to save gear. Please try again.',
      action: () async {
        final formItem = await _buildSaveItem(existingItem);
        if (existingItem == null) {
          await repository.createGear(formItem);
          return;
        }

        await repository.updateGear(formItem);
      },
    );
  }

  Future<void> _toggleRetiredStatus() async {
    final existingItem = widget.existingItem;
    if (_isSaving || existingItem == null || !_hasValidForm()) {
      return;
    }

    await _runMutation(
      errorMessage: 'Unable to update gear. Please try again.',
      action: () {
        return ref
            .read(gearRepositoryProvider)
            .updateGear(
              _buildFormItem(
                userId: existingItem.userId,
                existingItem: existingItem,
                retired: !existingItem.retired,
              ),
            );
      },
    );
  }

  Future<GearItem> _buildSaveItem(GearItem? existingItem) async {
    final userId = existingItem?.userId ?? await _resolveCurrentUserId();
    if (userId == null) {
      throw StateError('Missing user id');
    }

    return _buildFormItem(userId: userId, existingItem: existingItem);
  }

  Future<void> _confirmDelete() async {
    final existingItem = widget.existingItem;
    if (_isSaving || existingItem == null) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: GearFormScreen.deleteConfirmDialogKey,
        title: const Text('Delete gear?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    await _runMutation(
      errorMessage: 'Unable to delete gear. Please try again.',
      action: () =>
          ref.read(gearRepositoryProvider).deleteGear(existingItem.id),
    );
  }

  GearItem _buildFormItem({
    required String userId,
    GearItem? existingItem,
    bool? retired,
  }) {
    final parsedDistanceMeters = _parseOptionalDistanceMeters(
      _initialDistanceController.text,
    );
    return GearItem(
      id: existingItem?.id ?? '',
      userId: userId,
      name: _nameController.text.trim(),
      gearType: _selectedType,
      totalDistanceMeters: parsedDistanceMeters ?? 0,
      retired: retired ?? existingItem?.retired ?? false,
      startDate: _selectedStartDate,
      brand: _normalizeOptionalField(_brandController.text),
      model: _normalizeOptionalField(_modelController.text),
      notes: _normalizeOptionalField(_notesController.text),
    );
  }

  Future<void> _runMutation({
    required Future<void> Function() action,
    required String errorMessage,
  }) async {
    setState(() {
      _isSaving = true;
    });

    try {
      await action();
      ref.invalidate(gearListProvider);
      if (mounted) {
        _savedSnapshot = _captureSnapshot();
        _allowNextPop = true;
        _navigateBackToList();
      }
    } on Object {
      _showErrorSnackBar(errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String? _normalizeOptionalField(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  double? _parseOptionalDistanceMeters(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsedDistanceMeters = double.tryParse(trimmed);
    if (parsedDistanceMeters == null) {
      return null;
    }

    if (parsedDistanceMeters == 0 && trimmed.startsWith('-')) {
      return null;
    }

    return parsedDistanceMeters;
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final initialDate =
        _selectedStartDate ?? DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year + 20, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _selectedStartDate = _toDateOnly(picked);
    });
  }

  String _startDateButtonLabel(MaterialLocalizations localizations) {
    final selectedStartDate = _selectedStartDate;
    if (selectedStartDate == null) {
      return 'Select start date';
    }
    return localizations.formatMediumDate(selectedStartDate);
  }

  DateTime? _toDateOnly(DateTime? value) {
    if (value == null) {
      return null;
    }
    return DateTime(value.year, value.month, value.day);
  }

  String _formatDistanceForInput(double meters) {
    if (meters == 0) {
      return '0';
    }

    if (meters == meters.truncateToDouble()) {
      return meters.toStringAsFixed(0);
    }
    return meters.toString();
  }

  String _normalizeDistanceForSnapshot(String rawDistanceInput) {
    final parsedDistanceMeters = _parseOptionalDistanceMeters(rawDistanceInput);
    if (parsedDistanceMeters != null) {
      return _formatDistanceForInput(parsedDistanceMeters);
    }

    // Save semantics normalize an empty distance to 0 meters.
    if (rawDistanceInput.trim().isEmpty) {
      return _formatDistanceForInput(0);
    }

    return rawDistanceInput;
  }

  _GearFormSnapshot _captureSnapshot() {
    return _GearFormSnapshot(
      name: _nameController.text,
      brand: _brandController.text,
      model: _modelController.text,
      initialDistance: _normalizeDistanceForSnapshot(
        _initialDistanceController.text,
      ),
      notes: _notesController.text,
      startDate: _selectedStartDate,
      gearType: _selectedType,
    );
  }

  void _navigateBackToList() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    context.go(GearRoutes.gearPath);
  }

  Future<void> _handlePopInvoked(bool didPop, Object? result) async {
    if (didPop || _isSaving || !_hasUnsavedChanges) {
      return;
    }

    final shouldDiscard = await showDiscardChangesDialog(context);
    if (!shouldDiscard || !mounted) {
      return;
    }

    setState(() {
      _allowNextPop = true;
    });
    _navigateBackToList();
  }

  Future<String?> _resolveCurrentUserId() async {
    final authState = ref.read(authProvider).asData?.value;

    if (authState case Authenticated(:final userId)) {
      return userId;
    }

    try {
      final sessionState = await ref
          .read(authRepositoryProvider)
          .getCurrentSession();
      return switch (sessionState) {
        Authenticated(:final userId) => userId,
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  AppBar _buildAppBar() {
    return AppBar(title: Text(_isEditMode ? 'Edit Gear' : 'Add Gear'));
  }

  Widget _buildNameField() {
    return TextFormField(
      key: GearFormScreen.nameFieldKey,
      controller: _nameController,
      enabled: !_isSaving,
      decoration: const InputDecoration(labelText: 'Name'),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Name is required';
        }
        return null;
      },
    );
  }

  List<Widget> _buildTypeSection() {
    if (_isEditMode) {
      return const [];
    }

    return [
      const SizedBox(height: 16),
      const Text('Type'),
      const SizedBox(height: 8),
      SegmentedButton<GearType>(
        key: GearFormScreen.typeSegmentedButtonKey,
        segments: const [
          ButtonSegment(value: GearType.shoe, label: Text('Shoe')),
          ButtonSegment(value: GearType.bike, label: Text('Bike')),
          ButtonSegment(value: GearType.component, label: Text('Component')),
        ],
        selected: {_selectedType},
        onSelectionChanged: _isSaving
            ? null
            : (selection) {
                setState(() {
                  _selectedType = selection.first;
                });
              },
      ),
    ];
  }

  Widget _buildBrandField() {
    return TextFormField(
      key: GearFormScreen.brandFieldKey,
      controller: _brandController,
      enabled: !_isSaving,
      decoration: const InputDecoration(labelText: 'Brand (optional)'),
    );
  }

  Widget _buildModelField() {
    return TextFormField(
      key: GearFormScreen.modelFieldKey,
      controller: _modelController,
      enabled: !_isSaving,
      decoration: const InputDecoration(labelText: 'Model (optional)'),
    );
  }

  Widget _buildStartDateButton(MaterialLocalizations localizations) {
    return OutlinedButton.icon(
      key: GearFormScreen.startDateButtonKey,
      onPressed: _isSaving ? null : _pickStartDate,
      icon: const Icon(Icons.calendar_today),
      label: Text(_startDateButtonLabel(localizations)),
    );
  }

  Widget _buildInitialDistanceField() {
    return TextFormField(
      key: GearFormScreen.initialDistanceFieldKey,
      controller: _initialDistanceController,
      enabled: !_isSaving,
      decoration: const InputDecoration(
        labelText: 'Initial distance in meters (optional)',
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (value) {
        final parsedDistanceMeters = _parseOptionalDistanceMeters(value ?? '');
        if ((value ?? '').trim().isNotEmpty &&
            (parsedDistanceMeters == null || parsedDistanceMeters < 0)) {
          return 'Enter a valid distance';
        }
        return null;
      },
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      key: GearFormScreen.notesFieldKey,
      controller: _notesController,
      enabled: !_isSaving,
      decoration: const InputDecoration(labelText: 'Notes (optional)'),
      maxLines: 3,
    );
  }

  Widget _buildSaveButton() {
    final saveLabel = _isEditMode ? 'Save Changes' : 'Add Gear';
    return ElevatedButton(
      key: GearFormScreen.saveButtonKey,
      onPressed: _isSaving ? null : _saveGear,
      child: _isSaving ? const ButtonProgressIndicator() : Text(saveLabel),
    );
  }

  List<Widget> _buildEditModeActions({
    required GearItem? existingItem,
    required ThemeData theme,
  }) {
    if (existingItem == null) {
      return const [];
    }

    return [
      const SizedBox(height: 12),
      OutlinedButton(
        key: GearFormScreen.retireButtonKey,
        onPressed: _isSaving ? null : _toggleRetiredStatus,
        child: Text(existingItem.retired ? 'Unretire' : 'Retire'),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        key: GearFormScreen.deleteButtonKey,
        onPressed: _isSaving ? null : _confirmDelete,
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.error,
          side: BorderSide(color: theme.colorScheme.error),
        ),
        child: const Text('Delete Gear'),
      ),
    ];
  }

  List<Widget> _buildFormChildren({
    required GearItem? existingItem,
    required MaterialLocalizations localizations,
    required ThemeData theme,
  }) {
    return [
      _buildNameField(),
      ..._buildTypeSection(),
      const SizedBox(height: 16),
      _buildBrandField(),
      const SizedBox(height: 16),
      _buildModelField(),
      const SizedBox(height: 16),
      _buildStartDateButton(localizations),
      const SizedBox(height: 16),
      _buildInitialDistanceField(),
      const SizedBox(height: 16),
      _buildNotesField(),
      const SizedBox(height: 24),
      _buildSaveButton(),
      ..._buildEditModeActions(existingItem: existingItem, theme: theme),
    ];
  }

  Widget _buildFormBody(BuildContext context, GearItem? existingItem) {
    final localizations = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        cacheExtent: 4000,
        children: _buildFormChildren(
          existingItem: existingItem,
          localizations: localizations,
          theme: theme,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existingItem = widget.existingItem;

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: _handlePopInvoked,
      child: Scaffold(
        appBar: _buildAppBar(),
        body: _buildFormBody(context, existingItem),
      ),
    );
  }
}

/// Captures current form values to detect unsaved gear edits.
@immutable
class _GearFormSnapshot {
  const _GearFormSnapshot({
    required this.name,
    required this.brand,
    required this.model,
    required this.initialDistance,
    required this.notes,
    required this.startDate,
    required this.gearType,
  });

  const _GearFormSnapshot.empty()
    : name = '',
      brand = '',
      model = '',
      initialDistance = '',
      notes = '',
      startDate = null,
      gearType = GearType.shoe;

  final String name;
  final String brand;
  final String model;
  final String initialDistance;
  final String notes;
  final DateTime? startDate;
  final GearType gearType;

  @override
  bool operator ==(Object other) {
    return other is _GearFormSnapshot &&
        other.name == name &&
        other.brand == brand &&
        other.model == model &&
        other.initialDistance == initialDistance &&
        other.notes == notes &&
        other.startDate == startDate &&
        other.gearType == gearType;
  }

  @override
  int get hashCode => Object.hash(
    name,
    brand,
    model,
    initialDistance,
    notes,
    startDate,
    gearType,
  );
}

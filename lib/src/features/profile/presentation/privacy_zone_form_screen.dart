import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/core/presentation/button_progress_indicator.dart';
import 'package:uff/src/core/presentation/discard_changes_dialog.dart';
import 'package:uff/src/features/profile/application/privacy_zone_form_controller.dart';
import 'package:uff/src/features/profile/application/privacy_zone_location_service.dart';
import 'package:uff/src/features/profile/application/privacy_zone_providers.dart';
import 'package:uff/src/features/profile/domain/privacy_zone.dart';
import 'package:uff/src/features/profile/presentation/privacy_zone_map_preview.dart';
import 'package:uff/src/features/profile/presentation/profile_routes.dart';
import 'package:uff/src/features/profile/presentation/privacy_zone_form_recovery_state.dart';

/// Creates and edits user privacy zones.
class PrivacyZoneFormScreen extends ConsumerStatefulWidget {
  const PrivacyZoneFormScreen({this.zoneId, super.key});

  static const labelFieldKey = Key('privacy_zone_form_label_field');
  static const latitudeFieldKey = Key('privacy_zone_form_latitude_field');
  static const longitudeFieldKey = Key('privacy_zone_form_longitude_field');
  static const radiusFieldKey = Key('privacy_zone_form_radius_field');
  static const saveButtonKey = Key('privacy_zone_form_save_button');
  static const currentLocationButtonKey = Key(
    'privacy_zone_form_current_location_button',
  );
  static const submissionMessageKey = Key(
    'privacy_zone_form_submission_message',
  );
  static const currentLocationMessageKey = Key(
    'privacy_zone_form_current_location_message',
  );
  static const deleteButtonKey = Key('privacy_zone_form_delete_button');
  static const deleteCancelButtonKey = Key('privacy_zone_delete_cancel_button');
  static const deleteConfirmButtonKey = Key(
    'privacy_zone_delete_confirm_button',
  );
  static const missingZoneStateKey = Key(
    'privacy_zone_form_missing_zone_state',
  );
  static const loadErrorStateKey = Key('privacy_zone_form_load_error_state');
  static const radiusSliderKey = Key('privacy_zone_form_radius_slider');
  static const radiusLabelKey = Key('privacy_zone_form_radius_label');

  final String? zoneId;

  bool get isEditMode => zoneId != null;

  @override
  ConsumerState<PrivacyZoneFormScreen> createState() =>
      _PrivacyZoneFormScreenState();
}

/// TODO: Document _PrivacyZoneFormScreenState.
class _PrivacyZoneFormScreenState extends ConsumerState<PrivacyZoneFormScreen> {
  final _labelController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _radiusController = TextEditingController();
  final _radiusFocusNode = FocusNode();

  String? _prefilledZoneId;
  String? _submissionMessage;
  String? _currentLocationMessage;
  bool _isResolvingCurrentLocation = false;
  bool _allowNextPop = false;
  _PrivacyZoneFormSnapshot _savedSnapshot =
      const _PrivacyZoneFormSnapshot.empty();

  bool get _hasUnsavedChanges => _captureSnapshot() != _savedSnapshot;

  @override
  void initState() {
    super.initState();
    _labelController.addListener(_handleCoordinateInputChanged);
    _latitudeController.addListener(_handleCoordinateInputChanged);
    _longitudeController.addListener(_handleCoordinateInputChanged);
    _radiusController.addListener(_handleCoordinateInputChanged);
    _radiusFocusNode.addListener(_handleRadiusFocusChanged);
    if (_radiusController.text.isEmpty) {
      _radiusController.text = '200';
    }
    _savedSnapshot = _captureSnapshot();
  }

  @override
  void dispose() {
    _labelController.removeListener(_handleCoordinateInputChanged);
    _latitudeController.removeListener(_handleCoordinateInputChanged);
    _longitudeController.removeListener(_handleCoordinateInputChanged);
    _radiusController.removeListener(_handleCoordinateInputChanged);
    _radiusFocusNode.removeListener(_handleRadiusFocusChanged);
    _labelController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    _radiusFocusNode.dispose();
    super.dispose();
  }

  void _handleCoordinateInputChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _handleRadiusFocusChanged() {
    if (!mounted || _radiusFocusNode.hasFocus) {
      return;
    }
    final clamped = _sliderRadius.round().toString();
    if (_radiusController.text != clamped) {
      setState(() {
        _radiusController.text = clamped;
      });
    }
  }

  void _prefillFromZone(PrivacyZone zone) {
    final zoneSnapshot = _PrivacyZoneFormSnapshot.fromZone(zone);
    if (_prefilledZoneId != zone.id) {
      _prefilledZoneId = zone.id;
      _applySnapshot(zoneSnapshot);
      _savedSnapshot = zoneSnapshot;
      return;
    }

    if (_hasUnsavedChanges || _savedSnapshot == zoneSnapshot) {
      return;
    }

    _applySnapshot(zoneSnapshot);
    _savedSnapshot = zoneSnapshot;
  }

  void _navigateBackToList() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      context.go(ProfileRoutes.privacyZonesPath);
    }
  }

  Future<void> _handleSave({PrivacyZone? existingZone}) async {
    if (ref.read(privacyZoneFormControllerProvider).isSubmitting) {
      return;
    }

    final input = _parseSubmissionInput();
    if (input == null) {
      return;
    }

    final controller = ref.read(privacyZoneFormControllerProvider.notifier);
    final didSave = await _submitZone(
      controller: controller,
      input: input,
      existingZone: existingZone,
    );
    if (!mounted) {
      return;
    }

    _finishSubmission(
      success: didSave,
      failureMessage: 'Failed to save privacy zone. Please try again.',
    );
  }

  ValidatedPrivacyZoneFormInput? _parseSubmissionInput() {
    final parsedInput = parsePrivacyZoneFormInput(
      labelText: _labelController.text,
      latitudeText: _latitudeController.text,
      longitudeText: _longitudeController.text,
      radiusText: _radiusController.text,
    );
    _setSubmissionMessage(parsedInput.errorMessage);
    if (!parsedInput.isValid) {
      return null;
    }

    return parsedInput.value;
  }

  Future<bool> _submitZone({
    required PrivacyZoneFormController controller,
    required ValidatedPrivacyZoneFormInput input,
    required PrivacyZone? existingZone,
  }) async {
    if (existingZone == null) {
      return await controller.createZone(input) != null;
    }

    return controller.updateZone(existingZone: existingZone, input: input);
  }

  Future<void> _confirmDelete(String zoneId) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Privacy Zone'),
        content: const Text(
          'Are you sure you want to delete this privacy zone?',
        ),
        actions: [
          TextButton(
            key: PrivacyZoneFormScreen.deleteCancelButtonKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: PrivacyZoneFormScreen.deleteConfirmButtonKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) {
      return;
    }

    await _deleteZone(zoneId);
  }

  Future<void> _deleteZone(String zoneId) async {
    if (ref.read(privacyZoneFormControllerProvider).isSubmitting) {
      return;
    }

    _setSubmissionMessage(null);

    final didDelete = await ref
        .read(privacyZoneFormControllerProvider.notifier)
        .deleteZone(zoneId);
    if (!mounted) {
      return;
    }

    _finishSubmission(
      success: didDelete,
      failureMessage: 'Failed to delete privacy zone. Please try again.',
    );
  }

  Future<void> _useCurrentLocation() async {
    if (_isResolvingCurrentLocation ||
        ref.read(privacyZoneFormControllerProvider).isSubmitting) {
      return;
    }

    setState(() {
      _isResolvingCurrentLocation = true;
      _currentLocationMessage = null;
    });

    PrivacyZoneCurrentLocationResult locationResult;
    try {
      locationResult = await ref
          .read(privacyZoneLocationServiceProvider)
          .fetchCurrentLocation();
    } on Object {
      locationResult = const PrivacyZoneCurrentLocationResult.failure(
        PrivacyZoneCurrentLocationFailure.lookupFailed,
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isResolvingCurrentLocation = false;
    });

    if (locationResult.isSuccess) {
      _applyCoordinates(locationResult.coordinates!);
      return;
    }

    setState(() {
      _currentLocationMessage = _locationFailureMessage(
        locationResult.failure!,
      );
    });
  }

  void _setSubmissionMessage(String? message) {
    setState(() {
      _submissionMessage = message;
    });
  }

  void _finishSubmission({
    required bool success,
    required String failureMessage,
  }) {
    if (success) {
      _savedSnapshot = _captureSnapshot();
      _navigateBackToList();
      return;
    }

    _setSubmissionMessage(_controllerErrorMessage(failureMessage));
  }

  String _controllerErrorMessage(String fallback) {
    return ref.read(privacyZoneFormControllerProvider).errorMessage ?? fallback;
  }

  _PrivacyZoneFormSnapshot _captureSnapshot() {
    return _PrivacyZoneFormSnapshot(
      label: _labelController.text,
      latitude: _latitudeController.text,
      longitude: _longitudeController.text,
      radiusMeters: _radiusController.text,
    );
  }

  void _applySnapshot(_PrivacyZoneFormSnapshot snapshot) {
    _labelController.text = snapshot.label;
    _latitudeController.text = snapshot.latitude;
    _longitudeController.text = snapshot.longitude;
    _radiusController.text = snapshot.radiusMeters;
  }

  Future<void> _handlePopInvoked(bool didPop, Object? result) async {
    if (didPop || ref.read(privacyZoneFormControllerProvider).isSubmitting) {
      return;
    }

    if (!_hasUnsavedChanges) {
      return;
    }

    final shouldDiscard = await showDiscardChangesDialog(context);
    if (!shouldDiscard || !mounted) {
      return;
    }

    setState(() {
      _allowNextPop = true;
    });
    await Navigator.of(context).maybePop();
  }

  void _applyCoordinates(PrivacyZoneCoordinates coordinates) {
    setState(() {
      _latitudeController.text = coordinates.latitude.toStringAsFixed(6);
      _longitudeController.text = coordinates.longitude.toStringAsFixed(6);
    });
  }

  String _locationFailureMessage(PrivacyZoneCurrentLocationFailure failure) {
    switch (failure) {
      case PrivacyZoneCurrentLocationFailure.permissionDenied:
        return 'Location permission denied. Enable it to autofill coordinates.';
      case PrivacyZoneCurrentLocationFailure.permissionDeniedForever:
        return 'Location permission is permanently denied. Update app settings to autofill coordinates.';
      case PrivacyZoneCurrentLocationFailure.lookupFailed:
        return 'Unable to read current location. Please enter coordinates manually.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(privacyZoneFormControllerProvider);
    final isMutationInFlight = controllerState.isSubmitting;
    final canPop =
        _allowNextPop || (!isMutationInFlight && !_hasUnsavedChanges);
    final zoneId = widget.zoneId;
    final selectedZoneAsync = zoneId == null
        ? null
        : ref.watch(privacyZoneByIdProvider(zoneId));
    final selectedZone = selectedZoneAsync?.asData?.value;
    if (selectedZone != null) {
      _prefillFromZone(selectedZone);
    }

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: _handlePopInvoked,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isEditMode ? 'Edit Privacy Zone' : 'New Privacy Zone',
          ),
        ),
        body:
            selectedZoneAsync?.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => const PrivacyZoneFormRecoveryState(
                messageKey: PrivacyZoneFormScreen.loadErrorStateKey,
                message: 'Failed to load that privacy zone.',
              ),
              data: (zone) => zone == null
                  ? const PrivacyZoneFormRecoveryState(
                      messageKey: PrivacyZoneFormScreen.missingZoneStateKey,
                      message: 'Unable to find that privacy zone.',
                    )
                  : _buildFormBody(
                      controllerState: controllerState,
                      existingZone: zone,
                    ),
            ) ??
            _buildFormBody(controllerState: controllerState),
      ),
    );
  }

  Widget _buildFormBody({
    required PrivacyZoneFormState controllerState,
    PrivacyZone? existingZone,
  }) {
    final previewCoordinates = parsePrivacyZonePreviewCoordinates(
      latitudeText: _latitudeController.text,
      longitudeText: _longitudeController.text,
    );

    return Column(
      children: [
        Expanded(
          child: Form(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              // This settings form has a fixed, small number of controls.
              // Building the whole column keeps the text-controller single
              // source of truth visible to validation and tests even when the
              // map pushes manual fallback fields below the first viewport.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildLabelField(),
                  const SizedBox(height: 12),
                  _buildMapPreview(previewCoordinates),
                  const SizedBox(height: 12),
                  _buildRadiusSlider(),
                  const SizedBox(height: 12),
                  _buildCurrentLocationButton(controllerState),
                  if (_currentLocationMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _currentLocationMessage!,
                      key: PrivacyZoneFormScreen.currentLocationMessageKey,
                    ),
                  ],
                  const SizedBox(height: 12),
                  ..._buildManualCoordinateFields(),
                  if (_submissionMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _submissionMessage!,
                      key: PrivacyZoneFormScreen.submissionMessageKey,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (widget.isEditMode) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      key: PrivacyZoneFormScreen.deleteButtonKey,
                      onPressed:
                          controllerState.isSubmitting || existingZone == null
                          ? null
                          : () => _confirmDelete(existingZone.id),
                      child: const Text('Delete Privacy Zone'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // The map-first form is intentionally tall. Keep the final action
        // visible so map placement does not make saving depend on hidden scroll
        // position, while the form fields remain the validation source of truth.
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _buildSaveButton(
              controllerState: controllerState,
              existingZone: existingZone,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabelField() {
    return TextFormField(
      key: PrivacyZoneFormScreen.labelFieldKey,
      controller: _labelController,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(labelText: 'Label'),
    );
  }

  double get _sliderRadius {
    final parsed = double.tryParse(_radiusController.text) ?? 200;
    final clamped = parsed.clamp(50.0, 1000.0);
    return (clamped / 50).round() * 50.0;
  }

  Widget _buildRadiusSlider() {
    final radiusValue = _sliderRadius;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Radius: ${radiusValue.round()} m',
          key: PrivacyZoneFormScreen.radiusLabelKey,
        ),
        Slider(
          key: PrivacyZoneFormScreen.radiusSliderKey,
          value: radiusValue,
          min: 50,
          max: 1000,
          divisions: 19,
          onChanged: (value) {
            setState(() {
              _radiusController.text = value.round().toString();
            });
          },
        ),
      ],
    );
  }

  List<Widget> _buildManualCoordinateFields() {
    return [
      TextFormField(
        key: PrivacyZoneFormScreen.latitudeFieldKey,
        controller: _latitudeController,
        textInputAction: TextInputAction.next,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: const InputDecoration(labelText: 'Latitude'),
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: PrivacyZoneFormScreen.longitudeFieldKey,
        controller: _longitudeController,
        textInputAction: TextInputAction.next,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: const InputDecoration(labelText: 'Longitude'),
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: PrivacyZoneFormScreen.radiusFieldKey,
        controller: _radiusController,
        focusNode: _radiusFocusNode,
        textInputAction: TextInputAction.done,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Radius (m)'),
      ),
      const SizedBox(height: 12),
    ];
  }

  Widget _buildCurrentLocationButton(PrivacyZoneFormState controllerState) {
    final isCurrentLocationDisabled =
        controllerState.isSubmitting || _isResolvingCurrentLocation;
    return OutlinedButton(
      key: PrivacyZoneFormScreen.currentLocationButtonKey,
      onPressed: isCurrentLocationDisabled ? null : _useCurrentLocation,
      child: const Text('Use Current Location'),
    );
  }

  Widget _buildMapPreview(PrivacyZonePreviewCoordinates? previewCoordinates) {
    return PrivacyZoneMapPreview(
      latitude: previewCoordinates?.latitude,
      longitude: previewCoordinates?.longitude,
      radiusMeters: _sliderRadius.round(),
      // Map taps, current-location autofill, and manual text edits all write
      // through the same controllers. That keeps save validation and dirty-form
      // detection tied to one source of truth instead of separate map state.
      onCoordinateSelected: (lat, lon) => _applyCoordinates(
        PrivacyZoneCoordinates(latitude: lat, longitude: lon),
      ),
    );
  }

  Widget _buildSaveButton({
    required PrivacyZoneFormState controllerState,
    required PrivacyZone? existingZone,
  }) {
    return ElevatedButton(
      key: PrivacyZoneFormScreen.saveButtonKey,
      onPressed: controllerState.isSubmitting
          ? null
          : () => _handleSave(existingZone: existingZone),
      child: controllerState.isSubmitting
          ? const ButtonProgressIndicator(size: 16)
          : Text(widget.isEditMode ? 'Save Changes' : 'Save Privacy Zone'),
    );
  }
}

/// Captures editable privacy-zone fields to detect unsaved changes.
@immutable
class _PrivacyZoneFormSnapshot {
  const _PrivacyZoneFormSnapshot({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  const _PrivacyZoneFormSnapshot.empty()
    : label = '',
      latitude = '',
      longitude = '',
      radiusMeters = '200';

  factory _PrivacyZoneFormSnapshot.fromZone(PrivacyZone zone) {
    return _PrivacyZoneFormSnapshot(
      label: zone.label,
      latitude: zone.latitude.toString(),
      longitude: zone.longitude.toString(),
      radiusMeters: zone.radiusMeters.toString(),
    );
  }

  final String label;
  final String latitude;
  final String longitude;
  final String radiusMeters;

  @override
  bool operator ==(Object other) {
    return other is _PrivacyZoneFormSnapshot &&
        other.label == label &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.radiusMeters == radiusMeters;
  }

  @override
  int get hashCode => Object.hash(label, latitude, longitude, radiusMeters);
}

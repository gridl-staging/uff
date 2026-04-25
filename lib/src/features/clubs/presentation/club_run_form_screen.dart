import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/core/presentation/button_progress_indicator.dart';
import 'package:uff/src/core/presentation/discard_changes_dialog.dart';
import 'package:uff/src/features/clubs/application/club_providers.dart';
import 'package:uff/src/features/clubs/data/club_repository.dart';
import 'package:uff/src/features/clubs/presentation/club_routes.dart';

/// Schedules a new club run.
class ClubRunFormScreen extends ConsumerStatefulWidget {
  const ClubRunFormScreen({
    required this.clubId,
    this.initialDate,
    this.initialTime,
    super.key,
  });

  static const titleFieldKey = Key('club_run_form_title_field');
  static const descriptionFieldKey = Key('club_run_form_description_field');
  static const meetingPointFieldKey = Key('club_run_form_meeting_point_field');
  static const distanceFieldKey = Key('club_run_form_distance_field');
  static const paceFieldKey = Key('club_run_form_pace_field');
  static const datePickerButtonKey = Key('club_run_form_date_picker_button');
  static const timePickerButtonKey = Key('club_run_form_time_picker_button');
  static const saveButtonKey = Key('club_run_form_save_button');

  final String clubId;

  /// Optional initial date for the scheduled run. Defaults to tomorrow.
  final DateTime? initialDate;

  /// Optional initial time for the scheduled run. Defaults to 8:00 AM.
  final TimeOfDay? initialTime;

  @override
  ConsumerState<ClubRunFormScreen> createState() => _ClubRunFormScreenState();
}

/// TODO: Document _ClubRunFormScreenState.
class _ClubRunFormScreenState extends ConsumerState<ClubRunFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _meetingPointController = TextEditingController();
  final _distanceController = TextEditingController();
  final _paceController = TextEditingController();

  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  bool _isSaving = false;
  bool _allowNextPop = false;
  _ClubRunFormSnapshot _savedSnapshot = const _ClubRunFormSnapshot.empty();

  Iterable<TextEditingController> get _controllers => <TextEditingController>[
    _titleController,
    _descriptionController,
    _meetingPointController,
    _distanceController,
    _paceController,
  ];

  bool get _hasUnsavedChanges => _captureSnapshot() != _savedSnapshot;
  bool get _canPop => _allowNextPop || (!_isSaving && !_hasUnsavedChanges);

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_handleFormValueChanged);
    }

    if (widget.initialDate != null) {
      _selectedDate = widget.initialDate!;
    } else {
      // Default to tomorrow.
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      _selectedDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    }
    _selectedTime = widget.initialTime ?? const TimeOfDay(hour: 8, minute: 0);
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

  bool get _hasRequiredFields {
    return _titleController.text.trim().isNotEmpty;
  }

  DateTime _buildScheduledAt() {
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
  }

  double? _parseDistanceKm() {
    final text = _distanceController.text.trim();
    if (text.isEmpty) return null;
    final km = double.tryParse(text);
    if (km == null || km <= 0) return null;
    // Convert km to meters.
    return km * 1000;
  }

  Future<void> _save() async {
    if (_isSaving || !_hasValidForm()) return;

    final scheduledAt = _buildScheduledAt();
    if (!scheduledAt.isAfter(DateTime.now())) {
      _showErrorSnackBar('Scheduled time must be in the future.');
      return;
    }

    await _runMutation(
      action: () async {
        final input = CreateClubRunInput(
          clubId: widget.clubId,
          title: _titleController.text.trim(),
          scheduledAt: scheduledAt,
          description: normalizeOptionalClubText(_descriptionController.text),
          meetingPointName: normalizeOptionalClubText(
            _meetingPointController.text,
          ),
          distanceMeters: _parseDistanceKm(),
          paceDescription: normalizeOptionalClubText(_paceController.text),
        );
        await ref
            .read(clubMutationControllerProvider.notifier)
            .createClubRun(input);
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
      _showErrorSnackBar('Unable to schedule run. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  _ClubRunFormSnapshot _captureSnapshot() {
    return _ClubRunFormSnapshot(
      title: _titleController.text,
      description: _descriptionController.text,
      meetingPoint: _meetingPointController.text,
      distance: _distanceController.text,
      pace: _paceController.text,
      date: _selectedDate,
      time: _selectedTime,
    );
  }

  void _navigateBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    context.go(ClubRoutes.clubDetailPath(widget.clubId));
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    // Clamp initialDate to today if it's in the past (possible via
    // initialDate constructor parameter) to satisfy showDatePicker's
    // assertion that initialDate >= firstDate.
    final effectiveInitial = _selectedDate.isBefore(now)
        ? DateTime(now.year, now.month, now.day)
        : _selectedDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: effectiveInitial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: _handlePopInvoked,
      child: Scaffold(
        appBar: AppBar(title: const Text('Schedule Run')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                key: ClubRunFormScreen.titleFieldKey,
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Title is required';
                  }
                  return null;
                },
              ),
              _buildDateTimePickerRow(localizations),
              const SizedBox(height: 16),
              TextFormField(
                key: ClubRunFormScreen.meetingPointFieldKey,
                controller: _meetingPointController,
                decoration: const InputDecoration(
                  labelText: 'Meeting point (optional)',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: ClubRunFormScreen.descriptionFieldKey,
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: ClubRunFormScreen.distanceFieldKey,
                controller: _distanceController,
                decoration: const InputDecoration(
                  labelText: 'Distance in km (optional)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final km = double.tryParse(value.trim());
                  if (km == null || km <= 0) {
                    return 'Enter a valid distance';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: ClubRunFormScreen.paceFieldKey,
                controller: _paceController,
                decoration: const InputDecoration(
                  labelText: 'Pace description (optional)',
                ),
              ),
              const SizedBox(height: 24),
              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateTimePickerRow(MaterialLocalizations localizations) {
    return Column(
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: ClubRunFormScreen.datePickerButtonKey,
                onPressed: _isSaving ? null : _pickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(localizations.formatMediumDate(_selectedDate)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: ClubRunFormScreen.timePickerButtonKey,
                onPressed: _isSaving ? null : _pickTime,
                icon: const Icon(Icons.access_time),
                label: Text(_selectedTime.format(context)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      key: ClubRunFormScreen.saveButtonKey,
      onPressed: _isSaving || !_hasRequiredFields ? null : _save,
      child: _isSaving
          ? const ButtonProgressIndicator()
          : const Text('Schedule Run'),
    );
  }
}

/// Captures form state for unsaved-changes detection.
@immutable
class _ClubRunFormSnapshot {
  const _ClubRunFormSnapshot({
    required this.title,
    required this.description,
    required this.meetingPoint,
    required this.distance,
    required this.pace,
    required this.date,
    required this.time,
  });

  const _ClubRunFormSnapshot.empty()
    : title = '',
      description = '',
      meetingPoint = '',
      distance = '',
      pace = '',
      date = null,
      time = null;

  final String title;
  final String description;
  final String meetingPoint;
  final String distance;
  final String pace;
  final DateTime? date;
  final TimeOfDay? time;

  @override
  bool operator ==(Object other) {
    return other is _ClubRunFormSnapshot &&
        other.title == title &&
        other.description == description &&
        other.meetingPoint == meetingPoint &&
        other.distance == distance &&
        other.pace == pace &&
        other.date == date &&
        other.time == time;
  }

  @override
  int get hashCode =>
      Object.hash(title, description, meetingPoint, distance, pace, date, time);
}

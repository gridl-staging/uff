import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uff/src/core/presentation/button_progress_indicator.dart';
import 'package:uff/src/features/activity_tracking/application/activity_tracking_providers.dart';
import 'package:uff/src/features/activity_tracking/application/tracking_dependencies.dart';
import 'package:uff/src/features/activity_tracking/domain/tracking_domain.dart';

/// TODO: Document ActivityMetadataCard.
class ActivityMetadataCard extends ConsumerStatefulWidget {
  const ActivityMetadataCard({
    required this.detail,
    required this.onSaved,
    required this.onPendingChangesChanged,
    this.showInlineSaveButton = true,
    super.key,
  });

  static const titleFieldKey = Key('detail_title_field');
  static const descriptionFieldKey = Key('detail_description_field');
  static const saveButtonKey = Key('detail_save_button');
  static const visibilitySegmentedButtonKey = Key(
    'detail_visibility_segmented_button',
  );

  final ActivityDetailData detail;
  final VoidCallback onSaved;
  final ValueChanged<bool> onPendingChangesChanged;
  final bool showInlineSaveButton;

  @override
  ConsumerState<ActivityMetadataCard> createState() =>
      ActivityMetadataCardState();
}

/// TODO: Document ActivityMetadataCardState.
class ActivityMetadataCardState extends ConsumerState<ActivityMetadataCard> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  int? _sessionIdForControllers;
  String _currentVisibility = publicTrackingSessionVisibility;
  bool _didChangeVisibilitySelection = false;
  String? _savedMetadataPersistedVisibility;
  _ActivityMetadataSnapshot? _savedMetadataSnapshot;
  bool _isSavingDetails = false;
  bool? _lastReportedPendingChanges;

  bool get hasPendingChanges {
    final savedSnapshot = _savedMetadataSnapshot;
    final currentSnapshot = _currentMetadataSnapshot;
    if (savedSnapshot == null || currentSnapshot == null) {
      return false;
    }

    return currentSnapshot != savedSnapshot;
  }

  bool get isSaving => _isSavingDetails;
  bool get canSave => !_isSavingDetails && hasPendingChanges;

  _ActivityMetadataSnapshot? get _currentMetadataSnapshot {
    if (_savedMetadataSnapshot == null) {
      return null;
    }

    return _captureMetadataSnapshot(
      persistedVisibility: _savedMetadataPersistedVisibility,
    );
  }

  @override
  void initState() {
    super.initState();
    _syncControllers(widget.detail, notifyParent: true);
  }

  @override
  void didUpdateWidget(covariant ActivityMetadataCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers(widget.detail, notifyParent: true);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Title & Notes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              key: ActivityMetadataCard.titleFieldKey,
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Activity title',
              ),
              onChanged: (_) {
                setState(() {});
                _notifyPendingChangesChanged();
              },
            ),
            const SizedBox(height: 8),
            TextField(
              key: ActivityMetadataCard.descriptionFieldKey,
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
              ),
              minLines: 2,
              maxLines: 4,
              onChanged: (_) {
                setState(() {});
                _notifyPendingChangesChanged();
              },
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              key: ActivityMetadataCard.visibilitySegmentedButtonKey,
              segments: const [
                ButtonSegment<String>(
                  value: publicTrackingSessionVisibility,
                  label: Text('Public'),
                ),
                ButtonSegment<String>(
                  value: followersTrackingSessionVisibility,
                  label: Text('Followers'),
                ),
                ButtonSegment<String>(
                  value: privateTrackingSessionVisibility,
                  label: Text('Private'),
                ),
              ],
              selected: {_currentVisibility},
              onSelectionChanged: (selection) {
                if (selection.isEmpty) {
                  return;
                }
                setState(() {
                  _didChangeVisibilitySelection = true;
                  _currentVisibility = selection.first;
                });
                _notifyPendingChangesChanged();
              },
            ),
            const SizedBox(height: 8),
            if (widget.showInlineSaveButton)
              ElevatedButton(
                key: ActivityMetadataCard.saveButtonKey,
                onPressed: canSave ? saveMetadata : null,
                child: _isSavingDetails
                    ? const ButtonProgressIndicator(size: 16)
                    : const Text('Save details'),
              ),
          ],
        ),
      ),
    );
  }

  Future<bool> saveMetadata() async {
    if (_isSavingDetails) {
      return false;
    }

    setState(() {
      _isSavingDetails = true;
    });
    _notifyPendingChangesChanged(force: true);

    final detail = widget.detail;
    final repository = ref.read(trackingRepositoryProvider);
    final visibilityToPersist = _visibilityToPersist(
      _savedMetadataPersistedVisibility ?? detail.session.visibility,
    );
    final updatedSession = detail.session.copyWith(
      visibility: visibilityToPersist,
      updates: _buildMetadataUpdates(),
    );
    var didSave = false;

    try {
      await repository.saveSession(updatedSession);
      _rememberSavedMetadata(
        snapshot: _captureMetadataSnapshot(
          persistedVisibility: visibilityToPersist,
        ),
        persistedVisibility: visibilityToPersist,
      );
      ref.invalidate(activityDetailProvider(detail.session.id));
      didSave = true;
    } on Object {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save activity details. Please try again.'),
        ),
      );
    }

    if (!mounted) {
      return false;
    }

    setState(() {
      _isSavingDetails = false;
    });
    _notifyPendingChangesChanged(force: true);
    if (didSave) {
      widget.onSaved();
    }
    return didSave;
  }

  TrackingSessionRecordUpdates _buildMetadataUpdates() {
    final title = _normalizeMetadataText(_titleController.text);
    final description = _normalizeMetadataText(_descriptionController.text);

    return TrackingSessionRecordUpdates(
      title: title,
      clearTitle: title == null,
      description: description,
      clearDescription: description == null,
    );
  }

  _ActivityMetadataSnapshot _captureMetadataSnapshot({
    required String? persistedVisibility,
  }) {
    final updates = _buildMetadataUpdates();
    return _ActivityMetadataSnapshot(
      title: updates.title,
      description: updates.description,
      visibility: _visibilityToPersist(persistedVisibility),
    );
  }

  String? _visibilityToPersist(String? persistedVisibility) {
    final normalizedPersistedVisibility = normalizeTrackingSessionVisibility(
      persistedVisibility,
    );
    if (_currentVisibility != normalizedPersistedVisibility) {
      return _currentVisibility;
    }

    if (supportedTrackingSessionVisibilityOrNull(persistedVisibility) == null &&
        !_didChangeVisibilitySelection) {
      return persistedVisibility;
    }

    return _currentVisibility;
  }

  void _syncControllers(
    ActivityDetailData detail, {
    required bool notifyParent,
  }) {
    final session = detail.session;
    final sessionSnapshot = _ActivityMetadataSnapshot.fromSession(session);
    final isSameSession = _sessionIdForControllers == session.id;

    if (isSameSession) {
      if (hasPendingChanges) {
        return;
      }

      if (_savedMetadataSnapshot == sessionSnapshot &&
          _savedMetadataPersistedVisibility == session.visibility) {
        return;
      }
    } else {
      _sessionIdForControllers = session.id;
    }

    _loadSessionMetadata(session, sessionSnapshot);
    if (notifyParent) {
      _notifyPendingChangesChanged(force: true, deferToNextFrame: true);
    }
  }

  void _loadSessionMetadata(
    TrackingSessionRecord session,
    _ActivityMetadataSnapshot sessionSnapshot,
  ) {
    _titleController.text = session.title ?? '';
    _descriptionController.text = session.description ?? '';
    _currentVisibility = normalizeTrackingSessionVisibility(session.visibility);
    _rememberSavedMetadata(
      snapshot: sessionSnapshot,
      persistedVisibility: session.visibility,
    );
  }

  void _rememberSavedMetadata({
    required _ActivityMetadataSnapshot snapshot,
    required String? persistedVisibility,
  }) {
    _didChangeVisibilitySelection = false;
    _savedMetadataPersistedVisibility = persistedVisibility;
    _savedMetadataSnapshot = snapshot;
  }

  void _notifyPendingChangesChanged({
    bool force = false,
    bool deferToNextFrame = false,
  }) {
    final pendingChanges = hasPendingChanges;
    if (!force && _lastReportedPendingChanges == pendingChanges) {
      return;
    }
    _lastReportedPendingChanges = pendingChanges;

    if (!deferToNextFrame) {
      widget.onPendingChangesChanged(pendingChanges);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onPendingChangesChanged(pendingChanges);
    });
  }
}

String? _normalizeMetadataText(String? value) {
  final trimmedValue = value?.trim() ?? '';
  return trimmedValue.isEmpty ? null : trimmedValue;
}

/// TODO: Document _ActivityMetadataSnapshot.
@immutable
class _ActivityMetadataSnapshot {
  const _ActivityMetadataSnapshot({
    required this.title,
    required this.description,
    required this.visibility,
  });

  factory _ActivityMetadataSnapshot.fromSession(TrackingSessionRecord session) {
    return _ActivityMetadataSnapshot(
      title: _normalizeMetadataText(session.title),
      description: _normalizeMetadataText(session.description),
      visibility: session.visibility,
    );
  }

  final String? title;
  final String? description;
  final String? visibility;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _ActivityMetadataSnapshot &&
        other.title == title &&
        other.description == description &&
        other.visibility == visibility;
  }

  @override
  int get hashCode => Object.hash(title, description, visibility);
}

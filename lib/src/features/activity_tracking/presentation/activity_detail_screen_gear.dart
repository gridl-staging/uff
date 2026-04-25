part of 'activity_detail_screen.dart';

/// Gear assignment card, content, and save logic for the activity detail
/// screen. Extracted as a part to keep file sizes under the 800-line limit.
extension _ActivityDetailGearSection on _ActivityDetailScreenState {
  Widget _buildGearAssignmentCard(
    BuildContext context,
    AsyncValue<ActivityDetailGearState> gearState,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Gear', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            gearState.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Unable to load gear options right now.'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    key: ActivityDetailScreen.gearRetryButtonKey,
                    onPressed: () {
                      ref.invalidate(
                        activityDetailGearProvider(widget.activityId),
                      );
                    },
                    child: const Text('Try again'),
                  ),
                ],
              ),
              data: _buildGearAssignmentContent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGearAssignmentContent(ActivityDetailGearState state) {
    if (!state.isEditable) {
      return Text(
        state.nonEditableMessage ?? 'Gear is unavailable right now.',
      );
    }

    final dropdownItems = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(child: Text('No gear')),
      ...state.selectableGear.map(
        (item) => DropdownMenuItem<String?>(
          value: item.id,
          child: Text(item.name),
        ),
      ),
    ];

    final canSave = !_isSavingGearAssignment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String?>(
          key: ActivityDetailScreen.gearDropdownKey,
          // ignore: deprecated_member_use, reason: controlled value keeps UI in sync with provider state
          value: state.selectedGearId,
          items: dropdownItems,
          decoration: const InputDecoration(labelText: 'Assigned gear'),
          onChanged: canSave
              ? (selectedGearId) {
                  _saveGearAssignment(state, selectedGearId);
                }
              : null,
        ),
        if (state.selectableGear.isEmpty) ...[
          const SizedBox(height: 8),
          const Text('No active shoes or bikes available.'),
        ],
        if (state.hasStaleAssignedGear) ...[
          const SizedBox(height: 8),
          const Text(
            'Previously assigned gear is unavailable. Choose a new option.',
          ),
        ],
      ],
    );
  }

  Future<void> _saveGearAssignment(
    ActivityDetailGearState state,
    String? selectedGearId,
  ) async {
    if (_isSavingGearAssignment) {
      return;
    }
    if (!state.isEditable || state.remoteActivityId == null) {
      return;
    }
    if (!_isSelectableGearId(state, selectedGearId)) {
      _showSnackBarMessage('Unable to save gear assignment. Please try again.');
      return;
    }

    // ignore: invalid_use_of_protected_member, reason: part-file extension on State subclass
    setState(() {
      _isSavingGearAssignment = true;
    });

    late final String saveResultMessage;

    try {
      await ref
          .read(activityGearAssignmentRepositoryProvider)
          .updateAssignedGearId(state.remoteActivityId!, selectedGearId);
      ref
        ..invalidate(activityDetailProvider(widget.activityId))
        ..invalidate(gearListProvider);
      saveResultMessage = 'Gear assignment updated.';
    } on Object {
      saveResultMessage = 'Unable to save gear assignment. Please try again.';
    }

    if (!mounted) {
      return;
    }

    // ignore: invalid_use_of_protected_member, reason: part-file extension on State subclass
    setState(() {
      _isSavingGearAssignment = false;
    });
    _showSnackBarMessage(saveResultMessage);
  }

  bool _isSelectableGearId(
    ActivityDetailGearState state,
    String? selectedGearId,
  ) {
    return selectedGearId == null ||
        state.selectableGear.any((item) => item.id == selectedGearId);
  }
}

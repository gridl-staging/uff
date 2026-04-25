import 'package:flutter/material.dart';

const discardChangesDialogTitle = 'Discard changes?';
const discardChangesDialogMessage = 'You have unsaved changes.';
const discardChangesDialogStayAction = 'Stay';
const discardChangesDialogDiscardAction = 'Discard';

Future<bool> showDiscardChangesDialog(BuildContext context) async {
  final shouldDiscard = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text(discardChangesDialogTitle),
      content: const Text(discardChangesDialogMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(discardChangesDialogStayAction),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(discardChangesDialogDiscardAction),
        ),
      ],
    ),
  );

  return shouldDiscard ?? false;
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// TODO(uff): Document CopyableErrorText.
/// TODO: Document CopyableErrorText.
class CopyableErrorText extends StatelessWidget {
  const CopyableErrorText(
    this.message, {
    super.key,
    this.style,
    this.textAlign,
    this.copiedFeedback = 'Copied error message.',
  });

  final String message;
  final TextStyle? style;
  final TextAlign? textAlign;
  final String copiedFeedback;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _copyMessage(context),
      child: Text(
        message,
        textAlign: textAlign,
        style: style,
      ),
    );
  }

  Future<void> _copyMessage(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message));

    if (!context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(copiedFeedback)),
      );
  }
}

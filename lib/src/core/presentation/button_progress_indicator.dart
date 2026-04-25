import 'package:flutter/material.dart';

/// A compact circular progress indicator sized for use inside buttons.
///
/// Replaces the repeated pattern of wrapping a [CircularProgressIndicator]
/// in a [SizedBox] with a thin stroke width.
class ButtonProgressIndicator extends StatelessWidget {
  const ButtonProgressIndicator({this.size = 18, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

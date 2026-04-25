import 'package:flutter/material.dart';
import 'package:uff/src/core/presentation/copyable_error_text.dart';

const activityDetailErrorMessageKey = Key('detail_error_message');
const activityDetailRetryButtonKey = Key('detail_retry_button');

class ActivityDetailRouteScaffold extends StatelessWidget {
  const ActivityDetailRouteScaffold({required this.body, super.key});

  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity Detail')),
      body: body,
    );
  }
}

/// TODO: Document ActivityDetailRetryableMessage.
class ActivityDetailRetryableMessage extends StatelessWidget {
  const ActivityDetailRetryableMessage({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CopyableErrorText(message, key: activityDetailErrorMessageKey),
          const SizedBox(height: 12),
          ElevatedButton(
            key: activityDetailRetryButtonKey,
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _recoveryTitle = 'Unable to Open Page';
const _primaryActionLabel = 'Go to Home';
const _secondaryActionLabel = 'Go Back';
const _retryActionLabel = 'Retry';

/// Shared route-level recovery UI for social detail routes.
class SocialRouteRecoveryScaffold extends StatelessWidget {
  const SocialRouteRecoveryScaffold({
    required this.stateKey,
    required this.message,
    this.showLoadingIndicator = false,
    this.onRetry,
    super.key,
  });

  static const retryButtonKey = Key('social_route_recovery_retry_button');
  static const goHomeButtonKey = Key('social_route_recovery_go_home_button');
  static const goBackButtonKey = Key('social_route_recovery_go_back_button');

  final Key stateKey;
  final String message;
  final bool showLoadingIndicator;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    final canPop = router?.canPop() ?? Navigator.canPop(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(_recoveryTitle),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    key: stateKey,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showLoadingIndicator) ...[
                        const Align(
                          child: CircularProgressIndicator(),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(message),
                      const SizedBox(height: 16),
                      if (onRetry != null) ...[
                        OutlinedButton(
                          key: retryButtonKey,
                          onPressed: onRetry,
                          child: const Text(_retryActionLabel),
                        ),
                        const SizedBox(height: 8),
                      ],
                      FilledButton(
                        key: goHomeButtonKey,
                        onPressed: router == null
                            ? null
                            : () => context.go('/home'),
                        child: const Text(_primaryActionLabel),
                      ),
                      if (canPop)
                        TextButton(
                          key: goBackButtonKey,
                          onPressed: router?.canPop() ?? false
                              ? router!.pop
                              : () => Navigator.of(context).maybePop(),
                          child: const Text(_secondaryActionLabel),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

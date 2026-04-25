import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/profile/presentation/profile_routes.dart';

/// TODO: Document PrivacyZoneFormRecoveryState.
class PrivacyZoneFormRecoveryState extends StatelessWidget {
  const PrivacyZoneFormRecoveryState({
    required this.messageKey,
    required this.message,
    super.key,
  });

  final Key messageKey;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, key: messageKey, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => context.go(ProfileRoutes.privacyZonesPath),
            child: const Text('Back to Privacy Zones'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uff/src/features/legal/presentation/legal_routes.dart';

/// Shared legal-link row used on authentication surfaces.
class AuthLegalLinks extends StatelessWidget {
  const AuthLegalLinks({
    required this.privacyPolicyButtonKey,
    required this.termsOfServiceButtonKey,
    this.isLoading = false,
    super.key,
  });

  final Key privacyPolicyButtonKey;
  final Key termsOfServiceButtonKey;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        TextButton(
          key: privacyPolicyButtonKey,
          onPressed: isLoading
              ? null
              : () => context.push(LegalRoutes.privacyPath),
          child: const Text(LegalRoutes.privacyTitle),
        ),
        const Text('|'),
        TextButton(
          key: termsOfServiceButtonKey,
          onPressed: isLoading
              ? null
              : () => context.push(LegalRoutes.termsPath),
          child: const Text(LegalRoutes.termsTitle),
        ),
      ],
    );
  }
}

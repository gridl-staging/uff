/// Shared legal route and asset identifiers.
///
/// Keeping these constants in one place prevents route or asset-path drift
/// between router registration, auth entry points, and tests.
abstract final class LegalRoutes {
  static const privacyPath = '/legal/privacy';
  static const termsPath = '/legal/terms';

  static const privacyAssetPath = 'docs/privacy_policy.md';
  static const termsAssetPath = 'docs/terms_of_service.md';

  static const privacyTitle = 'Privacy Policy';
  static const termsTitle = 'Terms of Service';
}

// Wrapper to run the integration_test/ file on the Dart VM without a device.
// The actual test file lives in integration_test/ and uses relative imports
// that resolve correctly via Dart's URI-based import resolution.
import '../../integration_test/privacy_zone_masking_smoke_test.dart' as masking;

void main() => masking.main();

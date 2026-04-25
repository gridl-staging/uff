// Wrapper to run the integration_test/ file on the Dart VM without a device.
// The actual test file lives in integration_test/ and uses relative imports
// that resolve correctly via Dart's URI-based import resolution.
import '../../integration_test/auth_lifecycle_smoke_test.dart' as smoke_test;

void main() => smoke_test.main();

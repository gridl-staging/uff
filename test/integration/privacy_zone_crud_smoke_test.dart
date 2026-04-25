// Wrapper to run the integration_test/ file on the Dart VM without a device.
// The actual test file lives in integration_test/ and uses relative imports
// that resolve correctly via Dart's URI-based import resolution.
import '../../integration_test/privacy_zone_crud_smoke_test.dart' as crud_test;

void main() => crud_test.main();

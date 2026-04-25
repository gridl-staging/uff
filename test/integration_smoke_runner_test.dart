// Temporary runner to execute integration smoke tests on the Dart VM
// without requiring a device (Flutter forces device mode for integration_test/).
// These tests are pure Dart HTTP tests against Supabase — no UI or platform
// channels needed.
//
// Usage:
//   RUN_SUPABASE_SMOKE_TESTS=true SUPABASE_LOCAL_URL=http://localhost:54321 \
//     flutter test test/integration_smoke_runner_test.dart --reporter expanded
//
// Delete this file after the integration test run is validated.

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/activity_deletion_smoke_test.dart' as t01;
import '../integration_test/activity_photo_rls_smoke_test.dart' as t02;
import '../integration_test/activity_sync_smoke_test.dart' as t03;
import '../integration_test/auth_lifecycle_smoke_test.dart' as t04;
import '../integration_test/gear_rls_smoke_test.dart' as t05;
import '../integration_test/import_happy_path_smoke_test.dart' as t06;
import '../integration_test/privacy_zone_crud_smoke_test.dart' as t07;
import '../integration_test/privacy_zone_rls_smoke_test.dart' as t08;
import '../integration_test/profile_rls_smoke_test.dart' as t09;
import '../integration_test/profile_trigger_smoke_test.dart' as t10;
import '../integration_test/rls_cross_user_smoke_test.dart' as t11;
import '../integration_test/social_comments_smoke_test.dart' as t12;
import '../integration_test/social_feed_and_kudos_smoke_test.dart' as t13;
import '../integration_test/social_relationships_smoke_test.dart' as t14;
import '../integration_test/export_my_data_smoke_test.dart' as t15;

/// ## Test Scenarios
/// - `[positive]` Smoke runner wires all expected integration smoke suites
typedef SmokeSuiteMain = void Function();
const int _expectedSmokeSuiteCount = 15;

void main() {
  final suites = <SmokeSuiteMain>[
    t01.main,
    t02.main,
    t03.main,
    t04.main,
    t05.main,
    t06.main,
    t07.main,
    t08.main,
    t09.main,
    t10.main,
    t11.main,
    t12.main,
    t13.main,
    t14.main,
    t15.main,
  ];

  test('smoke runner wires all integration suites', () {
    expect(suites.length, _expectedSmokeSuiteCount);
  });

  for (final suiteMain in suites) {
    suiteMain();
  }
}

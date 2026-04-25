#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/patrol_cli_workarounds.sh"

failures=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  if [[ "${expected}" != "${actual}" ]]; then
    echo "FAIL: ${description} (expected '${expected}', got '${actual}')"
    failures=$((failures + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    echo "FAIL: ${description} (missing '${needle}')"
    failures=$((failures + 1))
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    echo "FAIL: ${description} (unexpected '${needle}')"
    failures=$((failures + 1))
  fi
}

setup_fixture() {
  local fixture_root
  fixture_root="$(mktemp -d)"

  mkdir -p \
    "${fixture_root}/hosted/pub.dev/patrol_cli-4.2.0/lib/src/crossplatform" \
    "${fixture_root}/hosted/pub.dev/patrol_cli-4.2.0/lib/src/commands" \
    "${fixture_root}/hosted/pub.dev/cli_completion-0.4.0/lib/src/command_runner" \
    "${fixture_root}/global_packages/patrol_cli/bin"

  cat > "${fixture_root}/hosted/pub.dev/patrol_cli-4.2.0/lib/src/crossplatform/app_options.dart" <<'DART'
List<String> buildForTestingInvocation() {
  return [
    r'OTHER_SWIFT_FLAGS=$(inherited) -D PATROL_ENABLED',
    'OTHER_CFLAGS=\$(inherited) -D FULL_ISOLATION=${fullIsolation ? 1 : 0} -D CLEAR_PERMISSIONS=${clearIOSPermissions ? 1 : 0}',
  ];
}
DART

  cat > "${fixture_root}/hosted/pub.dev/patrol_cli-4.2.0/lib/src/commands/test.dart" <<'DART'
class FlutterVersion {
  factory FlutterVersion.test() => FlutterVersion();
}

class Analytics {
  Future<void> sendCommand(FlutterVersion version, String name) async {}
}

class TestCommand {
  Future<int> run() async {
    unawaited(
      _analytics.sendCommand(FlutterVersion.fromCLI(flutterCommand), name),
    );
    return 0;
  }

  final Analytics _analytics = Analytics();
  final flutterCommand = Object();
  final name = 'test';
}
DART

  cat > "${fixture_root}/hosted/pub.dev/cli_completion-0.4.0/lib/src/command_runner/completion_command_runner.dart" <<'DART'
abstract class CompletionCommandRunner<T> {
  bool get enableAutoInstall => true;
}
DART

  touch "${fixture_root}/global_packages/patrol_cli/bin/main.dart-3.11.0.snapshot"

  printf '%s\n' "${fixture_root}"
}

test_repairs_broken_other_cflags_and_invalidates_snapshot() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  local expected_fixed_cflags="'OTHER_CFLAGS=' r'\$(inherited)' ' -D FULL_ISOLATION=\${fullIsolation ? 1 : 0} -D CLEAR_PERMISSIONS=\${clearIOSPermissions ? 1 : 0}',"
  local broken_cflags="'OTHER_CFLAGS=\$(inherited) -D FULL_ISOLATION=\${fullIsolation ? 1 : 0} -D CLEAR_PERMISSIONS=\${clearIOSPermissions ? 1 : 0}',"
  local invalid_unescaped_cflags="'OTHER_CFLAGS=\$(inherited) -D FULL_ISOLATION=\${fullIsolation ? 1 : 0} -D CLEAR_PERMISSIONS=\${clearIOSPermissions ? 1 : 0}',"

  local helper_output
  helper_output="$(
    repair_patrol_cli_ios_inherited_flag_bug "${fixture_root}" 2>&1
  )"

  local patched_contents
  patched_contents="$(cat "${fixture_root}/hosted/pub.dev/patrol_cli-4.2.0/lib/src/crossplatform/app_options.dart")"

  assert_contains "${patched_contents}" "${expected_fixed_cflags}" "helper rewrites the Patrol OTHER_CFLAGS line to use a literal inherited build setting"
  assert_not_contains "${patched_contents}" "${broken_cflags}" "helper removes the broken escaped Patrol OTHER_CFLAGS line"
  assert_not_contains "${patched_contents}" "${invalid_unescaped_cflags}" "helper does not leave Dart with an invalid unescaped dollar sign"
  assert_eq "1" "$(test -f "${fixture_root}/global_packages/patrol_cli/bin/main.dart-3.11.0.snapshot"; echo $?)" "helper removes stale global Patrol snapshot so the patched source is recompiled"
  assert_contains "${helper_output}" "Patrol CLI iOS build-flag workaround applied" "helper reports when it patches Patrol source"

  rm -rf "${fixture_root}"
}

test_is_idempotent_when_no_broken_escape_remains() {
  local fixture_root
  fixture_root="$(setup_fixture)"
  local expected_fixed_cflags="'OTHER_CFLAGS=' r'\$(inherited)' ' -D FULL_ISOLATION=\${fullIsolation ? 1 : 0} -D CLEAR_PERMISSIONS=\${clearIOSPermissions ? 1 : 0}',"

  repair_patrol_cli_ios_inherited_flag_bug "${fixture_root}" >/dev/null 2>&1

  local second_output
  second_output="$(
    repair_patrol_cli_ios_inherited_flag_bug "${fixture_root}" 2>&1
  )"

  local patched_contents
  patched_contents="$(cat "${fixture_root}/hosted/pub.dev/patrol_cli-4.2.0/lib/src/crossplatform/app_options.dart")"

  assert_contains "${patched_contents}" "${expected_fixed_cflags}" "idempotent second run keeps the repaired Patrol OTHER_CFLAGS line"
  assert_not_contains "${second_output}" "workaround applied" "idempotent second run stays quiet when no repair is needed"

  rm -rf "${fixture_root}"
}

test_disables_completion_auto_install_and_invalidates_snapshot() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  repair_patrol_cli_ios_inherited_flag_bug "${fixture_root}" >/dev/null 2>&1 || true

  local helper_output
  helper_output="$(
    repair_patrol_cli_completion_autoinstall_bug "${fixture_root}" 2>&1
  )"

  local runner_contents
  runner_contents="$(cat "${fixture_root}/hosted/pub.dev/cli_completion-0.4.0/lib/src/command_runner/completion_command_runner.dart")"

  assert_contains "${runner_contents}" "bool get enableAutoInstall => false;" \
    "helper disables Patrol completion auto-install in the command runner source"
  assert_not_contains "${runner_contents}" "bool get enableAutoInstall => true;" \
    "helper removes the Patrol auto-install enabled literal"
  assert_eq "1" "$(test -f "${fixture_root}/global_packages/patrol_cli/bin/main.dart-3.11.0.snapshot"; echo $?)" \
    "completion helper removes the stale Patrol snapshot so the patched runner is recompiled"
  assert_contains "${helper_output}" "Patrol CLI completion auto-install workaround applied" \
    "helper reports when it patches Patrol completion auto-install"

  rm -rf "${fixture_root}"
}

test_replaces_analytics_flutter_version_probe_in_test_command() {
  local fixture_root
  fixture_root="$(setup_fixture)"

  local helper_output
  helper_output="$(
    repair_patrol_cli_analytics_version_probe_bug "${fixture_root}" 2>&1
  )"

  local command_contents
  command_contents="$(cat "${fixture_root}/hosted/pub.dev/patrol_cli-4.2.0/lib/src/commands/test.dart")"

  assert_contains "${command_contents}" "_analytics.sendCommand(FlutterVersion.test(), name)" \
    "helper replaces the fragile FlutterVersion.fromCLI analytics probe in Patrol test command"
  assert_not_contains "${command_contents}" "FlutterVersion.fromCLI(flutterCommand)" \
    "helper removes the Patrol analytics FlutterVersion.fromCLI call from test command"
  assert_contains "${helper_output}" "Patrol CLI analytics version-probe workaround applied" \
    "helper reports when it patches the Patrol test command analytics probe"

  rm -rf "${fixture_root}"
}

test_repairs_broken_other_cflags_and_invalidates_snapshot
test_is_idempotent_when_no_broken_escape_remains
test_disables_completion_auto_install_and_invalidates_snapshot
test_replaces_analytics_flutter_version_probe_in_test_command

if [[ "${failures}" -gt 0 ]]; then
  exit 1
fi

echo "PASS: patrol_cli_workarounds_test"
